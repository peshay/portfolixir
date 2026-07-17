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

  defp delivery!(world, depot, security, type, qty, date) do
    {:ok, _tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: depot.id,
        security_id: security.id,
        type: type,
        date: date,
        quantity: qty,
        currency_code: "EUR"
      })
  end

  defp transfer!(world, from_depot, to_depot, security, qty, date) do
    {:ok, _tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: from_depot.id,
        counter_securities_account_id: to_depot.id,
        security_id: security.id,
        type: "security_transfer",
        date: date,
        quantity: qty,
        currency_code: "EUR"
      })
  end

  # User story:
  # As a local portfolio maintainer,
  # I want deliveries and depot transfers to move my holdings quantities,
  # so that a position that left the depot via a corporate action (e.g. a
  # takeover booked as an outbound delivery) does not linger as a phantom
  # holding.
  #
  # Acceptance criteria:
  # - A full outbound delivery drops the row, like a full sell would.
  # - A partial outbound delivery reduces the quantity; the moving-average
  #   cost of the priced buys is kept for the remaining shares.
  # - An inbound delivery adds quantity even without any priced trade.
  # - A security transfer moves quantity from the source depot to the
  #   counter depot.
  test "deliveries and security transfers move holdings quantities" do
    world = setup_world()
    %{depot_one: depot_one, depot_two: depot_two} = world

    a = equity!("Taken Over", "TKO")
    b = equity!("Partially Delivered", "PRT")
    c = equity!("Delivered In", "DIN")
    d = equity!("Transferred", "TRF")

    # Sec A: bought, then fully delivered out (takeover) — must not appear.
    trade!(world, depot_one, a, "buy", "615", "17.50", ~D[2026-01-02])
    delivery!(world, depot_one, a, "outbound_delivery", "615", ~D[2026-04-02])

    # Sec B: partial outbound delivery keeps the rest at the buy cost.
    trade!(world, depot_one, b, "buy", "100", "10", ~D[2026-01-03])
    delivery!(world, depot_one, b, "outbound_delivery", "40", ~D[2026-02-03])

    # Sec C: inbound delivery only — held without an own cost.
    delivery!(world, depot_one, c, "inbound_delivery", "50", ~D[2026-01-04])

    # Sec D: bought in depot one, partially transferred to depot two.
    trade!(world, depot_one, d, "buy", "10", "20", ~D[2026-01-05])
    transfer!(world, depot_one, depot_two, d, "4", ~D[2026-02-05])

    holdings = Ledger.holdings_for_portfolio(world.portfolio.id)

    assert row_for(holdings, a.id, depot_one.id) == nil

    b_row = row_for(holdings, b.id, depot_one.id)
    assert Decimal.equal?(b_row.quantity, Decimal.new("60"))
    assert Decimal.equal?(b_row.avg_cost, Decimal.new("10"))
    assert Decimal.equal?(b_row.cost_basis, Decimal.new("600"))

    c_row = row_for(holdings, c.id, depot_one.id)
    assert c_row.security_name == "Delivered In"
    assert Decimal.equal?(c_row.quantity, Decimal.new("50"))
    assert Decimal.equal?(c_row.avg_cost, Decimal.new("0"))

    d_source = row_for(holdings, d.id, depot_one.id)
    assert Decimal.equal?(d_source.quantity, Decimal.new("6"))
    assert Decimal.equal?(d_source.avg_cost, Decimal.new("20"))
    assert Decimal.equal?(d_source.cost_basis, Decimal.new("120"))

    d_target = row_for(holdings, d.id, depot_two.id)
    assert Decimal.equal?(d_target.quantity, Decimal.new("4"))
    assert d_target.security_name == "Transferred"
    # The transferred shares keep their recorded buy cost — a transfer between
    # own depots must not erase money that was actually spent.
    assert Decimal.equal?(d_target.avg_cost, Decimal.new("20"))
    assert Decimal.equal?(d_target.cost_basis, Decimal.new("80"))
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the cost basis to follow the shares through deliveries and
  # transfers,
  # so that unrealized P&L is always computed against the money actually
  # spent on the shares still held.
  #
  # Acceptance criteria:
  # - Re-buying after a full outbound delivery starts a fresh average
  #   (the delivered-out shares take their cost with them).
  # - Shares entering by an unpriced inbound delivery add no cost, so the
  #   cost basis stays the sum of the priced buys.
  # - After trades net to zero, delivered-in shares carry a zero basis.
  # - An over-delivered (negative) position reports a zero cost basis and
  #   the P&L percentage does not flip its sign.
  test "cost basis follows the shares through deliveries" do
    world = setup_world()
    %{depot_one: depot_one} = world

    r = equity!("Reopened", "ROP")
    m = equity!("Mixed Basis", "MIX")
    n = equity!("Netted", "NET")
    o = equity!("Over Delivered", "OVR")

    # Reopened: buy, deliver everything out, buy again at a new price.
    trade!(world, depot_one, r, "buy", "10", "100", ~D[2026-01-02])
    delivery!(world, depot_one, r, "outbound_delivery", "10", ~D[2026-02-02])
    trade!(world, depot_one, r, "buy", "5", "200", ~D[2026-03-02])

    # Mixed: one priced buy plus an unpriced inbound delivery (spin-off style).
    trade!(world, depot_one, m, "buy", "5", "100", ~D[2026-01-03])
    delivery!(world, depot_one, m, "inbound_delivery", "10", ~D[2026-02-03])

    # Netted: trades close to zero, then shares arrive by delivery.
    trade!(world, depot_one, n, "buy", "10", "100", ~D[2026-01-04])
    trade!(world, depot_one, n, "sell", "10", "110", ~D[2026-02-04])
    delivery!(world, depot_one, n, "inbound_delivery", "5", ~D[2026-03-04])

    # Over-delivered: more shares leave than were ever held.
    trade!(world, depot_one, o, "buy", "10", "100", ~D[2026-01-05])
    delivery!(world, depot_one, o, "outbound_delivery", "15", ~D[2026-02-05])

    holdings =
      Ledger.holdings_for_portfolio(world.portfolio.id,
        prices: %{m.id => Decimal.new("100"), o.id => Decimal.new("120")}
      )

    r_row = row_for(holdings, r.id, depot_one.id)
    assert Decimal.equal?(r_row.quantity, Decimal.new("5"))
    assert Decimal.equal?(r_row.avg_cost, Decimal.new("200"))
    assert Decimal.equal?(r_row.cost_basis, Decimal.new("1000"))

    m_row = row_for(holdings, m.id, depot_one.id)
    assert Decimal.equal?(m_row.quantity, Decimal.new("15"))
    assert Decimal.equal?(m_row.cost_basis, Decimal.new("500"))
    assert Decimal.equal?(Decimal.round(m_row.avg_cost, 4), Decimal.new("33.3333"))
    assert Decimal.equal?(m_row.market_value, Decimal.new("1500"))
    assert Decimal.equal?(m_row.unrealized_pnl_abs, Decimal.new("1000"))
    assert Decimal.equal?(m_row.unrealized_pnl_pct, Decimal.new("2"))

    n_row = row_for(holdings, n.id, depot_one.id)
    assert Decimal.equal?(n_row.quantity, Decimal.new("5"))
    assert Decimal.equal?(n_row.avg_cost, Decimal.new("0"))
    assert Decimal.equal?(n_row.cost_basis, Decimal.new("0"))

    o_row = row_for(holdings, o.id, depot_one.id)
    assert Decimal.equal?(o_row.quantity, Decimal.new("-5"))
    assert Decimal.equal?(o_row.cost_basis, Decimal.new("0"))
    assert Decimal.equal?(o_row.market_value, Decimal.new("-600"))
    assert Decimal.equal?(o_row.unrealized_pnl_abs, Decimal.new("-600"))
    assert Decimal.equal?(o_row.unrealized_pnl_pct, Decimal.new("0"))
  end
end
