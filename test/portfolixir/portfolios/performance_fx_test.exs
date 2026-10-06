defmodule Portfolixir.Portfolios.PerformanceFxTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, deposit!: 4]

  alias Portfolixir.Fx
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.WorldFixtures

  # User story:
  # As a maintainer with foreign-currency holdings,
  # I want the daily performance walk to value a non-EUR position and its cash
  # through the stored EUR-hub exchange rates of each day,
  # so that my TTWROR reflects both the security's price moves and the FX moves
  # between my position currency and my portfolio base currency.
  #
  # Acceptance criteria:
  # - A USD position in a EUR-base portfolio is valued each day at that day's
  #   USD price converted at that day's EUR/USD rate (the in-memory FX series).
  # - An external deposit booked in the foreign cash account counts as a base-
  #   currency flow at that day's rate.
  # - A pure FX move (no price or flow change) still moves the daily value and
  #   therefore contributes to the chained TTWROR.

  defp setup_world do
    # EUR base portfolio with a USD cash account + depot, so a USD security
    # buys cleanly into a matching-currency cash account (issue #343) while the
    # base-currency valuation still has to triangulate USD -> EUR.
    world = base_world(name: "FX", currency: "EUR", cash_currency: "USD")
    security = create_security!(name: "US Index", ticker: "USDX", currency: "USD")
    Map.put(world, :security, security)
  end

  defp buy!(world, qty, price, date) do
    WorldFixtures.buy!(world, world.security,
      quantity: qty,
      price: price,
      date: date,
      currency: "USD"
    )
  end

  defp quote!(world, close, date), do: WorldFixtures.put_quote!(world.security, date, close)

  defp rate!(quote_ccy, date, rate) do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: quote_ccy,
          date: date,
          rate: rate,
          source: "manual"
        }
      ])
  end

  defp rounded(decimal, places), do: Decimal.round(decimal, places)

  test "values a USD position through the stored EUR/USD rate of each day" do
    world = setup_world()

    # Day 1: 1000 USD in, all invested at 100 USD. EUR/USD = 1.25 (1 USD = 0.8
    # EUR), quote 100 USD -> value 1000 USD = 800 EUR.
    deposit!(world, "1000", ~D[2026-01-01], currency: "USD")
    buy!(world, "10", "100", ~D[2026-01-01])
    quote!(world, "100", ~D[2026-01-01])
    rate!("USD", ~D[2026-01-01], "1.25")

    # Day 10: USD price rises to 120 (rate unchanged) -> 1200 USD = 960 EUR.
    quote!(world, "120", ~D[2026-01-10])

    # Day 20: a pure FX move, EUR/USD = 1.20 (1 USD = 0.8333.. EUR), price held
    # at 120 USD -> 1200 USD = 1000 EUR. This exercises the in-memory FX series
    # advancing to a second rate point with no other booking that day.
    rate!("USD", ~D[2026-01-20], "1.20")

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-20])

    assert result.base_currency == "EUR"

    # TTWROR = (960/800) * (1000/960) - 1 = 1000/800 - 1 = 0.25.
    assert rounded(result.ttwror, 6) |> Decimal.equal?(Decimal.new("0.25"))

    # End value is the USD position valued at the final day's rate.
    assert Decimal.equal?(result.end_value, Decimal.new("1000"))
    assert Decimal.equal?(result.start_value, Decimal.new("0"))

    # The deposit is the only external flow, converted at day 1's rate.
    assert Decimal.equal?(result.net_external_flows, Decimal.new("800"))

    assert length(result.series) == 20

    last = List.last(result.series)
    assert Decimal.equal?(last.cumulative_ttwror, result.ttwror)

    # A single contribution that ends higher in base currency yields a positive
    # money-weighted return.
    assert %Decimal{} = result.irr
    assert Decimal.compare(result.irr, Decimal.new("0")) == :gt
  end

  # User story:
  # As a maintainer holding a London-listed security quoted in pence (GBX),
  # I want the daily walk to value it through GBP x 100 against my EUR base,
  # so that a pence-quoted position is valued as precisely as any other.
  #
  # Acceptance criteria:
  # - A GBX-quoted security in a EUR-base portfolio is valued each day at its
  #   pence price converted via GBP x 100 and the stored EUR/GBP rate.
  # - A rate stored before the first walk day is carried in as the opening
  #   rate (no separate point needed on day one).
  # - The chained TTWROR reflects the GBP price move, with values Decimal-exact.
  test "values a GBX (pence) position through GBP x 100 against the EUR base" do
    # EUR base portfolio, GBX cash account + depot so the pence-quoted security
    # buys cleanly into a matching-currency cash account (issue #343); the base-
    # currency valuation still has to triangulate GBX -> GBP x 100 -> EUR.
    world = base_world(name: "GBX", currency: "EUR", cash_currency: "GBX")
    security = create_security!(name: "London PLC", ticker: "LON", currency: "GBX")
    world = Map.put(world, :security, security)

    # Rate stored the day BEFORE the walk starts: EUR/GBP = 0.80 (1 GBP = 1.25
    # EUR). This exercises the carried-in FX point (Fx.hub_rate_before path).
    rate!("GBP", ~D[2025-12-31], "0.80")

    # Day 1: deposit 100000 GBX, buy 100 shares at 500 GBX each (= 50000 GBX),
    # leaving 50000 GBX cash. All amounts in GBX, matching the cash account.
    deposit!(world, "100000", ~D[2026-01-01], currency: "GBX")

    WorldFixtures.buy!(world, world.security,
      quantity: "100",
      price: "500",
      date: ~D[2026-01-01],
      currency: "GBX"
    )

    quote!(world, "500", ~D[2026-01-01])

    # Day 5: price rises to 600 GBX, rate unchanged.
    quote!(world, "600", ~D[2026-01-05])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-05])

    assert result.base_currency == "EUR"

    # EUR/GBP = 0.80 -> 1 GBP = 1.25 EUR, and 1 GBX = 0.01 GBP = 0.0125 EUR.
    # Day 1 value: position 100 * 500 = 50000 GBX + 50000 GBX cash = 100000 GBX
    #   = 1250 EUR. Day 5 value: position 100 * 600 = 60000 GBX + 50000 GBX cash
    #   = 110000 GBX = 1375 EUR.
    assert Decimal.equal?(result.end_value, Decimal.new("1375"))

    # Deposit of 100000 GBX at day 1's rate -> 1250 EUR external flow.
    assert Decimal.equal?(result.net_external_flows, Decimal.new("1250"))

    # No flow after the opening day, so TTWROR = 880/800 - 1 = 0.1.
    assert rounded(result.ttwror, 6) |> Decimal.equal?(Decimal.new("0.1"))
  end

  test "an unpriced FX path leaves a foreign position unvalued instead of crashing" do
    world = setup_world()

    # Deposit and buy a USD position, but never store a EUR/USD rate: the in-
    # memory conversion has no path to the base, so the position contributes
    # zero to the base-currency value (ADR-0010 trade-off) rather than failing.
    deposit!(world, "1000", ~D[2026-01-01], currency: "USD")
    buy!(world, "10", "100", ~D[2026-01-01])
    quote!(world, "100", ~D[2026-01-01])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-05])

    assert result.base_currency == "EUR"
    assert Decimal.equal?(result.end_value, Decimal.new("0"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("0"))
    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
  end

  # -- #1051: the currency a trade's fees and taxes are read in ----------------
  #
  # A cross-currency trade (ADR-0015) is priced in the security's currency and
  # settled through a cash account in another. Its fees and taxes are part of
  # the cash leg, so they are recorded in the ACCOUNT's currency: a buy's cash
  # is its settlement plus fees plus taxes (`Ledger.SettlementGuard`).
  # Invented figures; every hub rate below converts exactly.

  defp point_on(daily, date),
    do:
      Enum.find(daily, &(Date.compare(&1.date, date) == :eq)) ||
        flunk("no walk point on #{date}")

  defp costs_on(daily, date), do: daily |> point_on(date) |> Performance.trade_costs_of()

  defp exactly?(decimal, expected), do: Decimal.equal?(decimal, Decimal.new(expected))

  # User story (#1051, ADR-0015, #708):
  # As a maintainer who buys a USD security through my EUR account,
  # I want the walk to count the fees and taxes my broker charged in euros as
  # euros,
  # so that the trade costs the snapshot comparison reclassifies, and the
  # costs the contribution table charges the position, are what I paid.
  #
  # Acceptance criteria:
  # - A cross-currency buy's fees and taxes enter the day's trade costs
  #   converted from its cash account's currency, not from the trade's price
  #   currency.
  # - A cross-currency sell's likewise.
  # - The day's value and flow do not move: only the trade costs do.
  test "a cross-currency trade's fees and taxes are read in its cash account's currency" do
    world = base_world(name: "Cross Costs", cash_name: "Cash EUR", depot_name: "Depot")
    fund = create_security!(name: "US Fund", ticker: "USF", currency: "USD")

    # 1 EUR = 1.25 USD, so 1 USD = 0.8 EUR.
    rate!("USD", ~D[2026-01-01], "1.25")
    deposit!(world, "2000", ~D[2026-01-02], currency: "EUR")

    # 10 @ 100 USD settled 790 EUR, fees 5 and taxes 1 EUR: 796 EUR paid.
    WorldFixtures.cross_trade!(world, fund,
      quantity: "10",
      price: "100",
      settled: "790",
      fees: "5.00",
      taxes: "1.00",
      gross: "796",
      date: ~D[2026-01-05]
    )

    # 4 @ 120 USD settled 384 EUR, fees 2.50 and taxes 0.50 EUR: 381 EUR in.
    WorldFixtures.cross_trade!(world, fund,
      type: "sell",
      quantity: "4",
      price: "120",
      settled: "384",
      fees: "2.50",
      taxes: "0.50",
      gross: "381",
      date: ~D[2026-02-02]
    )

    WorldFixtures.put_quotes!(fund, [{~D[2026-01-05], "100"}, {~D[2026-02-02], "120"}])

    %{daily: daily} = Performance.analysis(world.portfolio.id, today: ~D[2026-02-10])

    # 6 EUR, not 6 read as USD at 0.8 (4.8).
    assert exactly?(costs_on(daily, ~D[2026-01-05]), "6.00")
    # 3 EUR, not 3 read as USD at 0.8 (2.4).
    assert exactly?(costs_on(daily, ~D[2026-02-02]), "3.00")

    # 1204 EUR left and 10 × 100 USD at 0.8; the trade is no external flow.
    buy_day = point_on(daily, ~D[2026-01-05])
    assert exactly?(buy_day.value, "2004")
    assert exactly?(buy_day.flow, "0")
  end

  # User story (#1051, ADR-0015):
  # As a maintainer whose portfolio reports in USD, with a EUR account that
  # buys a CHF security,
  # I want the trade's fees to be converted from euros to dollars,
  # so that a base currency other than the hub reads the costs I paid too.
  #
  # Acceptance criteria:
  # - With a USD base, a EUR cash account and a CHF security, the trade costs
  #   are the fees converted EUR -> USD through the EUR hub.
  test "with a USD base, a EUR account's fees on a CHF trade convert from EUR" do
    world =
      base_world(
        name: "Dollar Base",
        currency: "USD",
        cash_currency: "EUR",
        cash_name: "Cash EUR",
        depot_name: "Depot"
      )

    swiss = create_security!(name: "Swiss Co", ticker: "SWC", currency: "CHF")

    # 1 EUR = 1.25 USD = 0.8 CHF, so 1 CHF = 1.5625 USD and 1.25 EUR.
    rate!("USD", ~D[2026-01-01], "1.25")
    rate!("CHF", ~D[2026-01-01], "0.8")
    deposit!(world, "1000", ~D[2026-01-02], currency: "EUR")

    # 5 @ 40 CHF (250 EUR at the hub) settled 250 EUR, fees 4 EUR: 254 paid.
    WorldFixtures.cross_trade!(world, swiss,
      quantity: "5",
      price: "40",
      settled: "250",
      fees: "4",
      gross: "254",
      date: ~D[2026-01-05]
    )

    %{daily: daily, base_currency: "USD"} =
      Performance.analysis(world.portfolio.id, today: ~D[2026-01-10])

    # 4 EUR × 1.25, not 4 read as CHF × 1.5625 (6.25).
    assert exactly?(costs_on(daily, ~D[2026-01-05]), "5")
  end

  # User story (#1051, #708):
  # As a maintainer whose trades settle in the security's own currency,
  # I want their trade costs to stay exactly what they were,
  # so that fixing the cross-currency case moves nothing else.
  #
  # Acceptance criteria:
  # - A EUR trade through a EUR account and a USD trade through a USD account
  #   in a EUR-base portfolio carry the same trade costs as before #1051.
  test "a same-currency trade's fees are read as before" do
    world = base_world(name: "Same Costs", cash_name: "Cash EUR", depot_name: "Depot EUR")

    usd =
      world.portfolio
      |> WorldFixtures.add_depot(
        cash_currency: "USD",
        cash_name: "Cash USD",
        depot_name: "Depot USD"
      )
      |> Map.put(:portfolio, world.portfolio)

    euro = create_security!(name: "Euro Fund", ticker: "EUF")
    dollar = create_security!(name: "Dollar Fund", ticker: "DLF", currency: "USD")

    rate!("USD", ~D[2026-01-01], "1.25")
    deposit!(world, "2000", ~D[2026-01-02], currency: "EUR")
    deposit!(usd, "1000", ~D[2026-01-02], currency: "USD")

    WorldFixtures.buy!(world, euro,
      quantity: "10",
      price: "100",
      fees: "3",
      taxes: "1",
      date: ~D[2026-01-05]
    )

    WorldFixtures.buy!(usd, dollar,
      quantity: "5",
      price: "80",
      fees: "2",
      date: ~D[2026-01-06],
      currency: "USD"
    )

    %{daily: daily} = Performance.analysis(world.portfolio.id, today: ~D[2026-01-10])

    assert exactly?(costs_on(daily, ~D[2026-01-05]), "4")
    # 2 USD at 0.8.
    assert exactly?(costs_on(daily, ~D[2026-01-06]), "1.6")
  end

  # User story (#1051, ADR-0051 amendment 2026-10-03, §5's no-rate row):
  # As a maintainer who buys a security priced in a currency the instance
  # holds no rate for yet, through my EUR account,
  # I want the fees I paid in euros to count as euros,
  # so that a missing rate for the security's currency does not make the
  # trade look free.
  #
  # Acceptance criteria:
  # - The trade costs of a cross-currency trade whose price currency has no
  #   rate path are its fees and taxes converted from its account's currency.
  # - The position still counts zero, and the cash it cost leaves the value:
  #   value and flow do not move.
  test "a trade whose price currency has no rate counts its fees in its account's currency" do
    world = base_world(name: "Rateless Costs", cash_name: "Cash EUR", depot_name: "Depot")
    yen = create_security!(name: "Yen Co", ticker: "YNC", currency: "JPY")

    deposit!(world, "1000", ~D[2026-01-02], currency: "EUR")

    # 10 @ 1000 JPY settled 62 EUR, fees 2 and taxes 1 EUR: 65 EUR paid. No
    # JPY rate is ever stored.
    WorldFixtures.cross_trade!(world, yen,
      quantity: "10",
      price: "1000",
      settled: "62",
      fees: "2",
      taxes: "1",
      gross: "65",
      date: ~D[2026-01-05]
    )

    WorldFixtures.put_quotes!(yen, [{~D[2026-01-05], "1000"}])

    %{daily: daily} = Performance.analysis(world.portfolio.id, today: ~D[2026-01-10])

    # 3 EUR; read as JPY without a rate they counted zero.
    assert exactly?(costs_on(daily, ~D[2026-01-05]), "3")

    buy_day = point_on(daily, ~D[2026-01-05])
    assert exactly?(buy_day.value, "935")
    assert exactly?(buy_day.flow, "0")
  end
end
