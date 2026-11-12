defmodule Portfolixir.Repo.Migrations.CreateCrashWindowNames do
  @moduledoc """
  ADR-0058 §3 (Sprint 29, C3): `crash_window_names`, the names the operator
  or an agent gives detected crash windows. A detected window is derived at
  read and never stored (§2); only its name is, keyed as the read keys the
  window: the crash benchmark's security id and the window's start (its
  peak date), `d:<benchmark_security_id>:<start>`.

  **Unique:** one name per key. **Checks:** the id positive, the name 1 to
  80 characters (§4's rule, ADR-0054 §4's text rules in the context,
  `Portfolixir.Crashes.WindowName`), `updated_at` never before `created_at`.

  **No foreign key onto the benchmark security.** A name stays with the
  benchmark it was given for (§3): switching the benchmark hides it, and
  switching back restores it. A key that restricted would keep a security
  from being merged or deleted for the sake of a label; one that cascaded,
  nulled or followed a merge would delete a name or move it onto another
  series by a guess, which §3 forbids. A name whose benchmark is gone reads
  under `unmatched_names` with its stored key.

  **The journal:** every write is journaled under its actor, and the table
  is armed with the journal-actor guard.
  """
  use Ecto.Migration

  def up do
    create table(:crash_window_names) do
      add(:benchmark_security_id, :bigint, null: false)
      add(:start, :date, null: false)
      add(:name, :string, size: 80, null: false)

      timestamps(inserted_at: :created_at, type: :utc_datetime_usec)
    end

    create(
      unique_index(:crash_window_names, [:benchmark_security_id, :start],
        name: :crash_window_names_key_index
      )
    )

    check(:benchmark_security_id, "benchmark_security_id > 0")
    check(:name, "char_length(name) BETWEEN 1 AND 80")
    check(:updated_at, "updated_at >= created_at")

    execute("""
    CREATE TRIGGER crash_window_names_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON crash_window_names
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute(
      "DROP TRIGGER IF EXISTS crash_window_names_require_journal_actor ON crash_window_names"
    )

    drop(table(:crash_window_names))
  end

  defp check(name, expression) do
    create(
      constraint(:crash_window_names, :"crash_window_names_#{name}_check", check: expression)
    )
  end
end
