defmodule Portfolixir.Portfolios.Performance.RetiredSecuritiesTest do
  # Sprint 11 Lane X (D-3 of the plan): the daily walk on securities whose
  # quote feed has stopped — a delivery carrying a booked price (#779). Risk-tier (ADR-0036): every figure
  # below is an exact Decimal, derived by hand in the comments.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Performance

  defp r6(decimal), do: Decimal.round(decimal, 6)

  defp day(result, date), do: Enum.find(result.series, &(Date.compare(&1.date, date) == :eq))

  # A delivery, with or without a booked price: `price` is persisted on both
  # delivery kinds (#585) and, since #779, no longer data retention only.
  defp delivery!(world, security, type, quantity, date, opts \\ []) do
    attrs = %{
      portfolio_id: world.portfolio.id,
      securities_account_id: world.depot.id,
      security_id: security.id,
      type: type,
      date: date,
      quantity: quantity,
      currency_code: "EUR"
    }

    attrs =
      case Keyword.get(opts, :price) do
        nil -> attrs
        price -> Map.put(attrs, :price, price)
      end

    {:ok, tx} = Ledger.create_transaction(Actor.owner_ui(), attrs)
    tx
  end

  defp retire!(security) do
    {:ok, retired} = Catalog.update_security(Actor.owner_ui(), security, %{is_retired: true})
    retired
  end

  # User story (#779):
  # As a local portfolio maintainer whose failed holding was booked out of the
  # depot as an outbound delivery at price 0,
  # I want that total loss to enter the period's TTWROR,
  # so that the write-off is a loss in the figure and not a withdrawal at the
  # last stale quote.
  #
  # Acceptance criteria:
  # - A delivery carrying a booked price enters the day's external flow at that
  #   price: booked out at 0, the flow is 0 and the day's return is -100 %.
  # - The same booking without a price keeps the day's-quote rule: the stale
  #   quote values the outflow, the return base collapses to zero and the day
  #   reads flat, exactly as before this change.
  test "a total loss booked out at price 0 shows the loss in the period's TTWROR" do
    world = base_world(name: "TL", cash_name: "TL Cash", depot_name: "TL Depot")
    security = create_security!(name: "Failed Co", ticker: "FAIL")

    deposit!(world, "1000", ~D[2026-01-01])
    put_quote!(security, ~D[2026-01-01], "100")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])

    # The feed stopped at 100; the position leaves the depot at 0.
    delivery!(world, security, "outbound_delivery", "10", ~D[2026-01-20], price: "0")

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-21])

    # V_19 = 1000 (10 x the carried 100), F_20 = 10 x 0 = 0, V_20 = 0:
    # r_20 = 0 / (1000 + 0) - 1 = -1.
    assert Decimal.equal?(day(result, ~D[2026-01-20]).flow, Decimal.new("0"))
    assert Decimal.equal?(result.ttwror, Decimal.new("-1"))
    assert Decimal.equal?(result.end_value, Decimal.new("0"))
    # The money facts: the deposit is the only external money.
    assert Decimal.equal?(result.net_external_flows, Decimal.new("1000"))
  end

  test "the same write-off without a booked price stays as today: flat, at the stale quote" do
    world = base_world(name: "TLU", cash_name: "TLU Cash", depot_name: "TLU Depot")
    security = create_security!(name: "Unpriced Exit Co", ticker: "UEX")

    deposit!(world, "1000", ~D[2026-01-01])
    put_quote!(security, ~D[2026-01-01], "100")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])

    delivery!(world, security, "outbound_delivery", "10", ~D[2026-01-20])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-21])

    # F_20 = -10 x 100 at the carried quote; the base 1000 - 1000 = 0 makes
    # the day a factor of 1 (day_factor/2), so nothing of the loss shows.
    assert Decimal.equal?(day(result, ~D[2026-01-20]).flow, Decimal.new("-1000"))
    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("0"))
  end

  # User story (#779, the inbound side):
  # As a local portfolio maintainer recording an inbound delivery at the value
  # the transfer statement carries,
  # I want that value, not the day's quote, to be the flow,
  # so that the walk and the money-weighted set (ADR-0034 §1: deliveries at
  # full transaction value) agree on the same booking.
  #
  # Acceptance criteria:
  # - Delivered in at 80 while the quote is 100, the flow is 5 x 80 = 400 and
  #   the difference to the market value is the day's return.
  test "a priced inbound delivery enters the flow at its booked price" do
    world = base_world(name: "PID", cash_name: "PID Cash", depot_name: "PID Depot")
    security = create_security!(name: "Delivered Co", ticker: "DLV")

    deposit!(world, "1000", ~D[2026-01-01])
    put_quote!(security, ~D[2026-01-01], "100")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])

    delivery!(world, security, "inbound_delivery", "5", ~D[2026-01-10], price: "80")

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-11])

    # V_9 = 1000, F_10 = 5 x 80 = 400, V_10 = 15 x 100 = 1500:
    # r_10 = 1500 / 1400 - 1 = 0.0714285...
    assert Decimal.equal?(day(result, ~D[2026-01-10]).flow, Decimal.new("400"))
    assert Decimal.equal?(r6(result.ttwror), Decimal.new("0.071429"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("1400"))
  end

  # User story (#779, the basis queue):
  # As a local portfolio maintainer whose unquoted position is delivered out
  # at its booked price on the day a buy re-prices the rest,
  # I want the delivered units to leave the lot queue at that price like a
  # sale would,
  # so that F_d and B_d never disagree about the same units.
  #
  # Acceptance criteria:
  # - Booked out at the old price on a trade-step day: no return, the retained
  #   sleeve's step alone (was: the delivered units marked at the day's price).
  # - Booked out at 0 on the same day: the loss on those units is return, the
  #   retained sleeve's step is unchanged.
  test "a priced outbound delivery leaves the lot queue at its price on a trade-step day" do
    world = base_world(name: "PQ", cash_name: "PQ Cash", depot_name: "PQ Depot")
    security = create_security!(name: "Queue Co", ticker: "QUE")

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])

    delivery!(world, security, "outbound_delivery", "4", ~D[2026-01-10], price: "100")
    buy!(world, security, quantity: "1", price: "500", date: ~D[2026-01-10])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-11])

    # F_10 = -4 x 100 = -400; lots: the delivery consumes 4 of the sleeve at
    # its own price, the buy adds 1 at 500; B_10 = 6 x (500 - 100) = 2400.
    # V_10 = 7 x 500 - 500 (the buy's cash) = 3000 = 1000 - 400 + 2400.
    assert Decimal.equal?(day(result, ~D[2026-01-10]).flow, Decimal.new("-400"))
    assert Decimal.equal?(day(result, ~D[2026-01-10]).basis, Decimal.new("2400"))
    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
  end

  test "a write-off at 0 on a trade-step day realises the loss on the delivered units only" do
    world = base_world(name: "PQ0", cash_name: "PQ0 Cash", depot_name: "PQ0 Depot")
    security = create_security!(name: "Queue Zero Co", ticker: "QZE")

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])

    delivery!(world, security, "outbound_delivery", "4", ~D[2026-01-10], price: "0")
    buy!(world, security, quantity: "1", price: "500", date: ~D[2026-01-10])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-11])

    # F_10 = 0, B_10 = 2400 as above; base = 1000 + 0 + 2400 = 3400 against
    # V_10 = 3000: the 4 units worth 400 at basis are the loss, -0.117647.
    assert Decimal.equal?(day(result, ~D[2026-01-10]).flow, Decimal.new("0"))
    assert Decimal.equal?(day(result, ~D[2026-01-10]).basis, Decimal.new("2400"))
    assert Decimal.equal?(r6(result.ttwror), Decimal.new("-0.117647"))
  end
end
