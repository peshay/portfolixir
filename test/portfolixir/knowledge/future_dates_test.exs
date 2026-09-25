defmodule Portfolixir.Knowledge.FutureDatesTest do
  # E25 S6 (#891), F44 and G09: a research-log entry states what held on its
  # as_of day, and an event's checked_at is the day its source was re-read.
  # Neither can lie in the future: a future as_of on an append-only log could
  # never be removed and would keep a position off the review-hygiene read,
  # and a future checked_at hid an event from the stale-calendar read.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.WorldFixtures

  @today ~D[2026-03-10]

  defp owner, do: Actor.owner_ui()

  defp note_attrs(security, attrs) do
    Map.merge(
      %{
        security_id: security.id,
        author: "operator",
        kind: "invalidation_check",
        body: "Order book re-read; the condition is not met.",
        source_quality: "primary",
        as_of: @today
      },
      attrs
    )
  end

  defp event_attrs(security, attrs) do
    Map.merge(
      %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-04-20],
        timing: "estimated",
        source_quality: "awareness"
      },
      attrs
    )
  end

  # User story:
  # As the operator keeping a research log that is never edited,
  # I want an entry dated after today refused,
  # so that a typo in the year cannot become a permanent entry that keeps a
  # position off the review list.
  #
  # Acceptance criteria:
  # - An as_of after today is refused on as_of, and nothing is stored.
  # - Today is accepted, and valid_until and time_stop may lie in the future.
  test "a future as_of is refused; today and future blocks are accepted" do
    security = WorldFixtures.create_security!(name: "Harbour Crane Works", ticker: "HCW")

    assert {:error, changeset} =
             Knowledge.append_note(
               owner(),
               note_attrs(security, %{as_of: Date.add(@today, 1)}),
               today: @today
             )

    assert %{as_of: ["must not be in the future"]} = errors_on(changeset)
    assert Knowledge.list_notes(security.id) == []

    assert {:ok, _note} =
             Knowledge.append_note(
               owner(),
               note_attrs(security, %{
                 kind: "thesis",
                 valid_until: ~D[2027-12-31],
                 time_stop: ~D[2028-06-30]
               }),
               today: @today
             )
  end

  # User story:
  # As the operator reading the review-hygiene list,
  # I want an entry stored with a future as_of before the refusal existed to
  # count as reviewed no later than the day it was written,
  # so that it cannot hide a held position from the list indefinitely.
  #
  # Acceptance criteria:
  # - The unreviewed read and the thesis state's last review take such an
  #   entry's date as the day it was written (one day of zone slack), while
  #   the entry itself keeps its as_of.
  test "a stored future entry cannot hide an unreviewed position" do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!(name: "Quayside Logistics", ticker: "QSL")
    WorldFixtures.buy!(world, security, date: ~D[2025-01-02])

    written_on = Date.utc_today()

    # An entry from before the refusal: stored with a far-future as_of.
    assert {:ok, stored} =
             Knowledge.append_note(
               owner(),
               note_attrs(security, %{kind: "thesis", as_of: ~D[2099-01-01]}),
               today: ~D[2099-01-01]
             )

    assert stored.as_of == ~D[2099-01-01]

    later = Date.add(written_on, 120)
    rows = Knowledge.unreviewed_positions(days: 90, today: later)

    assert [%{security: %{id: id}, last_entry_as_of: reviewed}] =
             Enum.filter(rows, &(&1.security.id == security.id))

    assert id == security.id
    assert reviewed == Date.add(written_on, 1)

    state = Knowledge.thesis_state(security.id)
    assert state.last_reviewed_at == Date.add(written_on, 1)
    assert state.as_of == ~D[2099-01-01]
  end

  # User story:
  # As the operator trusting the stale-calendar read,
  # I want an event's checked_at no later than tomorrow,
  # so that a checked_at in the future cannot hide an event from the read.
  #
  # Acceptance criteria:
  # - A checked_at later than today plus one day of zone slack is refused on
  #   create and on update, and nothing is written.
  # - Today and tomorrow are accepted.
  # - An event stored with a later checked_at is listed by the stale read.
  test "an event's checked_at past tomorrow is refused on create and update" do
    security = WorldFixtures.create_security!(name: "Tidewater Power", ticker: "TWP")
    too_late = Date.add(@today, 2)

    assert {:error, changeset} =
             Events.create_event(owner(), event_attrs(security, %{checked_at: too_late}),
               today: @today
             )

    assert %{checked_at: ["must not be later than tomorrow"]} = errors_on(changeset)

    assert {:ok, event} =
             Events.create_event(owner(), event_attrs(security, %{checked_at: @today}),
               today: @today
             )

    assert {:error, changeset} =
             Events.update_event(owner(), event, %{checked_at: too_late}, today: @today)

    assert %{checked_at: [_]} = errors_on(changeset)
    assert Events.get_event(event.id).checked_at == @today

    assert {:ok, updated} =
             Events.update_event(owner(), event, %{checked_at: Date.add(@today, 1)},
               today: @today
             )

    assert updated.checked_at == Date.add(@today, 1)

    # One stored before the refusal existed is no re-read: the stale read
    # lists it rather than hiding it until that date.
    assert {:ok, hidden} =
             Events.create_event(owner(), event_attrs(security, %{checked_at: ~D[2099-01-01]}),
               today: ~D[2099-01-01]
             )

    assert hidden.id in Enum.map(Events.stale(today: @today), & &1.id)
    refute event.id in Enum.map(Events.stale(today: @today), & &1.id)
  end
end
