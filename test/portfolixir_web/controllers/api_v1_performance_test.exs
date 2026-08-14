defmodule PortfolixirWeb.ApiV1PerformanceTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, buy!: 3, deposit!: 4, put_quotes!: 2]

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
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "P",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Index Fund",
        ticker_symbol: "IDX",
        currency_code: "EUR",
        asset_class: "etf"
      })

    today = Date.utc_today()
    start = Date.add(today, -10)

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: start,
        gross_amount: "1000",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
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
    # The money-weighted IRR is exposed as a Decimal string alongside TTWROR.
    assert is_binary(data["irr"])

    # #568 (ADR-0034): invested capital, wealth multiple and the
    # non-annualized period MWR ride the same response as Decimal strings.
    assert data["invested_capital"] == "1000"
    assert data["wealth_multiple"] == "1.1"
    assert data["mwr"] == "0.1"

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

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want the money-weighted return (IRR) in the same performance response,
  # so that I can compare it to the TTWROR without a second tool.
  #
  # Acceptance criteria:
  # - A single deposit invested for a full year that ends 10% higher returns
  #   irr "0.1" as a Decimal string.
  # - A portfolio with no flows to weight returns irr null, never an error.
  test "returns the money-weighted IRR as a Decimal string", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "P",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Index Fund",
        ticker_symbol: "IDX",
        currency_code: "EUR",
        asset_class: "etf"
      })

    today = Date.utc_today()
    start = Date.add(today, -365)

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: start,
        gross_amount: "1000",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
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

    assert data["irr"] == "0.1"

    {:ok, empty} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Empty",
        base_currency_code: "EUR"
      })

    empty_data =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{empty.id}/performance")
      |> json_response(200)
      |> Map.fetch!("data")

    assert empty_data["irr"] == nil
    # #568: nothing invested — the multiple is null (n/a), never negative.
    assert empty_data["mwr"] == nil
    assert empty_data["wealth_multiple"] == nil
    assert empty_data["invested_capital"] == "0"
  end

  # User story (#563):
  # As an API client (and the LLM I connect over MCP),
  # I want a previous year or a custom from/to range as the performance
  # period,
  # so that "how was 2025?" is one call, matching the UI's period picker.
  #
  # Acceptance criteria:
  # - ?year=YYYY chains exactly that calendar year.
  # - ?from=&to= (ISO dates) chain the custom range, clamped to the history.
  # - A backwards range and a malformed year return 422.
  test "chains a single year and a custom range", %{conn: conn} do
    world = base_world(name: "Year P", cash_name: "Year Cash", depot_name: "Year Depot")
    security = create_security!(name: "Year Fund", ticker: "YRF")

    today = Date.utc_today()
    last_year = today.year - 1
    start = Date.new!(last_year, 1, 10)
    year_end = Date.new!(last_year, 12, 31)

    deposit!(world, "1000", start, [])
    buy!(world, security, quantity: "10", price: "100", date: start)
    put_quotes!(security, [{start, "100"}, {year_end, "110"}, {today, "121"}])

    year_data =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/performance?year=#{last_year}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert year_data["period"] == Integer.to_string(last_year)
    # start_date reports the honest clamp: the history starts Jan 10, so the
    # year chains from there, not from an invented Jan 1.
    assert year_data["start_date"] == Date.to_iso8601(start)
    assert year_data["end_date"] == Date.to_iso8601(year_end)
    assert year_data["ttwror"] |> Decimal.new() |> Decimal.round(6) |> Decimal.equal?("0.1")
    assert year_data["end_value"] == "1100"

    range_data =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/performance?from=#{year_end}&to=#{today}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert range_data["period"] == "#{year_end}..#{today}"
    assert range_data["ttwror"] |> Decimal.new() |> Decimal.round(6) |> Decimal.equal?("0.21")

    backwards =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/performance?from=#{today}&to=#{year_end}")
      |> json_response(422)

    assert backwards == %{"errors" => %{"period" => ["is invalid"]}}

    bad_year =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/performance?year=20xx")
      |> json_response(422)

    assert bad_year == %{"errors" => %{"period" => ["is invalid"]}}
  end

  test "rejects an unknown period and an unknown portfolio", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "P",
        base_currency_code: "EUR"
      })

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

  # User story (ADR-0039 C4, FR-1 binding property 3):
  # As an API client (and the LLM I connect over MCP),
  # I want as_of, an explicit stale flag and the metric's computation basis in
  # every performance response,
  # so that a materialized figure is never silent about its freshness and the
  # metric states what it was computed from.
  #
  # Acceptance criteria:
  # - The response carries as_of (ISO-8601 datetime string), stale (boolean)
  #   and computation_basis (input_series, window, reference, gaps).
  # - The fields are present for an empty portfolio too — no serialization
  #   drops them (I4).
  test "states freshness and the computation basis in the payload", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "P",
        base_currency_code: "EUR"
      })

    data =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/performance")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["stale"] == false
    assert {:ok, %DateTime{}, _offset} = DateTime.from_iso8601(data["as_of"])

    assert %{
             "input_series" => input_series,
             "window" => %{"start_date" => _, "end_date" => _},
             "reference" => nil,
             "gaps" => gaps
           } = data["computation_basis"]

    assert is_binary(input_series)
    assert is_binary(gaps)
  end
end
