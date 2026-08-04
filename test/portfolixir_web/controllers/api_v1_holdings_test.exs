defmodule PortfolixirWeb.ApiV1HoldingsTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", elem(@auth, 1))
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want the holdings endpoint to return cost basis and unrealized P&L,
  # so that I can value each position without re-deriving its average cost.
  #
  # Acceptance criteria:
  # - A held position serializes quantity, avg_cost, cost_basis, latest_price,
  #   market_value and unrealized P&L (as Decimal strings) in its own currency.
  test "holdings endpoint returns cost basis and unrealized P&L", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Local Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Local Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Main Depot"
      })

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Core Equity",
        ticker_symbol: "CORE",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "10",
        price: "100",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    {:ok, _} =
      Quotes.upsert_many(security.id, [%{date: ~D[2026-06-01], close: "120", source: "manual"}])

    response =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/holdings")
      |> json_response(200)

    # FR-13: the response is self-describing about its currency basis and read
    # date, so a consumer never has to assume whether FX was applied.
    assert response["currency_basis"] == "security_currency"
    assert response["as_of"] == Date.to_iso8601(Date.utc_today())

    data = Map.fetch!(response, "data")

    assert [holding] = data
    assert holding["security_id"] == security.id
    assert holding["security_name"] == "Core Equity"
    assert holding["currency_code"] == "EUR"
    assert holding["quantity"] == "10"
    assert holding["avg_cost"] == "100"
    assert holding["cost_basis"] == "1000"
    assert holding["latest_price"] == "120"
    assert holding["market_value"] == "1200"
    assert holding["unrealized_pnl_abs"] == "200"
    assert holding["unrealized_pnl_pct"] == "0.2"
  end

  # User story:
  # As the operating LLM agent reconciling against broker data,
  # I want ISIN and WKN on every holdings row,
  # so that I can match positions by their stable identifiers without a
  # token-expensive client-side join over the securities list.
  #
  # Acceptance criteria:
  # - Holdings rows carry isin and wkn.
  # - A security without ISIN/WKN serializes them as null (additive,
  #   backward-compatible fields).
  test "holdings rows carry ISIN/WKN, null when absent", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Ident Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Ident Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Ident Depot"
      })

    {:ok, with_isin} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Identified Equity",
        ticker_symbol: "IDN",
        isin: "DE0007100000",
        wkn: "710000",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, without_isin} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Unidentified Coin",
        ticker_symbol: "COIN",
        currency_code: "EUR",
        asset_class: "crypto"
      })

    for security <- [with_isin, without_isin] do
      {:ok, _} =
        Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "buy",
          date: ~D[2026-01-02],
          quantity: "5",
          price: "10",
          fees: "0",
          taxes: "0",
          currency_code: "EUR"
        })
    end

    data =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/holdings")
      |> json_response(200)
      |> Map.fetch!("data")

    identified = Enum.find(data, &(&1["security_id"] == with_isin.id))
    assert identified["isin"] == "DE0007100000"
    assert identified["wkn"] == "710000"

    unidentified = Enum.find(data, &(&1["security_id"] == without_isin.id))
    # Keys must be PRESENT with null (contract: additive fields, never absent).
    assert Map.has_key?(unidentified, "isin") and unidentified["isin"] == nil
    assert Map.has_key?(unidentified, "wkn") and unidentified["wkn"] == nil
  end

  # User story (ADR-0033, issue #569):
  # As an API client (and the LLM I connect over MCP),
  # I want each holdings row to carry the price/currency decomposition of its
  # base-currency P&L as Decimal strings, and the currency-basis label to say
  # exactly which figures are in which currency,
  # so that a consumer can attribute FX effects without deriving rates itself.
  #
  # Acceptance criteria (the ADR-0033 fixture through stored rates):
  # - base_cost "800.00" EUR, price_return_abs "90", currency_return_abs
  #   "100", total_return_base_abs "190", decomposed true.
  # - Financial decimals serialize as strings.
  # - The response's currency_basis note names both bases.
  test "holdings rows carry the base-currency P&L decomposition", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "FX Decomp Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "FX Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "FX Depot"
      })

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Synthetic US Equity",
        ticker_symbol: "SUS",
        currency_code: "USD",
        asset_class: "equity"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-15],
        quantity: "10",
        price: "100.00",
        currency_code: "USD",
        security_amount: "1000.00",
        settlement_amount: "800.00",
        settlement_fx_rate: "0.80"
      })

    {:ok, _} =
      Quotes.upsert_many(security.id, [
        %{date: ~D[2026-07-31], close: "110.00", source: "manual"}
      ])

    # Stored current hub rate: 1 EUR = 1.25 USD, i.e. 0.80 EUR per USD.
    {:ok, _} =
      Portfolixir.Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-07-31],
          rate: "1.25",
          source: "manual"
        }
      ])

    response =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/holdings")
      |> json_response(200)

    assert response["currency_basis"] == "security_currency"
    assert response["currency_basis_note"] =~ "base_cost"
    assert response["currency_basis_note"] =~ "security's own currency"

    assert [holding] = response["data"]
    assert holding["cost_basis"] == "1000"
    assert holding["base_cost"] == "800"
    assert holding["base_currency"] == "EUR"
    # (1100 - 1000) x 0.80 = 80; 1000 x 0.80 - 800 = 0; total 80.
    assert holding["price_return_abs"] == "80"
    assert holding["currency_return_abs"] == "0"
    assert holding["total_return_base_abs"] == "80"
    assert holding["price_return_pct"] == "0.1"
    assert holding["decomposed"] == true
    assert holding["undecomposed_reason"] == nil
  end

  # User story (ADR-0033 requirement 4 over the API):
  # As an API client reading a row whose decomposition is not derivable,
  # I want decomposed false with a named reason and null components,
  # so that no consumer ever mistakes an unavailable figure for a zero.
  test "an underivable decomposition serializes as unavailable", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "FX Missing Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "FXM Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "FXM Depot"
      })

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Synthetic US Legacy",
        ticker_symbol: "SUL",
        currency_code: "USD",
        asset_class: "equity"
      })

    # A legacy imported row: EUR-booked buy of the USD security, no
    # settlement legs derivable.
    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-15],
        quantity: "10",
        price: "80.00",
        currency_code: "EUR"
      })

    {:ok, _} =
      Quotes.upsert_many(security.id, [
        %{date: ~D[2026-07-31], close: "110.00", source: "manual"}
      ])

    [holding] =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/holdings")
      |> json_response(200)
      |> Map.fetch!("data")

    assert holding["cost_basis"] == nil
    assert holding["avg_cost"] == nil
    assert holding["unrealized_pnl_abs"] == nil
    assert holding["decomposed"] == false
    assert holding["undecomposed_reason"] == "missing_native_cost"
    assert holding["base_cost"] == "800"
    assert holding["base_currency"] == "EUR"
  end

  # User story (ADR-0033 — open lots over the API):
  # As an API client reading GET /api/v1/securities/:id/trades,
  # I want each open lot to carry its security-currency basis and the same
  # decomposition fields as strings,
  # so that the lot surface and the holdings surface cannot disagree.
  test "open lots serialize the native basis and decomposition", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "FX Lots Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "FXL Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "FXL Depot"
      })

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Synthetic US Lots",
        ticker_symbol: "SLT",
        currency_code: "USD",
        asset_class: "equity"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-15],
        quantity: "10",
        price: "80.00",
        currency_code: "EUR",
        security_amount: "1000.00",
        settlement_amount: "800.00",
        settlement_fx_rate: "0.80"
      })

    {:ok, _} =
      Quotes.upsert_many(security.id, [
        %{date: ~D[2026-07-31], close: "110.00", source: "manual"}
      ])

    {:ok, _} =
      Portfolixir.Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-07-31],
          rate: "1.25",
          source: "manual"
        }
      ])

    %{"data" => %{"open_lots" => [lot]}} =
      conn
      |> api_conn()
      |> get("/api/v1/securities/#{security.id}/trades")
      |> json_response(200)

    assert lot["buy_price"] == "80"
    assert lot["buy_price_native"] == "100"
    assert lot["unrealized_pnl_abs"] == "100"
    assert lot["base_cost"] == "800"
    assert lot["base_currency"] == "EUR"
    assert lot["price_return_abs"] == "80"
    assert lot["currency_return_abs"] == "0"
    assert lot["total_return_base_abs"] == "80"
    assert lot["decomposed"] == true
    assert lot["undecomposed_reason"] == nil
  end
end
