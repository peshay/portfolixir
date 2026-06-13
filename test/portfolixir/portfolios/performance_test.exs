defmodule Portfolixir.Portfolios.PerformanceTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, deposit!: 3]

  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.WorldFixtures

  # User story:
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want the portfolio's true time-weighted return (TTWROR) like Portfolio
  # Performance computes it,
  # so that I can judge my investments' performance independently of when I
  # deposited or withdrew money.
  #
  # Acceptance criteria:
  # - Daily returns chain geometrically; deposits/removals are neutralised.
  # - A balance snapshot's jump is an external flow, not return.
  # - Dividends count as return.
  # - Periods (ytd/1y/3y/5y/max) chain only the days inside the period,
  #   starting from the value just before the period.
  # - A security without quotes is priced at the latest own trade price until
  #   a quote exists, so imported portfolios are not valued at zero.
  # - Bookings with implausible dates (before 1970, e.g. a 0217 import typo)
  #   are applied on the first plausible day instead of walking centuries,
  #   and are reported as suspect_dates.
  # - A day with a zero-or-negative return base contributes no return.
  # - analysis/2 + summarise/2 equals for_portfolio/2, so the UI can cache
  #   the daily walk and switch periods without recomputing.

  defp setup_world do
    world = base_world(name: "P", cash_name: "Cash", depot_name: "Depot")
    security = create_security!(name: "Index Fund", ticker: "IDX", asset_class: "etf")
    Map.put(world, :security, security)
  end

  defp buy!(world, qty, price, date) do
    WorldFixtures.buy!(world, world.security, quantity: qty, price: price, date: date)
  end

  defp quote!(world, close, date) do
    WorldFixtures.put_quote!(world.security, date, close)
  end

  defp rounded(decimal, places), do: Decimal.round(decimal, places)

  test "chains daily returns and neutralises deposits" do
    world = setup_world()

    # Day 1: 1000 in, all invested at 100. Day 10: quote 120 (+20%).
    # Day 11: 600 more in, invested at 120 (no gain that day).
    # Day 20: quote 130 (+8.33% on the 1800 invested).
    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, "10", "100", ~D[2026-01-01])
    quote!(world, "100", ~D[2026-01-01])
    quote!(world, "120", ~D[2026-01-10])
    deposit!(world, "600", ~D[2026-01-11])
    buy!(world, "5", "120", ~D[2026-01-11])
    quote!(world, "130", ~D[2026-01-20])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-20])

    # 1.2 * (130/120) - 1 = 0.3 — money-weighting would differ.
    assert rounded(result.ttwror, 6) |> Decimal.equal?(Decimal.new("0.3"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("1600"))
    assert Decimal.equal?(result.start_value, Decimal.new("0"))
    assert Decimal.equal?(result.end_value, Decimal.new("1950"))
    assert length(result.series) == 20

    last = List.last(result.series)
    assert Decimal.equal?(last.cumulative_ttwror, result.ttwror)

    # The money-weighted return (IRR) is solved from the same dated flows and
    # terminal value; with two contributions and a gain it is a positive rate.
    assert %Decimal{} = result.irr
    assert Decimal.compare(result.irr, Decimal.new("0")) == :gt
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a money-weighted return (IRR) next to the TTWROR,
  # so that I can also judge the timing of my own deposits and withdrawals.
  #
  # Acceptance criteria:
  # - A single deposit invested for a full year that ends 10% higher yields an
  #   IRR of 10%, computed from the same series and external flows.
  # - A portfolio with no flows to weight has no IRR (nil), never a crash.
  test "computes a money-weighted IRR over a full-year holding" do
    world = setup_world()

    start = ~D[2025-06-13]
    today = ~D[2026-06-13]

    deposit!(world, "1000", start)
    buy!(world, "10", "100", start)
    quote!(world, "100", start)
    quote!(world, "110", today)

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: today)

    assert Decimal.equal?(result.end_value, Decimal.new("1100"))
    assert rounded(result.irr, 6) |> Decimal.equal?(Decimal.new("0.1"))
  end

  test "has no IRR for an empty portfolio" do
    world = setup_world()

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-20])

    assert result.series == []
    assert result.irr == nil
  end

  test "a balance snapshot's jump is an external flow, not return" do
    world = setup_world()

    deposit!(world, "1000", ~D[2026-01-01])

    {:ok, _} =
      Ledger.set_cash_balance(Portfolios.get_cash_account(world.cash.id), %{
        "date" => "2026-01-05",
        "amount" => "1500"
      })

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10])

    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
    assert Decimal.equal?(result.end_value, Decimal.new("1500"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("1500"))
  end

  test "dividends count as return" do
    world = setup_world()

    deposit!(world, "1000", ~D[2026-01-01])

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: world.security.id,
        type: "dividend",
        date: ~D[2026-01-05],
        gross_amount: "50",
        currency_code: "EUR"
      })

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10])

    assert Decimal.equal?(result.ttwror, Decimal.new("0.05"))
  end

  test "a period chains only its own days, from the value just before it" do
    world = setup_world()

    # 2025: +10% (100 -> 110). 2026 so far: +10% (110 -> 121).
    deposit!(world, "1000", ~D[2025-12-01])
    buy!(world, "10", "100", ~D[2025-12-01])
    quote!(world, "100", ~D[2025-12-01])
    quote!(world, "110", ~D[2025-12-31])
    quote!(world, "121", ~D[2026-01-20])

    {:ok, ytd} =
      Performance.for_portfolio(world.portfolio.id, period: "ytd", today: ~D[2026-01-20])

    {:ok, max} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-20])

    assert ytd.start_date == ~D[2026-01-01]
    assert Decimal.equal?(ytd.start_value, Decimal.new("1100"))
    assert rounded(ytd.ttwror, 6) |> Decimal.equal?(Decimal.new("0.1"))
    assert rounded(max.ttwror, 6) |> Decimal.equal?(Decimal.new("0.21"))
  end

  test "rejects an unknown period" do
    world = setup_world()

    assert {:error, :invalid_period} =
             Performance.for_portfolio(world.portfolio.id, period: "2w")
  end

  test "prices an unquoted security at the latest own trade price" do
    world = setup_world()

    # No quote exists: the buy itself is the price observation, so the
    # position is worth its cost and the chain shows no phantom loss.
    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, "10", "100", ~D[2026-01-01])

    {:ok, flat} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-05])

    assert Decimal.equal?(flat.end_value, Decimal.new("1000"))
    assert Decimal.equal?(flat.ttwror, Decimal.new("0"))

    # Once a quote appears it wins over the stale trade price.
    quote!(world, "120", ~D[2026-01-10])

    {:ok, quoted} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10])

    assert Decimal.equal?(quoted.end_value, Decimal.new("1200"))
    assert rounded(quoted.ttwror, 6) |> Decimal.equal?(Decimal.new("0.2"))
  end

  test "applies implausibly dated bookings on the first plausible day" do
    world = setup_world()

    # A PP export typo: year 0217 instead of 2017. Walking from year 0217
    # would mean ~660,000 daily steps — the walk must start at the first
    # plausible booking instead, with the ancient cash effect preserved.
    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "removal",
        date: ~D[0217-12-05],
        gross_amount: "300",
        currency_code: "EUR"
      })

    deposit!(world, "1000", ~D[2026-01-01])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10])

    assert result.start_date == ~D[2026-01-01]
    assert length(result.series) == 10
    assert result.suspect_dates == [~D[0217-12-05]]
    # Both flows land on the first day: 1000 in, 300 out, no return.
    assert Decimal.equal?(result.end_value, Decimal.new("700"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("700"))
    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
  end

  test "a day with a zero-or-negative return base contributes no return" do
    world = setup_world()

    deposit!(world, "100", ~D[2026-01-01])

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "removal",
        date: ~D[2026-01-02],
        gross_amount: "200",
        currency_code: "EUR"
      })

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-05])

    # Overdrawn data (value -100) must not explode the chain.
    assert Decimal.equal?(result.end_value, Decimal.new("-100"))
    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
  end

  test "analysis plus summarise equals for_portfolio for every period" do
    world = setup_world()

    deposit!(world, "1000", ~D[2025-12-01])
    buy!(world, "10", "100", ~D[2025-12-01])
    quote!(world, "100", ~D[2025-12-01])
    quote!(world, "110", ~D[2025-12-31])
    quote!(world, "121", ~D[2026-01-20])

    analysis = Performance.analysis(world.portfolio.id, today: ~D[2026-01-20])

    for period <- Performance.periods() do
      {:ok, from_analysis} = Performance.summarise(analysis, period)

      {:ok, direct} =
        Performance.for_portfolio(world.portfolio.id, period: period, today: ~D[2026-01-20])

      assert from_analysis == direct
    end

    assert {:error, :invalid_period} = Performance.summarise(analysis, "2w")
  end
end
