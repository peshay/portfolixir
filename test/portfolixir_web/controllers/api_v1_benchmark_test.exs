defmodule PortfolixirWeb.ApiV1BenchmarkTest do
  # Sprint 11 Lane B step 3 (ADR-0046 §4): the benchmark comparison as a read
  # under /api/v1 on both performance scopes, agent first.
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog

  @auth {"authorization", "Bearer test-api-token"}

  # Every request starts from a recycled conn: a test issues several reads.
  defp api_conn(conn) do
    conn
    |> recycle()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", elem(@auth, 1))
  end

  defp benchmark_security!(opts) do
    security = create_security!(opts)
    {:ok, flagged} = Catalog.update_security(Actor.owner_ui(), security, %{is_benchmark: true})
    flagged
  end

  # A small world whose figures are exact: 1000 deposited and invested on the
  # first day, 500 more cash later, the holding quoted at 100 → 120.
  defp seeded_world(name) do
    world = base_world(name: name, cash_name: "#{name} Cash", depot_name: "#{name} Depot")
    security = create_security!(name: "World ETF", ticker: "WLD")
    today = Date.utc_today()

    put_quotes!(security, [{Date.add(today, -20), "100"}, {Date.add(today, -1), "120"}])
    deposit!(world, "1000", Date.add(today, -20))
    buy!(world, security, quantity: "10", price: "100", date: Date.add(today, -20))
    deposit!(world, "500", Date.add(today, -10))

    Map.merge(world, %{security: security, today: today})
  end

  # User story (#572, ADR-0046 §4):
  # As an API client (and the LLM I connect over MCP),
  # I want the portfolio's benchmark comparison from one read — both
  # comparisons, every financial value a string, the basis in the payload —
  # so that "was the effort worth it" is answerable by an agent without a
  # screen.
  #
  # Acceptance criteria:
  # - GET /portfolios/:id/performance/benchmark?benchmark=rate:<decimal>
  #   returns the bought-once and savings-plan figures as Decimal strings,
  #   the covered window, the excluded flows and computation_basis naming
  #   the frictionless assumption; the series only when requested.
  # - benchmark=security:<id> works for a flagged security only.
  test "returns both comparisons for a fixed rate, series on request", %{conn: conn} do
    world = seeded_world("R")

    conn =
      get(api_conn(conn), "/api/v1/portfolios/#{world.portfolio.id}/performance/benchmark", %{
        "benchmark" => "rate:0"
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["portfolio_id"] == world.portfolio.id
    assert data["period"] == "max"
    assert data["base_currency"] == "EUR"
    assert data["benchmark"] == %{"kind" => "rate", "annual_rate" => "0"}

    assert data["window"] == %{
             "start_date" => Date.to_iso8601(Date.add(world.today, -20)),
             "end_date" => Date.to_iso8601(world.today)
           }

    assert data["requested_window"] == data["window"]
    assert data["excluded_flows"] == []
    # Identity 1 on the wire: the 0 % plan ends at the net invested capital.
    assert data["savings_plan"]["invested_capital"] == "1500"
    assert data["savings_plan"]["benchmark_end_value"] == "1500"
    assert data["savings_plan"]["portfolio_end_value"] == "1700"
    assert data["savings_plan"]["end_value_delta"] == "200"
    assert is_binary(data["savings_plan"]["portfolio_irr"])
    assert is_binary(data["savings_plan"]["benchmark_irr"])
    assert is_binary(data["savings_plan"]["benchmark_units"])
    assert data["bought_once"]["benchmark_return"] == "0"
    assert is_binary(data["bought_once"]["portfolio_ttwror"])
    refute Map.has_key?(data["bought_once"], "series")
    assert is_binary(data["as_of"])
    assert data["stale"] == false
    assert data["computation_basis"]["frictionless"] == true
    assert data["computation_basis"]["assumptions"] =~ "frictionless"
    assert data["computation_basis"]["window"] == data["window"]
    assert data["computation_basis"]["reference"] =~ "0"

    conn =
      get(api_conn(conn), "/api/v1/portfolios/#{world.portfolio.id}/performance/benchmark", %{
        "benchmark" => "rate:0",
        "series" => "true",
        "period" => "ytd"
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["period"] == "ytd"
    assert [%{"date" => _, "cumulative_return" => "0"} | _] = data["bought_once"]["series"]
  end

  test "compares against a flagged security and names the flows before its first quote", %{
    conn: conn
  } do
    world = seeded_world("S")
    bench = benchmark_security!(name: "Late Bench", ticker: "LATE")
    put_quotes!(bench, [{Date.add(world.today, -15), "50"}, {Date.add(world.today, -1), "55"}])

    conn =
      get(api_conn(conn), "/api/v1/portfolios/#{world.portfolio.id}/performance/benchmark", %{
        "benchmark" => "security:#{bench.id}"
      })

    assert %{"data" => data} = json_response(conn, 200)

    assert data["benchmark"] == %{
             "kind" => "security",
             "security_id" => bench.id,
             "name" => "Late Bench",
             "currency_code" => "EUR"
           }

    assert data["window"]["start_date"] == Date.to_iso8601(Date.add(world.today, -14))
    assert data["requested_window"]["start_date"] == Date.to_iso8601(Date.add(world.today, -20))

    assert [%{"date" => date, "flow" => "1000"}] = data["excluded_flows"]
    assert date == Date.to_iso8601(Date.add(world.today, -20))
    # V(-15) = 1000 at 50 → 20 units, plus 500 at 50 → 30 units; 30 × 55 = 1650
    # against the real 10 × 120 + 500 = 1700.
    assert data["savings_plan"]["benchmark_units"] == "30"
    assert data["savings_plan"]["benchmark_end_value"] == "1650"
    assert data["savings_plan"]["end_value_delta"] == "50"
    assert data["bought_once"]["benchmark_return"] == "0.1"
    assert data["computation_basis"]["reference"] =~ "Late Bench"
  end

  test "refuses a security that is not flagged, an unknown one, and a malformed benchmark", %{
    conn: conn
  } do
    world = seeded_world("X")
    unflagged = create_security!(name: "Plain", ticker: "PLN")

    for value <- ["security:#{unflagged.id}", "security:999999"] do
      conn =
        get(api_conn(conn), "/api/v1/portfolios/#{world.portfolio.id}/performance/benchmark", %{
          "benchmark" => value
        })

      assert %{"errors" => %{"benchmark" => ["is not a benchmark security"]}} =
               json_response(conn, 422)
    end

    for value <- [
          "foo",
          "rate:abc",
          "rate:-1",
          "rate:",
          "security:abc",
          "security:",
          "rate:NaN",
          "rate:Infinity"
        ] do
      conn =
        get(api_conn(conn), "/api/v1/portfolios/#{world.portfolio.id}/performance/benchmark", %{
          "benchmark" => value
        })

      assert %{"errors" => %{"benchmark" => ["is invalid"]}} = json_response(conn, 422), value
    end

    conn = get(api_conn(conn), "/api/v1/portfolios/#{world.portfolio.id}/performance/benchmark")
    assert %{"errors" => %{"benchmark" => ["can't be blank"]}} = json_response(conn, 422)

    conn =
      get(api_conn(conn), "/api/v1/portfolios/#{world.portfolio.id}/performance/benchmark", %{
        "benchmark" => "rate:0",
        "period" => "bogus"
      })

    assert %{"errors" => %{"period" => ["is invalid"]}} = json_response(conn, 422)

    conn =
      get(api_conn(conn), "/api/v1/portfolios/999999/performance/benchmark", %{
        "benchmark" => "rate:0"
      })

    assert json_response(conn, 404)

    # A bare conn (recycle/1 would keep the authorization header).
    conn =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> get("/api/v1/portfolios/#{world.portfolio.id}/performance/benchmark", %{
        "benchmark" => "rate:0"
      })

    assert json_response(conn, 401)
  end

  test "scopes the portfolio comparison to a view and echoes it", %{conn: conn} do
    world = seeded_world("V")
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Scoped"})

    conn =
      get(api_conn(conn), "/api/v1/portfolios/#{world.portfolio.id}/performance/benchmark", %{
        "benchmark" => "rate:0",
        "view" => Integer.to_string(view.id)
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["view"]["id"] == view.id

    conn =
      get(api_conn(conn), "/api/v1/portfolios/#{world.portfolio.id}/performance/benchmark", %{
        "benchmark" => "rate:0",
        "view" => "999999"
      })

    assert json_response(conn, 404)
  end

  # User story (#572, ADR-0046 §3):
  # As an API client asking a strategy view's "was it worth it",
  # I want the same comparison on the cross-portfolio view scope,
  # so that the view's total, its return and its benchmark speak about the
  # same accounts.
  test "returns the view comparison across all portfolios", %{conn: conn} do
    world = seeded_world("W")
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Everything-like"})

    conn =
      get(api_conn(conn), "/api/v1/views/#{view.id}/performance/benchmark", %{
        "benchmark" => "rate:0"
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["view_id"] == view.id
    refute Map.has_key?(data, "portfolio_id")
    assert data["base_currency"] == "EUR"
    assert data["benchmark"] == %{"kind" => "rate", "annual_rate" => "0"}
    assert data["view"]["id"] == view.id

    assert is_binary(data["savings_plan"]["benchmark_end_value"]) or
             is_nil(data["savings_plan"]["benchmark_end_value"])

    assert data["computation_basis"]["frictionless"] == true
    _ = world

    conn =
      get(api_conn(conn), "/api/v1/views/999999/performance/benchmark", %{"benchmark" => "rate:0"})

    assert json_response(conn, 404)

    conn =
      get(api_conn(conn), "/api/v1/views/#{view.id}/performance/benchmark", %{
        "benchmark" => "rate:0",
        "period" => "bogus"
      })

    assert %{"errors" => %{"period" => ["is invalid"]}} = json_response(conn, 422)

    conn = get(api_conn(conn), "/api/v1/views/#{view.id}/performance/benchmark")
    assert %{"errors" => %{"benchmark" => ["can't be blank"]}} = json_response(conn, 422)
  end
end
