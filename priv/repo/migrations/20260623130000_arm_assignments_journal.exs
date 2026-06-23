defmodule Portfolixir.Repo.Migrations.ArmAssignmentsJournal do
  @moduledoc """
  Arms the `security_category_assignments` table for the append-only audit
  journal (ADR-0017, FR-28), completing the Classifications context (stage 2).

  Attaches the reusable `portfolixir_require_journal_actor` guard trigger
  (defined by the `create_audit_journal` migration) to every row-level write of
  the table. After this migration, any INSERT/UPDATE/DELETE not routed through
  `Portfolixir.Journal.record/3` fails loudly — including the bulk
  assign/unassign paths, which now journal one entry per affected security.

  With this armed, every write the `Classifications` context makes is journaled.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE TRIGGER security_category_assignments_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON security_category_assignments
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute(
      "DROP TRIGGER IF EXISTS security_category_assignments_require_journal_actor ON security_category_assignments;"
    )
  end
end
