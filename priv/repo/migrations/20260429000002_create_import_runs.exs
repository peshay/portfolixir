defmodule Portfolixir.Repo.Migrations.CreateImportRuns do
  use Ecto.Migration

  def change do
    create table(:import_runs) do
      add(:import_source_id, references(:import_sources, on_delete: :restrict), null: false)
      add(:status, :string, default: "pending", null: false)
      add(:started_at, :utc_datetime_usec)
      add(:finished_at, :utc_datetime_usec)
      add(:summary, :map, default: "{}")

      timestamps()
    end

    create(index(:import_runs, [:import_source_id]))
  end
end
