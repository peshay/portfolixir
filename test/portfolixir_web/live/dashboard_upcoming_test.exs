defmodule PortfolixirWeb.DashboardUpcomingTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Knowledge.Events

  # User story (#828, ADR-0048 §2; design pick D3-A of 2026-09-19):
  # As the operator planning a purchase,
  # I want what is due across the WHOLE CATALOG on the surface that answers
  # "does anything need me today?",
  # so that a candidate I do not own yet cannot have an invisible date.
  #
  # Acceptance criteria:
  # - The "Due" card joins the Overview's attention column beside "Off
  #   target"; each row links to that security's Termine tab.
  # - A security with no position is MARKED, never filtered away — that mark
  #   is the difference between this card and a holdings-derived calendar.
  # - A date given as a range or a month is due when any day it could fall on
  #   is inside the horizon.

  setup do
    world = base_world(name: "Due World", cash_name: "DW Cash", depot_name: "DW Depot")
    held = create_security!(name: "Held Co", ticker: "HLD")
    candidate = create_security!(name: "Candidate Co", ticker: "CND")
    buy!(world, held, quantity: "1", price: "100", date: ~D[2026-01-05])

    %{world: world, held: held, candidate: candidate}
  end

  defp event!(security, attrs) do
    {:ok, event} =
      Events.create_event(
        Actor.owner_ui(),
        Enum.into(attrs, %{
          security_id: security.id,
          kind: "earnings",
          timing: "exact",
          source_quality: "primary"
        })
      )

    event
  end

  test "the Due card lists the catalog, marking what is not held", %{
    conn: conn,
    held: held,
    candidate: candidate
  } do
    today = Portfolixir.Clock.today()
    event!(held, date: Date.add(today, 3))
    event!(candidate, date: Date.add(today, 5))

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#dashboard-upcoming")
    card = view |> element("#dashboard-upcoming") |> render()

    assert card =~ "Held Co"
    assert card =~ "Candidate Co"
    assert card =~ "Earnings report"

    # The candidate is marked, not hidden.
    assert has_element?(view, "#dashboard-upcoming [data-role='upcoming-unheld']")

    assert has_element?(
             view,
             "#dashboard-upcoming a[href='/securities/#{candidate.id}?tab=events']"
           )
  end

  test "a month event is due when its month reaches into the horizon", %{
    conn: conn,
    candidate: candidate
  } do
    today = Portfolixir.Clock.today()
    event!(candidate, date: Date.end_of_month(today), timing: "month", kind: "guidance_update")

    {:ok, view, _html} = live(conn, "/")

    assert view |> element("#dashboard-upcoming") |> render() =~ "Candidate Co"
  end

  test "with nothing due the card is absent rather than empty", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "#dashboard-upcoming")
  end
end
