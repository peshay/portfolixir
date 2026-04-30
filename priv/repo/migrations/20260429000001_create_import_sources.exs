defmodule Portfolixir.Repo.Migrations.CreateImportSources do
  use Ecto.Migration

  def change do
    create table(:import_sources) do
      add(:name, :string, null: false)
      add(:type, :string, null: false)
      add(:status, :string, default: "active", null: false)
      add(:config, :map, default: "{}")

      timestamps()
    end
  end
end
