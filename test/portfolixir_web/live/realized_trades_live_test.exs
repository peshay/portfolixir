defmodule PortfolixirWeb.RealizedTradesLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3]

  # User story (#807; review C10, signed by Sprint 13's D-3 — the facet IS
  # the Trades view, and the `needs-decision` label comes off):
  # As a local portfolio maintainer,
  # I want the Realized gains facet to open on the closed trades and three
  # figures,
  # so that the facet shows what its name promises instead of one number in
  # a year × month matrix.
  #
  # Acceptance criteria:
  # - The facet opens with the realised total, the hit rate and the average
  #   holding period, then the trades list; each row links to that security's
  #   Trades tab.
  # - The matrix keeps its numbers, behind a "Realized per period" disclosure.

  defp seed_closed_trade! do
    world = base_world(name: "Facet World", cash_name: "FW Cash", depot_name: "FW Depot")
    winner = create_security!(name: "Winner Co", ticker: "WIN")
    deposit!(world, "100000", ~D[2026-01-01])
    buy!(world, winner, quantity: "10", price: "100", date: ~D[2026-01-05])
    sell!(world, winner, quantity: "10", price: "150", date: ~D[2026-03-06])
    winner
  end

  test "the facet opens on the trades and the three figures", %{conn: conn} do
    winner = seed_closed_trade!()
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    assert has_element?(view, "#realized-figures [data-role='realized-total']")
    assert has_element?(view, "#realized-figures [data-role='realized-hit-rate']")
    assert has_element?(view, "#realized-figures [data-role='realized-holding-period']")

    figures = view |> element("#realized-figures") |> render()
    assert figures =~ "500"
    assert figures =~ "100"

    rows = view |> element("#realized-trades-table") |> render()
    assert rows =~ "Winner Co"
    assert rows =~ "2026-01-05"
    assert rows =~ "2026-03-06"

    assert has_element?(
             view,
             "#realized-trades-table a[href='/securities/#{winner.id}?tab=trades']"
           )

    # The matrix keeps its numbers, behind the disclosure — and the section
    # keeps a heading on the ramp rather than letting the summary be it.
    assert view |> element("#realized-annual h2") |> render() =~ "Realized per period"
    assert has_element?(view, "#realized-annual-disclosure summary", "Year and month matrix")
    assert view |> element("#realized-annual") |> render() =~ "2026"
  end

  # Acceptance criteria (the honest empty state): the average of nothing is
  # not zero, so the two derived figures read as absent rather than as 0 %
  # and 0 days.
  test "with no closed trades the derived figures read as absent, not as zero", %{conn: conn} do
    _empty = base_world(name: "No Trades", cash_name: "NT Cash", depot_name: "NT Depot")
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    assert view |> element("[data-role='realized-hit-rate']") |> render() =~ "—"
    assert view |> element("[data-role='realized-holding-period']") |> render() =~ "—"
    refute has_element?(view, "#realized-trades-table")
    assert has_element?(view, "#realized-trades .empty-state")
  end
end
