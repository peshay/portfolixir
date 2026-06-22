defmodule Portfolixir.LedgerHoldingsForPortfolioTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  # User story:
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want each portfolio holding to carry its cost basis and unrealized P&L,
  # so that I can value a position without re-deriving its average cost myself.
  #
  # Acceptance criteria:
  # - One row per (depot, security); fully closed positions are dropped.
  # - The cost basis follows a moving average of the buy prices.
  # - Market value and P&L are computed against an injected/latest price.
  # - A holding whose security has no price is returned with nil price and P&L.

  defp setup_world do
    %{portfolio: portfolio, cash: cash, depot: depot_one} =
      base_world(depot_name: "Depot One")

    # A second depot on the same cash account, so the per-(depot, security)
    # row aggregation can be exercised across two depots.
    {:ok, depot_two} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot Two"
      })

    %{portfolio: portfolio, cash: cash, depot_one: depot_one, depot_two: depot_two}
  end

  defp equity!(name, ticker),
    do: create_security!(name: name, ticker: ticker, asset_class: "equity")

  defp trade!(world, depot, security, type, qty, price, date) do
    {:ok, _tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: type,
        date: date,
        quantity: qty,
        price: price,
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })
  end

  defp row_for(holdings, security_id, account_id) do
    Enum.find(
      holdings,
      &(&1.security_id == security_id and &1.securities_account_id == account_id)
    )
  end

  test "enriches each holding with moving-average cost basis and unrealized P&L" do
    world = setup_world()
    %{depot_one: depot_one, depot_two: depot_two} = world

    a = equity!("Sec A", "AAA")
    b = equity!("Sec B", "BBB")
    c = equity!("Sec C", "CCC")

    # Sec A in depot one: two buys at different prices, then a partial sell.
    trade!(world, depot_one, a, "buy", "10", "100", ~D[2026-01-02])
    trade!(world, depot_one, a, "buy", "10", "120", ~D[2026-02-02])
    trade!(world, depot_one, a, "sell", "5", "150", ~D[2026-03-02])

    # Sec A in a second depot: its own moving average.
    trade!(world, depot_two, a, "buy", "3", "100", ~D[2026-01-10])

    # Sec B: held but no price available.
    trade!(world, depot_one, b, "buy", "4", "50", ~D[2026-01-05])

    # Sec C: fully sold, so it must not appear.
    trade!(world, depot_one, c, "buy", "5", "10", ~D[2026-01-06])
    trade!(world, depot_one, c, "sell", "5", "12", ~D[2026-02-06])

    holdings =
      Ledger.holdings_for_portfolio(world.portfolio.id, prices: %{a.id => Decimal.new("130")})

    assert length(holdings) == 3

    a_one = row_for(holdings, a.id, depot_one.id)
    assert a_one.security_name == "Sec A"
    assert a_one.currency_code == "EUR"
    assert Decimal.equal?(a_one.quantity, Decimal.new("15"))
    # Moving average of the two buys: (10*100 + 10*120) / 20 = 110.
    assert Decimal.equal?(a_one.avg_cost, Decimal.new("110"))
    assert Decimal.equal?(a_one.cost_basis, Decimal.new("1650"))
    assert Decimal.equal?(a_one.latest_price, Decimal.new("130"))
    assert Decimal.equal?(a_one.market_value, Decimal.new("1950"))
    assert Decimal.equal?(a_one.unrealized_pnl_abs, Decimal.new("300"))
    assert Decimal.equal?(Decimal.round(a_one.unrealized_pnl_pct, 4), Decimal.new("0.1818"))

    a_two = row_for(holdings, a.id, depot_two.id)
    assert Decimal.equal?(a_two.quantity, Decimal.new("3"))
    assert Decimal.equal?(a_two.avg_cost, Decimal.new("100"))
    assert Decimal.equal?(a_two.market_value, Decimal.new("390"))
    assert Decimal.equal?(a_two.unrealized_pnl_abs, Decimal.new("90"))

    b_one = row_for(holdings, b.id, depot_one.id)
    assert Decimal.equal?(b_one.quantity, Decimal.new("4"))
    assert b_one.latest_price == nil
    assert b_one.market_value == nil
    assert b_one.unrealized_pnl_abs == nil
    assert b_one.unrealized_pnl_pct == nil

    assert row_for(holdings, c.id, depot_one.id) == nil
  end
end
