defmodule Portfolixir.Tax.Profile do
  @moduledoc """
  The taxpayer situation in force from a date (ADR-0031 §3): church-tax
  liability and rate, and whether the single or joint Sparer-Pauschbetrag
  ceiling applies.

  Effective-dated per `(holder, valid_from)` rather than mutable, because state,
  marital status and church membership change **on a date** and must not rewrite
  the past. `Portfolixir.Tax.profile_in_force/2` resolves the row with the
  greatest `valid_from <= on_date` — never an exact match — and story 19.3
  freezes the resolved church-tax rate onto the snapshot row, so a later profile
  edit changes future prefills and never a recorded transcription.

  Church-tax liability defaults to **not liable**, and a not-liable profile
  carries rate `0`. Both a DB CHECK and `validate_church_tax/1` enforce that: a
  stray non-zero rate on a not-liable profile would silently inflate every
  consistency finding for that holder.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Tax.Identity

  @type t :: %__MODULE__{}

  @assessment_types ~w(single joint)
  @jurisdictions ~w(DE)

  schema "tax_profiles" do
    field(:holder, :string)
    field(:valid_from, :date)
    field(:jurisdiction, :string, default: "DE")
    field(:church_tax_liable, :boolean, default: false)
    field(:church_tax_rate, :decimal, default: Decimal.new(0))
    field(:assessment_type, :string, default: "single")
    field(:note, :string)

    timestamps()
  end

  @doc """
  Builds a profile changeset. `holder` is normalised on write (§5a) and matched
  case-insensitively, so one taxpayer typed two ways stays one taxpayer.
  """
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :holder,
      :valid_from,
      :jurisdiction,
      :church_tax_liable,
      :church_tax_rate,
      :assessment_type,
      :note
    ])
    |> update_change(:holder, &Identity.normalize/1)
    |> validate_required([:holder, :valid_from, :assessment_type])
    |> validate_length(:holder, min: 1)
    |> validate_inclusion(:jurisdiction, @jurisdictions)
    |> validate_inclusion(:assessment_type, @assessment_types)
    |> validate_church_tax()
    |> unique_constraint(:holder, name: :tax_profiles_holder_valid_from_index)
    |> check_constraint(:church_tax_rate, name: :tax_profiles_church_tax_rate_check)
    |> check_constraint(:church_tax_rate, name: :tax_profiles_church_tax_liability_check)
    |> check_constraint(:assessment_type, name: :tax_profiles_assessment_type_check)
  end

  defp validate_church_tax(changeset) do
    liable? = get_field(changeset, :church_tax_liable)
    rate = get_field(changeset, :church_tax_rate)

    cond do
      is_nil(rate) ->
        add_error(changeset, :church_tax_rate, "is required")

      not rate?(rate) ->
        add_error(changeset, :church_tax_rate, "must be a fraction between 0 and 1 (0.09, not 9)")

      not liable? and Decimal.compare(rate, 0) != :eq ->
        add_error(changeset, :church_tax_rate, "must be 0 when not liable for church tax")

      true ->
        changeset
    end
  end

  defp rate?(%Decimal{} = value) do
    Decimal.compare(value, 0) != :lt and Decimal.compare(value, 1) == :lt
  end
end
