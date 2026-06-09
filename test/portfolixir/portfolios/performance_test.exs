defmodule Portfolixir.Portfolios.PerformanceTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance

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

  defp setup_world do
    {:ok, portfolio} = Portfolios.create_portfolio(%{name: "P", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, security} =
      Catalog.create_security(%{
        name: "Index Fund",
        ticker_symbol: "IDX",
        currency_code: "EUR",
        asset_class: "etf"
      })

    %{portfolio: portfolio, cash: cash, depot: depot, security: security}
  end

  defp deposit!(world, amount, date) do
    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "deposit",
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })
  end

  defp buy!(world, qty, price, date) do
    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: world.security.id,
        type: "buy",
        date: date,
        quantity: qty,
        price: price,
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })
  end

  defp quote!(world, close, date) do
    {:ok, _} =
      Quotes.upsert_many(world.security.id, [%{date: date, close: close, source: "manual"}])
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
end
