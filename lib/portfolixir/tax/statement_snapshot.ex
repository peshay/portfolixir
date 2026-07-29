defmodule Portfolixir.Tax.StatementSnapshot do
  @moduledoc """
  A recorded broker tax statement (ADR-0031 §2): the
  Verlustverrechnungstöpfe / Freistellungsauftrag block as printed, per
  `(institution, holder, tax_year, as_of)`.

  This row is a **transcription**, never a derivation. ADR-0031 rejects
  computing the German tax pots from the ledger because Portfolixir folds cost
  basis as a running average while the tax code mandates strict FIFO, and
  Teilfreistellung, Vorabpauschale, chronological allowance consumption and
  prior-year carry-forward are not in the transaction data at all. Nothing
  about a real position, security or transaction is stored here.

  **Sign convention — magnitudes only.** A loss pot is the *volume of loss
  available for offsetting*, not the negative number the statement prints. A
  negative input is rejected with a message naming the convention, never
  silently flipped: silent sign normalisation is how a transcription error
  becomes a permanently wrong number. The display layer (story 19.6) renders
  the statement's printed sign; storage stays magnitudes.

  `church_tax_rate` is `k` in the §32d Abs. 1 EStG reconstruction. It is
  prefilled by the context from the holder's profile in force at `as_of` and
  then frozen here, so a later profile edit changes future prefills and never
  what an already-recorded statement reconstructs to.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Tax.Identity

  @type t :: %__MODULE__{}

  @sources ~w(manual pdf_import)
  @min_tax_year 1990
  @max_tax_year 2200

  # Mirrors `@money_columns` in `20260726120000_create_tax_statement_snapshots`
  # and the DB magnitude CHECK exactly.
  @money_fields ~w(
    taxable_income
    allowance_granted
    allowance_used
    loss_pot_equities
    loss_pot_other
    loss_carryforward_prior_years
    withholding_tax_pot
    withholding_tax_credited
    capital_gains_tax_withheld
    solidarity_surcharge_withheld
    church_tax_withheld
  )a

  schema "tax_statement_snapshots" do
    field(:institution, :string)
    field(:holder, :string)
    field(:tax_year, :integer)
    field(:as_of, :date)
    field(:source, :string, default: "manual")
    field(:church_tax_rate, :decimal, default: Decimal.new(0))
    field(:note, :string)

    field(:taxable_income, :decimal, default: Decimal.new(0))
    field(:allowance_granted, :decimal, default: Decimal.new(0))
    field(:allowance_used, :decimal, default: Decimal.new(0))
    field(:loss_pot_equities, :decimal, default: Decimal.new(0))
    field(:loss_pot_other, :decimal, default: Decimal.new(0))
    field(:loss_carryforward_prior_years, :decimal, default: Decimal.new(0))
    field(:withholding_tax_pot, :decimal, default: Decimal.new(0))
    field(:withholding_tax_credited, :decimal, default: Decimal.new(0))
    field(:capital_gains_tax_withheld, :decimal, default: Decimal.new(0))
    field(:solidarity_surcharge_withheld, :decimal, default: Decimal.new(0))
    field(:church_tax_withheld, :decimal, default: Decimal.new(0))

    timestamps()
  end

  @doc "The recorded money columns, in statement order."
  @spec money_fields() :: [atom()]
  def money_fields, do: @money_fields

  @doc """
  Builds a snapshot changeset. `today` is injected by the context shell (the
  clock stays out of schemas, AR-2): an `as_of` after `today` is rejected — a
  statement reports a position that exists, never a future one.
  """
  def changeset(snapshot, attrs, today, opts \\ []) do
    snapshot
    |> cast(attrs, [:institution, :holder, :tax_year, :as_of, :source, :church_tax_rate, :note])
    |> cast(attrs, @money_fields)
    |> apply_default_church_tax_rate(Keyword.get(opts, :default_church_tax_rate))
    |> update_change(:institution, &Identity.normalize/1)
    |> update_change(:holder, &Identity.normalize/1)
    |> validate_required([:institution, :holder, :tax_year, :as_of, :source, :church_tax_rate])
    |> validate_length(:institution, min: 1)
    |> validate_length(:holder, min: 1)
    |> validate_inclusion(:source, @sources)
    |> validate_number(:tax_year,
      greater_than_or_equal_to: @min_tax_year,
      less_than_or_equal_to: @max_tax_year
    )
    |> validate_church_tax_rate()
    |> validate_magnitudes()
    |> validate_allowance_used()
    |> validate_church_tax_withheld()
    |> validate_not_future(today)
    |> unique_constraint(:institution, name: :tax_statement_snapshots_identity_index)
    |> check_constraint(:taxable_income, name: :tax_statement_snapshots_magnitudes_check)
    |> check_constraint(:church_tax_rate, name: :tax_statement_snapshots_church_tax_rate_check)
    |> check_constraint(:source, name: :tax_statement_snapshots_source_check)
    |> check_constraint(:tax_year, name: :tax_statement_snapshots_tax_year_check)
  end

  defp validate_magnitudes(changeset) do
    Enum.reduce(@money_fields, changeset, &validate_magnitude/2)
  end

  defp validate_magnitude(field, changeset) do
    validate_change(changeset, field, fn ^field, value ->
      if Decimal.compare(value, 0) == :lt do
        [{field, "is recorded as a positive magnitude — enter the amount without its sign"}]
      else
        []
      end
    end)
  end

  # The profile-resolved rate is applied before validation, so the hard C2 rule
  # sees the rate the row will actually carry. A rate the caller supplied always
  # wins: the statement's printed rate beats the profile's.
  defp apply_default_church_tax_rate(changeset, nil), do: changeset

  defp apply_default_church_tax_rate(changeset, rate) do
    case get_change(changeset, :church_tax_rate) do
      nil -> put_change(changeset, :church_tax_rate, rate)
      _supplied -> changeset
    end
  end

  # C1 (ADR-0031 §4, hard): within one institution, more allowance cannot be
  # consumed than was granted. Definitional, so it is a save-blocking error and
  # never an advisory.
  defp validate_allowance_used(changeset) do
    used = get_field(changeset, :allowance_used)
    granted = get_field(changeset, :allowance_granted)

    if Decimal.compare(used, granted) == :gt do
      add_error(changeset, :allowance_used, "must not exceed the granted allowance")
    else
      changeset
    end
  end

  # C2 (ADR-0031 §4, hard): church tax withheld at a zero church-tax rate is a
  # contradiction between the row's own two fields.
  defp validate_church_tax_withheld(changeset) do
    rate = get_field(changeset, :church_tax_rate)
    withheld = get_field(changeset, :church_tax_withheld)

    if Decimal.equal?(rate, 0) and Decimal.compare(withheld, 0) == :gt do
      add_error(changeset, :church_tax_withheld, "must be 0 when the church-tax rate is 0")
    else
      changeset
    end
  end

  defp validate_church_tax_rate(changeset) do
    validate_change(changeset, :church_tax_rate, fn :church_tax_rate, rate ->
      if Decimal.compare(rate, 0) != :lt and Decimal.compare(rate, 1) == :lt do
        []
      else
        [church_tax_rate: "must be a fraction between 0 and 1 (0.09, not 9)"]
      end
    end)
  end

  defp validate_not_future(changeset, today) do
    validate_change(changeset, :as_of, fn :as_of, as_of ->
      case Date.compare(as_of, today) do
        :gt -> [as_of: "must not lie in the future"]
        _ -> []
      end
    end)
  end
end
