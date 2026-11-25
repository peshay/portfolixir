defmodule Portfolixir.Repo.Migrations.CreateDashboardSeeds do
  @moduledoc """
  Sprint 32 S3 (ADR-0062's amendment of 2026-11-25, point 5; I57): the
  seed table. One row per starter template a boot stored (or counted as
  stored, „Überblick“ on an instance that already held a dashboard), by
  its key, so a starter the operator deleted is never stored again. It
  holds no figure and names no dashboard: the starter, once stored, is a
  dashboard like any other.

  Armed with the journal-actor guard at creation: every record is
  journaled under the boot's system actor (`Portfolixir.Dashboards.Starters`).
  """
  use Ecto.Migration

  def up do
    create table(:dashboard_seeds, primary_key: false) do
      add(:template_key, :string, size: 40, primary_key: true)
      add(:seeded_at, :utc_datetime_usec, null: false)
    end

    create(
      constraint(:dashboard_seeds, :dashboard_seeds_template_key_check,
        check: "char_length(template_key) BETWEEN 1 AND 40"
      )
    )

    execute("""
    CREATE TRIGGER dashboard_seeds_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON dashboard_seeds
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS dashboard_seeds_require_journal_actor ON dashboard_seeds")
    drop(table(:dashboard_seeds))
  end
end
