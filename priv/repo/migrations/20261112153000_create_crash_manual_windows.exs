defmodule Portfolixir.Repo.Migrations.CreateCrashManualWindows do
  @moduledoc """
  ADR-0058 §4 (Sprint 29, C3): `crash_manual_windows`, the crash windows a
  person draws: a span the rule folds into a longer window, or does not
  give at all. Unlike a detected window (§2, derived at read), a manual one
  is stored, with the dates its author chose, and read back as
  `m:<id>` with `kind: "manual"`, so every reader can weigh that its dates
  were chosen, maybe with the outcome in view.

  **Checks:** the name 1 to 80 characters (§4; ADR-0054 §4's text rules in
  the context, `Portfolixir.Crashes.ManualWindow`); `start` before
  `trough`; the author `operator` or `agent` (ADR-0054 §1, derived from
  the credential); `updated_at` never before `created_at`. That neither
  date lies in the future is the context's to check: it depends on the
  day of the write, which no CHECK may read.

  **No uniqueness and no exclusion:** manual windows may overlap a detected
  window and one another (§4, the owner's answer of 2026-11-07).

  **The journal:** every write is journaled under its actor, and the table
  is armed with the journal-actor guard.
  """
  use Ecto.Migration

  def up do
    create table(:crash_manual_windows) do
      add(:name, :string, size: 80, null: false)
      add(:start, :date, null: false)
      add(:trough, :date, null: false)
      add(:author, :string, null: false)
      add(:actor, :string)

      timestamps(inserted_at: :created_at, type: :utc_datetime_usec)
    end

    check(:name, "char_length(name) BETWEEN 1 AND 80")
    check(:dates, "start < trough")
    check(:author, "author IN ('operator', 'agent')")
    check(:updated_at, "updated_at >= created_at")

    execute("""
    CREATE TRIGGER crash_manual_windows_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON crash_manual_windows
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute(
      "DROP TRIGGER IF EXISTS crash_manual_windows_require_journal_actor ON crash_manual_windows"
    )

    drop(table(:crash_manual_windows))
  end

  defp check(name, expression) do
    create(
      constraint(:crash_manual_windows, :"crash_manual_windows_#{name}_check", check: expression)
    )
  end
end
