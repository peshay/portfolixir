defmodule Portfolixir.Taxonomies.Taxonomy do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Taxonomies.Category

  schema "taxonomies" do
    field(:name, :string)
    field(:description, :string)

    has_many(:categories, Category, foreign_key: :taxonomy_id, on_delete: :delete_all)

    timestamps()
  end

  @doc false
  def changeset(taxonomy, attrs) do
    taxonomy
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
  end
end
