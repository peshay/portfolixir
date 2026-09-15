defmodule PortfolixirWeb.PortfolioBenchmarkLiveTest do
  # Sprint 11 Lane B step 4 (ADR-0046 §4): the benchmark comparison on the
  # Wealth page — an overlay of at most two benchmarks on the performance
  # chart and a comparison block next to TTWROR/IRR, the selection explicit
  # per request and remembered by the page.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.WorldFixtures
  alias PortfolixirWeb.BenchmarkScope

  defp seed_world do
    Classifications.ensure_builtins()

    world =
      WorldFixtures.base_world(name: "Mein Depot", cash_name: "Giro", depot_name: "Depot")

    held = WorldFixtures.create_security!(name: "World ETF", ticker: "WLD")
    today = Date.utc_today()
    start = Date.add(today, -20)

    WorldFixtures.put_quotes!(held, [{start, "100"}, {Date.add(today, -1), "120"}])
    WorldFixtures.deposit!(world, "1000", start)
    WorldFixtures.buy!(world, held, quantity: "10", price: "100", date: start)
    WorldFixtures.deposit!(world, "500", Date.add(today, -10))

    bench = WorldFixtures.create_security!(name: "Bench ETF", ticker: "BNCH")
    {:ok, bench} = Catalog.update_security(Actor.owner_ui(), bench, %{is_benchmark: true})
    WorldFixtures.put_quotes!(bench, [{start, "50"}, {Date.add(today, -1), "55"}])

    Map.merge(world, %{held: held, bench: bench, today: today, start: start})
  end

  # User story (#572, ADR-0046 §4):
  # As a local portfolio maintainer asking whether the effort was worth it,
  # I want to pick up to two benchmarks on the Wealth page and see them as an
  # overlay on the performance chart and as a comparison block next to
  # TTWROR/IRR, remembered on my next visit,
  # so that the answer is on the screen and not only over the API.
  #
  # Acceptance criteria:
  # - ?benchmark[]=security:<id> and ?benchmark_rate=<percent> select a
  #   flagged security and a fixed rate; the chart carries one overlay per
  #   benchmark with a legend, the comparison block one row per benchmark
  #   with the savings-plan delta, the bought-once pair and the IRR pair, and
  #   its ⓘ carries the one-line explanation.
  # - The selection is remembered without re-specifying it, and a period
  #   switch re-chains the comparison instantly.
  test "picks two benchmarks, overlays them and remembers the choice", %{conn: conn} do
    world = seed_world()

    conn = get(conn, "/portfolio?benchmark[]=security:#{world.bench.id}&benchmark_rate=2")

    {:ok, view, _html} =
      live(conn, "/portfolio?benchmark[]=security:#{world.bench.id}&benchmark_rate=2")

    html = render_async(view)

    # The comparison block: one row per benchmark, the delta as the figure.
    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-row']", "Bench ETF")
    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-row']", "2.00 % p.a.")
    # The bench plan: 1000 at 50 + 500 at 50 = 30 units, 30 x 55 = 1650 against
    # the real 10 x 120 + 500 = 1700: +50.00 EUR.
    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-delta']", "+50.00")
    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-bought-once']")
    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-irr']")
    # The figure is named (design critic): the card says what it compares
    # and the money figure says which comparison it is.
    assert has_element?(view, "#kpi-benchmark", "Benchmark comparison")
    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-delta']", "savings plan")
    # A twenty-day history is a short window: the period MWR pair, labelled
    # like the sibling card (ADR-0034 §2), never an annualized IRR beside it.
    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-irr']", "MWR")
    refute has_element?(view, "#kpi-benchmark [data-role='benchmark-irr']", "IRR")
    # The chart's data is reachable as a table (UX-DR10): one column per
    # overlay, and the accessible name of the chart names the benchmarks.
    assert has_element?(view, "[data-role='perf-summary-table'] th", "Bench ETF")
    assert has_element?(view, "[data-role='perf-summary-table'] th", "2.00 % p.a.")
    assert has_element?(view, "#performance-figure svg[aria-label*='Bench ETF']")
    assert has_element?(view, "#tip-benchmark", "Savings plan")

    # The overlays and their legend on the TTWROR chart.
    assert html =~ ~s(class="chart-benchmark-1")
    assert html =~ ~s(class="chart-benchmark-2")
    assert has_element?(view, "[data-role='benchmark-legend']", "Bench ETF")
    assert has_element?(view, "[data-role='benchmark-legend']", "2.00 % p.a.")
    # The picker shows what is active.
    assert has_element?(
             view,
             "[data-role='benchmark-picker'] [data-role='benchmark-active']",
             "Bench ETF"
           )

    # One chip per active benchmark, carrying the legend swatch, so picker,
    # legend and card share one identity per benchmark.
    assert length(Regex.scan(~r/data-role="benchmark-chip"/, html)) == 2
    refute has_element?(view, "[data-role='benchmark-value-hint']")

    # A period switch re-chains the comparison with the period label.
    render_click(view, "select_period", %{"period" => "ytd"})
    assert has_element?(view, "#kpi-benchmark", "YTD")
    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-row']", "Bench ETF")

    # Remembered on the next visit without the parameters.
    {:ok, again, _html} = live(conn, "/portfolio")
    render_async(again)
    assert has_element?(again, "#kpi-benchmark [data-role='benchmark-row']", "Bench ETF")
  end

  test "the value chart carries no overlay; an explicit empty choice clears the selection", %{
    conn: conn
  } do
    world = seed_world()

    conn = get(conn, "/portfolio?benchmark[]=security:#{world.bench.id}")
    {:ok, view, _html} = live(conn, "/portfolio?benchmark[]=security:#{world.bench.id}")
    render_async(view)
    assert has_element?(view, "#kpi-benchmark")

    html = render_click(view, "set_chart_mode", %{"mode" => "value"})
    refute html =~ ~s(class="chart-benchmark-1")
    refute has_element?(view, "[data-role='benchmark-legend']")
    refute has_element?(view, "[data-role='perf-summary-table'] th", "Bench ETF")
    # The deliberate limit is stated where the overlay is missing (UX-DR26).
    assert has_element?(view, "[data-role='benchmark-value-hint']", "TTWROR")

    conn = get(conn, "/portfolio?benchmark[]=")
    {:ok, cleared, _html} = live(conn, "/portfolio?benchmark[]=")
    render_async(cleared)
    refute has_element?(cleared, "#kpi-benchmark")
    refute has_element?(cleared, "[data-role='benchmark-active']")
  end

  test "keeps at most two benchmarks and drops what is not a benchmark", %{conn: conn} do
    world = seed_world()
    other = WorldFixtures.create_security!(name: "Other Bench", ticker: "OTH")
    {:ok, other} = Catalog.update_security(Actor.owner_ui(), other, %{is_benchmark: true})
    WorldFixtures.put_quotes!(other, [{world.start, "10"}])

    query =
      "benchmark[]=security:#{world.bench.id}&benchmark[]=security:#{other.id}&benchmark_rate=2"

    conn = get(conn, "/portfolio?#{query}")
    {:ok, view, _html} = live(conn, "/portfolio?#{query}")
    render_async(view)

    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-row']", "Bench ETF")
    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-row']", "Other Bench")
    refute has_element?(view, "#kpi-benchmark [data-role='benchmark-row']", "% p.a.")

    unflagged = "benchmark[]=security:#{world.held.id}&benchmark[]=bogus&benchmark_rate=abc"
    conn = get(conn, "/portfolio?#{unflagged}")
    {:ok, none, _html} = live(conn, "/portfolio?#{unflagged}")
    render_async(none)
    refute has_element?(none, "#kpi-benchmark")
  end

  test "the comparison block and the picker read in German", %{conn: conn} do
    world = seed_world()

    conn = get(conn, "/portfolio?locale=de&benchmark[]=security:#{world.bench.id}")
    {:ok, view, _html} = live(conn, "/portfolio?locale=de&benchmark[]=security:#{world.bench.id}")
    render_async(view)

    assert has_element?(view, "#kpi-benchmark", "Benchmark-Vergleich")
    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-delta']", "Sparplan")

    assert has_element?(
             view,
             "#kpi-benchmark [data-role='benchmark-bought-once']",
             "Einmalanlage"
           )

    assert has_element?(view, "#tip-benchmark", "Sparplan")
    assert has_element?(view, "[data-role='benchmark-picker']", "Fester Zins")
  end

  # Closing-act finding (correctness hunter): a benchmark without a quote
  # covers no window, and the row said "from  — 1 earlier flow left out" with
  # a blank date. Nothing is covered, and the row says so.
  test "a benchmark without a quote shows the uncovered note, never a blank date", %{conn: conn} do
    world = seed_world()
    silent = WorldFixtures.create_security!(name: "Silent Bench", ticker: "SLNT")
    {:ok, silent} = Catalog.update_security(Actor.owner_ui(), silent, %{is_benchmark: true})

    conn = get(conn, "/portfolio?benchmark[]=security:#{silent.id}")
    {:ok, view, _html} = live(conn, "/portfolio?benchmark[]=security:#{silent.id}")
    render_async(view)

    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-delta']", "—")

    assert has_element?(
             view,
             "#kpi-benchmark [data-role='benchmark-coverage']",
             "no covered window — 2 flows before the benchmark's first priced day"
           )

    refute has_element?(view, "#kpi-benchmark [data-role='benchmark-coverage']", "from ")
    _ = world
  end

  describe "BenchmarkScope plug" do
    defp run_plug(conn) do
      conn
      |> Plug.Test.init_test_session(%{})
      |> BenchmarkScope.call(BenchmarkScope.init([]))
    end

    defp with_query(query) do
      :get
      |> Phoenix.ConnTest.build_conn("/?" <> query)
      |> Map.put(:query_string, query)
    end

    test "stores up to two valid selectors in the session and the cookie, the rate as a fraction" do
      conn =
        "benchmark[]=security:7&benchmark[]=bogus&benchmark[]=security:9&benchmark_rate=2.5"
        |> with_query()
        |> run_plug()

      assert get_session(conn, BenchmarkScope.session_key()) == ["security:7", "security:9"]
      assert %{value: "security:7,security:9"} = conn.resp_cookies[BenchmarkScope.cookie_name()]

      conn = "benchmark[]=security:7&benchmark_rate=2.5" |> with_query() |> run_plug()
      assert get_session(conn, BenchmarkScope.session_key()) == ["security:7", "rate:0.025"]
    end

    test "an explicit empty choice clears both; no choice carries the cookie" do
      conn = "benchmark[]=" |> with_query() |> run_plug()
      assert get_session(conn, BenchmarkScope.session_key()) == []
      assert %{max_age: 0} = conn.resp_cookies[BenchmarkScope.cookie_name()]

      conn =
        ""
        |> with_query()
        |> Plug.Test.put_req_cookie(BenchmarkScope.cookie_name(), "rate:0.02,security:3,bogus")
        |> run_plug()

      assert get_session(conn, BenchmarkScope.session_key()) == ["rate:0.02", "security:3"]
    end

    test "a rate outside the engine's bound, a non-numeric rate and an id beyond int8 are dropped" do
      for query <- [
            "benchmark_rate=-100",
            "benchmark_rate=abc",
            "benchmark_rate=NaN",
            "benchmark_rate=-99.99999999999999999999",
            "benchmark_rate=1001",
            "benchmark[]=rate:1e309",
            "benchmark[]=rate:-0.9999999999999999999999",
            "benchmark[]=security:99999999999999999999"
          ] do
        conn = query |> with_query() |> run_plug()
        assert get_session(conn, BenchmarkScope.session_key()) == [], query
      end
    end

    test "one spelling per rate: 2 and 2.0 are the same selector" do
      conn = "benchmark[]=rate:0.020&benchmark_rate=2.0" |> with_query() |> run_plug()
      assert get_session(conn, BenchmarkScope.session_key()) == ["rate:0.02"]
    end
  end
end
