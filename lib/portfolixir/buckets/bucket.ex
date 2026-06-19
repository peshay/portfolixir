defmodule Portfolixir.Buckets.Bucket do
  @moduledoc """
  A bucket: an overlapping tag applied to holdings (depots, cash accounts, and
  security positions) for tag-based wealth scoping (ADR-0018).

  Buckets are the root entity of the model; the `buckets` table is guard-armed
  (ADR-0017), so every write must be routed through `Portfolixir.Journal.record/3`
  by the `Portfolixir.Buckets` context.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "buckets" do
    field(:name, :string)
    field(:color, :string)

    timestamps()
  end

  def changeset(bucket, attrs) do
    bucket
    |> cast(attrs, [:name, :color])
    |> normalize_name()
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> unique_constraint(:name)
  end

  defp normalize_name(changeset) do
    update_change(changeset, :name, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
  end
end
