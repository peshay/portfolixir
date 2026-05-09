defmodule Portfolixir.MVPFoundationTest do
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
                 symbol: "SYN",
                 currency_code: "EUR",
                 isin: "XS0000000001"
               })

      assert {:ok, portfolio} =
               Portfolios.create_portfolio(%{
                 name: "MVP Portfolio",
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

      assert {:ok, _first_quote} =
               Catalog.create_security_quote(%{
                 security_id: security.id,
                 date: ~D[2026-01-02],
                 close: Decimal.new("100.25"),
                 currency_code: "EUR",
                 source: "manual"
               })

      assert {:ok, _second_quote} =
               Catalog.create_security_quote(%{
                 security_id: security.id,
                 date: ~D[2026-02-03],
                 close: Decimal.new("111.75"),
                 currency_code: "EUR",
                 source: "manual"
               })

      assert Enum.map(Catalog.list_security_quotes(security.id), & &1.date) == [
               ~D[2026-01-02],
               ~D[2026-02-03]
             ]

      assert Decimal.equal?(
               Catalog.get_latest_security_quote(security.id).close,
               Decimal.new("111.75")
             )
    end

    # User story:
    # As a local portfolio maintainer,
    # I want the reboot ledger to accept only manual buy and sell transactions,
    # so that deferred income, import, payment, and broker behaviors stay out of the MVP.
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
end
