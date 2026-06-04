defmodule Portfolixir.Portfolios.ValuationTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation

  # User story:
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want a live valuation of my portfolio that prices each held position
  # from its latest quote and reports each position's share of the total,
  # so that I can see current market values and actual weights without doing
  # the maths by hand.
  #
  # Acceptance criteria:
  # - Each held position carries a market value (quantity x latest close).
  # - The portfolio total equals the sum of the valued positions' market values.
  # - Actual weights of the valued positions sum to 1.
  # - A held position without any quote is reported as unvalued (nil market
  #   value and weight) and does not break the total or the weights.

  defp setup_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Local Portfolio", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Local Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Main Depot"
      })

    %{portfolio: portfolio, cash: cash, depot: depot}
  end

  defp create_security!(name, ticker, asset_class) do
    {:ok, security} =
      Catalog.create_security(%{
        name: name,
        ticker_symbol: ticker,
        currency_code: "EUR",
        asset_class: asset_class
      })

    security
  end

  defp buy!(%{portfolio: p, depot: d, cash: c}, security, qty, price) do
    {:ok, tx} =
      Ledger.create_transaction(%{
        portfolio_id: p.id,
        securities_account_id: d.id,
        cash_account_id: c.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: qty,
        price: price,
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    tx
  end

  defp put_quote!(security, close) do
    {:ok, _} =
      Quotes.upsert_many(security.id, [
        %{date: ~D[2026-06-01], close: close, source: "manual"}
      ])
  end

  test "prices held positions, totals them, and weights each share of the total" do
    world = setup_world()

    equity = create_security!("Apple Inc.", "AAPL", "equity")
    etf = create_security!("World ETF", "EUNL", "etf")
    no_quote = create_security!("Quiet Co.", "QUIET", "equity")

    buy!(world, equity, "10", "80")
    buy!(world, etf, "5", "150")
    buy!(world, no_quote, "3", "50")

    put_quote!(equity, "100")
    put_quote!(etf, "200")

    valuation = Valuation.for_portfolio(world.portfolio.id)

    assert Decimal.equal?(valuation.total_value, Decimal.new("2000"))

    by_security = Map.new(valuation.positions, &{&1.security_id, &1})

    equity_row = by_security[equity.id]
    etf_row = by_security[etf.id]
    unvalued_row = by_security[no_quote.id]

    assert Decimal.equal?(equity_row.market_value, Decimal.new("1000"))
    assert Decimal.equal?(equity_row.weight, Decimal.new("0.5"))
    assert Decimal.equal?(etf_row.market_value, Decimal.new("1000"))
    assert Decimal.equal?(etf_row.weight, Decimal.new("0.5"))

    refute unvalued_row.valued
    assert is_nil(unvalued_row.market_value)
    assert is_nil(unvalued_row.weight)

    valued_weights =
      valuation.positions
      |> Enum.filter(& &1.valued)
      |> Enum.map(& &1.weight)
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

    assert Decimal.equal?(valued_weights, Decimal.new("1"))
  end

  test "injects prices for tests without touching quote history" do
    world = setup_world()
    security = create_security!("Apple Inc.", "AAPL", "equity")
    buy!(world, security, "4", "10")

    valuation =
      Valuation.for_portfolio(world.portfolio.id, prices: %{security.id => Decimal.new("25")})

    [row] = valuation.positions
    assert Decimal.equal?(row.market_value, Decimal.new("100"))
    assert Decimal.equal?(valuation.total_value, Decimal.new("100"))
  end
end
