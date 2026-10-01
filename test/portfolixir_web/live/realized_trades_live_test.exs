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

  # User story (#984 rescoped, Sprint 17 T1b; UX-DR25, board G1 rule ⑤):
  # As a local portfolio maintainer with an imported history,
  # I want the sells no buy could be matched to named where the totals are
  # read,
  # so that a sale of delivered-in shares missing from every figure is a
  # stated gap, not a silent one.
  #
  # Acceptance criteria:
  # - An attention note leads the section with the count and the reason,
  #   after the currency-exclusion note when both appear, before the figures.
  # - Its disclosure lists each sell as security · date · quantity.
  # - It carries no remedy control: there is none (UX-DR25 clause 3); the
  #   basis line under the list states the limit.
  # - With no unmatched sell there is no note.
  test "the sells no buy was matched to are named after the currency note", %{conn: conn} do
    world = base_world(name: "Delivered Facet", cash_name: "DF Cash", depot_name: "DF Depot")
    delivered = create_security!(name: "Delivered Holdings", ticker: "DHD")
    deposit!(world, "100000", ~D[2026-01-01])

    {:ok, _delivery} =
      Portfolixir.Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: delivered.id,
        type: "inbound_delivery",
        date: ~D[2026-01-10],
        quantity: "15",
        currency_code: "EUR"
      })

    sell!(world, delivered, quantity: "15", price: "20", date: ~D[2026-05-12])

    # A pound sale with no stored rate on its close date: the currency note.
    pound = create_security!(name: "Pound Holdings", ticker: "PHD", currency: "GBP")

    gbp =
      Map.merge(
        world,
        Portfolixir.WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    buy!(gbp, pound, quantity: "2", price: "10", date: ~D[2026-01-09], currency: "GBP")
    sell!(gbp, pound, quantity: "2", price: "30", date: ~D[2026-02-20], currency: "GBP")

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    assert has_element?(view, "#realized-unmatched[data-role='realized-unmatched']")
    note = view |> element("#realized-unmatched") |> render()
    assert note =~ "1 sale with no matched buy"
    assert note =~ "Delivered Holdings"
    assert note =~ "2026-05-12"
    assert note =~ "15.0000 units"
    refute has_element?(view, "#realized-unmatched button")

    section = view |> element("#realized-trades") |> render()
    {excluded_at, _} = :binary.match(section, "realized-excluded")
    {unmatched_at, _} = :binary.match(section, "realized-unmatched")
    {figures_at, _} = :binary.match(section, "realized-figures")
    assert excluded_at < unmatched_at and unmatched_at < figures_at

    # In German, the board's copy and the German date and quantity forms.
    de_conn = Plug.Test.put_req_cookie(Phoenix.ConnTest.build_conn(), "portfolixir_locale", "de")
    {:ok, de_view, _html} = live(de_conn, "/cashflow?tab=realized")
    de_note = de_view |> element("#realized-unmatched") |> render()
    assert de_note =~ "1 Verkauf ohne zugeordneten Kauf"
    assert de_note =~ "Der Verkauf"
    assert de_note =~ "12.05.2026"
    assert de_note =~ "15,0000 Stück"
  end

  test "with every sell matched there is no unmatched-sells note", %{conn: conn} do
    _winner = seed_closed_trade!()
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    refute has_element?(view, "#realized-unmatched")
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
