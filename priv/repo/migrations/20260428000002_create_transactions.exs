defmodule Portfolixir.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create(
      unique_index(:securities_accounts, [:id, :portfolio_id],
        name: :securities_accounts_id_portfolio_id_unique_index
      )
    )

    create table(:transactions) do
      add(:portfolio_id, references(:portfolios, on_delete: :restrict), null: false)
      add(:type, :string, null: false)
      add(:date, :date, null: false)

      add(
        :currency_code,
        references(:currencies, column: :code, type: :string, on_delete: :restrict),
        null: false
      )

      add(:amount, :decimal, precision: 20, scale: 6)
      add(:notes, :text)

      add(:deposit_account_id, references(:deposit_accounts, on_delete: :restrict))
      add(:securities_account_id, references(:securities_accounts, on_delete: :restrict))
      add(:security_id, references(:securities, on_delete: :restrict))

      add(:quantity, :decimal, precision: 30, scale: 12)
      add(:price, :decimal, precision: 20, scale: 6)
      add(:fees, :decimal, precision: 20, scale: 6)
      add(:taxes, :decimal, precision: 20, scale: 6)

      timestamps()
    end

    create(index(:transactions, [:portfolio_id, :date]))
    create(index(:transactions, [:deposit_account_id]))
    create(index(:transactions, [:securities_account_id]))
    create(index(:transactions, [:security_id]))
    create(index(:transactions, [:currency_code]))

    create(
      constraint(:transactions, :transactions_supported_type_check,
        check: "type IN ('deposit', 'withdrawal', 'buy', 'sell', 'dividend')"
      )
    )

    execute(
      """
      ALTER TABLE transactions
      ADD CONSTRAINT transactions_deposit_account_portfolio_fkey
      FOREIGN KEY (deposit_account_id, portfolio_id)
      REFERENCES deposit_accounts(id, portfolio_id)
      """,
      """
      ALTER TABLE transactions
      DROP CONSTRAINT transactions_deposit_account_portfolio_fkey
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
  end
end
