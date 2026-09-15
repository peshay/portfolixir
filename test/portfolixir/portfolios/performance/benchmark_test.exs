defmodule Portfolixir.Portfolios.Performance.BenchmarkTest do
  # Sprint 11 Lane B (D-1 = ADR-0046): the benchmark comparison engine — a
  # benchmark is a price series the portfolio's own flows are replayed into.
  # Risk-tier (ADR-0036): the three identities named in ADR-0046's
  # consequences are the first tests, and every money figure below is an
  # exact Decimal derived by hand in the comments.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Performance.Benchmark

  defp d(value), do: Decimal.new(value)

  defp benchmark_security!(opts) do
    security = create_security!(opts)
    {:ok, flagged} = Catalog.update_security(Actor.owner_ui(), security, %{is_benchmark: true})
    flagged
  end

  defp removal!(world, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "removal",
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp rate!(date, rate, quote_currency \\ "USD") do
    {:ok, 1} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: quote_currency,
          date: date,
          rate: rate,
          source: "manual"
        }
      ])
  end

  # User story (#572, ADR-0046 identity 1):
  # As a local portfolio maintainer asking whether the effort was worth it,
  # I want my own flows replayed into a 0 % baseline to end at exactly the
  # net invested capital of ADR-0034,
  # so that the delta against a savings account is the money the investing
  # itself made.
  #
  # Acceptance criteria:
  # - benchmark_end_value equals invested_capital exactly.
  # - end_value_delta is the real end value minus that; the bought-once
  #   return of a 0 % rate is 0 and its IRR is 0.
  # - The comparison carries the window, the freshness pair and the basis.
  test "a 0 % fixed-rate savings plan ends at exactly the net invested capital" do
    world = base_world(name: "B1", cash_name: "B1 Cash", depot_name: "B1 Depot")
    security = create_security!(name: "World ETF", ticker: "WLD")

    put_quotes!(security, [
      {~D[2026-01-01], "100"},
      {~D[2026-01-10], "110"},
      {~D[2026-01-20], "120"}
    ])

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])
    deposit!(world, "500", ~D[2026-01-10])

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:rate, d("0")}, today: ~D[2026-01-21])

    # Invested capital: 0 opening value + 1000 + 500 = 1500. The real end
    # value is 10 x 120 + 500 cash = 1700, so the delta is 200.
    assert cmp.period == "max"
    assert cmp.portfolio_id == world.portfolio.id
    assert cmp.base_currency == "EUR"

    assert cmp.window == %{
             start_date: ~D[2026-01-01],
             end_date: ~D[2026-01-21],
             rebase_day: ~D[2026-01-01]
           }

    assert cmp.requested_window == %{start_date: ~D[2026-01-01], end_date: ~D[2026-01-21]}
    assert cmp.excluded_flows == []
    assert Decimal.equal?(cmp.savings_plan.invested_capital, d("1500"))
    assert Decimal.equal?(cmp.savings_plan.benchmark_end_value, d("1500"))
    assert Decimal.equal?(cmp.savings_plan.portfolio_end_value, d("1700"))
    assert Decimal.equal?(cmp.savings_plan.end_value_delta, d("200"))
    assert Decimal.equal?(cmp.bought_once.benchmark_return, d("0"))
    assert Decimal.equal?(cmp.savings_plan.benchmark_irr, d("0"))
    assert %Decimal{} = cmp.savings_plan.portfolio_irr
    assert %{kind: :rate, annual_rate: rate} = cmp.benchmark
    assert Decimal.equal?(rate, d("0"))
    assert %DateTime{} = cmp.as_of
    assert cmp.stale == false
    assert cmp.computation_basis.window == cmp.window
    assert cmp.computation_basis.frictionless == true
  end

  # User story (#572, ADR-0046 identity 2):
  # As a local portfolio maintainer whose benchmark is the very ETF I hold,
  # I want the savings-plan replay to reproduce my own end value,
  # so that a zero delta and equal IRRs prove the replay books my flows the
  # way the walk does.
  #
  # Acceptance criteria:
  # - The same flows at the same prices give the same units, so the end-value
  #   delta is exactly 0 and the two IRRs are equal.
  test "a benchmark that is the portfolio's single holding with the same flows yields a zero delta and equal IRRs" do
    world = base_world(name: "B2", cash_name: "B2 Cash", depot_name: "B2 Depot")
    bench = benchmark_security!(name: "Bench ETF", ticker: "BNCH")

    put_quotes!(bench, [
      {~D[2026-01-01], "100"},
      {~D[2026-01-05], "104"},
      {~D[2026-01-10], "110"},
      {~D[2026-01-15], "99"},
      {~D[2026-01-20], "120"}
    ])

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, bench, quantity: "10", price: "100", date: ~D[2026-01-01])
    deposit!(world, "550", ~D[2026-01-10])
    buy!(world, bench, quantity: "5", price: "110", date: ~D[2026-01-10])
    sell!(world, bench, quantity: "3", price: "99", date: ~D[2026-01-15])
    removal!(world, "297", ~D[2026-01-15])

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench}, today: ~D[2026-01-21])

    # Units: 1000/100 + 550/110 - 297/99 = 10 + 5 - 3 = 12, the depot's own
    # count; end value 12 x 120 = 1440 on both sides, cash is 0 throughout.
    assert Decimal.equal?(cmp.savings_plan.benchmark_units, d("12"))
    assert Decimal.equal?(cmp.savings_plan.benchmark_end_value, d("1440"))
    assert Decimal.equal?(cmp.savings_plan.portfolio_end_value, d("1440"))
    assert Decimal.equal?(cmp.savings_plan.end_value_delta, d("0"))
    assert %Decimal{} = cmp.savings_plan.portfolio_irr
    assert Decimal.equal?(cmp.savings_plan.portfolio_irr, cmp.savings_plan.benchmark_irr)
    # Bought once: 120/100 - 1.
    assert Decimal.equal?(cmp.bought_once.benchmark_return, d("0.2"))

    assert %{kind: :security, security_id: id, name: "Bench ETF", currency_code: "EUR"} =
             cmp.benchmark

    assert id == bench.id
  end

  # User story (#572, ADR-0046 identity 3):
  # As a local portfolio maintainer comparing against an index whose history
  # starts after my first bookings,
  # I want the flows before the benchmark's first quote excluded and named,
  # so that the comparison states the window it actually covers instead of
  # pricing those flows at a quote that did not exist.
  #
  # Acceptance criteria:
  # - The covered window opens the day after the first quote; the portfolio
  #   figures are re-chained over it, the earlier flows are listed.
  # - The computation basis names the window, the reference and the
  #   exclusion rule.
  test "a flow dated before the benchmark's first quote is excluded and named, and the window it covers is stated" do
    world = base_world(name: "B3", cash_name: "B3 Cash", depot_name: "B3 Depot")
    held = create_security!(name: "World ETF", ticker: "WLD")
    put_quotes!(held, [{~D[2026-01-01], "100"}, {~D[2026-01-20], "120"}])
    bench = benchmark_security!(name: "Late Bench", ticker: "LATE")
    put_quotes!(bench, [{~D[2026-01-10], "50"}, {~D[2026-01-20], "55"}])

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, held, quantity: "10", price: "100", date: ~D[2026-01-01])
    deposit!(world, "200", ~D[2026-01-05])
    deposit!(world, "300", ~D[2026-01-12])

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench}, today: ~D[2026-01-21])

    assert cmp.requested_window == %{start_date: ~D[2026-01-01], end_date: ~D[2026-01-21]}

    assert cmp.window == %{
             start_date: ~D[2026-01-11],
             end_date: ~D[2026-01-21],
             rebase_day: ~D[2026-01-10]
           }

    assert [%{date: ~D[2026-01-01], flow: f1}, %{date: ~D[2026-01-05], flow: f2}] =
             cmp.excluded_flows

    assert Decimal.equal?(f1, d("1000"))
    assert Decimal.equal?(f2, d("200"))

    # The covered window opens on V(01-10) = 10 x 100 + 200 = 1200, struck at
    # the benchmark's 50; the 300 of 01-12 buys at 50 too: 24 + 6 = 30 units,
    # 30 x 55 = 1650 at the end against the real 10 x 120 + 500 = 1700.
    assert Decimal.equal?(cmp.savings_plan.invested_capital, d("1500"))
    assert Decimal.equal?(cmp.savings_plan.benchmark_units, d("30"))
    assert Decimal.equal?(cmp.savings_plan.benchmark_end_value, d("1650"))
    assert Decimal.equal?(cmp.savings_plan.end_value_delta, d("50"))
    assert Decimal.equal?(cmp.bought_once.benchmark_return, d("0.1"))
    # Portfolio TTWROR over the covered window: 01-12 is 1500/(1200+300) - 1
    # = 0, 01-20 is 1700/1500 - 1 = 2/15.
    assert Decimal.equal?(Decimal.round(cmp.bought_once.portfolio_ttwror, 6), d("0.133333"))
    assert hd(cmp.bought_once.series).date == ~D[2026-01-11]

    assert cmp.computation_basis.window == cmp.window
    assert cmp.computation_basis.reference =~ "Late Bench"
    assert cmp.computation_basis.gaps =~ "excluded"
    assert cmp.computation_basis.assumptions =~ "frictionless"
    assert cmp.computation_basis.assumptions =~ "float"
    assert cmp.computation_basis.gaps =~ "excluded_flows"
    assert cmp.computation_basis.gaps =~ "rate path"
    assert cmp.computation_basis.gaps =~ "opening value"
    assert cmp.computation_basis.gaps =~ "rebase_day"
  end

  # User story (#572, ADR-0046 §1 "compounding daily from a base of 1"):
  # As a local portfolio maintainer typing the rate my savings account pays,
  # I want 2 % to mean 2 % after one year,
  # so that the baseline is the account I could have used.
  #
  # Acceptance criteria:
  # - The rate is an effective annual rate compounded daily on Act/365: a
  #   deposit held 365 days grows by exactly the rate.
  # - The rate series has a point on every day of the window.
  test "a fixed rate compounds daily to its effective annual rate over 365 days" do
    world = base_world(name: "B4", cash_name: "B4 Cash", depot_name: "B4 Depot")
    deposit!(world, "1000", ~D[2025-01-01])

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:rate, d("0.02")}, today: ~D[2026-01-01])

    assert cmp.window == %{
             start_date: ~D[2025-01-01],
             end_date: ~D[2026-01-01],
             rebase_day: ~D[2025-01-01]
           }

    assert Decimal.equal?(cmp.savings_plan.benchmark_units, d("1000"))
    # The period money-weighted pair rides along (ADR-0034 §2): over 365
    # days the period rate is the annual rate.
    assert Decimal.equal?(Decimal.round(cmp.savings_plan.benchmark_mwr, 4), d("0.02"))
    assert %Decimal{} = cmp.savings_plan.portfolio_mwr
    assert Decimal.equal?(Decimal.round(cmp.savings_plan.benchmark_end_value, 6), d("1020"))
    assert Decimal.equal?(Decimal.round(cmp.savings_plan.end_value_delta, 6), d("-20"))
    assert Decimal.equal?(Decimal.round(cmp.bought_once.benchmark_return, 8), d("0.02"))
    assert Decimal.equal?(Decimal.round(cmp.savings_plan.benchmark_irr, 5), d("0.02"))
    assert length(cmp.bought_once.series) == 366
    assert Decimal.equal?(hd(cmp.bought_once.series).cumulative_return, d("0"))
  end

  # A window that does not open the history rebases at the close before it —
  # the same convention as the TTWROR chain, whose start value is that close.
  test "a bounded window rebases the benchmark at the close before the window" do
    world = base_world(name: "B4b", cash_name: "B4b Cash", depot_name: "B4b Depot")
    bench = benchmark_security!(name: "Bench ETF", ticker: "BNCH")

    put_quotes!(bench, [
      {~D[2026-01-01], "100"},
      {~D[2026-01-10], "110"},
      {~D[2026-01-20], "121"}
    ])

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, bench, quantity: "10", price: "100", date: ~D[2026-01-01])

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench},
        today: ~D[2026-01-21],
        period: {:range, ~D[2026-01-11], ~D[2026-01-21]}
      )

    # Opening value V(01-10) = 1100 at the benchmark's 110: 10 units, 1210
    # at the end on both sides; bought once 121/110 - 1 = 0.1, as is the
    # chain 1210/1100 - 1.
    assert cmp.period == {:range, ~D[2026-01-11], ~D[2026-01-21]}

    assert cmp.window == %{
             start_date: ~D[2026-01-11],
             end_date: ~D[2026-01-21],
             rebase_day: ~D[2026-01-10]
           }

    assert Decimal.equal?(cmp.savings_plan.benchmark_units, d("10"))
    assert Decimal.equal?(cmp.savings_plan.end_value_delta, d("0"))
    assert Decimal.equal?(cmp.bought_once.benchmark_return, d("0.1"))
    assert Decimal.equal?(cmp.bought_once.portfolio_ttwror, d("0.1"))
    assert [%{date: ~D[2026-01-11], cumulative_return: first} | _] = cmp.bought_once.series
    assert Decimal.equal?(first, d("0"))
  end

  # A benchmark quoted in another currency is a base-currency price series:
  # the FX move is part of what a base-currency investor would have earned.
  test "a foreign-currency benchmark is priced in the base currency at each day's stored rate" do
    world = base_world(name: "B5", cash_name: "B5 Cash", depot_name: "B5 Depot")
    deposit!(world, "1000", ~D[2026-01-01])
    bench = benchmark_security!(name: "US Bench", ticker: "USB", currency: "USD")
    put_quotes!(bench, [{~D[2026-01-01], "100"}, {~D[2026-01-11], "100"}])
    rate!(~D[2026-01-01], "1.0")
    rate!(~D[2026-01-11], "1.25")

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench}, today: ~D[2026-01-11])

    # 100 USD is 100 EUR at 1.0 and 80 EUR at 1.25: -20 % for a EUR holder.
    assert Decimal.equal?(cmp.bought_once.benchmark_return, d("-0.2"))
    assert Decimal.equal?(cmp.savings_plan.benchmark_units, d("10"))
    assert Decimal.equal?(cmp.savings_plan.benchmark_end_value, d("800"))
    assert Decimal.equal?(cmp.savings_plan.end_value_delta, d("200"))
  end

  test "days without a benchmark close carry the most recent close forward" do
    world = base_world(name: "B6", cash_name: "B6 Cash", depot_name: "B6 Depot")
    deposit!(world, "1000", ~D[2026-01-01])
    bench = benchmark_security!(name: "Gappy", ticker: "GAP")
    put_quotes!(bench, [{~D[2026-01-01], "100"}, {~D[2026-01-05], "110"}])

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench}, today: ~D[2026-01-07])

    returns =
      Enum.map(cmp.bought_once.series, fn point ->
        {point.date, point.cumulative_return |> Decimal.normalize() |> Decimal.to_string()}
      end)

    assert returns == [
             {~D[2026-01-01], "0"},
             {~D[2026-01-02], "0"},
             {~D[2026-01-03], "0"},
             {~D[2026-01-04], "0"},
             {~D[2026-01-05], "0.1"},
             {~D[2026-01-06], "0.1"},
             {~D[2026-01-07], "0.1"}
           ]
  end

  test "a portfolio with nothing to walk yields an empty comparison, never an inverted one" do
    world = base_world(name: "B7", cash_name: "B7 Cash", depot_name: "B7 Depot")

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:rate, d("0.02")}, today: ~D[2026-01-21])

    assert cmp.window == %{start_date: nil, end_date: ~D[2026-01-21], rebase_day: nil}
    assert cmp.bought_once.series == []
    assert is_nil(cmp.bought_once.benchmark_return)
    assert is_nil(cmp.savings_plan.benchmark_end_value)
    assert is_nil(cmp.savings_plan.end_value_delta)
    assert is_nil(cmp.savings_plan.benchmark_mwr)
    assert cmp.excluded_flows == []
  end

  test "a benchmark without a quote in the window covers nothing and names every flow" do
    world = base_world(name: "B8", cash_name: "B8 Cash", depot_name: "B8 Depot")
    deposit!(world, "1000", ~D[2026-01-01])
    deposit!(world, "500", ~D[2026-01-10])
    bench = benchmark_security!(name: "Silent", ticker: "SIL")

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench}, today: ~D[2026-01-21])

    assert cmp.requested_window == %{start_date: ~D[2026-01-01], end_date: ~D[2026-01-21]}
    assert cmp.window == %{start_date: nil, end_date: ~D[2026-01-21], rebase_day: nil}
    assert [%{date: ~D[2026-01-01]}, %{date: ~D[2026-01-10]}] = cmp.excluded_flows
    assert is_nil(cmp.savings_plan.end_value_delta)
    assert is_nil(cmp.bought_once.benchmark_return)
    assert cmp.bought_once.series == []
  end

  test "the view scope compares the cross-portfolio walk under the same rules" do
    world = base_world(name: "B10", cash_name: "B10 Cash", depot_name: "B10 Depot")
    deposit!(world, "1000", ~D[2026-01-01])

    {:ok, cmp} = Benchmark.for_view(nil, {:rate, d("0")}, today: ~D[2026-01-21])

    assert cmp.portfolio_id == nil
    assert cmp.view_id == nil
    assert cmp.base_currency == "EUR"
    assert Decimal.equal?(cmp.savings_plan.invested_capital, d("1000"))
    assert Decimal.equal?(cmp.savings_plan.benchmark_end_value, d("1000"))
  end

  # Closing-act findings (risk-tier pass, both hunters): the rebase day is
  # part of the payload, a flow dated on it is invested at its close and so
  # not listed, and a stored close of 0 is not a price.
  test "a flow dated on the rebase day is replayed at that day's close, not listed as excluded" do
    world = base_world(name: "B3b", cash_name: "B3b Cash", depot_name: "B3b Depot")
    held = create_security!(name: "World ETF", ticker: "WLD")
    put_quotes!(held, [{~D[2026-01-01], "100"}, {~D[2026-01-20], "120"}])
    bench = benchmark_security!(name: "Late Bench", ticker: "LATE")
    put_quotes!(bench, [{~D[2026-01-10], "50"}, {~D[2026-01-20], "55"}])

    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, held, quantity: "10", price: "100", date: ~D[2026-01-01])
    deposit!(world, "200", ~D[2026-01-05])
    deposit!(world, "400", ~D[2026-01-10])
    deposit!(world, "300", ~D[2026-01-12])

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench}, today: ~D[2026-01-21])

    assert cmp.window.rebase_day == ~D[2026-01-10]
    assert [%{date: ~D[2026-01-01]}, %{date: ~D[2026-01-05]}] = cmp.excluded_flows
    # V(01-10) = 1000 + 200 + 400 = 1600 at 50 → 32 units, + 300/50 = 6: 38
    # units, 38 x 55 = 2090 against the real 10 x 120 + 900 = 2100.
    assert Decimal.equal?(cmp.savings_plan.benchmark_units, d("38"))
    assert Decimal.equal?(cmp.savings_plan.end_value_delta, d("10"))
  end

  test "a stored close of 0 is not a price: the day is unpriced and the previous close carries" do
    world = base_world(name: "B0", cash_name: "B0 Cash", depot_name: "B0 Depot")
    deposit!(world, "1000", ~D[2026-01-01])
    deposit!(world, "500", ~D[2026-01-08])
    bench = benchmark_security!(name: "Zero Close", ticker: "ZRO")

    put_quotes!(bench, [
      {~D[2026-01-01], "0"},
      {~D[2026-01-05], "50"},
      {~D[2026-01-08], "0"},
      {~D[2026-01-10], "55"}
    ])

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench}, today: ~D[2026-01-11])

    # The first real close is 01-05: the window opens the day after, the
    # 01-01 flow is named; the 0 on 01-08 carries 50 forward, so the 500
    # buys 10 units there: 20 + 10 = 30 units, 30 x 55 = 1650.
    assert cmp.window == %{
             start_date: ~D[2026-01-06],
             end_date: ~D[2026-01-11],
             rebase_day: ~D[2026-01-05]
           }

    assert [%{date: ~D[2026-01-01]}] = cmp.excluded_flows
    assert Decimal.equal?(cmp.savings_plan.benchmark_units, d("30"))
    assert Decimal.equal?(cmp.savings_plan.benchmark_end_value, d("1650"))
  end

  # The rate stays inside the solver's own domain (ADR-0034 §2): a rate a
  # hair above -100 % or beyond DBL_MAX crashed the arithmetic (closing-act
  # finding of both hunters); one bound, shared by the API parser and the
  # page's plug.
  test "a rate outside -99.9999 % .. 1000 % is refused, the bounds themselves are accepted" do
    world = base_world(name: "B11", cash_name: "B11 Cash", depot_name: "B11 Depot")
    deposit!(world, "1000", ~D[2026-01-01])

    for rate <- ["-1", "-0.99999999999999999999", "-0.9999995", "10.000001", "1e309", "1e100"] do
      assert {:error, :invalid_benchmark} =
               Benchmark.for_portfolio(world.portfolio.id, {:rate, d(rate)},
                 today: ~D[2026-01-21]
               ),
             rate
    end

    for rate <- ["-0.999999", "10", "0", "0.02"] do
      assert {:ok, _} =
               Benchmark.for_portfolio(world.portfolio.id, {:rate, d(rate)},
                 today: ~D[2026-01-21]
               ),
             rate
    end

    assert Benchmark.valid_rate?(d("10"))
    refute Benchmark.valid_rate?(d("10.5"))

    assert {:error, :invalid_period} =
             Benchmark.for_portfolio(world.portfolio.id, {:rate, d("0")},
               today: ~D[2026-01-21],
               period: "bogus"
             )
  end

  # A benchmark quoted in pence follows the walk's own rule: GBX is GBP / 100,
  # and a GBP rate stored before the window carries into it like a close does.
  test "a pence-quoted benchmark is priced through GBP at the carried rate" do
    world = base_world(name: "B5g", cash_name: "B5g Cash", depot_name: "B5g Depot")
    deposit!(world, "1000", ~D[2026-01-01])
    bench = benchmark_security!(name: "UK Bench", ticker: "UKB", currency: "GBX")
    put_quotes!(bench, [{~D[2026-01-01], "1000"}, {~D[2026-01-11], "1200"}])
    rate!(~D[2025-12-20], "0.8", "GBP")

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench}, today: ~D[2026-01-11])

    # 1 EUR = 0.8 GBP = 80 GBX: 1000 GBX is 12.5 EUR and 1200 GBX is 15 EUR,
    # +20 %. 1000 EUR at 12.5 is 80 units; 80 x 15 = 1200 against 1000 in cash.
    assert Decimal.equal?(cmp.bought_once.benchmark_return, d("0.2"))
    assert Decimal.equal?(cmp.savings_plan.benchmark_units, d("80"))
    assert Decimal.equal?(cmp.savings_plan.benchmark_end_value, d("1200"))
    assert Decimal.equal?(cmp.savings_plan.end_value_delta, d("-200"))
  end

  # A day without a stored rate is a day without a price: the foreign
  # benchmark is unpriced until its first rate, the window opens after that
  # day and the earlier flow enters through the opening value, named.
  test "a foreign benchmark without a stored rate is unpriced until its first rate" do
    world = base_world(name: "B5x", cash_name: "B5x Cash", depot_name: "B5x Depot")
    deposit!(world, "1000", ~D[2026-01-01])
    bench = benchmark_security!(name: "Late Rate", ticker: "LTR", currency: "USD")
    put_quotes!(bench, [{~D[2026-01-01], "100"}, {~D[2026-01-11], "100"}])
    rate!(~D[2026-01-06], "1.0")
    rate!(~D[2026-01-11], "1.25")

    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench}, today: ~D[2026-01-11])

    assert cmp.window == %{
             start_date: ~D[2026-01-07],
             end_date: ~D[2026-01-11],
             rebase_day: ~D[2026-01-06]
           }

    assert [%{date: ~D[2026-01-01], flow: flow}] = cmp.excluded_flows
    assert Decimal.equal?(flow, d("1000"))
    # V(01-06) = 1000 at 100 USD = 100 EUR: 10 units; 100 USD is 80 EUR at 1.25.
    assert Decimal.equal?(cmp.savings_plan.benchmark_units, d("10"))
    assert Decimal.equal?(cmp.savings_plan.benchmark_end_value, d("800"))
    assert Decimal.equal?(cmp.savings_plan.end_value_delta, d("200"))
    assert Decimal.equal?(cmp.bought_once.benchmark_return, d("-0.2"))
  end

  # The calendar-year period the API's ?year= resolves to (#563) bounds the
  # comparison like the range it spans.
  test "a calendar-year period bounds the comparison like the range it spans" do
    world = base_world(name: "B4y", cash_name: "B4y Cash", depot_name: "B4y Depot")
    bench = benchmark_security!(name: "Year Bench", ticker: "YRB")
    put_quotes!(bench, [{~D[2026-01-01], "100"}, {~D[2026-01-20], "121"}])
    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, bench, quantity: "10", price: "100", date: ~D[2026-01-01])

    {:ok, by_year} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench},
        today: ~D[2026-01-21],
        period: {:year, 2026}
      )

    {:ok, by_range} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench},
        today: ~D[2026-01-21],
        period: {:range, ~D[2026-01-01], ~D[2026-01-21]}
      )

    assert by_year.period == {:year, 2026}
    assert by_year.window == by_range.window
    assert Decimal.equal?(by_year.bought_once.benchmark_return, d("0.21"))

    assert Decimal.equal?(
             by_year.savings_plan.end_value_delta,
             by_range.savings_plan.end_value_delta
           )
  end

  # The engine's own refusal: its API parser and the page's plug refuse
  # earlier, but the engine is what an Elixir caller reaches.
  test "the engine refuses a benchmark term that is neither a rate nor a security" do
    world = base_world(name: "B9", cash_name: "B9 Cash", depot_name: "B9 Depot")
    deposit!(world, "1000", ~D[2026-01-01])

    for term <- [:bogus, {:rate, "0.02"}, {:rate, 0.02}, {:security, nil}] do
      assert {:error, :invalid_benchmark} =
               Benchmark.for_portfolio(world.portfolio.id, term, today: ~D[2026-01-11])
    end

    refute Benchmark.valid_rate?("0.02")
    refute Benchmark.valid_rate?(0.02)
  end
end
