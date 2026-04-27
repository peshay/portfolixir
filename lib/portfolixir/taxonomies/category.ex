defmodule Portfolixir.Taxonomies.Category do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Taxonomies.Taxonomy

  schema "categories" do
    field(:name, :string)
    field(:description, :string)
    field(:color, :string)
    field(:sort_order, :integer)

    belongs_to(:taxonomy, Taxonomy)
    belongs_to(:parent, __MODULE__, foreign_key: :parent_id)
    has_many(:children, __MODULE__, foreign_key: :parent_id)

    timestamps()
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:taxonomy_id, :parent_id, :name, :description, :color, :sort_order])
    |> validate_required([:taxonomy_id, :name])
    |> validate_number(:sort_order, greater_than_or_equal_to: 0)
    |> assoc_constraint(:taxonomy)
    |> foreign_key_constraint(:parent_id)
  end
end
