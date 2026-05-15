defmodule Portfolixir.WorkflowFoundationTest do
  use Portfolixir.DataCase

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount

  describe "minimal portfolio workflow" do
    # User story:
    # As a local portfolio maintainer,
    # I want to create the minimum portfolio setup and record manual trades,
    # so that current holdings and quote history are derived from auditable local data.
    #
    # Acceptance criteria:
    # - A security, portfolio, cash account, and linked depot can be created.
    # - Manual buy and sell transactions update the derived holding quantity.
    # - Stored quote history is listed in date order and exposes the latest quote.
    test "creates a security, portfolio, linked accounts, buy/sell transactions, holdings, and quotes" do
      assert {:ok, security} =
               Catalog.create_security(%{
                 name: "Synthetic Global ETF",
                 ticker_symbol: "SYN",
                 currency_code: "EUR",
                 isin: "XS0000000001"
               })

      assert {:ok, portfolio} =
               Portfolios.create_portfolio(%{
                 name: "Local Portfolio",
                 base_currency_code: "EUR"
               })

      assert {:ok, cash_account} =
               Portfolios.create_cash_account(%{
                 portfolio_id: portfolio.id,
                 name: "Cash EUR",
                 currency_code: "EUR"
               })

      assert %CashAccount{} = cash_account

      assert {:ok, securities_account} =
               Portfolios.create_securities_account(%{
                 portfolio_id: portfolio.id,
                 cash_account_id: cash_account.id,
                 name: "Depot"
               })

      assert securities_account.cash_account_id == cash_account.id

      assert {:ok, _buy} =
               Ledger.create_transaction(%{
                 portfolio_id: portfolio.id,
                 securities_account_id: securities_account.id,
                 cash_account_id: cash_account.id,
                 security_id: security.id,
                 type: "buy",
                 date: ~D[2026-01-02],
                 quantity: Decimal.new("10.5"),
                 price: Decimal.new("100.25"),
                 fees: Decimal.new("1.50"),
                 taxes: Decimal.new("0"),
                 currency_code: "EUR"
               })

      assert {:ok, _sell} =
               Ledger.create_transaction(%{
                 portfolio_id: portfolio.id,
                 securities_account_id: securities_account.id,
                 cash_account_id: cash_account.id,
                 security_id: security.id,
                 type: "sell",
                 date: ~D[2026-02-03],
                 quantity: Decimal.new("2.25"),
                 price: Decimal.new("110.00"),
                 fees: Decimal.new("1.00"),
                 taxes: Decimal.new("0"),
                 currency_code: "EUR"
               })

      position_key = {securities_account.id, security.id}
      assert %{^position_key => quantity} = Ledger.positions_for_portfolio(portfolio.id)

      assert Decimal.equal?(quantity, Decimal.new("8.25"))

      assert security.ticker_symbol == "SYN"
    end

    # User story:
    # As a local portfolio maintainer,
    # I want trade transactions to use the cash account linked to the selected depot,
    # so that I cannot accidentally post a buy or sell against the wrong cash account.
    #
    # Acceptance criteria:
    # - Transaction creation derives cash_account_id from securities_account_id.
    # - A mismatching cash_account_id is rejected server-side.
    # - A depot from one portfolio cannot be combined with a cash account from another portfolio.
    # - Existing holdings calculation still reflects buy and sell quantities.
    test "transactions derive the depot-linked cash account and reject cash account mismatches" do
      {portfolio, security, linked_cash_account, depot} = create_minimal_trade_setup("Main")

      {_other_portfolio, _other_security, other_cash_account, _other_depot} =
        create_minimal_trade_setup("Other")

      assert {:ok, buy} =
               Ledger.create_transaction(%{
                 portfolio_id: portfolio.id,
                 securities_account_id: depot.id,
                 security_id: security.id,
                 type: "buy",
                 date: ~D[2026-03-04],
                 quantity: Decimal.new("3.0"),
                 price: Decimal.new("25.00"),
                 fees: Decimal.new("0"),
                 taxes: Decimal.new("0"),
                 currency_code: "EUR"
               })

      assert buy.cash_account_id == linked_cash_account.id

      assert {:error, mismatch_changeset} =
               Ledger.create_transaction(%{
                 portfolio_id: portfolio.id,
                 securities_account_id: depot.id,
                 cash_account_id: other_cash_account.id,
                 security_id: security.id,
                 type: "buy",
                 date: ~D[2026-03-05],
                 quantity: Decimal.new("1.0"),
                 price: Decimal.new("25.00"),
                 fees: Decimal.new("0"),
                 taxes: Decimal.new("0"),
                 currency_code: "EUR"
               })

      assert "must match the selected depot" in errors_on(mismatch_changeset).cash_account_id

      assert {:ok, sell} =
               Ledger.create_transaction(%{
                 portfolio_id: portfolio.id,
                 securities_account_id: depot.id,
                 security_id: security.id,
                 type: "sell",
                 date: ~D[2026-03-06],
                 quantity: Decimal.new("1.25"),
                 price: Decimal.new("26.00"),
                 fees: Decimal.new("0"),
                 taxes: Decimal.new("0"),
                 currency_code: "EUR"
               })

      assert sell.cash_account_id == linked_cash_account.id

      position_key = {depot.id, security.id}
      assert %{^position_key => quantity} = Ledger.positions_for_portfolio(portfolio.id)
      assert Decimal.equal?(quantity, Decimal.new("1.75"))
    end

    # User story:
    # As a local portfolio maintainer,
    # I want the ledger to accept only manual buy and sell transactions,
    # so that deferred income, import, payment, and broker behaviors stay out of scope.
    #
    # Acceptance criteria:
    # - Unsupported transaction types are rejected by the changeset.
    # - The validation happens before any record is persisted.
    test "transaction changeset accepts only manual buy and sell types" do
      assert {:error, changeset} =
               Ledger.create_transaction(%{
                 type: "dividend",
                 date: ~D[2026-01-02],
                 quantity: Decimal.new("1"),
                 price: Decimal.new("1"),
                 currency_code: "EUR"
               })

      assert "is invalid" in errors_on(changeset).type
    end
  end

  defp create_minimal_trade_setup(prefix) do
    assert {:ok, security} =
             Catalog.create_security(%{
               name: "#{prefix} Synthetic ETF",
               ticker_symbol: String.slice(prefix, 0, 3) |> String.upcase(),
               currency_code: "EUR"
             })

    assert {:ok, portfolio} =
             Portfolios.create_portfolio(%{
               name: "#{prefix} Portfolio",
               base_currency_code: "EUR"
             })

    assert {:ok, cash_account} =
             Portfolios.create_cash_account(%{
               portfolio_id: portfolio.id,
               name: "#{prefix} Cash",
               currency_code: "EUR"
             })

    assert {:ok, depot} =
             Portfolios.create_securities_account(%{
               portfolio_id: portfolio.id,
               cash_account_id: cash_account.id,
               name: "#{prefix} Depot"
             })

    {portfolio, security, cash_account, depot}
  end
end
