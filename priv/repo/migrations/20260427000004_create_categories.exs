defmodule Portfolixir.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add(:taxonomy_id, references(:taxonomies, on_delete: :delete_all), null: false)
      add(:parent_id, references(:categories, on_delete: :nilify_all))
      add(:name, :string, null: false)
      add(:description, :text)
      add(:color, :string)
      add(:sort_order, :integer)

      timestamps()
    end

    create(index(:categories, [:taxonomy_id]))
    create(index(:categories, [:parent_id]))
  end
end
