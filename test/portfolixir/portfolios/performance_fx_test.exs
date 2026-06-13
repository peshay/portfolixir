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
end
