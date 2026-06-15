defmodule PortfolixirWeb.ApiV1ValuationCashQuoteTest do
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
  # I want the valuation endpoint to return the cash quote,
  # so that I can read my cash share directly from the API.
  #
  # Acceptance criteria:
  # - GET /api/v1/portfolios/:id/valuation returns cash_quote as a Decimal string.
  # - The same response exposes counting_cash (the cash entering the quote) as a
  #   Decimal string, so the consumer can reconstruct the quote itself.
  test "valuation endpoint returns the cash quote", %{conn: conn} do
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
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Core Equity",
        ticker_symbol: "CORE",
        currency_code: "EUR",
        asset_class: "equity"
      })

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

    {:ok, _} =
      Quotes.upsert_many(security.id, [%{date: ~D[2026-06-01], close: "80", source: "manual"}])

    data =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/valuation")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["total_with_cash"] == "1000"
    assert data["cash_quote"] == "0.2"

    # counting_cash is the cash that enters the quote, as a Decimal string, so
    # the consumer can recompute cash_quote = counting_cash / (total + counting_cash).
    assert data["counting_cash"] == "200"
    assert is_binary(data["counting_cash"])
  end
end
