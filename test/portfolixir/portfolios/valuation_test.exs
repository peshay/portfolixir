defmodule Portfolixir.Portfolios.ValuationTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, put_quote!: 3]

  alias Portfolixir.Ledger
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
  # - A held position without a quote falls back to the latest own trade price
  #   (price_source :trade), like Portfolio Performance seeds prices from
  #   bookings, so a freshly imported portfolio is not valued at zero.
  # - A held position with neither quote nor trade price is reported as
  #   unvalued (nil market value and weight) and does not break the total or
  #   the weights.

  defp equity!(name, ticker),
    do: create_security!(name: name, ticker: ticker, asset_class: "equity")

  defp etf!(name, ticker), do: create_security!(name: name, ticker: ticker, asset_class: "etf")

  defp june_quote!(security, close), do: put_quote!(security, ~D[2026-06-01], close)

  test "prices held positions, totals them, and weights each share of the total" do
    world = base_world()

    equity = equity!("Apple Inc.", "AAPL")
    etf = etf!("World ETF", "EUNL")
    no_quote = equity!("Quiet Co.", "QUIET")
    no_price = equity!("Delivered Co.", "DLVR")

    buy!(world, equity, quantity: "10", price: "80")
    buy!(world, etf, quantity: "5", price: "150")
    buy!(world, no_quote, quantity: "10", price: "50")

    # Held via delivery only: no quote and no own trade price exists.
    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: no_price.id,
        type: "inbound_delivery",
        date: ~D[2026-01-02],
        quantity: "7",
        currency_code: "EUR"
      })

    june_quote!(equity, "100")
    june_quote!(etf, "200")

    valuation = Valuation.for_portfolio(world.portfolio.id)

    # 1000 (quote) + 1000 (quote) + 500 (latest trade price fallback).
    assert Decimal.equal?(valuation.total_value, Decimal.new("2500"))

    by_security = Map.new(valuation.positions, &{&1.security_id, &1})

    equity_row = by_security[equity.id]
    etf_row = by_security[etf.id]
    trade_row = by_security[no_quote.id]
    unvalued_row = by_security[no_price.id]

    assert Decimal.equal?(equity_row.market_value, Decimal.new("1000"))
    assert Decimal.equal?(equity_row.weight, Decimal.new("0.4"))
    assert equity_row.price_source == :quote
    assert Decimal.equal?(etf_row.market_value, Decimal.new("1000"))
    assert Decimal.equal?(etf_row.weight, Decimal.new("0.4"))

    assert trade_row.valued
    assert trade_row.price_source == :trade
    assert Decimal.equal?(trade_row.market_value, Decimal.new("500"))
    assert Decimal.equal?(trade_row.weight, Decimal.new("0.2"))

    refute unvalued_row.valued
    assert is_nil(unvalued_row.price_source)
    assert is_nil(unvalued_row.market_value)
    assert is_nil(unvalued_row.weight)

    assert valuation.trade_priced_count == 1
    assert valuation.unvalued_count == 1

    valued_weights =
      valuation.positions
      |> Enum.filter(& &1.valued)
      |> Enum.map(& &1.weight)
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

    assert Decimal.equal?(valued_weights, Decimal.new("1"))
  end

  test "injects prices for tests without touching quote history" do
    world = base_world()
    security = equity!("Apple Inc.", "AAPL")
    buy!(world, security, quantity: "4", price: "10")

    valuation =
      Valuation.for_portfolio(world.portfolio.id, prices: %{security.id => Decimal.new("25")})

    [row] = valuation.positions
    assert Decimal.equal?(row.market_value, Decimal.new("100"))
    assert Decimal.equal?(valuation.total_value, Decimal.new("100"))
  end
end
