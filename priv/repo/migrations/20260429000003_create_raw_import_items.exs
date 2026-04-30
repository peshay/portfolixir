defmodule Portfolixir.Repo.Migrations.CreateRawImportItems do
  use Ecto.Migration

  def change do
    create table(:raw_import_items) do
      add(:import_source_id, references(:import_sources, on_delete: :restrict), null: false)
      add(:import_run_id, references(:import_runs, on_delete: :restrict))
      add(:external_id, :string)
      add(:content_hash, :string)
      add(:content_type, :string)
      add(:original_filename, :string)
      add(:payload, :map, default: "{}")
      add(:status, :string, default: "new", null: false)

      timestamps()
    end

    create(index(:raw_import_items, [:import_source_id]))
    create(index(:raw_import_items, [:import_run_id]))

    create(
      unique_index(
        :raw_import_items,
        [:import_source_id, :external_id],
        name: :raw_import_items_source_id_external_id_uq,
        where: "external_id IS NOT NULL"
      )
    )

    create(
      unique_index(
        :raw_import_items,
        [:import_source_id, :content_hash],
        name: :raw_import_items_source_id_content_hash_uq,
        where: "content_hash IS NOT NULL"
      )
    )
  end
end
