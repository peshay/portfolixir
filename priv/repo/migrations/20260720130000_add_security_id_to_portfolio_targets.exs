defmodule Portfolixir.Repo.Migrations.AddSecurityIdToPortfolioTargets do
  @moduledoc """
  Position-level SOLL targets (ADR-0030, issue #481 slice 1).

  Adds a nullable `security_id` to `portfolio_targets` so a row targets either a
  **category** (`security_id` NULL — unchanged behaviour) or an individual
  **position** (`security_id` set, the security sitting under that category).

  The single `(plan_id, category_id)` uniqueness is replaced by TWO **partial**
  unique indexes, so one category row and N distinct position rows coexist per
  category without either overwriting the other:

    * `(plan_id, category_id) WHERE security_id IS NULL` — at most one category
      row per category (the legacy conflict target);
    * `(plan_id, category_id, security_id) WHERE security_id IS NOT NULL` — at
      most one row per position.

  Existing category rows keep `security_id` NULL and stay valid under the first
  index. The migration is reversible: `down/0` restores the single
  `(plan_id, category_id)` uniqueness (safe because no position rows can exist
  before this migration adds the column).

  The `security_id` FK uses `on_delete: :delete_all`, matching the sibling
  security-referencing tables (`security_category_assignments`,
  `security_quotes`): removing a security drops its position targets. This DDL
  inserts no rows, so the journal guard triggers armed on `portfolio_targets`
  (ADR-0017) do not fire here.
  """
  use Ecto.Migration

  def up do
    alter table(:portfolio_targets) do
      add(:security_id, references(:securities, on_delete: :delete_all))
    end

    drop(unique_index(:portfolio_targets, [:plan_id, :category_id]))

    execute(
      """
      CREATE UNIQUE INDEX portfolio_targets_plan_category_index
        ON portfolio_targets (plan_id, category_id)
        WHERE security_id IS NULL;
      """,
      "DROP INDEX portfolio_targets_plan_category_index;"
    )

    execute(
      """
      CREATE UNIQUE INDEX portfolio_targets_plan_category_security_index
        ON portfolio_targets (plan_id, category_id, security_id)
        WHERE security_id IS NOT NULL;
      """,
      "DROP INDEX portfolio_targets_plan_category_security_index;"
    )

    create(index(:portfolio_targets, [:security_id]))
  end

  def down do
    drop(index(:portfolio_targets, [:security_id]))
    execute("DROP INDEX IF EXISTS portfolio_targets_plan_category_security_index;")
    execute("DROP INDEX IF EXISTS portfolio_targets_plan_category_index;")

    create(unique_index(:portfolio_targets, [:plan_id, :category_id]))

    alter table(:portfolio_targets) do
      remove(:security_id)
    end
  end
end
