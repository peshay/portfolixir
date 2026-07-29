defmodule Portfolixir.Repo.Migrations.ArmTaxSnapshotsJournal do
  @moduledoc """
  Arms `tax_statement_snapshots` for the append-only audit journal (ADR-0017,
  FR-28), on the same terms as the tax configuration tables armed by
  `20260725130000`.

  A recorded statement is the authority a trim decision is sized against, so
  who transcribed it and when has to be as traceable as the numbers themselves.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE TRIGGER tax_statement_snapshots_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON tax_statement_snapshots
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute(
      "DROP TRIGGER IF EXISTS tax_statement_snapshots_require_journal_actor ON tax_statement_snapshots;"
    )
  end
end
