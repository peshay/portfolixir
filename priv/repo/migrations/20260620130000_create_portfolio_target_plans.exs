defmodule Portfolixir.Repo.Migrations.CreatePortfolioTargetPlans do
  @moduledoc """
  View-bound SOLL target plans (ADR-0020, epic #463, story #464).

  A SOLL target plan belongs to a **view**. This migration introduces the
  `portfolio_target_plans` plan unit keyed `(portfolio_id, view_id,
  classification_id)`, hangs the existing `portfolio_targets` rows off a plan via
  `plan_id`, and moves the per-portfolio cash target onto the plan — replacing the
  single global `portfolios.cash_target_weight`.

  `view_id = NULL` is the **Gesamt** (total) plan: today's portfolio-wide
  behaviour. `classification_id = NULL` is the **portfolio-wide cash-only** plan
  that holds the legacy global cash target (which was never classification-scoped
  and rendered identically across every classification breakdown).

  The migration is **loss-free and reversible**:

    * existing `portfolio_targets` are carried into their matching Gesamt plan
      (`view_id NULL`, the row's own `classification_id`) before the old
      `(portfolio_id, category_id)` uniqueness is replaced by `(plan_id,
      category_id)`;
    * the existing `portfolios.cash_target_weight` is carried into a Gesamt,
      classification-less plan before the column is dropped;
    * `down/0` carries both values back and restores the original shape.

  Journaling (ADR-0017): `portfolio_target_plans` and `portfolio_targets` are
  **not** guard-armed here. The owning Portfolios/Targets write path is not yet
  actor-first (the leaf-first audit-journal rollout has reached Catalog/Fx only;
  Portfolios/Classifications is a later slice — see ADR-0017 "Rollout status" and
  `test/write_actor_test.exs`). Arming these tables now would reject the plain
  Repo writes the existing target write path still uses (and the data-carry steps
  in this migration). The new plan tables follow the **same** non-journaled
  policy as the `portfolio_targets` table they extend; per-view journaling lands
  with the Portfolios actor-first slice.

  `NULLS NOT DISTINCT` (PostgreSQL 15+) makes the nullable `view_id` /
  `classification_id` participate in uniqueness, so there is exactly one Gesamt
  plan per classification and exactly one portfolio-wide cash plan — the same
  pattern this codebase already uses for `position_bucket_overrides`.
  """
  use Ecto.Migration

  def up do
    create table(:portfolio_target_plans) do
      add(:portfolio_id, references(:portfolios, on_delete: :delete_all), null: false)
      add(:view_id, references(:views, on_delete: :delete_all))
      add(:classification_id, references(:classifications, on_delete: :delete_all))
      add(:cash_target_weight, :decimal)

      timestamps()
    end

    # At most one plan per (portfolio, view, classification). NULLS NOT DISTINCT
    # so the Gesamt plan (view_id NULL) is a single distinct plan, and the
    # classification-less cash plan (classification_id NULL) is a single row too.
    execute(
      """
      CREATE UNIQUE INDEX portfolio_target_plans_unique_index
        ON portfolio_target_plans (portfolio_id, view_id, classification_id)
        NULLS NOT DISTINCT;
      """,
      "DROP INDEX portfolio_target_plans_unique_index;"
    )

    create(index(:portfolio_target_plans, [:view_id]))
    create(index(:portfolio_target_plans, [:classification_id]))

    # Hang targets off a plan. Nullable first so the data-carry can backfill it.
    alter table(:portfolio_targets) do
      add(:plan_id, references(:portfolio_target_plans, on_delete: :delete_all))
    end

    # Carry existing targets into their matching Gesamt plan (one plan per distinct
    # (portfolio, classification); view_id NULL).
    execute("""
    INSERT INTO portfolio_target_plans
      (portfolio_id, view_id, classification_id, cash_target_weight, inserted_at, updated_at)
    SELECT DISTINCT
      t.portfolio_id,
      NULL::bigint,
      t.classification_id,
      NULL::numeric,
      NOW(),
      NOW()
    FROM portfolio_targets t
    """)

    execute("""
    UPDATE portfolio_targets t
    SET plan_id = p.id
    FROM portfolio_target_plans p
    WHERE p.portfolio_id = t.portfolio_id
      AND p.classification_id = t.classification_id
      AND p.view_id IS NULL
    """)

    # Carry the legacy portfolio-wide cash target into a Gesamt, classification-less
    # plan (view_id NULL, classification_id NULL). One row per portfolio that had
    # a steered cash target.
    execute("""
    INSERT INTO portfolio_target_plans
      (portfolio_id, view_id, classification_id, cash_target_weight, inserted_at, updated_at)
    SELECT pf.id, NULL::bigint, NULL::bigint, pf.cash_target_weight, NOW(), NOW()
    FROM portfolios pf
    WHERE pf.cash_target_weight IS NOT NULL
    """)

    # Every target now belongs to a plan: enforce NOT NULL (the FK already exists
    # from the nullable `add` above; `modify` would try to re-create it).
    execute(
      "ALTER TABLE portfolio_targets ALTER COLUMN plan_id SET NOT NULL",
      "ALTER TABLE portfolio_targets ALTER COLUMN plan_id DROP NOT NULL"
    )

    drop(unique_index(:portfolio_targets, [:portfolio_id, :category_id]))
    create(unique_index(:portfolio_targets, [:plan_id, :category_id]))
    create(index(:portfolio_targets, [:plan_id]))

    # The cash target now lives on the plan.
    alter table(:portfolios) do
      remove(:cash_target_weight)
    end
  end

  def down do
    # Restore the global cash-target column.
    alter table(:portfolios) do
      add(:cash_target_weight, :decimal)
    end

    # Carry the portfolio-wide cash target back from the Gesamt, classification-less
    # plan.
    execute("""
    UPDATE portfolios pf
    SET cash_target_weight = p.cash_target_weight
    FROM portfolio_target_plans p
    WHERE p.portfolio_id = pf.id
      AND p.view_id IS NULL
      AND p.classification_id IS NULL
    """)

    # Restore the original target uniqueness key.
    drop(index(:portfolio_targets, [:plan_id]))
    drop(unique_index(:portfolio_targets, [:plan_id, :category_id]))
    create(unique_index(:portfolio_targets, [:portfolio_id, :category_id]))

    # Drop the plan link. portfolio_id / classification_id are still on the target
    # rows, so the original shape is fully restored without re-deriving anything.
    alter table(:portfolio_targets) do
      remove(:plan_id)
    end

    execute("DROP INDEX IF EXISTS portfolio_target_plans_unique_index;")
    drop(table(:portfolio_target_plans))
  end
end
