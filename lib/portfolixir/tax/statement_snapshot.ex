defmodule Portfolixir.Tax.StatementSnapshot do
  @moduledoc """
  A recorded broker tax statement (ADR-0031 §2): the
  Verlustverrechnungstöpfe / Freistellungsauftrag block as printed, per
  `(institution, holder, tax_year, as_of)`.

  This row is a **transcription**, never a derivation. ADR-0031 rejects
  computing the German tax pots from the ledger, and the reason is *not* a
  missing FIFO: `Ledger.TradeMatcher` matches lots FIFO already. It is that
  Teilfreistellung, Vorabpauschale, chronological allowance consumption and
  certified prior-year carry-forward never enter the transaction data, and that
  the pots are kept per tax-reporting institution, which Portfolixir does not
  model. FIFO yields a gross gain; a gross gain is not a tax pot. Nothing about
  a real position, security or transaction is stored here.

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

  **Who recorded and who corrected it** (security review 2026-10-12, K12,
  T-16): `author` is set from the actor of the create and `corrected_by`
  from the actor of every update, each `operator` or `agent`
  (`Portfolixir.Actor.author/1`), never cast from input; `source` stays the
  system's (F20) and says how the figures arrived, not who wrote them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Input.BoundedDecimal
  alias Portfolixir.Input.Text
  alias Portfolixir.Tax.Identity

  @type t :: %__MODULE__{}

  @sources ~w(manual pdf_import)
  # The `numeric(precision, scale)` of the money and rate columns (ADR-0016 §2).
  @money_column {20, 6}
  @rate_column {6, 4}
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
    # K12 (T-16): set by the context from the write's actor (`put_author/2`,
    # `put_corrected_by/2`), never cast; `nil` on a row stored before authors
    # existed that the backfill could not trace, and `corrected_by` until the
    # first correction.
    field(:author, Ecto.Enum, values: [:operator, :agent])
    field(:corrected_by, Ecto.Enum, values: [:operator, :agent])

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
  Sets the author of a new statement's changeset from the actor of the write
  (K12, T-16); the input never carries it.
  """
  @spec put_author(Ecto.Changeset.t(), Portfolixir.Actor.t()) :: Ecto.Changeset.t()
  def put_author(changeset, actor) do
    changeset
    |> put_change(:author, Portfolixir.Actor.author(actor))
    |> check_constraint(:author, name: :tax_statement_snapshots_author_check)
  end

  @doc """
  Sets who corrected a stored statement last from the actor of the update
  (K12, T-16); the input never carries it. An update that changes nothing
  corrects nothing and keeps it.
  """
  @spec put_corrected_by(Ecto.Changeset.t(), Portfolixir.Actor.t()) :: Ecto.Changeset.t()
  def put_corrected_by(%Ecto.Changeset{changes: changes} = changeset, _actor)
      when changes == %{},
      do: changeset

  def put_corrected_by(changeset, actor) do
    changeset
    |> put_change(:corrected_by, Portfolixir.Actor.author(actor))
    |> check_constraint(:corrected_by, name: :tax_statement_snapshots_corrected_by_check)
  end

  @doc """
  Whether the agent recorded the statement or corrected it last (K12): what
  the Tax page and the trim budget's basis line mark.
  """
  @spec agent_written?(t()) :: boolean()
  def agent_written?(%__MODULE__{author: author, corrected_by: corrected_by}),
    do: author == :agent or corrected_by == :agent

  @doc """
  Builds a snapshot changeset. `today` is injected by the context shell (the
  clock stays out of schemas, AR-2): an `as_of` after `today` is rejected — a
  statement reports a position that exists, never a future one.
  """
  def changeset(snapshot, attrs, today, opts \\ []) do
    snapshot
    # `source` is the system's to state (E25 S6, F20): the public changeset
    # never casts it, so every writer stores the default `manual`, and a
    # future PDF intake (ADR-0021) sets `pdf_import` on its own path.
    |> cast(attrs, [:institution, :holder, :tax_year, :as_of, :church_tax_rate, :note])
    |> cast(attrs, @money_fields)
    |> apply_default_church_tax_rate(Keyword.get(opts, :default_church_tax_rate))
    |> bound_to_columns()
    |> update_change(:institution, &Identity.normalize/1)
    |> update_change(:holder, &Identity.normalize/1)
    |> validate_required([:institution, :holder, :tax_year, :as_of, :source, :church_tax_rate])
    |> BoundedDate.validate([:as_of])
    |> Text.validate([:institution, :holder], max: 255)
    |> Text.validate(:note, multiline: true, max: Text.free_text_max())
    |> check_constraint(:note, name: :tax_statement_snapshots_note_length_check)
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

  # E25 S4 (G16, G17): every amount is rounded to its column's scale and
  # bounded by its precision before the sign and consistency checks, so the
  # value checked is the value stored, answered and journaled.
  defp bound_to_columns(changeset) do
    @money_fields
    |> Enum.reduce(changeset, &BoundedDecimal.bound_to_column(&2, &1, @money_column))
    |> BoundedDecimal.bound_to_column(:church_tax_rate, @rate_column)
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
