defmodule Portfolixir.Classifications.Category do
  @moduledoc """
  A node within one classification tree.

  Categories form a tree through a nullable `parent_id`. A `color` is an optional
  hex string for the UI. A `key` is set only on built-in categories (the derived
  code, e.g. an asset-class or currency code) so built-in trees can be re-synced.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Classifications.Classification

  @color_format ~r/^#[0-9a-fA-F]{6}$/

  schema "classification_categories" do
    field(:name, :string)
    field(:key, :string)
    field(:color, :string)
    field(:description, :string)
    field(:position, :integer, default: 0)

    belongs_to(:classification, Classification)
    belongs_to(:parent, __MODULE__, foreign_key: :parent_id)
    has_many(:children, __MODULE__, foreign_key: :parent_id)

    timestamps()
  end

  @doc "Changeset for user-editable category attributes."
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :color, :description, :position, :parent_id, :classification_id])
    |> update_change(:name, &normalize_name/1)
    |> update_change(:color, &normalize_color/1)
    |> update_change(:description, &normalize_description/1)
    |> validate_required([:name, :classification_id])
    |> validate_length(:name, max: 255)
    |> validate_length(:description, max: 2000)
    |> validate_format(:color, @color_format, message: "must be a hex color like #1a2b3c")
    |> assoc_constraint(:classification)
    |> foreign_key_constraint(:parent_id)
  end

  @doc "Changeset that updates only the color (allowed on built-in categories)."
  def color_changeset(category, color) do
    category
    |> cast(%{color: color}, [:color])
    |> update_change(:color, &normalize_color/1)
    |> validate_format(:color, @color_format, message: "must be a hex color like #1a2b3c")
  end

  @doc false
  def builtin_changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :key, :color, :position, :parent_id, :classification_id])
    |> validate_required([:name, :key, :classification_id])
    |> assoc_constraint(:classification)
  end

  defp normalize_name(name) when is_binary(name), do: String.trim(name)
  defp normalize_name(name), do: name

  defp normalize_description(description) when is_binary(description) do
    case String.trim(description) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_description(description), do: description

  defp normalize_color(color) when is_binary(color) do
    color |> String.trim() |> String.downcase()
  end

  defp normalize_color(color), do: color
end
