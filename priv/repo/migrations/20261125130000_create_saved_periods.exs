defmodule Portfolixir.Repo.Migrations.CreateSavedPeriods do
  @moduledoc """
  ADR-0062's amendment of 2026-11-25, point 6 (Sprint 32 T2): `saved_periods`,
  the operator's own periods — a `name`, a first day `starts_on`, a last day
  `ends_on` or none ("until today"), and the `lock_version` a replace
  carries. A period holds no figure: no foreign key, no money, nothing the
  ledger reads; a pin names one by reference inside a dashboard's layout.

  **Bounds:** the name 1 to 40 characters (trimmed, one line, in the
  context, `Portfolixir.Periods.SavedPeriod`); the first day on or before
  the last; the lock_version 1 or more. At most 50 periods is the
  context's, under a lock, since no row constraint can count rows.

  **The journal:** every write is journaled under its actor, and the table
  is armed with the journal-actor guard at creation.
  """
  use Ecto.Migration

  def up do
    create table(:saved_periods) do
      add(:name, :string, size: 40, null: false)
      add(:starts_on, :date, null: false)
      add(:ends_on, :date)
      add(:lock_version, :integer, null: false, default: 1)

      timestamps(type: :utc_datetime_usec)
    end

    check(:name, "char_length(name) BETWEEN 1 AND 40")
    check(:span, "ends_on IS NULL OR starts_on <= ends_on")
    check(:lock_version, "lock_version >= 1")

    execute("""
    CREATE TRIGGER saved_periods_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON saved_periods
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS saved_periods_require_journal_actor ON saved_periods")
    drop(table(:saved_periods))
  end

  defp check(name, expression) do
    create(constraint(:saved_periods, :"saved_periods_#{name}_check", check: expression))
  end
end
