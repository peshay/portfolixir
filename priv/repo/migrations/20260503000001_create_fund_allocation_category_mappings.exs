defmodule Portfolixir.Repo.Migrations.CreateFundAllocationCategoryMappings do
  use Ecto.Migration

  def change do
    create table(:fund_allocation_category_mappings) do
      add(:allocation_type, :string, null: false)
      add(:source_label, :string, null: false)
      add(:taxonomy_id, references(:taxonomies, on_delete: :delete_all), null: false)
      add(:category_id, references(:categories, on_delete: :delete_all), null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps()
    end

    create(index(:fund_allocation_category_mappings, [:taxonomy_id]))
    create(index(:fund_allocation_category_mappings, [:category_id]))

    create(
      unique_index(
        :fund_allocation_category_mappings,
        [:allocation_type, :source_label, :taxonomy_id],
        name: :fund_allocation_category_mappings_unique_key
      )
    )
  end
end
