defmodule Portfolixir.Repo.Migrations.AddCountsTowardCashQuoteToCashAccounts do
  use Ecto.Migration

  def change do
    alter table(:cash_accounts) do
      add(:counts_toward_cash_quote, :boolean, default: true, null: false)
    end
  end
end
