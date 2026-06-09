defmodule PortfolixirWeb.ApiV1PerformanceTest do
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
  # I want the portfolio TTWROR over a chosen period from one endpoint,
  # so that performance no longer requires a manual look into Portfolio
  # Performance.
  #
  # Acceptance criteria:
  # - GET /portfolios/:id/performance returns ttwror and the period totals as
  #   Decimal strings; series only when requested.
  # - An unknown period returns 422; an unknown portfolio 404.
  test "returns the TTWROR with optional series", %{conn: conn} do
    {:ok, portfolio} = Portfolios.create_portfolio(%{name: "P", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, security} =
      Catalog.create_security(%{
        name: "Index Fund",
        ticker_symbol: "IDX",
        currency_code: "EUR",
        asset_class: "etf"
      })

    today = Date.utc_today()
    start = Date.add(today, -10)

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: start,
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
        date: start,
        quantity: "10",
        price: "100",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    {:ok, _} =
      Quotes.upsert_many(security.id, [
        %{date: start, close: "100", source: "manual"},
        %{date: today, close: "110", source: "manual"}
      ])

    data =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/performance")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["period"] == "max"
    assert data["ttwror"] == "0.1"
    assert data["end_value"] == "1100"
    assert data["net_external_flows"] == "1000"
    refute Map.has_key?(data, "series")

    with_series =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/performance?period=max&series=true")
      |> json_response(200)
      |> Map.fetch!("data")

    assert length(with_series["series"]) == 11
    assert List.last(with_series["series"])["cumulative_ttwror"] == "0.1"
  end

  test "rejects an unknown period and an unknown portfolio", %{conn: conn} do
    {:ok, portfolio} = Portfolios.create_portfolio(%{name: "P", base_currency_code: "EUR"})

    invalid =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/performance?period=2w")
      |> json_response(422)

    assert invalid == %{"errors" => %{"period" => ["is invalid"]}}

    missing =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/999999/performance")
      |> json_response(404)

    assert missing == %{"errors" => %{"detail" => "not found"}}
  end
end
