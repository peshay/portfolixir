defmodule Portfolixir.ValuationTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Valuation

  setup do
    :ok = Catalog.ensure_mvp_currencies!()

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{
        name: "Valuation Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        name: "Main Depot",
        currency_code: "EUR"
      })

    {:ok, security} =
      Catalog.create_security(%{
        name: "MSCI World ETF",
        symbol: "MSCI",
        currency_code: "EUR"
      })

    %{portfolio: portfolio, securities_account: securities_account, security: security}
  end

  test "position with latest quote returns market value", %{
    portfolio: portfolio,
    securities_account: account,
    security: security
  } do
    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               type: "buy",
               date: ~D[2026-05-01],
               currency_code: "EUR",
               amount: Decimal.new("1000"),
               quantity: Decimal.new("10"),
               price: Decimal.new("100"),
               deposit_account_id: nil,
               securities_account_id: account.id,
               security_id: security.id
             })

    assert {:ok, _quote} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "EUR",
               close: Decimal.new("123.45")
             })

    snapshot = Valuation.position_market_value_snapshot(portfolio.id)
    [row] = snapshot.positions

    assert row.portfolio_id == portfolio.id
    assert row.securities_account == "Main Depot"
    assert row.security == "MSCI World ETF"
    assert Decimal.equal?(row.quantity, Decimal.new("10"))
    assert row.latest_quote_date == ~D[2026-05-01]
    assert Decimal.equal?(row.latest_quote_close, Decimal.new("123.45"))
    assert Decimal.equal?(row.market_value, Decimal.new("1234.50"))
    assert row.currency_code == "EUR"
    assert row.warning == nil
    assert Decimal.equal?(snapshot.totals_by_currency["EUR"], Decimal.new("1234.50"))
  end

  test "latest quote uses newest quote by date", %{
    portfolio: portfolio,
    securities_account: account,
    security: security
  } do
    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               type: "buy",
               date: ~D[2026-05-01],
               currency_code: "EUR",
               amount: Decimal.new("200"),
               quantity: Decimal.new("2"),
               price: Decimal.new("100"),
               deposit_account_id: nil,
               securities_account_id: account.id,
               security_id: security.id
             })

    assert {:ok, _} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-01],
               source: "manual",
               currency_code: "EUR",
               close: Decimal.new("110")
             })

    assert {:ok, _} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-02],
               source: "manual",
               currency_code: "EUR",
               close: Decimal.new("120")
             })

    [row] = Valuation.position_market_value_snapshot(portfolio.id).positions

    assert row.latest_quote_date == ~D[2026-05-02]
    assert Decimal.equal?(row.latest_quote_close, Decimal.new("120"))
    assert Decimal.equal?(row.market_value, Decimal.new("240"))
  end

  test "missing quote returns nil market value and warning", %{
    portfolio: portfolio,
    securities_account: account,
    security: security
  } do
    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               type: "buy",
               date: ~D[2026-05-01],
               currency_code: "EUR",
               amount: Decimal.new("200"),
               quantity: Decimal.new("2"),
               price: Decimal.new("100"),
               deposit_account_id: nil,
               securities_account_id: account.id,
               security_id: security.id
             })

    [row] = Valuation.position_market_value_snapshot(portfolio.id).positions

    assert row.market_value == nil
    assert row.latest_quote_date == nil
    assert row.latest_quote_close == nil
    assert row.warning == "missing_latest_quote"
    assert row.currency_code == "EUR"
  end

  test "sell reduces quantity before valuation", %{
    portfolio: portfolio,
    securities_account: account,
    security: security
  } do
    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               type: "buy",
               date: ~D[2026-05-01],
               currency_code: "EUR",
               amount: Decimal.new("1000"),
               quantity: Decimal.new("10"),
               price: Decimal.new("100"),
               deposit_account_id: nil,
               securities_account_id: account.id,
               security_id: security.id
             })

    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               type: "sell",
               date: ~D[2026-05-02],
               currency_code: "EUR",
               amount: Decimal.new("400"),
               quantity: Decimal.new("4"),
               price: Decimal.new("100"),
               deposit_account_id: nil,
               securities_account_id: account.id,
               security_id: security.id
             })

    assert {:ok, _} =
             Catalog.create_security_quote(%{
               security_id: security.id,
               date: ~D[2026-05-03],
               source: "manual",
               currency_code: "EUR",
               close: Decimal.new("150")
             })

    [row] = Valuation.position_market_value_snapshot(portfolio.id).positions

    assert Decimal.equal?(row.quantity, Decimal.new("6"))
    assert Decimal.equal?(row.market_value, Decimal.new("900"))
  end

  test "valuation does not create transactions or quotes", %{portfolio: portfolio} do
    transaction_count = Repo.aggregate(Portfolixir.Ledger.Transaction, :count, :id)
    quote_count = Repo.aggregate(Portfolixir.Catalog.SecurityQuote, :count, :id)

    _snapshot = Valuation.position_market_value_snapshot(portfolio.id)

    assert Repo.aggregate(Portfolixir.Ledger.Transaction, :count, :id) == transaction_count
    assert Repo.aggregate(Portfolixir.Catalog.SecurityQuote, :count, :id) == quote_count
  end
end
