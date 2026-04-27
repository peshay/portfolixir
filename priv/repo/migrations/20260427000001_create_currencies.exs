defmodule Portfolixir.Repo.Migrations.CreateCurrencies do
  use Ecto.Migration

  def change do
    create table(:currencies, primary_key: false) do
      add(:code, :string, primary_key: true, null: false)
      add(:name, :string, null: false)
      add(:minor_units, :integer, null: false)

      timestamps()
    end

    create(unique_index(:currencies, [:code]))
  end
end
