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
  alias PortfolixirWeb.Format

  # The instance on loopback, where the browser labels every request it
  # sends, so a choice made by following the page's own links is remembered
  # (H41).
  setup %{conn: conn}, do: %{conn: %{conn | host: "localhost"}}

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

  # --- Sprint 28 S2 begin ---
  # Polish: Wealth (#1366), the line of 2026-11-08; amendment D-A4, board 07
  # ③: the benchmark sentence read „Ansicht %% (TTWROR)“.
  #
  # User story:
  # As the operator with a benchmark chosen, reading the value chart,
  # I want the sentence that benchmarks are drawn in the TTWROR series only
  # to name that series as the switch does, „% (TTWROR)“,
  # so that the page does not print a stray „%%“.
  #
  # Acceptance criteria:
  # - At the level „Gesamt“ the visible sentence reads "the % (TTWROR)
  #   view", in English and German, and no „%%“.
  # - In the stack it joins the method behind the basis line's ⓘ, with one
  #   „%“, and is not repeated under it.
  test "the benchmark sentence prints one %", %{conn: conn} do
    world = seed_world()
    choice = "benchmark[]=security:#{world.bench.id}"

    conn = get(conn, "/portfolio?" <> choice)
    {:ok, view, _html} = live(conn, "/portfolio?level=total&" <> choice)
    render_async(view)

    hint = view |> element("[data-role='benchmark-value-hint']") |> render()
    assert hint =~ "drawn in the % (TTWROR) view only"
    refute hint =~ "%%"

    german =
      PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
        %{build_conn() | host: "localhost"},
        "portfolixir_locale",
        "de"
      )

    {:ok, view, _html} = live(german, "/portfolio?level=total&" <> choice)
    render_async(view)

    hint = view |> element("[data-role='benchmark-value-hint']") |> render()
    assert hint =~ "Ansicht % (TTWROR)"
    refute hint =~ "%%"

    {:ok, view, _html} = live(conn, "/portfolio?level=category&" <> choice)
    Enum.each(1..4, fn _round -> render_async(view) end)

    tip =
      view
      |> element("[data-role='stack-basis'] [data-role='section-info'] [role='tooltip']")
      |> render()

    assert tip =~ "drawn in the % (TTWROR) view only"
    refute tip =~ "%%"
    assert length(Regex.scan(~r/data-role="benchmark-value-hint"/, render(view))) == 1
  end

  # --- Sprint 28 S2 end ---

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
    # The deliberate limit is stated where the overlay is missing (UX-DR26);
    # in the stack, the value series' default level, behind the ⓘ of its
    # basis line once its bands have landed (#1366, Sprint 28 S2).
    render_async(view)
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

    # #1416 (B2; ADR-0058 F5): what is not a benchmark is a security
    # without a stored quote, as the API answers 422; a held fund with one
    # is a benchmark now and stays chosen (the B2 tests below).
    unquoted = WorldFixtures.create_security!(name: "Unquoted Fund", ticker: "UQF")
    invalid = "benchmark[]=security:#{unquoted.id}&benchmark[]=bogus&benchmark_rate=abc"
    conn = get(conn, "/portfolio?#{invalid}")
    {:ok, none, _html} = live(conn, "/portfolio?#{invalid}")
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

  # User story (#1416, the closing act's flaky picker walk on 651850e):
  # As the operator opening „Benchmark…“ while Holdings still loads,
  # I want the picker to stay open when the loads land,
  # so that it does not fold shut under my click.
  #
  # Acceptance criteria:
  # - The picker carries an id and the shell's `DisclosureState` hook:
  #   LiveView removes every attribute the server did not render, `open`
  #   included, and the hook restores it after each patch.
  # - The hook reads the open state just before each patch, not only from
  #   the `toggle` event, which the browser dispatches later in a task of
  #   its own: a load that lands between the click and that event must not
  #   fold the picker shut. (LiveViewTest does not run the client patch;
  #   the hook's contract is pinned on its source, and the browser walk
  #   `test/browser/benchmark_picker_layout.js` clicks the picker in the
  #   same task as a load's patch and checks it is still open.)
  test "the picker keeps its open state across a patch", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert has_element?(
             view,
             "details#benchmark-picker[data-role='benchmark-picker'][phx-hook='DisclosureState']"
           )

    hook =
      "lib/portfolixir_web/layout_view.ex"
      |> File.read!()
      |> String.split("Hooks.DisclosureState = ")
      |> Enum.at(1, "")
      |> String.split(~r/\n\s*Hooks\.\w+ = /)
      |> hd()

    assert hook =~ ~r/beforeUpdate: function \(\) \{\s*this\.open = this\.el\.open;/s
  end

  # Closing-act finding (correctness hunter): a benchmark without a quote
  # covers no window, and the row said "from  — 1 earlier flow left out" with
  # a blank date. Nothing is covered, and the row says so.
  test "a benchmark quoted only after every flow shows the uncovered note, never a blank date", %{
    conn: conn
  } do
    world = seed_world()
    silent = WorldFixtures.create_security!(name: "Silent Bench", ticker: "SLNT")
    {:ok, silent} = Catalog.update_security(Actor.owner_ui(), silent, %{is_benchmark: true})
    # #1416 (B2): a benchmark with no stored quote at all is refused now, on
    # the screen as by the API; one first quoted today covers no window.
    WorldFixtures.put_quotes!(silent, [{world.today, "10"}])

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
  end

  # User story (#572, UX-DR13 — the basis line):
  # As a local portfolio maintainer comparing against an index whose history
  # starts after my first deposit,
  # I want the card to say from which day the comparison runs and that the
  # earlier flow enters through the opening value, and the overlay to start
  # from my own chain's level on that day,
  # so that a shorter benchmark history never reads as a shorter portfolio.
  #
  # Acceptance criteria:
  # - The row carries "from <date> — 1 earlier flow enters through the
  #   opening value" with the covered window's first day.
  # - The overlay is drawn, with its legend entry and its table column.
  test "a benchmark quoted late shows the covered-window note and an anchored overlay",
       %{conn: conn} do
    world = seed_world()
    late = WorldFixtures.create_security!(name: "Late Bench", ticker: "LATE")
    {:ok, late} = Catalog.update_security(Actor.owner_ui(), late, %{is_benchmark: true})
    first_quote = Date.add(world.today, -15)
    WorldFixtures.put_quotes!(late, [{first_quote, "50"}, {Date.add(world.today, -1), "55"}])

    conn = get(conn, "/portfolio?benchmark[]=security:#{late.id}")
    {:ok, view, _html} = live(conn, "/portfolio?benchmark[]=security:#{late.id}")
    html = render_async(view)

    assert has_element?(
             view,
             "#kpi-benchmark [data-role='benchmark-coverage']",
             "from #{Date.add(first_quote, 1)} — 1 earlier flow enters through the opening value"
           )

    assert html =~ ~s(class="chart-benchmark-1")
    assert has_element?(view, "[data-role='benchmark-legend']", "Late Bench")
    assert has_element?(view, "[data-role='perf-summary-table'] th", "Late Bench")
  end

  # User story (Sprint 19 PR γ U3, the sweep):
  # As a German-speaking operator comparing against an index quoted late,
  # I want the row's covered window to start on a day written DD.MM.YYYY,
  # so that the comparison block reads its date as the chart's basis line
  # does.
  #
  # Acceptance criteria:
  # - The row reads "ab <DD.MM.YYYY> — …" with the covered window's first
  #   day, never ISO.
  test "a benchmark quoted late names its covered window's first day in German",
       %{conn: conn} do
    world = seed_world()
    late = WorldFixtures.create_security!(name: "Late Bench", ticker: "LATE")
    {:ok, late} = Catalog.update_security(Actor.owner_ui(), late, %{is_benchmark: true})
    first_quote = Date.add(world.today, -15)
    WorldFixtures.put_quotes!(late, [{first_quote, "50"}, {Date.add(world.today, -1), "55"}])

    path = "/portfolio?locale=de&benchmark[]=security:#{late.id}"
    conn = get(conn, path)
    {:ok, view, _html} = live(conn, path)
    render_async(view)

    coverage = view |> element("#kpi-benchmark [data-role='benchmark-coverage']") |> render()
    day = PortfolixirWeb.Format.date(Date.add(first_quote, 1), "de")

    assert coverage =~ "ab #{day} —"
    refute coverage =~ Date.to_iso8601(Date.add(first_quote, 1))
  end

  # The seed world plus costs in the window: a buy's fee and tax legs, a
  # standalone fee, a tax and a tax refund, so the two sums are exact and
  # the fee crosses a thousands separator: fees 4.20 + 1250.00 = 1254.20,
  # taxes 1.30 + 10.00 - 2.00 = 9.30. One fee of 3.00 lies outside the
  # page's default period (1y), so a read of another period (`max`: fees
  # 1257.20) differs from the page's.
  defp seed_costs_world do
    world = seed_world()
    WorldFixtures.deposit!(world, "2000", Date.add(world.today, -12))

    WorldFixtures.buy!(world, world.held,
      quantity: "1",
      price: "100",
      fees: "4.20",
      taxes: "1.30",
      date: Date.add(world.today, -8)
    )

    for {type, amount, days_ago} <- [
          {"fee", "3.00", 400},
          {"fee", "1250.00", 5},
          {"tax", "10.00", 4},
          {"tax_refund", "2.00", 3}
        ] do
      {:ok, _cost} =
        Portfolixir.Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          cash_account_id: world.cash.id,
          type: type,
          date: Date.add(world.today, -days_ago),
          gross_amount: amount,
          currency_code: "EUR"
        })
    end

    world
  end

  # The comparison's own payload over the public API: the same read an agent
  # makes for the page's scope (the total), benchmark and period — the
  # page's default, 1y (`PortfolioLive`'s `param_period/1`); the API's own
  # default is `max`.
  defp total_costs_paid(conn, benchmark, period \\ "1y") do
    conn
    |> recycle()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get("/api/v1/performance/benchmark", %{"benchmark" => benchmark, "period" => period})
    |> json_response(200)
    |> get_in(["data", "costs_paid"])
  end

  defp costs_line(view) do
    view
    |> element("#kpi-benchmark > [data-role='benchmark-costs']")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # User story (Sprint 24 B2; ADR-0046, amended 2026-11-04; idea I17;
  # board ux-design-2026-11-04-sprint24/02, variant A):
  # As a local portfolio maintainer reading "was it worth it" on Wealth's
  # Performance tab,
  # I want one line under the benchmark rows saying the fees and taxes my
  # portfolio paid in the same period, and that the benchmark paid none,
  # with the ⓘ saying what was summed and what is not in it,
  # so that I see how large the frictionless benchmark's advantage was
  # without adding up bookings, and never read the rest of the gap as
  # "selection and timing".
  #
  # Acceptance criteria:
  # - Once under the benchmark rows (not once per row), with two
  #   benchmarks: "Paid in the period: fees 1,254.20 EUR · taxes 9.30 EUR;
  #   the benchmark pays none." / „Im Zeitraum gezahlt: Gebühren 1.254,20 EUR
  #   · Steuern 9,30 EUR — die Benchmark zahlt keine.“
  # - The two figures are the comparison payload's costs_paid fees and taxes
  #   (GET /api/v1/performance/benchmark for the same scope, benchmark and
  #   period), formatted by Format.money (D-1, criterion 4).
  # - The ⓘ carries the sentence: what was summed, at which rate, and that
  #   the forgone return of the money paid is not in it.
  # - Hidden while the comparison computes.
  # - Nothing on the page reads "selection and timing" / „Auswahl und
  #   Timing“ (the amendment's point 4).
  test "the costs line states the payload's fees and taxes once under the rows", %{conn: conn} do
    world = seed_costs_world()

    # The payload of the page's scope, for each of its benchmarks: the same
    # exact Decimal strings, so the screen states it once.
    for benchmark <- ["rate:0.02", "security:#{world.bench.id}"] do
      assert %{"fees" => "1254.2", "taxes" => "9.3"} = total_costs_paid(conn, benchmark)
    end

    # The fee before the period counts only in a read of another period.
    assert %{"fees" => "1257.2"} = total_costs_paid(conn, "rate:0.02", "max")

    costs = total_costs_paid(conn, "rate:0.02")

    for locale <- ["en", "de"] do
      path =
        "/portfolio?locale=#{locale}&benchmark[]=security:#{world.bench.id}&benchmark_rate=2"

      page_conn = get(recycle(conn), path)

      # While the comparison computes (the dead render starts no walk), the
      # block waits on its skeleton and says nothing about costs.
      pending = html_response(page_conn, 200)
      assert pending =~ ~s(data-waits="performance")
      refute pending =~ ~s(data-role="benchmark-costs")

      {:ok, view, _html} = live(page_conn, path)
      html = render_async(view)

      fees = Format.money(Decimal.new(costs["fees"]), locale)
      taxes = Format.money(Decimal.new(costs["taxes"]), locale)

      {expected, info} =
        case locale do
          "en" ->
            {"Paid in the period: fees\u00a0#{fees} EUR · taxes\u00a0#{taxes} EUR; the benchmark pays none.",
             "Paid in the period: the fees and taxes booked in the same period across all portfolios, converted at their booking day's rate; refunds reduce the taxes. Not included is the return the money paid would otherwise have earned."}

          "de" ->
            {"Im Zeitraum gezahlt: Gebühren\u00a0#{fees} EUR · Steuern\u00a0#{taxes} EUR — die Benchmark zahlt keine.",
             "Gezahlt im Zeitraum: die Gebühren und Steuern, die im selben Zeitraum über alle Portfolios gebucht wurden, umgerechnet zum Kurs ihres Buchungstags; Erstattungen mindern die Steuern. Nicht enthalten ist der Ertrag, den das gezahlte Geld sonst erwirtschaftet hätte."}
        end

      # Once, under the two rows, inside neither.
      assert length(Regex.scan(~r/data-role="benchmark-row"/, html)) == 2
      assert length(Regex.scan(~r/data-role="benchmark-costs"/, html)) == 1
      refute has_element?(view, "[data-role='benchmark-row'] [data-role='benchmark-costs']")
      assert costs_line(view) == expected
      assert has_element?(view, "#tip-benchmark", info)

      # Never a residual labelled as attribution (the amendment's point 4).
      refute html =~ ~r/selection and timing/i
      refute html =~ ~r/Auswahl und Timing/i
    end

    # At 390 px a label never ends one line and its figure starts the next
    # (closing act, B2): a no-break space joins them in the copy (above),
    # and a figure never breaks between its amount and its currency.
    css = File.read!("priv/static/app.css")

    assert [_, fig] = Regex.run(~r/\.benchmark-costs \.benchmark-costs__fig \{([^}]*)\}/, css)
    assert fig =~ "white-space: nowrap;"

    # The formatter's own spelling of the payload's fees, pinned.
    assert Format.money(Decimal.new("1254.2"), "en") == "1,254.20"
    assert Format.money(Decimal.new("1254.2"), "de") == "1.254,20"
  end

  # The seed world plus a USD cash account whose 7.00 USD fee is booked on
  # a day with no stored USD rate (one before it and one after it): the
  # costs read it in USD and leave it out of both sums, named.
  defp seed_unconverted_cost_world do
    world = seed_world()

    dollar =
      WorldFixtures.add_depot(world.portfolio,
        cash_currency: "USD",
        cash_name: "Dollar Cash",
        depot_name: "Dollar Depot"
      )

    {:ok, 2} =
      Portfolixir.Fx.upsert_many(
        for date <- [world.start, Date.add(world.today, -1)] do
          %{
            base_currency: "EUR",
            quote_currency: "USD",
            date: date,
            rate: "1.25",
            source: "manual"
          }
        end
      )

    for {type, amount, date} <- [
          {"deposit", "500", world.start},
          {"fee", "7.00", Date.add(world.today, -5)}
        ] do
      {:ok, _tx} =
        Portfolixir.Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          cash_account_id: dollar.cash.id,
          type: type,
          date: date,
          gross_amount: amount,
          currency_code: "USD"
        })
    end

    world
  end

  # User story (Sprint 24 closing act, B2; ADR-0046, amended 2026-11-04,
  # point 2):
  # As a local portfolio maintainer reading the costs line,
  # I want a cost the page could not convert named on the line, and the ⓘ
  # to say which costs it summed for the scope I am looking at,
  # so that a missing rate never reads as a smaller cost, and the total
  # never claims to be one portfolio.
  #
  # Acceptance criteria:
  # - A 7.00 USD fee with no stored rate on its booking day is in neither
  #   sum, and the line says so: "1 cost in USD has no stored rate on its
  #   booking day and is not included." / „1 Kostenposten in USD ohne
  #   gespeicherten Kurs am Buchungstag ist nicht enthalten.“ — the count
  #   and currencies the payload's costs_paid.excluded names.
  # - Under the total the ⓘ speaks of every portfolio; under a view, of the
  #   cash accounts in the view (the scope follows the money, point 3).
  test "the costs line names a cost it could not convert, the ⓘ its scope", %{conn: conn} do
    seed_unconverted_cost_world()

    assert %{"fees" => "0", "excluded" => %{"count" => 1, "currencies" => ["USD"]}} =
             total_costs_paid(conn, "rate:0.02")

    path = fn locale -> "/portfolio?locale=#{locale}&benchmark_rate=2" end

    for {locale, line, total_info} <- [
          {"en",
           "Paid in the period: fees\u00a00.00 EUR · taxes\u00a00.00 EUR; the benchmark pays none. " <>
             "1 cost in USD has no stored rate on its booking day and is not included.",
           "Paid in the period: the fees and taxes booked in the same period across all portfolios, converted at their booking day's rate; refunds reduce the taxes. Not included is the return the money paid would otherwise have earned."},
          {"de",
           "Im Zeitraum gezahlt: Gebühren\u00a00,00 EUR · Steuern\u00a00,00 EUR — die Benchmark zahlt keine. " <>
             "1 Kostenposten in USD ohne gespeicherten Kurs am Buchungstag ist nicht enthalten.",
           "Gezahlt im Zeitraum: die Gebühren und Steuern, die im selben Zeitraum über alle Portfolios gebucht wurden, umgerechnet zum Kurs ihres Buchungstags; Erstattungen mindern die Steuern. Nicht enthalten ist der Ertrag, den das gezahlte Geld sonst erwirtschaftet hätte."}
        ] do
      {:ok, view, _html} = live(get(recycle(conn), path.(locale)), path.(locale))
      html = render_async(view)

      assert costs_line(view) == line
      assert has_element?(view, "#tip-benchmark", total_info)
      refute html =~ "this portfolio (this view)"
      refute html =~ "dieses Portfolio (diese Ansicht)"
    end

    {:ok, family} = Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "Family"})

    for {locale, view_info} <- [
          {"en",
           "Paid in the period: the fees and taxes paid in the same period from the cash accounts in this view, converted at their booking day's rate; refunds reduce the taxes. Not included is the return the money paid would otherwise have earned."},
          {"de",
           "Gezahlt im Zeitraum: die Gebühren und Steuern, die im selben Zeitraum von den Verrechnungskonten dieser Ansicht gezahlt wurden, umgerechnet zum Kurs ihres Buchungstags; Erstattungen mindern die Steuern. Nicht enthalten ist der Ertrag, den das gezahlte Geld sonst erwirtschaftet hätte."}
        ] do
      scoped = path.(locale) <> "&view=#{family.id}"
      {:ok, view, _html} = live(get(recycle(conn), scoped), scoped)
      render_async(view)

      assert has_element?(view, "[data-role='benchmark-costs']")
      assert has_element?(view, "#tip-benchmark", view_info)
    end
  end

  # --- Sprint 29 B2 begin ---
  # The picker's GET request as a browser builds it from the form: its
  # action, the hidden empty entry, every box ticked (here: the boxes named
  # by `ticked`, whatever was ticked before cleared, as the operator does),
  # and the rate field as it stands.
  defp picker_request(view, ticked) do
    form =
      view
      |> element("[data-role='benchmark-form']")
      |> render()
      |> LazyHTML.from_fragment()

    [action] = LazyHTML.attribute(form, "action")

    # The form's hidden fields other than the empty entry, as a browser
    # sends them (the closing act: the address's order of the chosen ones).
    hidden =
      for input <- form |> LazyHTML.query("input[type='hidden']"),
          [name] = LazyHTML.attribute(input, "name"),
          name != "benchmark[]",
          [value] = LazyHTML.attribute(input, "value"),
          do: {name, value}

    boxes =
      for label <- form |> LazyHTML.query("label.benchmark-form__option"),
          name = label |> LazyHTML.text() |> String.trim(),
          name in ticked,
          [value] = label |> LazyHTML.query("input") |> LazyHTML.attribute("value"),
          do: {"benchmark[]", value}

    rate =
      form
      |> LazyHTML.query("input[name='benchmark_rate']")
      |> LazyHTML.attribute("value")
      |> List.first("")

    action <>
      "?" <>
      URI.encode_query([{"benchmark[]", ""} | hidden] ++ boxes ++ [{"benchmark_rate", rate}])
  end

  defp group_names(view, group) do
    view
    |> element("[data-role='benchmark-form']")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-group='#{group}'] label.benchmark-form__option")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp group_labels(view) do
    view
    |> element("[data-role='benchmark-form']")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".bm-groups__label")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  # User story (#1416, B2; ADR-0046's amendment of 2026-11-07, point 3;
  # ADR-0058 F5; board 02 ①, Q1 A):
  # As the operator who holds the fund I want to compare with,
  # I want Holdings' „Benchmark…“ to offer the flagged benchmarks first and
  # then the securities I hold today, as two labelled groups,
  # so that I tick my own fund and see the comparison drawn with it, the
  # same figure the API answers, without flagging it reference-only.
  #
  # Acceptance criteria:
  # - The picker shows „Benchmarks“ (the flagged ones with a quote) then
  #   „In holdings“ (held today, with a quote, not flagged), by name.
  # - Ticking the held fund and applying sends benchmark[]=security:<id>;
  #   the page draws it as a chip, a comparison row and a legend entry.
  # - The row's savings-plan delta is GET /api/v1/performance/benchmark's
  #   end_value_delta for the same benchmark and the page's period (1y).
  test "a held fund ticked in the picker is drawn and equals the API's figure", %{conn: conn} do
    world = seed_world()

    conn = get(conn, "/portfolio")
    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert group_labels(view) == ["Benchmarks", "In holdings"]
    assert group_names(view, "flagged") == ["Bench ETF"]
    assert group_names(view, "held") == ["World ETF"]

    request = picker_request(view, ["World ETF"])
    assert request =~ "benchmark%5B%5D=security%3A#{world.held.id}"

    conn = get(recycle(conn), request)
    {:ok, picked, _html} = live(conn, request)
    render_async(picked)

    assert has_element?(
             picked,
             "[data-role='benchmark-active'] [data-role='benchmark-chip']",
             "World ETF"
           )

    assert has_element?(picked, "#kpi-benchmark [data-role='benchmark-row']", "World ETF")
    assert has_element?(picked, "[data-role='benchmark-legend']", "World ETF")

    assert has_element?(
             picked,
             "[data-group='held'] input[value='security:#{world.held.id}'][checked]"
           )

    api =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")
      |> get("/api/v1/performance/benchmark", %{
        "benchmark" => "security:#{world.held.id}",
        "period" => "1y"
      })
      |> json_response(200)
      |> get_in(["data", "savings_plan", "end_value_delta"])

    delta =
      picked
      |> element("#kpi-benchmark [data-role='benchmark-delta']")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()

    assert delta =~ Format.signed_decimal(Decimal.new(api), 2)
  end

  # Acceptance criteria (#1416, B2; ADR-0058 F5):
  # - A held security named in the address is active, not dropped to "not
  #   selected"; an unheld one with a quote is active too, as the API takes
  #   it, and the picker shows it ticked in a third group so Apply keeps it.
  # - A flagged security that is also held is offered once, under
  #   „Benchmarks“.
  # - The groups read „Benchmarks“ and „Im Bestand“ in German.
  test "a held or quoted security in the address stays chosen; a held benchmark is listed once",
       %{conn: conn} do
    world = seed_world()
    WorldFixtures.buy!(world, world.bench, quantity: "1", price: "50", date: world.start)
    watched = WorldFixtures.create_security!(name: "Watched Fund", ticker: "WTCH")
    WorldFixtures.put_quotes!(watched, [{world.start, "10"}, {Date.add(world.today, -1), "11"}])

    query =
      "locale=de&benchmark[]=security:#{world.held.id}&benchmark[]=security:#{watched.id}"

    conn = get(conn, "/portfolio?" <> query)
    {:ok, view, _html} = live(conn, "/portfolio?" <> query)
    render_async(view)

    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-row']", "World ETF")
    assert has_element?(view, "#kpi-benchmark [data-role='benchmark-row']", "Watched Fund")

    assert group_labels(view) == ["Benchmarks", "Im Bestand", "Weitere"]
    assert group_names(view, "flagged") == ["Bench ETF"]
    assert group_names(view, "held") == ["World ETF"]
    assert group_names(view, "other") == ["Watched Fund"]
    assert has_element?(view, "[data-group='other'] input[checked]")

    request = picker_request(view, ["World ETF", "Watched Fund"])
    assert request =~ "security%3A#{watched.id}"
  end

  # The closing act (#1416, B2): „Anwenden“ sent the ticked boxes in the
  # groups' order, so a held fund chosen first and a flagged one second
  # came back swapped, and the chips swapped colours. The address's order is
  # kept for the boxes already chosen; a box ticked anew comes after them.
  test "applying the picker keeps the address's order and appends a box ticked anew",
       %{conn: conn} do
    world = seed_world()
    query = "benchmark[]=security:#{world.held.id}&benchmark[]=security:#{world.bench.id}"

    conn = get(conn, "/portfolio?" <> query)
    {:ok, view, _html} = live(conn, "/portfolio?" <> query)
    render_async(view)

    chips = fn view ->
      view
      |> element("[data-role='benchmark-active']")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-role='benchmark-chip']")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
    end

    assert chips.(view) == ["World ETF", "Bench ETF"]

    request = picker_request(view, ["Bench ETF", "World ETF"])
    conn = get(recycle(conn), request)
    {:ok, applied, _html} = live(conn, request)
    render_async(applied)
    assert chips.(applied) == ["World ETF", "Bench ETF"]

    # Only the held fund kept, the benchmark ticked anew: it comes after.
    request = picker_request(applied, ["World ETF"])
    conn = get(recycle(conn), request)
    {:ok, one, _html} = live(conn, request)
    render_async(one)
    assert chips.(one) == ["World ETF"]

    request = picker_request(one, ["Bench ETF", "World ETF"])
    conn = get(recycle(conn), request)
    {:ok, appended, _html} = live(conn, request)
    render_async(appended)
    assert chips.(appended) == ["World ETF", "Bench ETF"]
  end

  # The closing act (#1416, UAT-13's rule): two held funds of one name read
  # the same in the picker; each twin's box now carries what tells it
  # apart (PortfolixirWeb.SecurityNames).
  test "same-named held funds are told apart in the picker", %{conn: conn} do
    world = seed_world()

    for isin <- ["DE000TWIN011", "LU000TWIN022"] do
      twin = WorldFixtures.create_security!(name: "Twin Fund", ticker: nil, isin: isin)
      WorldFixtures.put_quotes!(twin, [{world.start, "10"}])
      WorldFixtures.buy!(world, twin, quantity: "1", price: "10", date: world.start)
    end

    conn = get(conn, "/portfolio")
    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert group_names(view, "held") ==
             ["Twin Fund · DE000TWIN011", "Twin Fund · LU000TWIN022", "World ETF"]
  end

  # --- Sprint 29 B2 end ---

  describe "BenchmarkScope plug" do
    defp run_plug(conn) do
      conn
      |> Map.put(:secret_key_base, PortfolixirWeb.Endpoint.config(:secret_key_base))
      |> put_req_header("sec-fetch-site", "same-origin")
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

      assert PortfolixirWeb.PreferenceCookieHelpers.remembered(conn, BenchmarkScope.cookie_name()) ==
               "security:7,security:9"

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
        |> PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
          BenchmarkScope.cookie_name(),
          "rate:0.02,security:3,bogus"
        )
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

    test "a single selector without the array brackets is one selector" do
      conn = "benchmark=security:7" |> with_query() |> run_plug()
      assert get_session(conn, BenchmarkScope.session_key()) == ["security:7"]
    end

    # User story (E25 S4, F06):
    # As the operator whose Wealth page remembers a benchmark rate,
    # I want a rate the engine cannot hold exactly refused before it is
    # remembered, and one remembered earlier dropped on the next request,
    # so that the stored selector is always one short, exact value.
    #
    # Acceptance criteria:
    # - A rate with more decimal places than the engine's scale is not stored,
    #   whether it comes as a selector or as the picker's percentage.
    # - A rate exactly at the engine's scale is kept.
    # - A cookie carrying such a rate loses it on the next request: the
    #   session holds the rest, and the cookie is rewritten without it.
    test "a rate past the engine's scale is not stored, and a stored one is dropped" do
      for query <- [
            "benchmark[]=rate:1e-400",
            "benchmark[]=rate:0.02000000000000000001",
            "benchmark_rate=2.0000000000000000001"
          ] do
        conn = query |> with_query() |> run_plug()
        assert get_session(conn, BenchmarkScope.session_key()) == [], query
      end

      conn = "benchmark[]=rate:0.123456789012345" |> with_query() |> run_plug()
      assert get_session(conn, BenchmarkScope.session_key()) == ["rate:0.123456789012345"]

      conn =
        ""
        |> with_query()
        |> PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
          BenchmarkScope.cookie_name(),
          "rate:1e-400,security:3"
        )
        |> run_plug()

      assert get_session(conn, BenchmarkScope.session_key()) == ["security:3"]

      assert PortfolixirWeb.PreferenceCookieHelpers.remembered(conn, BenchmarkScope.cookie_name()) ==
               "security:3"
    end

    test "one spelling per rate: 2 and 2.0 are the same selector" do
      conn = "benchmark[]=rate:0.020&benchmark_rate=2.0" |> with_query() |> run_plug()
      assert get_session(conn, BenchmarkScope.session_key()) == ["rate:0.02"]
    end
  end
end
