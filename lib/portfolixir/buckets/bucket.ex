defmodule Portfolixir.Buckets.Bucket do
  @moduledoc """
  A bucket: an overlapping tag applied to holdings (depots, cash accounts, and
  security positions) for tag-based wealth scoping (ADR-0018).

  The `dimension` sorts a bucket into one of two roles (ADR-0024): `"tag"`
  (default) is a free overlapping tag; `"scope"` is the exclusive dimension —
  a depot/cash account carries at most one scope bucket (enforced by the
  `Portfolixir.Buckets` context on assignment), so scope-scoped totals always
  add up. The dimension is fixed at creation: flipping it later could silently
  break that invariant on existing assignments.

  `source_portfolio_id` marks a bucket seeded by the ADR-0024 portfolio
  migration (NULL = user-created); the migration rollback removes only marked
  records. It is deliberately not castable — user and API writes never set it.

  Buckets are the root entity of the model; the `buckets` table is guard-armed
  (ADR-0017), so every write must be routed through `Portfolixir.Journal.record/3`
  by the `Portfolixir.Buckets` context.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @dimensions ~w(tag scope)

  schema "buckets" do
    field(:name, :string)
    field(:color, :string)
    field(:dimension, :string, default: "tag")
    field(:source_portfolio_id, :integer)

    timestamps()
  end

  @doc "The closed bucket-dimension taxonomy (ADR-0024)."
  def dimensions, do: @dimensions

  def changeset(bucket, attrs) do
    bucket
    |> cast(attrs, [:name, :color, :dimension])
    |> normalize_name()
    |> validate_required([:name, :dimension])
    |> validate_length(:name, max: 100)
    |> validate_inclusion(:dimension, @dimensions)
    |> forbid_dimension_change()
    |> unique_constraint(:name)
  end

  # The dimension is create-only: a persisted bucket rejects any change to it.
  defp forbid_dimension_change(%{data: %{id: nil}} = changeset), do: changeset

  defp forbid_dimension_change(changeset) do
    case get_change(changeset, :dimension) do
      nil -> changeset
      _changed -> add_error(changeset, :dimension, "cannot be changed after creation")
    end
  end

  defp normalize_name(changeset) do
    update_change(changeset, :name, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
  end
end
