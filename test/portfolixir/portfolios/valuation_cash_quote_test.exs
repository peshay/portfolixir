defmodule Portfolixir.Portfolios.ValuationCashQuoteTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 0]

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Valuation

  # User story:
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want the valuation to report my cash quote,
  # so that I can see how much of my portfolio is cash without dividing the
  # totals myself.
  #
  # Acceptance criteria:
  # - cash_quote is deployable cash / (total_value + deployable cash).
  # - An empty portfolio (nothing to value) reports a cash_quote of 0.

  defp setup_world, do: base_world()

  defp set_balance!(portfolio, account, amount, date) do
    {:ok, _} =
      Ledger.set_cash_balance(account, %{date: date, amount: amount})

    portfolio
  end

  defp deposit!(portfolio, account, amount, date) do
    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: account.id,
        type: "deposit",
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    portfolio
  end

  test "reports the cash quote as deployable cash over total including cash" do
    %{portfolio: portfolio, cash: cash, depot: depot} = setup_world()

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Core Equity",
        ticker_symbol: "CORE",
        currency_code: "EUR",
        asset_class: "equity"
      })

    # Deposit 1000, then spend 800 on shares -> 200 cash left, 800 invested.
    deposit!(portfolio, cash, "1000", ~D[2026-01-01])

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
    assert Decimal.equal?(valuation.counting_cash, Decimal.new("200"))
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
  # As a local portfolio maintainer with overdraft/Lombard and reserve accounts,
  # I want deployable cash to count only genuine spendable cash,
  # so that the cash quote never reports fake liquidity from a credit line or a
  # reserve bucket, while liabilities still reduce my net worth.
  #
  # Acceptance criteria:
  # - liquidity_role defaults to free_cash and rejects unknown values.
  # - deployable cash = Σ free_cash accounts with balance >= 0.
  # - a negative free_cash balance is excluded from deployable cash.
  # - a credit_line never counts (type beats sign): a positive balance is
  #   excluded and a negative (drawn) balance is a liability, excluded.
  # - a reserve account is excluded from deployable cash.
  # - total_cash still spans every valued account, so a drawn credit line
  #   reduces net worth.

  test "liquidity_role defaults to free_cash, can be set, and rejects unknown values" do
    %{cash: cash} = setup_world()

    assert CashAccount.liquidity_roles() == ~w(free_cash credit_line reserve)
    assert cash.liquidity_role == "free_cash"

    assert {:ok, updated} =
             Portfolios.update_cash_account(Portfolixir.Actor.owner_ui(), cash, %{
               "liquidity_role" => "reserve"
             })

    assert updated.liquidity_role == "reserve"

    assert {:error, changeset} =
             Portfolios.update_cash_account(Portfolixir.Actor.owner_ui(), updated, %{
               "liquidity_role" => "bogus"
             })

    assert %{liquidity_role: ["is invalid"]} = errors_on(changeset)

    assert {:error, nil_changeset} =
             Portfolios.update_cash_account(Portfolixir.Actor.owner_ui(), updated, %{
               "liquidity_role" => nil
             })

    assert %{liquidity_role: ["can't be blank"]} = errors_on(nil_changeset)
  end

  test "deployable cash counts only positive free_cash; credit lines and reserves never count" do
    %{portfolio: portfolio, cash: free_cash} = setup_world()

    # free_cash: +200 deployable.
    set_balance!(portfolio, free_cash, "200", ~D[2026-01-01])

    # free_cash overdrawn: -50, excluded from deployable cash but still in
    # total_cash (it is real money owed, reducing net worth).
    {:ok, overdrawn_free} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Overdrawn Free",
        currency_code: "EUR",
        liquidity_role: "free_cash"
      })

    set_balance!(portfolio, overdrawn_free, "-50", ~D[2026-01-01])

    # credit_line drawn: -300, a liability (excluded from deployable, in total).
    {:ok, drawn_credit} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Lombard",
        currency_code: "EUR",
        liquidity_role: "credit_line"
      })

    set_balance!(portfolio, drawn_credit, "-300", ~D[2026-01-01])

    # credit_line with a positive balance: type beats sign, still excluded from
    # deployable cash though it joins total_cash.
    {:ok, positive_credit} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Credit Surplus",
        currency_code: "EUR",
        liquidity_role: "credit_line"
      })

    set_balance!(portfolio, positive_credit, "100", ~D[2026-01-01])

    # reserve: +500 visible but excluded from deployable cash.
    {:ok, reserve} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Reserve",
        currency_code: "EUR",
        liquidity_role: "reserve"
      })

    set_balance!(portfolio, reserve, "500", ~D[2026-01-01])

    valuation = Valuation.for_portfolio(portfolio.id)

    # Deployable cash = the +200 free_cash only.
    assert Decimal.equal?(valuation.counting_cash, Decimal.new("200"))

    # total_cash spans every valued account: 200 - 50 - 300 + 100 + 500 = 450.
    assert Decimal.equal?(valuation.total_cash, Decimal.new("450"))

    # cash_quote = 200 / (0 + 200) = 1 here (no securities held).
    assert Decimal.equal?(valuation.cash_quote, Decimal.new("1"))

    roles =
      Map.new(valuation.cash_balances, fn entry ->
        {entry.cash_account_id, {entry.liquidity_role, entry.deployable}}
      end)

    assert {"free_cash", true} = roles[free_cash.id]
    assert {"free_cash", false} = roles[overdrawn_free.id]
    assert {"credit_line", false} = roles[drawn_credit.id]
    assert {"credit_line", false} = roles[positive_credit.id]
    assert {"reserve", false} = roles[reserve.id]
  end
end
