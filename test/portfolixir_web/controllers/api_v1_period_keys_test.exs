defmodule PortfolixirWeb.ApiV1PeriodKeysTest do
  # Sprint 32 T1 (I59; ADR-0062's amendment of 2026-11-25, point 6): every
  # route that reads `PortfolixirWeb.Api.V1.PeriodParam` takes the period
  # vocabulary (`Portfolixir.Periods`) as `period=`, `from`/`to` keeping
  # their precedence. The eight controllers and their twelve routes:
  #
  #   PerformanceController       GET /portfolios/:portfolio_id/performance
  #   BenchmarkController         GET /portfolios/:portfolio_id/performance/benchmark
  #   ContributionController      GET /portfolios/:portfolio_id/performance/contribution
  #   BandsController             GET /portfolios/:portfolio_id/performance/bands
  #   ViewPerformanceController   GET /views/:view_id/performance, GET /performance
  #   ViewBenchmarkController     GET /views/:view_id/performance/benchmark,
  #                               GET /performance/benchmark
  #   ViewContributionController  GET /views/:view_id/performance/contribution,
  #                               GET /performance/contribution
  #   ViewBandsController         GET /views/:view_id/performance/bands,
  #                               GET /performance/bands
  #
  # Invented figures only, in EUR.
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Periods

  defp get_json(conn, path, status) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(status)
  end

  # Two years of a fund, priced at every month's end, so every key's span
  # holds walked days.
  defp world do
    today = Clock.today()
    first = Date.new!(today.year - 2, 1, 2)
    world = base_world(name: "Periods", cash_name: "Cash", depot_name: "Depot")
    fund = create_security!(name: "Period Fund", ticker: "PRF")

    deposit!(world, "10000", first)
    buy!(world, fund, quantity: "20", price: "100", date: first)

    closes =
      first
      |> Stream.iterate(&(&1 |> Date.shift(month: 1) |> Date.end_of_month()))
      |> Enum.take_while(&(Date.compare(&1, today) != :gt))
      |> Enum.with_index()
      |> Enum.map(fn {date, n} -> {date, Integer.to_string(100 + rem(n * 7, 23))} end)

    put_quotes!(fund, closes ++ [{today, "111"}])

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Period bucket"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), world.cash, [bucket.id])
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Periods", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    Map.put(world, :view, view)
  end

  # The twelve routes, each with what it needs besides a period.
  defp routes(w) do
    p = "/api/v1/portfolios/#{w.portfolio.id}/performance"
    v = "/api/v1/views/#{w.view.id}/performance"

    [
      {p, ""},
      {p <> "/benchmark", "benchmark=rate:0.02"},
      {p <> "/contribution", ""},
      {p <> "/bands", ""},
      {v, ""},
      {"/api/v1/performance", ""},
      {v <> "/benchmark", "benchmark=rate:0.02"},
      {"/api/v1/performance/benchmark", "benchmark=rate:0.02"},
      {v <> "/contribution", ""},
      {"/api/v1/performance/contribution", ""},
      {v <> "/bands", ""},
      {"/api/v1/performance/bands", ""}
    ]
  end

  defp path(route, extra, query) do
    case Enum.reject([extra, query], &(&1 == "")) do
      [] -> route
      parts -> route <> "?" <> Enum.join(parts, "&")
    end
  end

  # The parameters a client sent before the vocabulary for the same span.
  defp spelled_out({:range, from, to}), do: "from=#{from}&to=#{to}"
  defp spelled_out({:year, year}), do: "year=#{year}"
  defp spelled_out(key) when is_binary(key), do: "period=#{key}"

  # When an answer was computed is not what it answers.
  defp without_times(map) when is_map(map) do
    map
    |> Map.drop(~w(as_of computed_at stale))
    |> Map.new(fn {key, value} -> {key, without_times(value)} end)
  end

  defp without_times(list) when is_list(list), do: Enum.map(list, &without_times/1)
  defp without_times(other), do: other

  # User story:
  # As my agent and I, asking any read of the performance family,
  # I want every period key of the vocabulary taken as `period=`,
  # so that "Vorquartal" or "lfd. Monat" is one call on every route, as on
  # the dashboard.
  #
  # Acceptance criteria:
  # - On each of the twelve routes, `period=<key>` answers exactly what the
  #   span spelled out answers (`from`/`to`, or `year=`), for a rolling key
  #   new to the routes (6m, 1m), the calendar keys (mtd, prev_month, qtd,
  #   prev_quarter, the current quarter, prev_year) and year:YYYY.
  # - `from`/`to` keep their precedence over `period=`.
  # - A key that has not begun (next year, a quarter to come) and one that
  #   is no key answer 422 on `period`, as an unknown period did.
  test "every route takes every key, from/to first, a key not begun refused", %{conn: conn} do
    w = world()
    today = Clock.today()
    current_quarter = "q#{div(today.month - 1, 3) + 1}"

    keys =
      ~w(6m 1m mtd prev_month qtd prev_quarter prev_year) ++
        [current_quarter, "year:#{today.year - 1}"]

    for {route, extra} <- routes(w), key <- keys do
      {:ok, term} = Periods.resolve(key, today)

      by_key = get_json(conn, path(route, extra, "period=#{key}"), 200)["data"]
      spelled = get_json(conn, path(route, extra, spelled_out(term)), 200)["data"]

      assert without_times(by_key) == without_times(spelled), "#{route} period=#{key}"
    end

    {:ok, {:range, from, to}} = Periods.resolve("prev_month", today)

    for {route, extra} <- routes(w) do
      both = get_json(conn, path(route, extra, "period=6m&from=#{from}&to=#{to}"), 200)["data"]
      range = get_json(conn, path(route, extra, "from=#{from}&to=#{to}"), 200)["data"]
      assert without_times(both) == without_times(range), "#{route}: from/to first"

      for refused <- ["year:#{today.year + 1}", "q5", "quarter", "prev_week"] do
        assert get_json(conn, path(route, extra, "period=#{refused}"), 422) ==
                 %{"errors" => %{"period" => ["is invalid"]}},
               "#{route} period=#{refused}"
      end
    end
  end
end
