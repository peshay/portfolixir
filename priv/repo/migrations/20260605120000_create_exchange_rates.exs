defmodule Portfolixir.Repo.Migrations.CreateExchangeRates do
  use Ecto.Migration

  def change do
    create table(:exchange_rates) do
      add(:base_currency, :string, size: 3, null: false)
      add(:quote_currency, :string, size: 3, null: false)
      add(:date, :date, null: false)
      add(:rate, :decimal, precision: 30, scale: 15, null: false)
      add(:source, :string, null: false, default: "auto")

      timestamps()
    end

    create(unique_index(:exchange_rates, [:base_currency, :quote_currency, :date]))
    create(index(:exchange_rates, [:base_currency, :quote_currency]))
  end
end
