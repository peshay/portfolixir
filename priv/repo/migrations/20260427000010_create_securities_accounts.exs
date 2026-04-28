defmodule Portfolixir.Repo.Migrations.CreateSecuritiesAccounts do
  use Ecto.Migration

  def change do
    create table(:securities_accounts) do
      add(:portfolio_id, references(:portfolios, on_delete: :restrict), null: false)

      add(:name, :string, null: false)

      add(
        :currency_code,
        references(:currencies, column: :code, type: :string, on_delete: :restrict),
        null: false
      )

      add(:active, :boolean, null: false, default: true)
      add(:notes, :text)

      timestamps()
    end

    create(index(:securities_accounts, [:portfolio_id]))
    create(index(:securities_accounts, [:currency_code]))
    create(index(:securities_accounts, [:portfolio_id, :name]))
  end
end
