defmodule Portfolixir.Portfolios.ValuationCashQuoteTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 0]

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

  defp setup_world, do: base_world()

  test "reports the cash quote as cash over total including cash" do
    %{portfolio: portfolio, cash: cash, depot: depot} = setup_world()

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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

  # User story:
  # As a local portfolio maintainer with a business account,
  # I want to mark a cash account as not counting toward the cash quote,
  # so that the account stays visible without distorting my private quote.
  #
  # Acceptance criteria:
  # - counts_toward_cash_quote defaults to true and can be toggled.
  # - cash_quote is computed over counting accounts only, as if excluded
  #   accounts did not exist.
  # - total_cash and the cash listing still include all accounts; each entry
  #   carries counts_toward_cash_quote so excluded ones can be marked.

  test "counts_toward_cash_quote defaults to true, can be toggled, and rejects nil" do
    %{cash: cash} = setup_world()

    assert cash.counts_toward_cash_quote == true

    assert {:ok, updated} =
             Portfolios.update_cash_account(cash, %{"counts_toward_cash_quote" => false})

    assert updated.counts_toward_cash_quote == false

    assert {:error, changeset} =
             Portfolios.update_cash_account(updated, %{"counts_toward_cash_quote" => nil})

    assert %{counts_toward_cash_quote: ["can't be blank"]} = errors_on(changeset)
  end

  test "excludes flagged accounts from the cash quote but keeps them listed" do
    %{portfolio: portfolio, cash: cash, depot: depot} = setup_world()

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Core Equity",
        ticker_symbol: "CORE",
        currency_code: "EUR",
        asset_class: "equity"
      })

    # Private account: deposit 1000, spend 800 on shares -> 200 cash left.
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

    # Business account: 500 visible, but excluded from the cash quote.
    {:ok, business} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Business Account",
        currency_code: "EUR",
        counts_toward_cash_quote: false
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: business.id,
        type: "deposit",
        date: ~D[2026-01-03],
        gross_amount: "500",
        currency_code: "EUR"
      })

    valuation = Valuation.for_portfolio(portfolio.id, prices: %{security.id => Decimal.new("80")})

    # Totals and the listing still include the business account...
    assert Decimal.equal?(valuation.total_value, Decimal.new("800"))
    assert Decimal.equal?(valuation.total_cash, Decimal.new("700"))
    assert Decimal.equal?(valuation.total_with_cash, Decimal.new("1500"))

    # ...but the cash quote is 200 / (800 + 200), as if it did not exist.
    assert Decimal.equal?(valuation.cash_quote, Decimal.new("0.2"))

    business_entry = Enum.find(valuation.cash_balances, &(&1.cash_account_id == business.id))
    private_entry = Enum.find(valuation.cash_balances, &(&1.cash_account_id == cash.id))

    assert business_entry.counts_toward_cash_quote == false
    assert Decimal.equal?(business_entry.balance, Decimal.new("500"))
    assert private_entry.counts_toward_cash_quote == true
  end
end
