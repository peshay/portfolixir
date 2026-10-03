defmodule PortfolixirWeb.SecuritiesDeleteRefusalTest do
  # Sprint 18 pick H8.2 = A (#918; board ux-design-2026-10-02/08-dialogs-copy):
  # deleting a security says truthfully what blocks it. The confirmation,
  # which opens before any check, names the blocking kinds in general terms
  # and what is removed with the security. "Cannot delete" names what blocks
  # this one, counted from the refusal, and the reason for its way out:
  # research entries mean retire, anything a merge carries means merge or
  # retire. The delete path, the API and MCP are unchanged.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.Events

  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp delete_row(view, security) do
    view
    |> element(
      ~s(#securities-table button[phx-click="open_row_menu"][phx-value-id="#{security.id}"])
    )
    |> render_click()

    view
    |> element(~s(button[phx-value-action="delete"][phx-value-id="#{security.id}"]))
    |> render_click()
  end

  defp confirmation(view, security) do
    view
    |> element(
      ~s(#securities-table button[phx-click="open_row_menu"][phx-value-id="#{security.id}"])
    )
    |> render_click()

    [text] =
      view
      |> element(~s(button[phx-value-action="delete"][phx-value-id="#{security.id}"]))
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("data-confirm")

    render_hook(view, "close_row_menu", %{})
    text
  end

  defp paragraphs(view) do
    view
    |> element("#delete-blocked-dialog .modal-body")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("p")
    |> Enum.map(&(&1 |> Floki.text() |> String.split() |> Enum.join(" ")))
  end

  defp footer(view) do
    view
    |> element("#delete-blocked-dialog .modal-footer")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("button")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end

  defp quotes(n), do: for(day <- 1..n, do: {Date.add(~D[2026-01-01], day), "100"})

  defp world do
    world = base_world(name: "Löschen")
    deposit!(world, "100000", ~D[2026-01-02])

    researched = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
    for day <- 5..6, do: buy!(world, researched, quantity: "1", date: Date.new!(2026, 1, day))
    put_quotes!(researched, quotes(3))

    for body <- ["Auftragsbestand stabil.", "Marge unter Druck."] do
      {:ok, _} =
        Knowledge.append_note(Actor.owner_ui(), %{
          security_id: researched.id,
          author: "operator",
          kind: "evidence",
          body: body,
          source_quality: "primary",
          as_of: ~D[2026-01-10]
        })
    end

    duplicate = create_security!(name: "Meridian Global Equity ETF", ticker: "MGEQ")
    buy!(world, duplicate, quantity: "1", date: ~D[2026-01-07])
    put_quotes!(duplicate, quotes(2))

    {:ok, _} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: duplicate.id,
        kind: "earnings",
        date: ~D[2026-11-04],
        timing: "exact",
        source_quality: "primary"
      })

    %{researched: researched, duplicate: duplicate}
  end

  # User story (#918; pick H8.2 = A, board 08-dialogs-copy):
  # As the operator deleting a security,
  # I want the confirmation to say what blocks a delete and what goes with
  # the security, and "Cannot delete" to name what blocks this one, counted,
  # so that I see why the way out is merge or retire.
  #
  # Acceptance criteria:
  # - The confirmation names bookings, quotes, events, research entries and
  #   policy rules as what blocks, and the classifications, position
  #   targets, bucket assignments, former ISINs and the logo as removed with
  #   it; it no longer says notes are lost.
  # - A security with research entries: "“Nordwind Industrie AG” still has
  #   2 bookings, 3 quotes and 2 research entries.", the research sentence,
  #   and Cancel and Retire instead only.
  # - A security whose bookings, quotes and events a merge carries: the
  #   counts, the merge sentence naming bookings, quotes and events, and
  #   Cancel, Merge into… and Retire instead.
  # - The security is still there after either refusal.
  test "the confirmation and Cannot delete name what blocks, with counts", %{conn: conn} do
    %{researched: researched, duplicate: duplicate} = world()
    {:ok, view, _html} = live(conn, "/securities")

    assert confirmation(view, researched) ==
             "Delete this security? Bookings, quotes, events, research entries and policy rules block the deletion. Removed with it: its classifications, position targets, bucket assignments and former ISINs, each journaled, and its logo."

    delete_row(view, researched)

    assert paragraphs(view) == [
             "“Nordwind Industrie AG” still has 2 bookings, 3 quotes and 2 research entries.",
             "Research entries are never removed, and no merge carries them. Retiring hides the security from the active list; everything is kept."
           ]

    assert footer(view) == ["Cancel", "Retire instead"]
    assert has_element?(view, "#delete-blocked-dialog .modal-body bdi", "Nordwind Industrie AG")

    view |> element("#delete-blocked-dialog .modal-footer button", "Cancel") |> render_click()
    delete_row(view, duplicate)

    assert paragraphs(view) == [
             "“Meridian Global Equity ETF” still has 1 booking, 2 quotes and 1 event.",
             "If it is a duplicate, “Merge into…” moves its bookings, quotes and events into the other security. Retiring hides it from the active list; everything is kept."
           ]

    assert footer(view) == ["Cancel", "Merge into…", "Retire instead"]

    assert Catalog.get_security(researched.id)
    assert Catalog.get_security(duplicate.id)
  end

  test "the confirmation and Cannot delete read in German", %{conn: conn} do
    %{researched: researched, duplicate: duplicate} = world()
    {:ok, view, _html} = live(german(conn), "/securities")

    assert confirmation(view, researched) ==
             "Dieses Wertpapier löschen? Buchungen, Kurse, Termine, Research-Einträge und eigene Regeln blockieren das Löschen. Mit entfernt werden seine Klassifizierungen, Positionsziele, Bucket-Zuordnungen und früheren ISINs, jede im Journal, und das Logo."

    delete_row(view, researched)

    assert paragraphs(view) == [
             "„Nordwind Industrie AG“ hat noch 2 Buchungen, 3 Kurse und 2 Research-Einträge.",
             "Research-Einträge werden nie entfernt und ziehen bei keiner Zusammenführung mit. Stilllegen blendet das Wertpapier aus der aktiven Liste aus; alles bleibt erhalten."
           ]

    assert footer(view) == ["Abbrechen", "Stattdessen stilllegen"]

    view |> element("#delete-blocked-dialog .modal-footer button", "Abbrechen") |> render_click()
    delete_row(view, duplicate)

    assert paragraphs(view) == [
             "„Meridian Global Equity ETF“ hat noch 1 Buchung, 2 Kurse und 1 Termin.",
             "Ist es ein Duplikat, führt „Zusammenführen in…“ seine Buchungen, Kurse und Termine in das andere Wertpapier. Stilllegen blendet es aus der aktiven Liste aus; alles bleibt erhalten."
           ]

    assert footer(view) == ["Abbrechen", "Zusammenführen in…", "Stattdessen stilllegen"]
  end
end
