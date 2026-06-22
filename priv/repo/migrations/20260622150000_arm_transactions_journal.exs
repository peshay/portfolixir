defmodule Portfolixir.Repo.Migrations.ArmTransactionsJournal do
  @moduledoc """
  Arms the `transactions` table for the append-only audit journal (ADR-0017,
  FR-28) — the ledger crown jewel. Every booking (manual or imported) is now an
  attributable, reversible-by-inspection record, which is the safety net FR-14
  requires before an agent gets write grants.

  Attaches the reusable `portfolixir_require_journal_actor` guard trigger
  (defined by the `create_audit_journal` migration) to every row-level write of
  `transactions`. After this migration, any INSERT/UPDATE/DELETE not routed
  through `Portfolixir.Journal.record/3` fails loudly — including the import
  applier, which now journals each inserted booking under an import actor.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE TRIGGER transactions_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON transactions
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS transactions_require_journal_actor ON transactions;")
  end
end
