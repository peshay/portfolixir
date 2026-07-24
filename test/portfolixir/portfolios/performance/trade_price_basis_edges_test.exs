defmodule Portfolixir.Portfolios.Performance.TradePriceBasisEdgesTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [
      base_world: 1,
      buy!: 3,
      create_security!: 1,
      deposit!: 3,
      deposit!: 4,
      put_quote!: 3,
      sell!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Performance

  defp r6(decimal), do: Decimal.round(decimal, 6)

  defp day(result, date), do: Enum.find(result.series, &(Date.compare(&1.date, date) == :eq))

  defp delivery!(world, security, type, quantity, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: security.id,
        type: type,
        date: date,
        quantity: quantity,
        currency_code: "EUR"
      })

    tx
  end

  defp oversell!(world, security, quantity, price, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: "sell",
        date: date,
        quantity: quantity,
        price: price,
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    tx
  end

  defp usd_rate!(date, rate) do
    {:ok, _rows} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: date,
          rate: rate,
          source: "manual"
        }
      ])
  end

  # -- D1: several trade points on one day ------------------------------------

  # User story (issue #545 fix round, defect D1):
  # As a local portfolio maintainer who books more than one trade of the same
  # unquoted security on one day,
  # I want the day's whole re-pricing neutralised, not just a quantity net,
  # so that splitting one economic decision into several bookings cannot invent
  # or destroy return.
  #
  # Acceptance criteria:
  # - Selling the whole position and buying it back the same day at a higher
  #   own trade price is no market move (was -0.6666..., `main` said 0).
  # - Two buys at different prices on one day are no market move
  #   (was +0.0285714...).
  # - One order filled twice a day 1 % apart is no market move
  #   (was +0.0004995...).
  test "selling out and re-entering the same day at a new own price is no return" do
    world = base_world(name: "D1G", cash_name: "D1G Cash", depot_name: "D1G Depot")
    security = create_security!(name: "Roundtrip Co", ticker: "D1G")

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])

    sell!(world, security, quantity: "10", price: "100", date: ~D[2026-01-10])
    buy!(world, security, quantity: "10", price: "300", date: ~D[2026-01-10])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-11])

    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
    # 3,000 of position against a 2,000 overdraft: the money facts as booked.
    assert Decimal.equal?(result.end_value, Decimal.new("1000"))
    assert Decimal.equal?(day(result, ~D[2026-01-10]).basis, Decimal.new("0"))
  end

  test "two buys of one unquoted security on one day are no return" do
    world = base_world(name: "D1A", cash_name: "D1A Cash", depot_name: "D1A Depot")
    security = create_security!(name: "Two Fills Co", ticker: "D1A")

    deposit!(world, "20000", ~D[2026-01-01])
    buy!(world, security, quantity: "100", price: "100", date: ~D[2026-01-01])

    buy!(world, security, quantity: "10", price: "150", date: ~D[2026-01-05])
    buy!(world, security, quantity: "10", price: "250", date: ~D[2026-01-05])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-06])

    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
    assert Decimal.equal?(day(result, ~D[2026-01-05]).basis, Decimal.new("16000"))
  end

  test "one order booked as two same-day fills is no return" do
    world = base_world(name: "D1Q", cash_name: "D1Q Cash", depot_name: "D1Q Depot")
    security = create_security!(name: "Partial Fill Co", ticker: "D1Q")

    deposit!(world, "100000", ~D[2026-01-01])
    buy!(world, security, quantity: "100", price: "100", date: ~D[2026-01-01])

    buy!(world, security, quantity: "50", price: "100", date: ~D[2026-01-10])
    buy!(world, security, quantity: "50", price: "101", date: ~D[2026-01-10])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-11])

    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
    assert Decimal.equal?(day(result, ~D[2026-01-10]).basis, Decimal.new("150"))
  end

  # -- D2: sign-blind retained quantity ---------------------------------------

  # User story (issue #545 fix round, defect D2):
  # As a local portfolio maintainer whose ledger contains a short (or an
  # oversell, which the ledger does not currently reject),
  # I want the basis step to follow the sign of what is actually held,
  # so that a negative position neither fabricates return nor swallows a real
  # loss.
  #
  # Acceptance criteria:
  # - Selling 15 of a 10-lot realises the 10 held units and nothing else
  #   (was +3.0, `main` said +1.0).
  # - Buying 3 of that short back at double the price books the 600 loss
  #   (the day factor was exactly 1.0 — the loss vanished).
  # - Opening a short in an unquoted security fabricates no step (was +0.40).
  # - Flipping long to short in one day keeps the realised doubling (was 0.00).
  test "overselling into a short realises the held slice and nothing more" do
    world = base_world(name: "D2B", cash_name: "D2B Cash", depot_name: "D2B Depot")
    security = create_security!(name: "Oversold Co", ticker: "D2B")

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])
    oversell!(world, security, "15", "200", ~D[2026-01-05])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-06])

    assert Decimal.equal?(result.ttwror, Decimal.new("1"))
    assert Decimal.equal?(day(result, ~D[2026-01-05]).basis, Decimal.new("0"))
    assert Decimal.equal?(result.end_value, Decimal.new("2000"))
  end

  test "buying back part of a short books its loss" do
    world = base_world(name: "D2C", cash_name: "D2C Cash", depot_name: "D2C Depot")
    security = create_security!(name: "Bought Back Co", ticker: "D2C")

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])
    oversell!(world, security, "15", "200", ~D[2026-01-05])
    buy!(world, security, quantity: "3", price: "400", date: ~D[2026-01-10])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-11])

    # 01-05 doubles (factor 2), 01-10 loses 600 against a base of 1600
    # (factor 0.625): 2 x 0.625 - 1 = 0.25.
    assert Decimal.equal?(r6(result.ttwror), Decimal.new("0.250000"))
    assert Decimal.equal?(day(result, ~D[2026-01-10]).basis, Decimal.new("-400"))
  end

  test "opening a short in an unquoted security fabricates no basis step" do
    world = base_world(name: "D2S", cash_name: "D2S Cash", depot_name: "D2S Depot")
    quoted = create_security!(name: "Quoted Co", ticker: "D2SQ")
    unquoted = create_security!(name: "Shorted Co", ticker: "D2SU")

    deposit!(world, "2000", ~D[2026-01-01])
    put_quote!(quoted, ~D[2026-01-01], "100")
    buy!(world, quoted, quantity: "10", price: "100", date: ~D[2026-01-01])

    put_quote!(quoted, ~D[2026-01-05], "110")
    oversell!(world, unquoted, "10", "50", ~D[2026-01-05])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-05])

    # The only observed move is the quoted +10 % on a 2,000 base.
    assert Decimal.equal?(r6(result.ttwror), Decimal.new("0.050000"))
    assert Decimal.equal?(result.end_value, Decimal.new("2100"))
  end

  test "flipping long to short in one day keeps the realised doubling" do
    world = base_world(name: "D2F", cash_name: "D2F Cash", depot_name: "D2F Depot")
    security = create_security!(name: "Flipped Co", ticker: "D2F")

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])
    oversell!(world, security, "25", "200", ~D[2026-01-10])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10])

    assert Decimal.equal?(r6(result.ttwror), Decimal.new("1.000000"))
    assert Decimal.equal?(result.end_value, Decimal.new("2000"))
  end

  # -- D3: outbound delivery is not a realisation -----------------------------

  # User story (issue #545 fix round, defect D3):
  # As a local portfolio maintainer who moves an unquoted position out of the
  # portfolio without selling it,
  # I want the delivered-out quantity to carry its basis step like the retained
  # quantity does,
  # so that a removal that produced no cash cannot show up as return.
  #
  # Acceptance criteria:
  # - Delivering 4 out on the day a buy re-prices the position is no market
  #   move (was +0.6666...).
  # - With a real sale on the same day only the sold slice earns
  #   (was +0.5555...).
  test "an outbound delivery on a trade-step day carries its basis step" do
    world = base_world(name: "D3E", cash_name: "D3E Cash", depot_name: "D3E Depot")
    security = create_security!(name: "Delivered Co", ticker: "D3E")

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])

    delivery!(world, security, "outbound_delivery", "4", ~D[2026-01-10])
    buy!(world, security, quantity: "1", price: "500", date: ~D[2026-01-10])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-11])

    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
    assert Decimal.equal?(day(result, ~D[2026-01-10]).basis, Decimal.new("4000"))
  end

  test "a sale and an outbound delivery on one day earn only on the sold slice" do
    world = base_world(name: "D3O", cash_name: "D3O Cash", depot_name: "D3O Depot")
    security = create_security!(name: "Split Exit Co", ticker: "D3O")

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])

    sell!(world, security, quantity: "2", price: "200", date: ~D[2026-01-10])
    delivery!(world, security, "outbound_delivery", "3", ~D[2026-01-10])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10])

    # Base 1000 - 600 (flow) + 800 (basis) = 1200 against a value of 1400.
    assert Decimal.equal?(r6(result.ttwror), Decimal.new("0.166667"))
    assert Decimal.equal?(result.end_value, Decimal.new("1400"))
    assert Decimal.equal?(day(result, ~D[2026-01-10]).basis, Decimal.new("800"))
  end

  # -- D4: the step belongs to the previous day's FX ---------------------------

  # User story (issue #545 fix round, defect D4):
  # As a local portfolio maintainer holding an unquoted foreign-currency
  # position,
  # I want the currency move of the retained sleeve to stay in my return,
  # so that neutralising a fabricated price step cannot silently neutralise a
  # real exchange-rate move with it.
  #
  # Acceptance criteria:
  # - USD halving against EUR on the same day a buy re-prices the position is
  #   exactly -50 % (was -0.476190...).
  # - The identical economics with the price step one day later is unchanged
  #   at -50 % (the control that pinned the defect).
  test "a same-day FX move survives the basis step" do
    usd_rate!(~D[2025-12-01], "1.0")
    usd_rate!(~D[2026-01-10], "2.0")

    world =
      base_world(
        name: "D4A",
        cash_name: "D4A Cash",
        depot_name: "D4A Depot",
        cash_currency: "USD"
      )

    security = create_security!(name: "US Unquoted Co", ticker: "D4A", currency: "USD")

    deposit!(world, "10000", ~D[2026-01-01], currency: "USD")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01], currency: "USD")
    buy!(world, security, quantity: "1", price: "200", date: ~D[2026-01-10], currency: "USD")

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-11])

    assert Decimal.equal?(r6(result.ttwror), Decimal.new("-0.500000"))
    # 10 retained units x (200 - 100) USD, converted at yesterday's rate.
    assert Decimal.equal?(day(result, ~D[2026-01-10]).basis, Decimal.new("1000"))
  end

  test "the same FX move with the price step a day later is unchanged" do
    usd_rate!(~D[2025-12-01], "1.0")
    usd_rate!(~D[2026-01-10], "2.0")

    world =
      base_world(
        name: "D4B",
        cash_name: "D4B Cash",
        depot_name: "D4B Depot",
        cash_currency: "USD"
      )

    security = create_security!(name: "US Unquoted Co", ticker: "D4B", currency: "USD")

    deposit!(world, "10000", ~D[2026-01-01], currency: "USD")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01], currency: "USD")
    buy!(world, security, quantity: "1", price: "200", date: ~D[2026-01-11], currency: "USD")

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-12])

    assert Decimal.equal?(r6(result.ttwror), Decimal.new("-0.500000"))
  end

  # -- D5: the first quote ever is a basis step, a gap is not ------------------

  # User story (issue #545 fix round, defect D5):
  # As a local portfolio maintainer who follows the documented remedy and loads
  # quote history for an unquoted holding,
  # I want the arrival of the first quote to restate the fabricated basis, not
  # to discharge years of it as one day of return,
  # so that the recommended fix does not reproduce the explosion #545 removed.
  #
  # Acceptance criteria:
  # - A forward-only quote load (one quote, long after the buys) leaves the
  #   TTWROR flat (was +49, i.e. +4,900 %).
  # - A quote landing on the same day as a trade of a never-quoted security is
  #   the same transition, not a market day (was +1.55).
  # - A security that already has quote history is measured: the later quote
  #   move stays return (the control that keeps AC 2 honest).
  test "the first quote ever for a trade-priced position is a basis step" do
    world = base_world(name: "D5L", cash_name: "D5L Cash", depot_name: "D5L Depot")
    security = create_security!(name: "Late Quote Co", ticker: "D5L")

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])

    # The feed only covers recent dates — the usual shape of a quote load.
    put_quote!(security, ~D[2026-01-20], "5000")

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-21])

    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
    assert Decimal.equal?(day(result, ~D[2026-01-20]).basis, Decimal.new("49000"))
    # The money facts stay as booked.
    assert Decimal.equal?(result.end_value, Decimal.new("50000"))
  end

  test "a quote landing on a trade day of a never-quoted security is a basis step" do
    world = base_world(name: "D5M", cash_name: "D5M Cash", depot_name: "D5M Depot")
    security = create_security!(name: "First Quote Co", ticker: "D5M")

    deposit!(world, "2000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])

    buy!(world, security, quantity: "1", price: "300", date: ~D[2026-01-10])
    put_quote!(security, ~D[2026-01-10], "400")

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-11])

    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
    assert Decimal.equal?(day(result, ~D[2026-01-10]).basis, Decimal.new("3100"))
  end

  test "a security with quote history keeps its later quote moves as return" do
    world = base_world(name: "D5R", cash_name: "D5R Cash", depot_name: "D5R Depot")
    security = create_security!(name: "Backfilled Co", ticker: "D5R")

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])
    put_quote!(security, ~D[2026-01-01], "100")
    put_quote!(security, ~D[2026-01-20], "5000")

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-21])

    assert Decimal.equal?(r6(result.ttwror), Decimal.new("49.000000"))
    assert Decimal.equal?(day(result, ~D[2026-01-20]).basis, Decimal.new("0"))
  end

  # -- guards on cases the fix must leave alone --------------------------------

  # User story (issue #545 fix round, no-regression guard):
  # As a local portfolio maintainer,
  # I want the cases the basis step already handled correctly to keep their
  # exact figures,
  # so that repairing the same-day and sign edges cannot quietly move a number
  # that was already right.
  #
  # Acceptance criteria:
  # - A same-day buy and sell of an unquoted security realises the round trip
  #   and neutralises the rest.
  # - An inbound delivery plus a sale on one day stays flat: the delivered
  #   units arrive at the day's price, so nothing was realised against them.
  test "a same-day buy and sell realises only the round trip" do
    world = base_world(name: "GC", cash_name: "GC Cash", depot_name: "GC Depot")
    security = create_security!(name: "Round Trip Co", ticker: "GCC")

    deposit!(world, "3000", ~D[2026-01-02])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(world, security, quantity: "5", price: "200", date: ~D[2026-01-10])
    sell!(world, security, quantity: "5", price: "300", date: ~D[2026-01-10])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10])

    assert Decimal.equal?(r6(result.ttwror), Decimal.new("0.100000"))
    assert Decimal.equal?(day(result, ~D[2026-01-10]).basis, Decimal.new("2000"))
  end

  test "an inbound delivery and a sale on one day stay flat" do
    world = base_world(name: "GH", cash_name: "GH Cash", depot_name: "GH Depot")
    security = create_security!(name: "Delivered In Co", ticker: "GHC")

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])

    delivery!(world, security, "inbound_delivery", "5", ~D[2026-01-10])
    sell!(world, security, quantity: "2", price: "500", date: ~D[2026-01-10])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-11])

    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
    assert Decimal.equal?(day(result, ~D[2026-01-10]).basis, Decimal.new("4000"))
  end

  # User story (issue #545 fix round, defect D6 — documented residual):
  # As a local portfolio maintainer writing an unquoted holding off,
  # I want to know that a partial write-off and a full one do not report the
  # same percentage,
  # so that the divergence is a recorded property of the method rather than a
  # surprise.
  #
  # Acceptance criteria:
  # - Selling 4 of 10 at price 0 reads -0.2857...: only the sold slice is
  #   realised, the retained slice's mark-down restates the base.
  # - Selling all 10 at price 0 reads -0.5: everything became (zero) cash.
  # - The asymmetry is inherent to neutralising trade-price marks; ADR-0010
  #   records it instead of special-casing a zero price.
  test "a partial and a full write-off diverge (documented residual)" do
    partial = base_world(name: "W4", cash_name: "W4 Cash", depot_name: "W4 Depot")
    partial_security = create_security!(name: "Partial Off Co", ticker: "W4C")

    deposit!(partial, "2000", ~D[2026-01-01])
    buy!(partial, partial_security, quantity: "10", price: "100", date: ~D[2026-01-01])
    sell!(partial, partial_security, quantity: "4", price: "0", date: ~D[2026-01-10])

    full = base_world(name: "W10", cash_name: "W10 Cash", depot_name: "W10 Depot")
    full_security = create_security!(name: "Full Off Co", ticker: "W1C")

    deposit!(full, "2000", ~D[2026-01-01])
    buy!(full, full_security, quantity: "10", price: "100", date: ~D[2026-01-01])
    sell!(full, full_security, quantity: "10", price: "0", date: ~D[2026-01-10])

    {:ok, partial_result} = Performance.for_portfolio(partial.portfolio.id, today: ~D[2026-01-11])
    {:ok, full_result} = Performance.for_portfolio(full.portfolio.id, today: ~D[2026-01-11])

    assert Decimal.equal?(r6(partial_result.ttwror), Decimal.new("-0.285714"))
    assert Decimal.equal?(r6(full_result.ttwror), Decimal.new("-0.500000"))
  end
end
