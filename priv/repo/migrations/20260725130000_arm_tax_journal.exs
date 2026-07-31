defmodule Portfolixir.Repo.Migrations.ArmTaxJournal do
  @moduledoc """
  Arms `tax_parameters`, `tax_profiles` and `allowance_orders` for the
  append-only audit journal (ADR-0017, FR-28).

  Attaches the reusable `portfolixir_require_journal_actor` guard trigger
  (defined by the `create_audit_journal` migration) to every row-level write of
  the three tables. After this migration, any INSERT/UPDATE/DELETE not routed
  through `Portfolixir.Journal.record/3` fails loudly.

  `tax_parameters` is armed deliberately, and that is the point ADR-0031 makes
  load-bearing: a statutory-rate edit silently changes every consistency
  finding for that year, so it has to be as traceable as the transcribed
  numbers themselves.
  """
  use Ecto.Migration

  def up do
    for table <- ~w(tax_parameters tax_profiles allowance_orders) do
      execute("""
      CREATE TRIGGER #{table}_require_journal_actor
        BEFORE INSERT OR UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
      """)
    end
  end

  def down do
    for table <- ~w(tax_parameters tax_profiles allowance_orders) do
      execute("DROP TRIGGER IF EXISTS #{table}_require_journal_actor ON #{table};")
    end
  end
end
