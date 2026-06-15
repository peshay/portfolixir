defmodule Portfolixir.Repo.Migrations.ArmSecuritiesJournal do
  @moduledoc """
  Arms the `securities` table for the append-only audit journal (ADR-0017,
  FR-28), first slice of the leaf-first rollout (Catalog/Fx).

  Attaches the reusable `portfolixir_require_journal_actor` guard trigger
  (defined by the `create_audit_journal` migration) to every row-level write of
  `securities`. After this migration, any INSERT/UPDATE/DELETE that does not set
  the transaction-local `portfolixir.journal_actor` GUC — i.e. any write not
  routed through `Portfolixir.Journal.record/3` — fails loudly.

  `security_quotes` and `exchange_rates` stay deliberately un-armed: they are
  market-data ingestion tables on `Portfolixir.Journal.Allowlist`.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE TRIGGER securities_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON securities
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS securities_require_journal_actor ON securities;")
  end
end
