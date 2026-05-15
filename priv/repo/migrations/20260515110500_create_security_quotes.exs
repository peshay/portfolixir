defmodule Portfolixir.Repo.Migrations.CreateSecurityQuotes do
  use Ecto.Migration

  def change do
    create table(:security_quotes) do
      add(:security_id, references(:securities, on_delete: :delete_all), null: false)
      add(:date, :date, null: false)
      add(:close, :decimal, precision: 20, scale: 6, null: false)
      add(:source, :string, null: false, default: "auto")

      timestamps()
    end

    create(unique_index(:security_quotes, [:security_id, :date]))
    create(index(:security_quotes, [:security_id]))
  end
end
