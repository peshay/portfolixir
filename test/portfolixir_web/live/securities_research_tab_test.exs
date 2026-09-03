defmodule PortfolixirWeb.SecuritiesResearchTabTest do
  # ADR-0044 §6 (issue #751), one of the three clauses the owner signed: the
  # research timeline lands on the security detail pane in the same batch as
  # the log itself.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Knowledge
  alias Portfolixir.WorldFixtures

  defp security!, do: WorldFixtures.create_security!(name: "Timeline Co.", ticker: "TMLN")

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

  # User story (ADR-0044 §6, issue #751):
  # As a local portfolio maintainer opening a security,
  # I want a Research tab on the detail pane showing the derived thesis state
  # on top and the log newest first — kind and source quality visible,
  # superseded entries shown as superseded, retractions legible as such,
  # so that what the agent believed, and when it was wrong, is readable on
  # the same screen as the position.
  #
  # Acceptance criteria:
  # - The pane's second-level tab row carries "Research"; ?tab=research
  #   selects it.
  # - The thesis-state block states the status; a retracted thesis names the
  #   retraction and its reason.
  # - Entries render newest first with kind, source quality, as_of and
  #   author; a superseded entry stays in the list marked superseded; a
  #   retraction is marked as retracting its target.
  # - Nothing on the surface edits or removes an entry.
  test "the research tab shows the thesis state and the timeline, superseded and retracted legible",
       %{conn: conn} do
    security = security!()

    thesis =
      append!(security, %{
        kind: "thesis",
        body: "Pricing power holds through 2027.",
        conviction: "high",
        invalidation_condition: "gross margin below 40% for two quarters",
        time_stop: ~D[2027-06-30],
        as_of: ~D[2026-06-01]
      })

    rumour =
      append!(security, %{
        body: "Supplier dispute will hit Q3.",
        source_quality: "awareness",
        as_of: ~D[2026-07-10]
      })

    retraction =
      append!(security, %{
        kind: "retraction",
        body: "Checked the 10-Q: no dispute disclosed. Withdrawn.",
        supersedes_id: rumour.id,
        as_of: ~D[2026-08-02]
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=research")

    assert has_element?(
             view,
             "#detail-pane-tabs button[phx-value-tab='research'][aria-selected='true']"
           )

    panel = view |> element("#detail-tab-panel-research") |> render()

    # The thesis state on top: intact, with its fields and the entry it
    # derives from.
    state = view |> element(~s([data-role="thesis-state"])) |> render()
    assert state =~ "Intact"
    assert state =~ "Pricing power holds through 2027."
    assert state =~ "High"
    assert state =~ "gross margin below 40%"
    assert state =~ "2027-06-30"
    assert state =~ "##{thesis.id}"

    # Newest first: the retraction, then the rumour, then the thesis.
    ids =
      Regex.scan(~r/data-entry-id="(\d+)"/, panel)
      |> Enum.map(fn [_, id] -> String.to_integer(id) end)

    assert ids == [retraction.id, rumour.id, thesis.id]

    # Kind and source quality are visible; the author too.
    rumour_row = view |> element("#research-entry-#{rumour.id}") |> render()
    assert rumour_row =~ "Evidence"
    assert rumour_row =~ "Awareness"
    assert rumour_row =~ "Agent"
    assert rumour_row =~ "2026-07-10"

    # The superseded rumour stays in the list, marked with what superseded it.
    assert rumour_row =~ "research-entry--superseded"
    assert rumour_row =~ "Superseded by ##{retraction.id}"

    # The retraction is legible as such and names what it retracts.
    retraction_row = view |> element("#research-entry-#{retraction.id}") |> render()
    assert retraction_row =~ "Retraction"
    assert retraction_row =~ "Retracts ##{rumour.id}"
    assert retraction_row =~ "no dispute disclosed"

    # Nothing edits or removes an entry.
    refute panel =~ "phx-click=\"delete_research_entry\""
    refute panel =~ "phx-click=\"edit_research_entry\""
    refute panel =~ "Delete entry"
  end

  # User story (ADR-0044 §6 — the operator can append from the pane):
  # As a local portfolio maintainer,
  # I want to append an entry from the Research tab as the operator,
  # so that my own decisions and checks land in the same log the agent reads.
  #
  # Acceptance criteria:
  # - The form appends an entry with author operator; the timeline shows it
  #   at once and the thesis state updates.
  # - A rejected entry keeps the form and names the error.
  test "the operator appends an entry from the pane", %{conn: conn} do
    security = security!()
    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=research")

    state = view |> element(~s([data-role="thesis-state"])) |> render()
    assert state =~ "No thesis recorded"

    # Choosing the thesis kind reveals the thesis-only fields.
    view |> form("#research-entry-form", note: %{kind: "thesis"}) |> render_change()
    assert has_element?(view, "#research-entry-form [name='note[conviction]']")

    view
    |> form("#research-entry-form",
      note: %{
        kind: "thesis",
        body: "Compounder; hold while ROIC > 15%.",
        source_quality: "primary",
        as_of: "2026-09-01",
        conviction: "medium",
        invalidation_condition: "ROIC below 15% for a year",
        time_stop: "2027-09-01"
      }
    )
    |> render_submit()

    [note] = Knowledge.list_notes(security.id)
    assert note.author == :operator
    assert note.kind == :thesis
    assert note.conviction == :medium

    state = view |> element(~s([data-role="thesis-state"])) |> render()
    assert state =~ "Intact"
    assert state =~ "Compounder"
    assert state =~ "Medium"

    row = view |> element("#research-entry-#{note.id}") |> render()
    assert row =~ "Operator"
    assert row =~ "Thesis"

    assert render(view) =~ "Entry appended."

    # A rejected entry: a retraction without a target.
    view
    |> form("#research-entry-form",
      note: %{
        kind: "retraction",
        body: "withdrawn",
        source_quality: "primary",
        as_of: "2026-09-02"
      }
    )
    |> render_submit()

    assert render(view) =~ "a retraction must supersede an entry"
    assert length(Knowledge.list_notes(security.id)) == 1
  end
end
