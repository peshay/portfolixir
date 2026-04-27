defmodule Portfolixir.Repo.Migrations.AddUniqueIndexToCategories do
  use Ecto.Migration

  def change do
    create(
      unique_index(:categories, [:taxonomy_id, :name], name: :categories_taxonomy_id_name_index)
    )
  end
end
