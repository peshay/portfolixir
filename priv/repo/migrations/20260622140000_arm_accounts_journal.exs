defmodule Portfolixir.Repo.Migrations.ArmAccountsJournal do
  @moduledoc """
  Arms the `cash_accounts` and `securities_accounts` tables for the append-only
  audit journal (ADR-0017, FR-28), completing the Portfolios context after the
  `portfolios` slice (`arm_portfolios_journal`).

  Attaches the reusable `portfolixir_require_journal_actor` guard trigger
  (defined by the `create_audit_journal` migration) to every row-level write of
  both account tables. After this migration, any INSERT/UPDATE/DELETE not routed
  through `Portfolixir.Journal.record/3` (which sets the transaction-local
  `portfolixir.journal_actor` GUC) fails loudly.

  With these armed, every write the `Portfolios` context makes is journaled, so
  the context becomes fully actor-first.
  """
  use Ecto.Migration

  def up do
    for table <- ~w(cash_accounts securities_accounts) do
      execute("""
      CREATE TRIGGER #{table}_require_journal_actor
        BEFORE INSERT OR UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
      """)
    end
  end

  def down do
    for table <- ~w(cash_accounts securities_accounts) do
      execute("DROP TRIGGER IF EXISTS #{table}_require_journal_actor ON #{table};")
    end
  end
end
