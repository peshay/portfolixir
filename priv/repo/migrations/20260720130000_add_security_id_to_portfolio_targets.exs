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
  index. The migration is schema-reversible but **not** loss-free: position
  rows have no representation in the pre-ADR-0030 shape (and would collide with
  their category row on the restored single `(plan_id, category_id)` unique
  index), so `down/0` first DELETES every row with `security_id IS NOT NULL` —
  stated here rather than failing or losing them silently — and then restores
  the original uniqueness. The delete satisfies the guard trigger armed by
  `20260716130000_arm_targets_journal` by setting the transaction-local journal
  actor GUC for the migration transaction (the same mechanism
  `Portfolixir.Journal` uses); the discarded rows are not journaled per row —
  rolling back the schema is an explicit operator action.

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
    # Discard position rows first (see the moduledoc: they cannot exist in the
    # restored schema and would break the single unique index below). Ecto runs
    # this migration in one transaction, so the transaction-local actor GUC
    # (`set_config(..., is_local = true)`) covers the DELETE and expires with
    # the migration — it authorises the write against the armed journal guard
    # without touching application state.
    execute(
      "SELECT set_config('portfolixir.journal_actor', 'migration:rollback_position_targets', true);"
    )

    execute("DELETE FROM portfolio_targets WHERE security_id IS NOT NULL;")

    drop(index(:portfolio_targets, [:security_id]))
    execute("DROP INDEX IF EXISTS portfolio_targets_plan_category_security_index;")
    execute("DROP INDEX IF EXISTS portfolio_targets_plan_category_index;")

    create(unique_index(:portfolio_targets, [:plan_id, :category_id]))

    alter table(:portfolio_targets) do
      remove(:security_id)
    end
  end
end
