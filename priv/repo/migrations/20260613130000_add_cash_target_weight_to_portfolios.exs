defmodule Portfolixir.Repo.Migrations.AddCashTargetWeightToPortfolios do
  use Ecto.Migration

  def change do
    alter table(:portfolios) do
      add(:cash_target_weight, :decimal)
    end
  end
end
