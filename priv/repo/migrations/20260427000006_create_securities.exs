defmodule Portfolixir.Repo.Migrations.CreateSecurities do
  use Ecto.Migration

  def change do
    create table(:securities) do
      add(:name, :string, null: false)
      add(:symbol, :string, null: false)
      add(:exchange_code, :string)
      add(:provider_symbol, :string)
      add(:isin, :string)

      add(
        :currency_code,
        references(:currencies, column: :code, type: :string, on_delete: :restrict),
        null: false
      )

      add(:notes, :text)

      timestamps()
    end

    create(index(:securities, [:currency_code]))

    create(
      unique_index(:securities, [:provider_symbol, :exchange_code],
        name: :securities_provider_symbol_exchange_code_unique_index,
        where: "provider_symbol IS NOT NULL AND exchange_code IS NOT NULL"
      )
    )
  end
end
