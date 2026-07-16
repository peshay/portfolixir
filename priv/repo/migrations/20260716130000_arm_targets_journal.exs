defmodule Portfolixir.Repo.Migrations.ArmTargetsJournal do
  @moduledoc """
  Arms the `portfolio_target_plans` and `portfolio_targets` tables for the
  append-only audit journal (ADR-0017, FR-28) — the last unjournaled write
  path, closing the leaf-first rollout together with the plan-versioning
  feature (ADR-0027) that adds new write paths to these tables.

  Attaches the reusable `portfolixir_require_journal_actor` guard trigger
  (defined by the `create_audit_journal` migration) to every row-level write of
  both tables. After this migration, any INSERT/UPDATE/DELETE not routed
  through `Portfolixir.Journal.record/3` fails loudly. Cascaded deletes
  (portfolio/view/classification removal, plan removal cascading its targets)
  run inside their initiating context's journaled transaction, so the actor is
  set when the cascade fires.
  """
  use Ecto.Migration

  def up do
    for table <- ~w(portfolio_target_plans portfolio_targets) do
      execute("""
      CREATE TRIGGER #{table}_require_journal_actor
        BEFORE INSERT OR UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
      """)
    end
  end

  def down do
    for table <- ~w(portfolio_target_plans portfolio_targets) do
      execute("DROP TRIGGER IF EXISTS #{table}_require_journal_actor ON #{table};")
    end
  end
end
