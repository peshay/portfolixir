defmodule Portfolixir.Tax.AllowanceOrder do
  @moduledoc """
  A Freistellungsauftrag as **instructed** by the taxpayer, per
  `(holder, institution, tax_year)` (ADR-0031 §3).

  This is the instruction side of the instruction-vs-reality split: what the
  bank actually applied is transcribed on the snapshot (story 19.3), and story
  19.4 compares the two. Recording the instruction separately is what makes
  "the bank applied less than I granted" visible at all.

  `holder` and `institution` are normalised on write and matched case-folded
  (`Portfolixir.Tax.Identity`) — a case split here would make the cross-check
  report a missing instruction that is not missing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Tax.Identity

  @type t :: %__MODULE__{}

  @min_tax_year 1990
  @max_tax_year 2200

  schema "allowance_orders" do
    field(:holder, :string)
    field(:institution, :string)
    field(:tax_year, :integer)
    field(:amount_granted, :decimal)
    field(:note, :string)

    timestamps()
  end

  @doc "Builds an allowance-order changeset."
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:holder, :institution, :tax_year, :amount_granted, :note])
    |> update_change(:holder, &Identity.normalize/1)
    |> update_change(:institution, &Identity.normalize/1)
    |> validate_required([:holder, :institution, :tax_year, :amount_granted])
    |> validate_length(:holder, min: 1)
    |> validate_length(:institution, min: 1)
    |> validate_number(:tax_year,
      greater_than_or_equal_to: @min_tax_year,
      less_than_or_equal_to: @max_tax_year
    )
    |> validate_non_negative(:amount_granted)
    |> unique_constraint(:institution,
      name: :allowance_orders_holder_institution_year_index
    )
    |> check_constraint(:amount_granted, name: :allowance_orders_amount_granted_check)
    |> check_constraint(:tax_year, name: :allowance_orders_tax_year_check)
  end

  defp validate_non_negative(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if Decimal.compare(value, 0) == :lt, do: [{field, "must not be negative"}], else: []
    end)
  end
end
