defmodule Portfolixir.Repo.Migrations.AddPlanVersioning do
  @moduledoc """
  Plan versioning (ADR-0027): target plans become named entities with a
  lifecycle status (`active` / `draft` / `archived`).

  The ADR-0020 invariant "at most one plan per (portfolio, view,
  classification)" tightens to "at most one **active** plan" — drafts and
  archived plans coexist freely in the same scope, which is what makes
  duplicate-to-edit possible. The migration is loss-free: every existing plan
  becomes the `active` plan of its scope under a default name, so nothing
  changes for existing data.
  """
  use Ecto.Migration

  def up do
    alter table(:portfolio_target_plans) do
      add(:name, :string, null: false, default: "Plan")
      add(:status, :string, null: false, default: "active")
    end

    create(
      constraint(:portfolio_target_plans, :portfolio_target_plans_status_check,
        check: "status IN ('active', 'draft', 'archived')"
      )
    )

    # Uniqueness moves from "one plan per scope" to "one ACTIVE plan per scope".
    execute("DROP INDEX portfolio_target_plans_unique_index;")

    execute("""
    CREATE UNIQUE INDEX portfolio_target_plans_active_unique_index
      ON portfolio_target_plans (portfolio_id, view_id, classification_id)
      NULLS NOT DISTINCT
      WHERE status = 'active';
    """)
  end

  def down do
    # Rolling back the feature removes draft/archived plans (and their targets
    # via the plan_id cascade) — the pre-versioning schema can only hold one
    # plan per scope. Active plans, the only ones pre-versioning code ever saw,
    # are preserved. The targets-journal arm migration sorts after this one, so
    # its down has already dropped the guard triggers when this runs.
    execute("""
    DELETE FROM portfolio_target_plans WHERE status <> 'active';
    """)

    execute("DROP INDEX portfolio_target_plans_active_unique_index;")

    execute("""
    CREATE UNIQUE INDEX portfolio_target_plans_unique_index
      ON portfolio_target_plans (portfolio_id, view_id, classification_id)
      NULLS NOT DISTINCT;
    """)

    drop(constraint(:portfolio_target_plans, :portfolio_target_plans_status_check))

    alter table(:portfolio_target_plans) do
      remove(:name)
      remove(:status)
    end
  end
end
