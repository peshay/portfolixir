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

  # Review round: the retracted thesis state names the retraction with its
  # reason; a superseding entry says what it replaces; a machine-generated
  # proposal is marked; source links and dated blocks render; a rejected form
  # names the offending field.
  test "retracted state, replacement markers, proposals and facts render", %{conn: conn} do
    security = security!()

    thesis =
      append!(security, %{kind: "thesis", body: "turnaround by 2027", as_of: ~D[2026-05-01]})

    retraction =
      append!(security, %{
        kind: "retraction",
        body: "management guided down twice",
        supersedes_id: thesis.id,
        as_of: ~D[2026-08-20]
      })

    old_risk = append!(security, %{kind: "risk", body: "FX exposure", as_of: ~D[2026-06-01]})

    _new_risk =
      append!(security, %{
        kind: "risk",
        body: "FX exposure now hedged",
        supersedes_id: old_risk.id,
        as_of: ~D[2026-07-01]
      })

    proposal =
      append!(security, %{
        author: "local_model",
        machine_generated: true,
        source_url: "https://example.invalid/filing",
        source_quality: "unverified",
        body: "extracted: dividend raised",
        valid_until: ~D[2026-12-31],
        as_of: ~D[2026-08-25]
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=research")

    state = view |> element(~s([data-role="thesis-state"])) |> render()
    assert state =~ "Retracted"
    assert state =~ "Retracted by ##{retraction.id}: management guided down twice"
    # A thesis without a conviction tier shows the dash, not a crash.
    assert state =~ "—"

    replacement = view |> element("#research-entry-#{old_risk.id + 1}") |> render()
    assert replacement =~ "Replaces ##{old_risk.id}"

    proposal_row = view |> element("#research-entry-#{proposal.id}") |> render()
    assert proposal_row =~ "machine-generated proposal"
    assert proposal_row =~ "Local model"
    assert proposal_row =~ ~s(href="https://example.invalid/filing")
    assert proposal_row =~ "2026-12-31"

    # A change on another field leaves the kind alone; an unknown kind falls
    # back to the default.
    view |> form("#research-entry-form", note: %{body: "typing"}) |> render_change()
    assert has_element?(view, "#research-entry-form option[value='evidence'][selected]")

    view
    |> form("#research-entry-form", note: %{kind: "thesis", body: "x", source_quality: "primary"})
    |> render_submit(%{note: %{as_of: "not-a-date"}})

    assert render(view) =~ "As of: is invalid"
  end

  # User story (E25 S6, F15, decision T-5):
  # As the operator reading the research log,
  # I want an entry I append from the page to carry only what the form asks
  # for, with its provenance stated by the system,
  # so that no crafted submit can mark my entry a machine-generated proposal
  # or file it under another security.
  #
  # Acceptance criteria:
  # - A submit carrying machine_generated, author, security_id or any other
  #   key the form does not render stores an operator entry, not
  #   machine-generated, on the security the page shows.
  test "the research form stores only the keys it renders", %{conn: conn} do
    security = security!()
    other = WorldFixtures.create_security!(name: "Elsewhere Co.", ticker: "ELSW")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=research")

    view
    |> element("#research-entry-form")
    |> render_submit(%{
      note: %{
        kind: "evidence",
        body: "Order book read from the half-year report.",
        source_quality: "primary",
        as_of: "2026-09-01",
        source_url: "https://example.invalid/report",
        machine_generated: "true",
        author: "local_model",
        security_id: other.id
      }
    })

    assert render(view) =~ "Entry appended."
    assert [note] = Knowledge.list_notes(security.id)
    assert note.machine_generated == false
    assert note.author == :operator
    assert Knowledge.list_notes(other.id) == []
  end

  # User story (E25 S6, F44; board 11, before/after 2):
  # As the operator appending to a research log that is never edited,
  # I want an entry dated after today refused in the form's error list, in my
  # language, with what I typed still there,
  # so that I correct the year instead of writing the entry again.
  #
  # Acceptance criteria:
  # - A future as_of is named in the error list ("Field: message"), the
  #   message translated through errors.po; nothing is appended.
  # - The refused submit keeps the typed body and dates in the form.
  # - The timeline and the thesis state are unchanged.
  test "a future as of is refused in the form's error list and the typing stays",
       %{conn: conn} do
    security = security!()
    kept = append!(security, %{kind: "invalidation_check", as_of: ~D[2026-09-02]})
    future = Portfolixir.Clock.today() |> Date.add(365) |> Date.to_iso8601()

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=research&locale=de")
    before_state = view |> element(~s([data-role="thesis-state"])) |> render()

    view
    |> form("#research-entry-form",
      note: %{
        kind: "invalidation_check",
        body: "Half-year figures read; the condition is not met.",
        source_quality: "primary",
        as_of: future,
        valid_until: "2030-01-31"
      }
    )
    |> render_submit()

    errors = view |> element(".research-entry-form__errors") |> render()
    assert errors =~ "Stichtag: darf nicht in der Zukunft liegen"
    assert render(view) =~ "Eintrag konnte nicht angehängt werden."

    form = view |> element("#research-entry-form") |> render()
    assert form =~ ~s(value="#{future}")
    assert form =~ ~s(value="2030-01-31")
    assert form =~ "Half-year figures read; the condition is not met."

    assert [%{id: id}] = Knowledge.list_notes(security.id)
    assert id == kept.id
    assert view |> element(~s([data-role="thesis-state"])) |> render() == before_state
  end

  # User story (E25 S6, G01):
  # As the operator appending to the research log from the page,
  # I want an entry body past its bound refused in the form's error list,
  # so that the page meets the same cap as the API.
  #
  # Acceptance criteria:
  # - A body one code point past the cap is named in the error list and
  #   nothing is appended.
  test "an entry body past its cap is refused in the form's error list", %{conn: conn} do
    security = security!()
    max = Portfolixir.Input.Text.entry_body_max()

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=research")

    view
    |> form("#research-entry-form",
      note: %{
        kind: "evidence",
        body: String.duplicate("a", max + 1),
        source_quality: "primary",
        as_of: "2026-09-01"
      }
    )
    |> render_submit()

    errors = view |> element(".research-entry-form__errors") |> render()
    assert errors =~ "Entry: should be at most #{max} character(s)"
    assert Knowledge.list_notes(security.id) == []
  end
end
