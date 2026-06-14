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

    {:ok, security} =
      Catalog.create_security(%{
        name: "Core Equity",
        ticker_symbol: "CORE",
        currency_code: "EUR",
        asset_class: "equity"
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
end
