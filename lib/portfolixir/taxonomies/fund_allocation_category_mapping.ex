defmodule Portfolixir.Taxonomies.FundAllocationCategoryMapping do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Taxonomies.{Category, Taxonomy}

  @allocation_types ["region", "country", "sector", "asset_class"]

  schema "fund_allocation_category_mappings" do
    field(:allocation_type, :string)
    field(:source_label, :string)
    field(:metadata, :map, default: %{})

    belongs_to(:taxonomy, Taxonomy)
    belongs_to(:category, Category)

    timestamps()
  end

  @doc false
  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:allocation_type, :source_label, :taxonomy_id, :category_id, :metadata])
    |> validate_required([:allocation_type, :source_label, :taxonomy_id, :category_id])
    |> validate_inclusion(:allocation_type, @allocation_types)
    |> update_change(:source_label, &String.trim/1)
    |> validate_length(:source_label, min: 1)
    |> unique_constraint(:source_label, name: :fund_allocation_category_mappings_unique_key)
    |> assoc_constraint(:taxonomy)
    |> assoc_constraint(:category)
  end
end
