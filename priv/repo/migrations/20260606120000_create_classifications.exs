defmodule Portfolixir.Repo.Migrations.CreateClassifications do
  use Ecto.Migration

  def change do
    create table(:classifications) do
      add(:name, :string, null: false)
      add(:key, :string, null: true)
      add(:built_in, :boolean, null: false, default: false)
      add(:position, :integer, null: false, default: 0)
      add(:description, :text, null: true)

      timestamps()
    end

    create(unique_index(:classifications, [:key]))

    create table(:classification_categories) do
      add(:classification_id, references(:classifications, on_delete: :delete_all), null: false)
      add(:parent_id, references(:classification_categories, on_delete: :delete_all), null: true)
      add(:name, :string, null: false)
      add(:key, :string, null: true)
      add(:color, :string, null: true)
      add(:position, :integer, null: false, default: 0)

      timestamps()
    end

    create(index(:classification_categories, [:classification_id]))
    create(index(:classification_categories, [:parent_id]))

    create(unique_index(:classification_categories, [:classification_id, :key]))

    create table(:security_category_assignments) do
      add(:security_id, references(:securities, on_delete: :delete_all), null: false)
      add(:classification_id, references(:classifications, on_delete: :delete_all), null: false)

      add(
        :category_id,
        references(:classification_categories, on_delete: :delete_all),
        null: false
      )

      timestamps()
    end

    create(unique_index(:security_category_assignments, [:security_id, :classification_id]))
    create(index(:security_category_assignments, [:category_id]))
  end
end
