defmodule Portfolixir.Repo.Migrations.AddReferenceDepositAccountToSecuritiesAccounts do
  use Ecto.Migration

  def change do
    create(
      unique_index(:deposit_accounts, [:id, :portfolio_id],
        name: :deposit_accounts_id_portfolio_id_unique_index
      )
    )

    alter table(:securities_accounts) do
      add(
        :reference_deposit_account_id,
        references(:deposit_accounts, on_delete: :restrict)
      )
    end

    create(index(:securities_accounts, [:reference_deposit_account_id]))

    execute(
      """
      ALTER TABLE securities_accounts
      ADD CONSTRAINT securities_accounts_reference_deposit_account_portfolio_fkey
      FOREIGN KEY (reference_deposit_account_id, portfolio_id)
      REFERENCES deposit_accounts(id, portfolio_id)
      """,
      """
      ALTER TABLE securities_accounts
      DROP CONSTRAINT securities_accounts_reference_deposit_account_portfolio_fkey
      """
    )
  end
end
