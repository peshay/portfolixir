defmodule Portfolixir.Repo.Migrations.ArmPortfoliosJournal do
  @moduledoc """
  Arms the `portfolios` table for the append-only audit journal (ADR-0017,
  FR-28), continuing the leaf-first rollout after the Catalog/Fx slice
  (`arm_securities_journal`).

  Attaches the reusable `portfolixir_require_journal_actor` guard trigger
  (defined by the `create_audit_journal` migration) to every row-level write of
  `portfolios`. After this migration, any INSERT/UPDATE/DELETE that does not set
  the transaction-local `portfolixir.journal_actor` GUC — i.e. any write not
  routed through `Portfolixir.Journal.record/3` — fails loudly.

  `cash_accounts` and `securities_accounts` are armed in their own follow-up
  slices; `security_quotes`/`exchange_rates` stay deliberately un-armed
  (market-data ingestion, `Portfolixir.Journal.Allowlist`).
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE TRIGGER portfolios_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON portfolios
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS portfolios_require_journal_actor ON portfolios;")
  end
end
