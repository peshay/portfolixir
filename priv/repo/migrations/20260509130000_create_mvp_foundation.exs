defmodule Portfolixir.Repo.Migrations.CreateMvpFoundation do
  use Ecto.Migration

  def change do
    create table(:securities) do
      add(:name, :string, null: false)
      add(:symbol, :string, null: false)
      add(:currency_code, :string, null: false)
      add(:isin, :string)
      add(:exchange_code, :string)
      add(:notes, :text)

      timestamps()
    end

    create(index(:securities, [:symbol]))
    create(unique_index(:securities, [:symbol, :currency_code]))

    create table(:portfolios) do
      add(:name, :string, null: false)
      add(:base_currency_code, :string, null: false)
      add(:notes, :text)

      timestamps()
    end

    create table(:cash_accounts) do
      add(:portfolio_id, references(:portfolios, on_delete: :restrict), null: false)
      add(:name, :string, null: false)
      add(:currency_code, :string, null: false)
      add(:notes, :text)

      timestamps()
    end

    create(index(:cash_accounts, [:portfolio_id]))

    create(
      unique_index(:cash_accounts, [:id, :portfolio_id],
        name: :cash_accounts_id_portfolio_id_unique_index
      )
    )

    create table(:securities_accounts) do
      add(:portfolio_id, references(:portfolios, on_delete: :restrict), null: false)
      add(:cash_account_id, references(:cash_accounts, on_delete: :restrict), null: false)
      add(:name, :string, null: false)
      add(:notes, :text)

      timestamps()
    end

    create(index(:securities_accounts, [:portfolio_id]))
    create(index(:securities_accounts, [:cash_account_id]))

    create(
      unique_index(:securities_accounts, [:id, :portfolio_id],
        name: :securities_accounts_id_portfolio_id_unique_index
      )
    )

    execute(
      """
      ALTER TABLE securities_accounts
      ADD CONSTRAINT securities_accounts_cash_account_portfolio_fkey
      FOREIGN KEY (cash_account_id, portfolio_id)
      REFERENCES cash_accounts(id, portfolio_id)
      """,
      """
      ALTER TABLE securities_accounts
      DROP CONSTRAINT securities_accounts_cash_account_portfolio_fkey
      """
    )

    create table(:transactions) do
      add(:portfolio_id, references(:portfolios, on_delete: :restrict), null: false)

      add(:securities_account_id, references(:securities_accounts, on_delete: :restrict),
        null: false
      )

      add(:cash_account_id, references(:cash_accounts, on_delete: :restrict), null: false)
      add(:security_id, references(:securities, on_delete: :restrict), null: false)
      add(:type, :string, null: false)
      add(:date, :date, null: false)
      add(:quantity, :decimal, precision: 30, scale: 12, null: false)
      add(:price, :decimal, precision: 20, scale: 6, null: false)
      add(:fees, :decimal, precision: 20, scale: 6, null: false, default: "0")
      add(:taxes, :decimal, precision: 20, scale: 6, null: false, default: "0")
      add(:currency_code, :string, null: false)
      add(:notes, :text)

      timestamps()
    end

    create(index(:transactions, [:portfolio_id, :date]))
    create(index(:transactions, [:securities_account_id]))
    create(index(:transactions, [:cash_account_id]))
    create(index(:transactions, [:security_id]))

    create(
      constraint(:transactions, :transactions_manual_trade_type_check,
        check: "type IN ('buy', 'sell')"
      )
    )

    execute(
      """
      ALTER TABLE transactions
      ADD CONSTRAINT transactions_cash_account_portfolio_fkey
      FOREIGN KEY (cash_account_id, portfolio_id)
      REFERENCES cash_accounts(id, portfolio_id)
      """,
      """
      ALTER TABLE transactions
      DROP CONSTRAINT transactions_cash_account_portfolio_fkey
      """
    )

    execute(
      """
      ALTER TABLE transactions
      ADD CONSTRAINT transactions_securities_account_portfolio_fkey
      FOREIGN KEY (securities_account_id, portfolio_id)
      REFERENCES securities_accounts(id, portfolio_id)
      """,
      """
      ALTER TABLE transactions
      DROP CONSTRAINT transactions_securities_account_portfolio_fkey
      """
    )

    create table(:security_quotes) do
      add(:security_id, references(:securities, on_delete: :restrict), null: false)
      add(:date, :date, null: false)
      add(:source, :string, null: false, default: "manual")
      add(:currency_code, :string, null: false)
      add(:open, :decimal, precision: 20, scale: 6)
      add(:high, :decimal, precision: 20, scale: 6)
      add(:low, :decimal, precision: 20, scale: 6)
      add(:close, :decimal, precision: 20, scale: 6, null: false)
      add(:volume, :decimal, precision: 30, scale: 6)

      timestamps()
    end

    create(index(:security_quotes, [:security_id, :date]))
    create(unique_index(:security_quotes, [:security_id, :source, :date]))
  end
end
