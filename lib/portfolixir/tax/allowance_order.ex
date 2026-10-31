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

  **Who put it** (security review 2026-10-12, K12, T-16): `author` is set
  from the actor of the create and `corrected_by` from the actor of every
  later put, each `operator` or `agent` (`Portfolixir.Actor.author/1`), never
  cast from input.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.BoundedDecimal
  alias Portfolixir.Input.Text
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
    # K12 (T-16): set by the context from the write's actor, never cast;
    # `nil` on a row stored before authors existed that the backfill could not
    # trace, and `corrected_by` until the first replacement.
    field(:author, Ecto.Enum, values: [:operator, :agent])
    field(:corrected_by, Ecto.Enum, values: [:operator, :agent])

    timestamps()
  end

  @doc "Sets the author of a new order from the actor of the write (K12, T-16)."
  @spec put_author(Ecto.Changeset.t(), Portfolixir.Actor.t()) :: Ecto.Changeset.t()
  def put_author(changeset, actor) do
    changeset
    |> put_change(:author, Portfolixir.Actor.author(actor))
    |> check_constraint(:author, name: :allowance_orders_author_check)
  end

  @doc """
  Sets who replaced a stored order last from the actor of the put (K12,
  T-16); a put that changes nothing keeps it.
  """
  @spec put_corrected_by(Ecto.Changeset.t(), Portfolixir.Actor.t()) :: Ecto.Changeset.t()
  def put_corrected_by(%Ecto.Changeset{changes: changes} = changeset, _actor)
      when changes == %{},
      do: changeset

  def put_corrected_by(changeset, actor) do
    changeset
    |> put_change(:corrected_by, Portfolixir.Actor.author(actor))
    |> check_constraint(:corrected_by, name: :allowance_orders_corrected_by_check)
  end

  @doc "Whether the agent put the order or replaced it last (K12): what the Tax page marks."
  @spec agent_written?(t()) :: boolean()
  def agent_written?(%__MODULE__{author: author, corrected_by: corrected_by}),
    do: author == :agent or corrected_by == :agent

  @doc "Builds an allowance-order changeset."
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:holder, :institution, :tax_year, :amount_granted, :note])
    |> update_change(:holder, &Identity.normalize/1)
    |> update_change(:institution, &Identity.normalize/1)
    |> validate_required([:holder, :institution, :tax_year, :amount_granted])
    |> validate_length(:holder, min: 1)
    |> validate_length(:institution, min: 1)
    |> Text.validate([:holder, :institution], max: 255)
    |> Text.validate(:note, multiline: true, max: Text.free_text_max())
    |> check_constraint(:note, name: :allowance_orders_note_length_check)
    |> validate_number(:tax_year,
      greater_than_or_equal_to: @min_tax_year,
      less_than_or_equal_to: @max_tax_year
    )
    # E25 S4 (G16, G17): rounded to its numeric(20,6) column and bounded by
    # it before the sign check, so the amount checked is the amount stored.
    |> BoundedDecimal.bound_to_column(:amount_granted, {20, 6})
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
