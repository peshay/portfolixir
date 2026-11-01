defmodule PortfolixirWeb.SecuritiesHoldingsTradePriceTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Valuation
  alias Portfolixir.WorldFixtures

  @panel "#detail-tab-panel-holdings"

  # User story (#1316; ADR-0010's amendment of 2026-06-10; Sprint 22 plan
  # D-6, board 02 ①):
  # As a local portfolio maintainer,
  # I want the security page's Bestände tab to value a position without a
  # quote at its last own trade price, and to say so,
  # so that its rows add up to its total and agree with the portfolio total
  # that already counts the position that way.
  #
  # Acceptance criteria:
  # - Each row's current value is quantity x the last own trade price,
  #   with "at trade price" beneath it.
  # - The total is the sum of the rows (Decimal-exact), and so is its P&L.
  # - The rows' figures are the valuation's own: their sum equals the
  #   portfolio valuation's total for the security.
  test "a position without a quote is valued at its last trade price and named so",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Helios World", depot_name: "Depot Nord")
    south = WorldFixtures.add_depot(world.portfolio, depot_name: "Depot Süd", cash_name: "South")
    south_world = Map.merge(world, south)

    helios = WorldFixtures.create_security!(name: "Helios Example SE", ticker: "HLX")
    WorldFixtures.deposit!(world, "5000", ~D[2025-01-02])
    WorldFixtures.deposit!(south_world, "5000", ~D[2025-01-02])

    WorldFixtures.buy!(world, helios, quantity: "15", price: "18.00", date: ~D[2025-01-10])
    WorldFixtures.buy!(south_world, helios, quantity: "5", price: "19.20", date: ~D[2025-03-14])

    {:ok, view, _html} = live(conn, "/securities/#{helios.id}?tab=holdings")
    panel = view |> element(@panel) |> render()

    # 15 x 19.20 = 288.00 and 5 x 19.20 = 96.00, each at its trade price.
    assert panel =~ "288.00"
    assert panel =~ "96.00"
    assert has_element?(view, "#{@panel} td small.cell-note", "at trade price")

    footer = view |> element("#{@panel} tfoot") |> render()
    assert footer =~ "384.00"
    assert footer =~ "+18.00"
    refute footer =~ "0.00 <small>"

    # The same figure the portfolio's total counts.
    total = Valuation.for_portfolio(world.portfolio.id).total_value
    assert Decimal.equal?(total, Decimal.new("384.00"))
  end

  # User story (#1316, board 02 ① 1b; UX-DR25):
  # As a local portfolio maintainer,
  # I want a position with no price at all (no quote, no own trade) to read
  # "no price known" instead of a total of 0.00, and the row the total leaves out
  # named beneath it,
  # so that a missing figure never reads as a value of nothing.
  #
  # Acceptance criteria:
  # - The row's value cell reads "—" with "no price known" ("kein Preis").
  # - The total reads "—", never 0.00.
  # - An attention note under the table names the row left out.
  test "a position with no price reads no price and is named beside the total",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Dark World", depot_name: "Demo Depot")
    dark = WorldFixtures.create_security!(name: "Placeholder Bond", ticker: "PLB")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: dark.id,
        type: "inbound_delivery",
        date: ~D[2025-02-01],
        quantity: "5",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/securities/#{dark.id}?tab=holdings")

    assert has_element?(view, "#{@panel} td small.cell-note", "no price known")

    footer = view |> element("#{@panel} tfoot") |> render()
    refute footer =~ "0.00"
    assert footer =~ "—"

    note = view |> element(~s(#{@panel} [data-role="holdings-unvalued"])) |> render()
    assert note =~ "1 position is missing from the total"
    assert note =~ "Demo Depot"
    assert note =~ "(5 units)"
  end
end
