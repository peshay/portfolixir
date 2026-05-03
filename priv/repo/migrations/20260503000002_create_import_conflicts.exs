defmodule Portfolixir.Repo.Migrations.CreateImportConflicts do
  use Ecto.Migration

  def change do
    create table(:import_conflicts) do
      add(:import_source_id, references(:import_sources, on_delete: :restrict), null: false)
      add(:import_run_id, references(:import_runs, on_delete: :restrict), null: false)
      add(:raw_import_item_id, references(:raw_import_items, on_delete: :nilify_all))
      add(:conflict_type, :string, null: false)
      add(:status, :string, null: false, default: "open")
      add(:summary, :string, null: false)
      add(:details, :map, null: false, default: "{}")

      timestamps()
    end

    create(index(:import_conflicts, [:import_source_id]))
    create(index(:import_conflicts, [:import_run_id]))
    create(index(:import_conflicts, [:raw_import_item_id]))
    create(index(:import_conflicts, [:status]))
  end
end
