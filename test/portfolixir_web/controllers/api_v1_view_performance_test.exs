defmodule PortfolixirWeb.ApiV1ViewPerformanceTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, buy!: 3, deposit!: 4, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets

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
    assert data["end_value"] == "2300"
    assert data["net_external_flows"] == "2000"
    assert data["ttwror"] |> Decimal.new() |> Decimal.round(6) |> Decimal.equal?("0.15")
    assert is_list(data["series"]) and length(data["series"]) == 11
    assert data["view"] == %{"id" => view.id, "name" => "Both"}

    # Without ?series the series stays out of the payload.
    lean =
      get_json(conn, "/api/v1/views/#{view.id}/performance")
      |> json_response(200)
      |> Map.fetch!("data")

    refute Map.has_key?(lean, "series")

    # Unknown and non-integer ids 404; a bad period 422.
    assert get_json(conn, "/api/v1/views/999999/performance") |> json_response(404)
    assert get_json(conn, "/api/v1/views/abc/performance") |> json_response(404)

    assert get_json(conn, "/api/v1/views/#{view.id}/performance?period=2w")
           |> json_response(422)
  end
end
