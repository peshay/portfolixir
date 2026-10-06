defmodule PortfolixirWeb.ApiV1ViewPerformanceTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, buy!: 3, deposit!: 4, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Fx
  alias Portfolixir.Portfolios.Performance
  alias PortfolixirWeb.Api.V1.JSON

  @auth {"authorization", "Bearer test-api-token"}

  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
    |> get(path)
  end

  # User story (#577):
  # As an API client (and the LLM I connect over MCP),
  # I want a view's TTWROR/IRR across all portfolios from one endpoint,
  # so that the performance figures cover exactly the accounts the view
  # valuation covers, without client-side stitching of per-portfolio series.
  #
  # Acceptance criteria:
  # - GET /api/v1/views/:view_id/performance returns the cross-portfolio
  #   performance, financial decimals as strings, with the view echoed.
  # - ?period= and ?series= work like the portfolio performance endpoint.
  # - Unknown and non-integer view ids return 404; a bad period returns 422.
  test "returns the cross-portfolio view performance", %{conn: conn} do
    alpha = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")
    beta = base_world(name: "Beta", cash_name: "Beta Cash", depot_name: "Beta Depot")

    sec_a = create_security!(name: "Fund A", ticker: "FNA", asset_class: "etf")
    sec_b = create_security!(name: "Fund B", ticker: "FNB", asset_class: "etf")

    start = Date.add(Date.utc_today(), -10)
    deposit!(alpha, "1000", start, [])
    buy!(alpha, sec_a, quantity: "10", price: "100", date: start)
    put_quotes!(sec_a, [{start, "100"}, {Date.utc_today(), "120"}])

    deposit!(beta, "1000", start, [])
    buy!(beta, sec_b, quantity: "10", price: "100", date: start)
    put_quotes!(sec_b, [{start, "100"}, {Date.utc_today(), "110"}])

    {:ok, bucket_a} = Buckets.create_bucket(Actor.owner_ui(), %{name: "scope-a"})
    {:ok, bucket_b} = Buckets.create_bucket(Actor.owner_ui(), %{name: "scope-b"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), alpha.depot, [bucket_a.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), alpha.cash, [bucket_a.id])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), beta.depot, [bucket_b.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), beta.cash, [bucket_b.id])

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Both", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket_a.id, bucket_b.id], [])

    data =
      get_json(conn, "/api/v1/views/#{view.id}/performance?series=true")
      |> json_response(200)
      |> Map.fetch!("data")

    # 2000 in, 2300 out: one combined +15%, decimals as strings.
    assert data["view_id"] == view.id
    assert data["period"] == "max"
    assert data["base_currency"] == "EUR"
    # ADR-0039 C4: freshness and computation basis ride every performance
    # payload, the view walk's included (I4 — no serialization drops them).
    assert data["stale"] == false
    assert {:ok, %DateTime{}, _offset} = DateTime.from_iso8601(data["as_of"])
    assert %{"input_series" => _, "window" => _, "gaps" => _} = data["computation_basis"]
    assert data["end_value"] == "2300"
    assert data["net_external_flows"] == "2000"
    assert data["ttwror"] |> Decimal.new() |> Decimal.round(6) |> Decimal.equal?("0.15")
    # #568 (ADR-0034): the money-weighted companions ride the view response.
    assert data["invested_capital"] == "2000"
    assert data["wealth_multiple"] == "1.15"
    assert is_binary(data["mwr"])
    assert is_list(data["series"]) and length(data["series"]) == 11
    assert data["view"] == %{"id" => view.id, "name" => "Both"}

    # Without ?series the series stays out of the payload.
    lean =
      get_json(conn, "/api/v1/views/#{view.id}/performance")
      |> json_response(200)
      |> Map.fetch!("data")

    refute Map.has_key?(lean, "series")

    # The #563 period parameters work here too: a single year chains that
    # calendar year, and a backwards custom range is rejected.
    this_year = Date.utc_today().year

    year_data =
      get_json(conn, "/api/v1/views/#{view.id}/performance?year=#{this_year}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert year_data["period"] == Integer.to_string(this_year)

    assert get_json(conn, "/api/v1/views/#{view.id}/performance?from=2026-05-01&to=2026-01-01")
           |> json_response(422)

    # Unknown and non-integer ids 404; a bad period 422.
    assert get_json(conn, "/api/v1/views/999999/performance") |> json_response(404)
    assert get_json(conn, "/api/v1/views/abc/performance") |> json_response(404)

    assert get_json(conn, "/api/v1/views/#{view.id}/performance?period=2w")
           |> json_response(422)

    # The view form's basis is the engine's, with no scope sentence of the
    # view-less read (#1056): the view JSON is unchanged.
    refute data["computation_basis"]["input_series"] =~ "Scope:"
  end

  # Two portfolios, the first in USD: 1250 USD in, 10 units of a USD fund
  # at 100 USD, now 120 USD; then a EUR portfolio, 1000 EUR in, 10 units at
  # 100 EUR, now 110 EUR. EUR/USD stands at 1.25 throughout, so the end value
  # in EUR is 1200 / 1.25 + 250 / 1.25 + 1100 = 2260.
  defp two_currency_seed do
    start = Date.add(Date.utc_today(), -10)

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: Date.add(start, -1),
          rate: "1.25",
          source: "manual"
        }
      ])

    dollar =
      base_world(
        name: "Dollar",
        currency: "USD",
        cash_name: "Dollar Cash",
        depot_name: "Dollar Depot"
      )

    euro = base_world(name: "Euro", cash_name: "Euro Cash", depot_name: "Euro Depot")

    us_fund = create_security!(name: "US Fund", ticker: "USF", currency: "USD")
    eu_fund = create_security!(name: "EU Fund", ticker: "EUF", asset_class: "etf")

    deposit!(dollar, "1250", start, currency: "USD")
    buy!(dollar, us_fund, quantity: "10", price: "100", date: start, currency: "USD")
    put_quotes!(us_fund, [{start, "100"}, {Date.utc_today(), "120"}])

    deposit!(euro, "1000", start, [])
    buy!(euro, eu_fund, quantity: "10", price: "100", date: start)
    put_quotes!(eu_fund, [{start, "100"}, {Date.utc_today(), "110"}])

    %{dollar: dollar, euro: euro}
  end

  # User story (#1056; Sprint 19 plan D-7):
  # As the agent asked how everything did, with no view picked,
  # I want the return of every account in one read,
  # so that I answer the operator's Everything scope without creating a
  # catch-all view first or adding up returns that do not add up.
  #
  # Acceptance criteria:
  # - GET /api/v1/performance answers Performance.for_view(nil): every
  #   account of every portfolio, each counted once, with view_id null and
  #   no view echo.
  # - It answers in EUR, the hub, even when the first portfolio's base
  #   currency is not EUR.
  # - computation_basis.input_series names the scope and the currency, and
  #   says the screen's Everything scope is computed in the first
  #   portfolio's base currency.
  # - ?period=, ?year=, ?from=/?to= and ?series= behave as on the view read;
  #   a bad period is a 422 on period.
  test "answers the performance of every account without a view", %{conn: conn} do
    two_currency_seed()

    assert Buckets.list_views() == []

    data =
      get_json(conn, "/api/v1/performance?period=ytd")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["view_id"] == nil
    refute Map.has_key?(data, "view")
    refute Map.has_key?(data, "portfolio_id")
    assert data["base_currency"] == "EUR"
    assert data["period"] == "ytd"
    assert data["end_value"] == "2260"
    refute Map.has_key?(data, "series")

    # The engine's Everything walk, figure for figure.
    {:ok, expected} = Performance.for_view(nil, period: "ytd")

    for key <-
          ~w(start_value end_value net_external_flows ttwror irr invested_capital wealth_multiple mwr) do
      assert data[key] == JSON.decimal(Map.fetch!(expected, String.to_existing_atom(key))), key
    end

    basis = data["computation_basis"]["input_series"]
    assert basis =~ "Scope: every account in every portfolio, each counted once, with no view"
    assert basis =~ "in EUR, converted through the EUR hub"
    assert basis =~ "computed in the first portfolio's base currency"

    series =
      get_json(conn, "/api/v1/performance?series=true")
      |> json_response(200)
      |> Map.fetch!("data")

    assert is_list(series["series"])
    assert series["period"] == "max"

    for query <- ["period=nope", "from=2026-05-01&to=2026-01-01", "year=abc"] do
      assert get_json(conn, "/api/v1/performance?#{query}") |> json_response(422) ==
               %{"errors" => %{"period" => ["is invalid"]}},
             query
    end
  end

  test "an include-all view with no exclusion reads the view-less performance", %{conn: conn} do
    two_currency_seed()

    {:ok, everything} = Buckets.create_view(Actor.owner_ui(), %{name: "Everything"})

    total =
      get_json(conn, "/api/v1/performance?period=ytd")
      |> json_response(200)
      |> Map.fetch!("data")

    view =
      get_json(conn, "/api/v1/views/#{everything.id}/performance?period=ytd")
      |> json_response(200)
      |> Map.fetch!("data")

    for key <- ~w(period base_currency start_date end_date start_value end_value
                  net_external_flows ttwror irr invested_capital wealth_multiple mwr
                  suspect_dates unvalued_cash_accounts) do
      assert total[key] == view[key], key
    end

    # The scope sentence is the view-less read's alone: the view form's
    # basis is unchanged, and the view-less one adds to it.
    view_basis = view["computation_basis"]["input_series"]
    refute view_basis =~ "Scope:"
    assert String.starts_with?(total["computation_basis"]["input_series"], view_basis)

    assert Map.delete(total["computation_basis"], "input_series") ==
             Map.delete(view["computation_basis"], "input_series")
  end

  # Acceptance criteria (#1056, review round): the view-less read takes no
  # scope. A view= or a portfolio_id= is ignored, as on GET
  # /api/v1/valuation: the answer is every account's, with view_id null and
  # no view echo. The view form and the portfolio form are the routes that
  # take a scope.
  test "the view-less performance ignores view= and portfolio_id=", %{conn: conn} do
    %{euro: euro} = two_currency_seed()
    {:ok, narrow} = Buckets.create_view(Actor.owner_ui(), %{name: "Narrow", include_all: false})

    plain =
      get_json(conn, "/api/v1/performance?period=ytd")
      |> json_response(200)
      |> Map.fetch!("data")

    scoped =
      get_json(
        conn,
        "/api/v1/performance?period=ytd&view=#{narrow.id}&portfolio_id=#{euro.portfolio.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert scoped["view_id"] == nil
    refute Map.has_key?(scoped, "view")
    assert scoped["end_value"] == "2260"
    assert Map.drop(scoped, ["as_of"]) == Map.drop(plain, ["as_of"])

    assert get_json(conn, "/api/v1/performance?view=abc") |> json_response(200)
  end

  # Acceptance criteria (#1056, #1091, review round): the four view-less reads
  # answer 200 on an instance with no portfolio, and on one whose portfolio
  # has no booking, and still state their scope: the performance family in
  # computation_basis.input_series, the category result in basis_note.
  test "the four view-less reads answer on an empty instance", %{conn: conn} do
    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    assert_empty_reads = fn label ->
      for path <- [
            "/api/v1/performance",
            "/api/v1/performance/benchmark?benchmark=rate:0",
            "/api/v1/performance/contribution"
          ] do
        data = get_json(conn, path) |> json_response(200) |> Map.fetch!("data")

        assert data["view_id"] == nil, "#{label} #{path}"
        assert data["base_currency"] == "EUR", "#{label} #{path}"

        assert data["computation_basis"]["input_series"] =~
                 "Scope: every account in every portfolio, each counted once, with no view",
               "#{label} #{path}"
      end

      categories =
        get_json(conn, "/api/v1/category-results?classification_id=#{classification.id}")
        |> json_response(200)
        |> Map.fetch!("data")

      assert categories["scope"] == "all", label
      assert categories["categories"] == [], label
      assert categories["excluded_members"] == [], label
      assert categories["basis_note"] =~ "Scope: the positions of every portfolio", label
    end

    assert_empty_reads.("no portfolio")

    performance =
      get_json(conn, "/api/v1/performance") |> json_response(200) |> Map.fetch!("data")

    assert performance["start_date"] == nil
    assert performance["ttwror"] == "0"

    base_world(name: "Idle", cash_name: "Idle Cash", depot_name: "Idle Depot")

    assert_empty_reads.("no booking")

    contribution =
      get_json(conn, "/api/v1/performance/contribution")
      |> json_response(200)
      |> Map.fetch!("data")

    assert contribution["start_date"] == nil
    assert contribution["positions"] == []
    assert contribution["totals"] == %{"result" => "0", "positions" => "0", "remainder" => "0"}
  end
end
