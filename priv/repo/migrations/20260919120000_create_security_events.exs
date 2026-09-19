defmodule Portfolixir.Repo.Migrations.CreateSecurityEvents do
  @moduledoc """
  ADR-0048 §§1-6: **security events** — dated calendar facts about a security
  that book nothing.

  Four properties are enforced here, at the database, not only in the context:

  1. **The catalog, not the holdings** (§2): the table keys on `security_id`
     and **nothing else** — no portfolio, no depot, no view. The default scope
     of every read is therefore every security the catalog holds, which is the
     requirement rather than a query detail: a calendar derived from the
     position list cannot hold a date for a security not yet owned, and that
     is exactly how a purchase candidate's reporting date became invisible.
  2. **Closed sets** (§6): `kind`, `timing` and `source_quality` are
     CHECK-constrained to the values the schema module resolves with
     `String.to_existing_atom/1`. `source_quality` reuses ADR-0044's
     vocabulary exactly — one scale for "how well do we know this" across the
     two knowledge families.
  3. **Journaled from the first migration** (§4, the ADR-0044 precedent, and
     non-negotiable here because an agent writes these rows): the
     journal-actor guard trigger is attached in the same migration that
     creates the table. Unlike the research log this table is **mutable** —
     a rescheduled earnings call does not make the old date a second fact, it
     makes it wrong — so its change history lives in the append-only audit
     journal, which is where change histories already live.
  4. **A guess is never stored as a filing** (§3): `timing` qualifies the
     date, and a `window` event must carry a `date_end` at or after `date`
     while every other timing must not carry one at all.

  Deliberately absent: any `Decimal` column. An event carries no money (§6);
  an expected dividend amount would turn a calendar into a forecast and is a
  separate decision. `machine_generated` is reserved and unused (NFR-10), the
  same way ADR-0044 reserves it, and an event carrying it must carry its
  source.
  """
  use Ecto.Migration

  def up do
    create table(:security_events) do
      add(:security_id, references(:securities, on_delete: :restrict), null: false)
      add(:kind, :string, null: false)
      add(:date, :date, null: false)
      add(:date_end, :date)
      add(:timing, :string, null: false)
      add(:confirmed, :boolean, null: false, default: false)
      add(:source_url, :string)
      add(:source_quality, :string, null: false)
      # A DATE, not a timestamp: the day the fact was last re-read against its
      # source. The staleness read asks "older than N days".
      add(:checked_at, :date)
      add(:note, :text)
      add(:machine_generated, :boolean, null: false, default: false)

      timestamps()
    end

    create(index(:security_events, [:security_id, :date]))
    create(index(:security_events, [:date]))
    create(index(:security_events, [:kind]))
    create(index(:security_events, [:confirmed]))
    create(index(:security_events, [:checked_at]))

    # Mirrors the closed sets in Portfolixir.Knowledge.SecurityEvent exactly.
    create(
      constraint(:security_events, :security_events_kind_check,
        check:
          "kind IN ('earnings', 'ex_dividend', 'dividend_payment', 'lockup_expiry', " <>
            "'index_review', 'shareholder_meeting', 'regulatory_decision', 'guidance_update')"
      )
    )

    create(
      constraint(:security_events, :security_events_timing_check,
        check: "timing IN ('exact', 'estimated', 'window', 'month')"
      )
    )

    create(
      constraint(:security_events, :security_events_source_quality_check,
        check: "source_quality IN ('primary', 'secondary_multi', 'awareness', 'unverified')"
      )
    )

    # §3: only a window has a range, and it never runs backwards.
    create(
      constraint(:security_events, :security_events_window_end_check,
        check:
          "(timing = 'window' AND date_end IS NOT NULL AND date_end >= date) " <>
            "OR (timing <> 'window' AND date_end IS NULL)"
      )
    )

    # §6 / NFR-10: an extracted event is a proposal carrying its source.
    create(
      constraint(:security_events, :security_events_machine_generated_source_check,
        check: "machine_generated = false OR source_url IS NOT NULL"
      )
    )

    # §4: journal-armed at creation (ADR-0017 pattern, the same guard function
    # the other armed tables use). Unlike security_notes this table admits
    # UPDATE and DELETE, which is precisely why the guard matters on all three.
    execute("""
    CREATE TRIGGER security_events_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON security_events
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS security_events_require_journal_actor ON security_events;")
    drop(table(:security_events))
  end
end
