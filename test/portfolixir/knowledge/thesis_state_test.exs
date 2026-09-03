defmodule Portfolixir.Knowledge.ThesisStateTest do
  # ADR-0044 §1 (issue #749): the thesis state is a projection over the log,
  # pure over the entries, rebuildable from them alone.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.Knowledge.ThesisState
  alias Portfolixir.WorldFixtures

  defp security!, do: WorldFixtures.create_security!(name: "Thesis Co.", ticker: "THES")

  defp append!(security, attrs) do
    base = %{
      security_id: security.id,
      author: "agent",
      kind: "evidence",
      body: "finding",
      source_quality: "primary",
      as_of: ~D[2026-08-01]
    }

    {:ok, note} = Knowledge.append_note(Actor.owner_ui(), Map.merge(base, attrs))
    note
  end

  # User story (ADR-0044 §1, the B4.1 fields):
  # As the operating agent (and the operator reading the detail pane),
  # I want the current thesis — text, status, conviction tier, invalidation
  # condition, time stop, last reviewed and by whom — derived from the log,
  # so that a status that flipped can always say why: the entry it derives
  # from is named, and a retraction is what flips it.
  #
  # Acceptance criteria:
  # - No thesis entry → status none, every field nil, last_reviewed from an
  #   invalidation_check if one exists.
  # - The newest unsuperseded thesis is current; its fields are carried.
  # - A thesis superseded by a newer thesis yields the newer one (intact).
  # - A thesis superseded by a retraction is retracted, naming the retraction.
  # - last_reviewed is the newest thesis or invalidation_check entry.
  test "an empty log projects to none" do
    assert %{status: :none, thesis: nil, derived_from_entry_id: nil, basis: basis} =
             ThesisState.project([])

    assert basis =~ "never stored"
  end

  test "the newest unsuperseded thesis is current and intact, carrying its fields" do
    security = security!()

    old =
      append!(security, %{
        kind: "thesis",
        body: "pricing power holds",
        conviction: "medium",
        as_of: ~D[2026-03-01]
      })

    new =
      append!(security, %{
        kind: "thesis",
        body: "pricing power holds and margins expand",
        conviction: "high",
        invalidation_condition: "gross margin below 40% for two quarters",
        time_stop: ~D[2027-03-01],
        as_of: ~D[2026-06-01],
        supersedes_id: old.id
      })

    check =
      append!(security, %{
        kind: "invalidation_check",
        body: "Q2: margin 43%, condition not met",
        as_of: ~D[2026-08-15],
        author: "operator"
      })

    state = Knowledge.thesis_state(security.id)

    assert state.status == :intact
    assert state.thesis == "pricing power holds and margins expand"
    assert state.conviction == :high
    assert state.invalidation_condition == "gross margin below 40% for two quarters"
    assert state.time_stop == ~D[2027-03-01]
    assert state.as_of == ~D[2026-06-01]
    assert state.derived_from_entry_id == new.id
    assert state.retracted_by_entry_id == nil
    assert state.last_reviewed_at == check.as_of
    assert state.last_reviewed_by == :operator
  end

  test "a thesis superseded by a retraction is retracted, naming the retraction" do
    security = security!()
    thesis = append!(security, %{kind: "thesis", body: "turnaround by 2027", conviction: "low"})

    retraction =
      append!(security, %{
        kind: "retraction",
        body: "management guided down twice; thesis withdrawn",
        supersedes_id: thesis.id,
        as_of: ~D[2026-08-20]
      })

    state = Knowledge.thesis_state(security.id)
    assert state.status == :retracted
    assert state.thesis == "turnaround by 2027"
    assert state.derived_from_entry_id == thesis.id
    assert state.retracted_by_entry_id == retraction.id
    # The retraction is not a review of the thesis; the thesis entry is the
    # last thing that stated the thesis' standing.
    assert state.last_reviewed_at == thesis.as_of
  end

  test "the projection is pure over the entries (same input, same output, any order)" do
    now = ~N[2026-08-01 10:00:00]

    a = %SecurityNote{
      id: 1,
      kind: :thesis,
      body: "A",
      as_of: ~D[2026-01-01],
      inserted_at: now,
      author: :agent
    }

    b = %SecurityNote{
      id: 2,
      kind: :thesis,
      body: "B",
      as_of: ~D[2026-02-01],
      inserted_at: now,
      author: :agent,
      supersedes_id: 1
    }

    assert ThesisState.project([a, b]) == ThesisState.project([b, a])
    assert ThesisState.project([a, b]).thesis == "B"
  end
end
