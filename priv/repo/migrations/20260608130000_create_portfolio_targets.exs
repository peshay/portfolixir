defmodule Portfolixir.Repo.Migrations.CreatePortfolioTargets do
  use Ecto.Migration

  def change do
    create table(:portfolio_targets) do
      add(:portfolio_id, references(:portfolios, on_delete: :delete_all), null: false)

      add(:classification_id, references(:classifications, on_delete: :delete_all), null: false)

      add(
        :category_id,
        references(:classification_categories, on_delete: :delete_all),
        null: false
      )

      add(:target_weight, :decimal, null: false)

      timestamps()
    end

    # A portfolio sets at most one target weight per category. The category
    # already fixes the classification, so this is the natural conflict target
    # for upserts.
    create(unique_index(:portfolio_targets, [:portfolio_id, :category_id]))
    create(index(:portfolio_targets, [:portfolio_id, :classification_id]))
    create(index(:portfolio_targets, [:category_id]))
  end
end
