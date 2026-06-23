defmodule Portfolixir.Repo.Migrations.ArmClassificationsJournal do
  @moduledoc """
  Arms the `classifications` and `classification_categories` tables for the
  append-only audit journal (ADR-0017, FR-28), Classifications slice (stage 1).

  Attaches the reusable `portfolixir_require_journal_actor` guard trigger
  (defined by the `create_audit_journal` migration) to every row-level write of
  both tables. After this migration, any INSERT/UPDATE/DELETE not routed through
  `Portfolixir.Journal.record/3` fails loudly.

  Custom classification/category CRUD and recolor are now actor-first; the
  built-in tree seeding writes under a fixed `system_job` actor (it only writes
  on genuine first creation, guarded by a `get_by` check, so reads do not write).

  The `security_category_assignments` table is armed in stage 2 (assign/unassign,
  including the bulk paths).
  """
  use Ecto.Migration

  def up do
    for table <- ~w(classifications classification_categories) do
      execute("""
      CREATE TRIGGER #{table}_require_journal_actor
        BEFORE INSERT OR UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
      """)
    end
  end

  def down do
    for table <- ~w(classifications classification_categories) do
      execute("DROP TRIGGER IF EXISTS #{table}_require_journal_actor ON #{table};")
    end
  end
end
