defmodule Portfolixir.LedgerHoldingsForSecurityTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger

  # User story:
  # As a local portfolio maintainer,
  # I want to see how many units of a security I currently hold in each
  # portfolio/depot, what the moving-average cost basis is, and the
  # current value at the latest known price,
  # so that the security detail view can act as a single-asset
  # holdings summary.

  defp setup_world do
    security =
      create_security!(name: "Apple Inc.", ticker: "AAPL", currency: "USD", asset_class: "equity")

    %{portfolio: portfolio_a, cash: cash_a, depot: depot_a} =
      base_world(
        name: "Personal",
        currency: "USD",
        cash_name: "Personal Cash",
        depot_name: "Personal Depot"
      )

    %{portfolio: portfolio_b, cash: cash_b, depot: depot_b} =
      base_world(
        name: "Joint",
        currency: "USD",
        cash_name: "Joint Cash",
        depot_name: "Joint Depot"
      )

    %{
      security: security,
      portfolio_a: portfolio_a,
      cash_a: cash_a,
      depot_a: depot_a,
      portfolio_b: portfolio_b,
      cash_b: cash_b,
      depot_b: depot_b
    }
  end

  defp tx!(w, depot, cash, portfolio, type, date, qty, price) do
    {:ok, t} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: w.security.id,
        type: type,
        date: date,
        quantity: Decimal.new(qty),
        price: Decimal.new(price),
        fees: Decimal.new("0"),
        taxes: Decimal.new("0"),
        currency_code: "USD"
      })

    t
  end

  test "aggregates open quantity and moving-average cost per depot" do
    w = setup_world()
    tx!(w, w.depot_a, w.cash_a, w.portfolio_a, "buy", ~D[2026-01-10], "10", "100.00")
    tx!(w, w.depot_a, w.cash_a, w.portfolio_a, "buy", ~D[2026-02-10], "10", "200.00")
    tx!(w, w.depot_a, w.cash_a, w.portfolio_a, "sell", ~D[2026-03-10], "5", "180.00")

    [holding] = Ledger.holdings_for_security(w.security.id)

    assert holding.portfolio.id == w.portfolio_a.id
    assert holding.depot.id == w.depot_a.id
    # 10 + 10 - 5 = 15 units
    assert Decimal.equal?(holding.quantity, Decimal.new("15"))
    # Moving avg cost stayed at 150 after the second buy (10*100 + 10*200) / 20 = 150
    # Sell does not change avg cost.
    assert Decimal.equal?(holding.avg_cost, Decimal.new("150"))
  end

  test "returns one row per (portfolio, depot) and uses latest quote for value" do
    w = setup_world()
    tx!(w, w.depot_a, w.cash_a, w.portfolio_a, "buy", ~D[2026-01-10], "10", "100.00")
    tx!(w, w.depot_b, w.cash_b, w.portfolio_b, "buy", ~D[2026-02-10], "5", "120.00")

    {:ok, _} =
      Quotes.upsert_many(w.security.id, [
        %{date: ~D[2026-05-15], close: "150.00", source: "manual"}
      ])

    rows = Ledger.holdings_for_security(w.security.id)
    assert length(rows) == 2

    personal = Enum.find(rows, &(&1.portfolio.id == w.portfolio_a.id))
    joint = Enum.find(rows, &(&1.portfolio.id == w.portfolio_b.id))

    # 10 * 150 = 1500
    assert Decimal.equal?(personal.current_value, Decimal.new("1500"))
    # 10 * (150 - 100) = +500
    assert Decimal.equal?(personal.unrealized_pnl_abs, Decimal.new("500"))

    assert Decimal.equal?(joint.current_value, Decimal.new("750"))
    # 5 * (150 - 120) = +150
    assert Decimal.equal?(joint.unrealized_pnl_abs, Decimal.new("150"))
  end

  test "omits fully closed positions (zero remaining quantity)" do
    w = setup_world()
    tx!(w, w.depot_a, w.cash_a, w.portfolio_a, "buy", ~D[2026-01-10], "10", "100.00")
    tx!(w, w.depot_a, w.cash_a, w.portfolio_a, "sell", ~D[2026-03-10], "10", "180.00")

    assert Ledger.holdings_for_security(w.security.id) == []
  end

  defp delivery!(w, depot, portfolio, type, date, qty) do
    {:ok, t} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        security_id: w.security.id,
        type: type,
        date: date,
        quantity: Decimal.new(qty),
        currency_code: "USD"
      })

    t
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the security detail holdings to reflect deliveries,
  # so that shares that left the depot without a sell (e.g. a takeover
  # booked as an outbound delivery) are not reported as still held.
  #
  # Acceptance criteria:
  # - A full outbound delivery closes the position (no row).
  # - A partial outbound delivery reduces the quantity while the
  #   moving-average cost of the buys is kept.
  # - An inbound delivery adds held quantity without a priced trade.
  test "deliveries move the held quantity per depot" do
    w = setup_world()

    # Depot A: bought, then partially delivered out.
    tx!(w, w.depot_a, w.cash_a, w.portfolio_a, "buy", ~D[2026-01-10], "10", "100.00")
    delivery!(w, w.depot_a, w.portfolio_a, "outbound_delivery", ~D[2026-03-10], "4")

    # Depot B: shares arrived by inbound delivery only.
    delivery!(w, w.depot_b, w.portfolio_b, "inbound_delivery", ~D[2026-02-10], "3")

    rows = Ledger.holdings_for_security(w.security.id)
    assert length(rows) == 2

    personal = Enum.find(rows, &(&1.portfolio.id == w.portfolio_a.id))
    assert Decimal.equal?(personal.quantity, Decimal.new("6"))
    assert Decimal.equal?(personal.avg_cost, Decimal.new("100"))

    joint = Enum.find(rows, &(&1.portfolio.id == w.portfolio_b.id))
    assert joint.depot.id == w.depot_b.id
    assert Decimal.equal?(joint.quantity, Decimal.new("3"))
    assert Decimal.equal?(joint.avg_cost, Decimal.new("0"))
  end

  test "omits a position fully removed by an outbound delivery" do
    w = setup_world()
    tx!(w, w.depot_a, w.cash_a, w.portfolio_a, "buy", ~D[2026-01-10], "10", "100.00")
    delivery!(w, w.depot_a, w.portfolio_a, "outbound_delivery", ~D[2026-03-10], "10")

    assert Ledger.holdings_for_security(w.security.id) == []
  end

  test "returns nil current value when no quote is available" do
    w = setup_world()
    tx!(w, w.depot_a, w.cash_a, w.portfolio_a, "buy", ~D[2026-01-10], "10", "100.00")

    [holding] = Ledger.holdings_for_security(w.security.id)
    assert is_nil(holding.current_value)
    assert is_nil(holding.unrealized_pnl_abs)
    assert is_nil(holding.unrealized_pnl_pct)
  end
end
