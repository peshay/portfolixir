defmodule Portfolixir.Repo.Migrations.CreateSecurityCategoryAssignments do
  use Ecto.Migration

  def change do
    create table(:security_category_assignments) do
      add(:security_id, references(:securities, on_delete: :restrict), null: false)
      add(:category_id, references(:categories, on_delete: :restrict), null: false)
      add(:weight, :decimal, null: false, default: "1.0")

      timestamps()
    end

    create(index(:security_category_assignments, [:security_id]))
    create(index(:security_category_assignments, [:category_id]))

    create(
      unique_index(:security_category_assignments, [:security_id, :category_id],
        name: :security_category_assignments_security_id_category_id_index
      )
    )
  end
end
