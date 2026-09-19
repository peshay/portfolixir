defmodule Portfolixir.Knowledge.EventsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Journal.Entry, as: JournalEntry
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Knowledge.SecurityEvent

  @today ~D[2026-09-19]

  defp journal_count, do: Repo.aggregate(JournalEntry, :count, :id)

  defp event!(security, attrs) do
    {:ok, event} =
      Events.create_event(
        Actor.owner_ui(),
        Enum.into(attrs, %{
          security_id: security.id,
          kind: "earnings",
          date: @today,
          timing: "exact",
          source_quality: "primary"
        })
      )

    event
  end

  # User story (FR-44, ADR-0048 §1, §3, §6):
  # As the operator's agent tracking a purchase candidate,
  # I want a dated calendar fact about a security that books nothing,
  # so that a reporting date I must not miss has somewhere to live even
  # before I own the security.
  #
  # Acceptance criteria:
  # - An event is stored against a security with its kind, date, timing
  #   qualifier, source quality and note; it carries no money.
  # - The write is journaled (the table is guard-armed in its first
  #   migration), so an agent's write is auditable.
  test "records a security event against a security, journaled" do
    security = create_security!(name: "Event Co", ticker: "EVC")

    before = journal_count()

    {:ok, event} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-11-04],
        timing: "exact",
        confirmed: true,
        source_url: "https://example.invalid/ir/calendar",
        source_quality: "primary",
        checked_at: @today,
        note: "Q3 report, confirmed on the IR page"
      })

    assert event.security_id == security.id
    assert event.kind == :earnings
    assert event.timing == :exact
    assert event.source_quality == :primary
    assert event.confirmed
    assert event.machine_generated == false
    assert journal_count() == before + 1
  end

  # Acceptance criteria (ADR-0048 §6):
  # - The closed sets are closed: an unknown kind, timing or source quality is
  #   a plain changeset error, and no atom is created from the input.
  test "an unknown closed-set value is refused without creating an atom" do
    security = create_security!(name: "Closed Co", ticker: "CLS")

    for {field, value} <- [kind: "rumour", timing: "soonish", source_quality: "vibes"] do
      {:error, changeset} =
        Events.create_event(
          Actor.owner_ui(),
          Map.merge(
            %{
              security_id: security.id,
              kind: "earnings",
              date: @today,
              timing: "exact",
              source_quality: "primary"
            },
            %{field => value}
          )
        )

      assert %{^field => ["is invalid"]} = errors_on(changeset)
    end

    # The refusal happens before any atom is created: the strings are still
    # unknown to the atom table (`String.to_atom/1` is forbidden, AGENTS.md).
    for value <- ["rumour_kind_never_seen", "soonish_timing_never_seen"] do
      assert_raise ArgumentError, fn -> String.to_existing_atom(value) end
    end

    refute "rumour" in SecurityEvent.kinds()
    refute "soonish" in SecurityEvent.timings()
  end

  # User story (ADR-0048 §3):
  # As the operator recording "earnings expected late February",
  # I want a guess stored as a guess,
  # so that an estimate is never indistinguishable from a filing.
  #
  # Acceptance criteria:
  # - A `window` event requires `date_end` and refuses one before `date`.
  # - `date_end` is refused on a timing that has no range.
  test "a window event carries its end, and only a window event may" do
    security = create_security!(name: "Window Co", ticker: "WND")

    {:ok, event} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-02-20],
        date_end: ~D[2026-02-28],
        timing: "window",
        source_quality: "secondary_multi"
      })

    assert event.date_end == ~D[2026-02-28]

    {:error, missing} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-02-20],
        timing: "window",
        source_quality: "awareness"
      })

    assert %{date_end: [_ | _]} = errors_on(missing)

    {:error, inverted} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-02-20],
        date_end: ~D[2026-02-01],
        timing: "window",
        source_quality: "awareness"
      })

    assert %{date_end: [_ | _]} = errors_on(inverted)

    {:error, stray} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-02-20],
        date_end: ~D[2026-02-28],
        timing: "exact",
        source_quality: "awareness"
      })

    assert %{date_end: [_ | _]} = errors_on(stray)
  end

  # Acceptance criteria (ADR-0048 §4):
  # - An event is MUTABLE: a rescheduled date replaces the old one rather
  #   than adding a second row, and the change history is in the journal.
  test "a rescheduled event is one row updated, with the change in the journal" do
    security = create_security!(name: "Moved Co", ticker: "MVD")
    event = event!(security, date: ~D[2026-11-04])

    before = journal_count()

    {:ok, moved} =
      Events.update_event(Actor.owner_ui(), event, %{date: ~D[2026-11-11], confirmed: true})

    assert moved.id == event.id
    assert moved.date == ~D[2026-11-11]
    assert Events.count_events() == 1
    assert journal_count() == before + 1
  end

  # Acceptance criteria (ADR-0048 §4):
  # - A deletion is journaled too, so nothing is lost by removing a duplicate.
  test "deleting an event is journaled" do
    security = create_security!(name: "Gone Co", ticker: "GNE")
    event = event!(security, [])

    before = journal_count()
    {:ok, _deleted} = Events.delete_event(Actor.owner_ui(), event)

    assert Events.count_events() == 0
    assert journal_count() == before + 1
  end

  # User story (ADR-0048 §5.1):
  # As the operator reading one security,
  # I want all of its events, past and future,
  # so that the calendar of that instrument is one list.
  #
  # Acceptance criteria:
  # - Events of one security come back soonest-relevant first and no other
  #   security's events appear.
  test "lists one security's events" do
    a = create_security!(name: "List A", ticker: "LSA")
    b = create_security!(name: "List B", ticker: "LSB")

    event!(a, date: ~D[2026-12-01])
    event!(a, date: ~D[2026-10-01], kind: "ex_dividend")
    event!(b, date: ~D[2026-11-01])

    dates = a.id |> Events.list_for_security() |> Enum.map(& &1.date)
    assert dates == [~D[2026-10-01], ~D[2026-12-01]]
  end

  # User story (ADR-0048 §2, §5.2 — the read the agent is missing):
  # As the operator's agent,
  # I want the dates due in the next N days across the WHOLE CATALOG,
  # so that a purchase candidate I do not yet own cannot have an invisible
  # reporting date.
  #
  # Acceptance criteria:
  # - The default scope is every security in the catalog, held or not.
  # - `held_only: true` narrows it; it is never the default.
  # - A `window` or `month` event is due when ANY day it could fall on is
  #   inside the horizon.
  test "upcoming covers the whole catalog by default and resolves a range conservatively" do
    world = base_world(name: "Upcoming World", cash_name: "UW Cash", depot_name: "UW Depot")
    held = create_security!(name: "Held Co", ticker: "HLD")
    candidate = create_security!(name: "Candidate Co", ticker: "CND")
    buy!(world, held, quantity: "1", price: "100", date: ~D[2026-01-05])

    event!(held, date: ~D[2026-09-25])
    event!(candidate, date: ~D[2026-09-24])
    # A month event whose stored day is outside the horizon but whose month
    # reaches into it.
    event!(candidate, date: ~D[2026-09-30], timing: "month", kind: "guidance_update")
    # A window that opened before today and has not closed.
    event!(candidate,
      date: ~D[2026-09-10],
      date_end: ~D[2026-09-21],
      timing: "window",
      kind: "index_review"
    )

    # Outside the horizon entirely.
    event!(candidate, date: ~D[2026-12-31], kind: "lockup_expiry")

    upcoming = Events.upcoming(days: 7, today: @today)
    assert length(upcoming) == 4
    assert Enum.any?(upcoming, &(&1.security_id == candidate.id))

    held_only = Events.upcoming(days: 7, today: @today, held_only: true)
    assert Enum.map(held_only, & &1.security_id) == [held.id]

    filtered = Events.upcoming(days: 7, today: @today, kind: "earnings")
    assert length(filtered) == 2
  end

  # User story (ADR-0048 §5.3):
  # As the operator,
  # I want the events whose date has passed and that nobody confirmed,
  # so that the calendar cannot quietly rot.
  #
  # Acceptance criteria:
  # - Only unconfirmed events whose whole span is in the past are listed.
  test "unconfirmed lists the events whose date has passed and that nobody confirmed" do
    security = create_security!(name: "Rot Co", ticker: "ROT")

    past = event!(security, date: ~D[2026-09-01])
    event!(security, date: ~D[2026-09-02], confirmed: true)
    event!(security, date: ~D[2026-10-01])

    assert security.id && Enum.map(Events.unconfirmed_past(today: @today), & &1.id) == [past.id]
  end

  # User story (ADR-0048 §5.4):
  # As the operator,
  # I want the events nobody has re-read in N days,
  # so that the staleness of the CALENDAR is visible, distinct from a date
  # that has passed.
  #
  # Acceptance criteria:
  # - Events whose `checked_at` is older than N days are listed, oldest first,
  #   and one that was never checked is listed too with a null age.
  test "stale lists the events nobody re-read, never-checked ones included" do
    security = create_security!(name: "Stale Co", ticker: "STL")

    old = event!(security, checked_at: ~D[2026-01-01], date: ~D[2026-12-01])
    never = event!(security, date: ~D[2026-12-02])
    event!(security, checked_at: @today, date: ~D[2026-12-03])

    rows = Events.stale(days: 30, today: @today)
    assert Enum.map(rows, & &1.id) == [never.id, old.id]
    assert Enum.find(rows, &(&1.id == never.id)).days_since_checked == nil

    assert Enum.find(rows, &(&1.id == old.id)).days_since_checked ==
             Date.diff(@today, ~D[2026-01-01])
  end

  # Acceptance criteria (ADR-0048 §6, NFR-10):
  # - `machine_generated` is reserved: an extracted event would be a proposal
  #   carrying its source, and a machine-generated event without one is
  #   refused.
  test "a machine-generated event must carry its source" do
    security = create_security!(name: "Machine Co", ticker: "MCH")

    {:error, changeset} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: security.id,
        kind: "earnings",
        date: @today,
        timing: "exact",
        source_quality: "unverified",
        machine_generated: true
      })

    assert %{source_url: [_ | _]} = errors_on(changeset)
  end

  # Acceptance criteria (ADR-0048 §6):
  # - `source_url` is rendered as an anchor and handed to an agent: only
  #   http(s), never javascript: or a bare path.
  test "a source url must be http(s)" do
    security = create_security!(name: "Link Co", ticker: "LNK")

    {:error, changeset} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: security.id,
        kind: "earnings",
        date: @today,
        timing: "exact",
        source_quality: "unverified",
        source_url: "javascript:alert(1)"
      })

    assert %{source_url: [_ | _]} = errors_on(changeset)
  end
end
