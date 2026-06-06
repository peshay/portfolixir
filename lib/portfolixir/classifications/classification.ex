defmodule Portfolixir.Classifications.Classification do
  @moduledoc """
  A classification (taxonomy) tree: a named way to organise securities.

  Custom classifications are user-defined; built-in ones (`built_in: true`,
  identified by `key`, e.g. `"asset_class"` / `"currency"`) are auto-managed
  from security data and their structure is not hand-editable (see ADR-0006).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Classifications.Category

  schema "classifications" do
    field(:name, :string)
    field(:key, :string)
    field(:built_in, :boolean, default: false)
    field(:position, :integer, default: 0)
    field(:description, :string)

    has_many(:categories, Category)

    timestamps()
  end

  @doc "Changeset for user-editable classification attributes."
  def changeset(classification, attrs) do
    classification
    |> cast(attrs, [:name, :position, :description])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
  end

  @doc false
  def builtin_changeset(classification, attrs) do
    classification
    |> cast(attrs, [:name, :key, :built_in, :position, :description])
    |> validate_required([:name, :key, :built_in])
    |> unique_constraint(:key, name: :classifications_key_index)
  end

  defp normalize_name(name) when is_binary(name), do: String.trim(name)
  defp normalize_name(name), do: name
end
