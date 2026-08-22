defmodule Portfolixir.Portfolios.RealizedGainsTest do
  # Issue #724 (risk-tier; FX basis D-1, signed 2026-08-20 on PR #734):
  # the Realized-gains facet's cross-security read. Each sale converts to the
  # base currency through the EUR hub at the rate stored on ITS OWN close
  # date; a sale whose
  # booking-date rate is not stored is EXCLUDED from the converted totals
  # and NAMED — never converted at a neighbouring date's rate, never
  # silently dropped (the ADR-0041 excluded-and-named shape).
  use Portfolixir.DataCase

  alias Portfolixir.Fx
  alias Portfolixir.Portfolios.RealizedGains
  alias Portfolixir.WorldFixtures

  # User story (issue #724):
  # As a local portfolio maintainer,
  # I want realized gains per period across ALL securities,
  # so that the Cash-flow facet can answer "what did selling actually make"
  # without me summing per-security trade lists by hand.
  #
  # Acceptance criteria (exact Decimal expectations — risk-tier):
  # - A same-currency round-trip lands with its FIFO realized P&L
  #   (proceeds net of sell fees/taxes minus consumed basis) in the month of
  #   its CLOSE date.
  # - A foreign-currency sale converts at the most recent stored hub rate on
  #   or before its close date.
  # - The payload states its computation basis (series, window, reference,
  #   gap treatment) per the AGENTS.md metric rule.
  test "aggregates FIFO realized P&L per period, converted at each sale's close date" do
    world = WorldFixtures.base_world()

    eur = WorldFixtures.create_security!(name: "Euro Equity", ticker: "EEQ", currency: "EUR")
    WorldFixtures.buy!(world, eur, quantity: "10", price: "100", date: ~D[2026-01-05])

    WorldFixtures.sell!(world, eur,
      quantity: "10",
      price: "120",
      fees: "9.90",
      date: ~D[2026-03-10]
    )

    usd = WorldFixtures.create_security!(name: "Dollar Equity", ticker: "DEQ", currency: "USD")

    usd_world =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          currency: "USD",
          cash_name: "USD Cash",
          depot_name: "USD Depot"
        )
      )

    WorldFixtures.buy!(usd_world, usd,
      quantity: "4",
      price: "50",
      date: ~D[2026-01-08],
      currency: "USD"
    )

    WorldFixtures.sell!(usd_world, usd,
      quantity: "4",
      price: "75",
      date: ~D[2026-03-20],
      currency: "USD"
    )

    # 1 EUR = 1.25 USD, stored on the sale's OWN close date. D-1 admits no
    # other date: a rate from 2026-03-15 would leave this sale excluded and
    # named rather than valued at a neighbouring day's rate.
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-03-20],
          rate: "1.25",
          source: "manual"
        }
      ])

    report = RealizedGains.report(base_currency: "EUR")

    # EUR trade: proceeds 10×120 − 9.90 = 1190.10; basis 1000 → +190.10.
    # USD trade: 4×75 − 4×50 = 100 USD → ÷1.25 = 80 EUR.
    assert report.base_currency == "EUR"
    assert [%{year: 2026} = year_row] = report.annual
    assert Decimal.equal?(year_row.months[3], Decimal.new("270.10"))
    assert Decimal.equal?(year_row.total, Decimal.new("270.10"))
    assert report.excluded.count == 0
    assert report.excluded.securities == []

    assert report.computation_basis.series =~ "FIFO"
    assert report.computation_basis.reference =~ "EUR hub"
    assert report.computation_basis.gaps =~ "excluded"
  end

  # User story (issue #724, the D-1 rate-availability behaviour):
  # As a local portfolio maintainer,
  # I want a sale with no stored booking-date rate excluded and named,
  # so that a missing rate can never silently distort the realized total —
  # and never gets guessed from a neighbouring date.
  #
  # Acceptance criteria:
  # - The unconvertible sale is absent from every period total.
  # - `excluded` carries the count and the security names.
  # - A rate stored only AFTER the close date does not convert the sale
  #   (at-or-before, never a neighbouring later rate).
  test "a sale with no rate at its close date is excluded from the totals and named" do
    world = WorldFixtures.base_world()

    eur = WorldFixtures.create_security!(name: "Euro Equity", ticker: "EEQ", currency: "EUR")
    WorldFixtures.buy!(world, eur, quantity: "1", price: "100", date: ~D[2026-01-05])
    WorldFixtures.sell!(world, eur, quantity: "1", price: "150", date: ~D[2026-02-10])

    gbp = WorldFixtures.create_security!(name: "Pound Equity", ticker: "PEQ", currency: "GBP")

    gbp_world =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    WorldFixtures.buy!(gbp_world, gbp,
      quantity: "2",
      price: "10",
      date: ~D[2026-01-09],
      currency: "GBP"
    )

    WorldFixtures.sell!(gbp_world, gbp,
      quantity: "2",
      price: "30",
      date: ~D[2026-02-20],
      currency: "GBP"
    )

    # The only GBP rate lies AFTER the close date: at-or-before must refuse it.
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "GBP",
          date: ~D[2026-03-01],
          rate: "0.85",
          source: "manual"
        }
      ])

    report = RealizedGains.report(base_currency: "EUR")

    assert [%{year: 2026} = year_row] = report.annual
    assert Decimal.equal?(year_row.months[2], Decimal.new("50"))
    assert Decimal.equal?(year_row.total, Decimal.new("50"))

    assert report.excluded.count == 1
    assert report.excluded.securities == ["Pound Equity"]
  end

  # D-1 (signed 2026-08-20), the rate-availability clause verbatim:
  # "a sale whose booking-date rate is not stored is excluded from the
  # converted total and named on the surface (count + securities), NEVER
  # converted at a neighboring date's rate and never silently dropped."
  test "a sale whose OWN booking date has no stored rate is excluded, not valued at an earlier rate" do
    world = WorldFixtures.base_world(currency: "EUR")
    today = Date.utc_today()

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: Date.add(today, -10),
          rate: "2",
          source: "manual"
        }
      ])

    dollar = WorldFixtures.create_security!(name: "Dollar ETF", ticker: "USE", currency: "USD")

    usd =
      WorldFixtures.add_depot(world.portfolio,
        currency: "USD",
        cash_name: "USD Cash",
        depot_name: "USD Depot"
      )

    usd_world = %{portfolio: world.portfolio, depot: usd.depot, cash: usd.cash}

    WorldFixtures.buy!(usd_world, dollar,
      quantity: "10",
      price: "100",
      date: Date.add(today, -100),
      currency: "USD"
    )

    # Sold on a date with NO stored rate. The only stored rate is 10 days ago.
    WorldFixtures.sell!(usd_world, dollar,
      quantity: "10",
      price: "120",
      date: Date.add(today, -5),
      currency: "USD"
    )

    report = RealizedGains.report(base_currency: "EUR")

    assert report.excluded.count == 1,
           "D-1: the sale must be excluded and named, not converted at the -10d rate"
  end
end
