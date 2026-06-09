defmodule Portfolixir.Portfolios.ValuationCashQuoteTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation

  # User story:
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want the valuation to report my cash quote,
  # so that I can see how much of my portfolio is cash without dividing the
  # totals myself.
  #
  # Acceptance criteria:
  # - cash_quote is total_cash / total_with_cash.
  # - An empty portfolio (nothing to value) reports a cash_quote of 0.

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

  test "reports the cash quote as cash over total including cash" do
    %{portfolio: portfolio, cash: cash, depot: depot} = setup_world()

    {:ok, security} =
      Catalog.create_security(%{
        name: "Core Equity",
        ticker_symbol: "CORE",
        currency_code: "EUR",
        asset_class: "equity"
      })

    # Deposit 1000, then spend 800 on shares -> 200 cash left, 800 invested.
    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: ~D[2026-01-01],
        gross_amount: "1000",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "10",
        price: "80",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    valuation = Valuation.for_portfolio(portfolio.id, prices: %{security.id => Decimal.new("80")})

    assert Decimal.equal?(valuation.total_value, Decimal.new("800"))
    assert Decimal.equal?(valuation.total_cash, Decimal.new("200"))
    assert Decimal.equal?(valuation.total_with_cash, Decimal.new("1000"))
    assert Decimal.equal?(valuation.cash_quote, Decimal.new("0.2"))
  end

  test "reports a zero cash quote for an empty portfolio" do
    %{portfolio: portfolio} = setup_world()

    valuation = Valuation.for_portfolio(portfolio.id)

    assert Decimal.equal?(valuation.total_with_cash, Decimal.new("0"))
    assert Decimal.equal?(valuation.cash_quote, Decimal.new("0"))
  end
end
