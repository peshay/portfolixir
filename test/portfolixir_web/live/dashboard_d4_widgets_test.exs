defmodule PortfolixirWeb.DashboardD4WidgetsTest do
  # Sprint 31 D4 (FR-60; ADR-0062 §1, §12; plan D-1 exit criterion 1;
  # planning board ux-design-2026-11-21-sprint31/01 ①; idea boards
  # ux-design-2026-11-21-idea-i56 01, 03, 06): the four widgets the owner
  # named — „Wertentwicklung“, „Allokation und Drift“ and „Snapshots“ here,
  # „Crashes im Vergleich“ in dashboard_crashes_widget_test.exs — each
  # drawing its source's figures. Every figure a widget draws, in its wide
  # form at each size and in its compact form, is compared with its source
  # route's answer for the same scope (Everything here) and period, called
  # through the conn with the API's bearer token. Synthetic data only.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable` row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PeriodMenuHelpers
  import Portfolixir.WorldFixtures
  import PortfolixirWeb.PreferenceCookieHelpers

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.Portfolios.Targets
  alias PortfolixirWeb.Dashboard.Widgets.Performance, as: PerformanceWidget
  alias PortfolixirWeb.Format

  defp api(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp loaded(conn, path \\ "/") do
    {:ok, view, _html} = live(conn, path)
    render_async(view)
    view |> render() |> Floki.parse_document!()
  end

  defp compact(doc, widget), do: Floki.find(doc, "##{widget} [data-form='compact']")
  defp wide(doc, widget), do: Floki.find(doc, "##{widget} [data-form='wide']")

  defp money(value), do: Format.money(Decimal.new(value))
  defp percent(value), do: Format.signed_percent(Decimal.new(value)) <> "%"
  defp weight(value), do: Format.percent(Decimal.new(value)) <> "%"

  defp store!(items) do
    layout =
      Enum.map(items, fn {kind, size, col, row} ->
        %{"kind" => kind, "size" => size, "col" => col, "row" => row}
      end)

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "D4", "layout" => layout})

    dashboard
  end

  # A year and more of history, two positions, a sale and cash.
  defp seed do
    world = base_world()
    today = Clock.today()
    alpha = create_security!(name: "Alpha Works", ticker: "ALW")
    beta = create_security!(name: "Beta Lines", ticker: "BTL")
    deposit!(world, "5000", Date.add(today, -420))
    buy!(world, alpha, quantity: "10", price: "100", date: Date.add(today, -400))
    buy!(world, beta, quantity: "20", price: "50", date: Date.add(today, -390))
    sell!(world, alpha, quantity: "2", price: "130", date: Date.add(today, -30))

    put_quotes!(alpha, [
      {Date.add(today, -400), "100"},
      {Date.add(today, -200), "112"},
      {Date.add(today, -90), "125"},
      {Date.add(today, -1), "120"},
      {today, "126"}
    ])

    put_quotes!(beta, [
      {Date.add(today, -390), "50"},
      {Date.add(today, -180), "44"},
      {Date.add(today, -60), "47"},
      {today, "52"}
    ])

    Map.merge(world, %{alpha: alpha, beta: beta, today: today})
  end

  # A steering tree with Alpha in „Core“ (target 30 %) and Beta in
  # „Satellite“ (target 10 %), cash targeted at 60 %.
  defp steer!(world) do
    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Steering"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Core"
      })

    {:ok, satellite} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Satellite"
      })

    {:ok, _} = Classifications.assign_security(Actor.owner_ui(), world.alpha.id, tree.id, core.id)

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), world.beta.id, tree.id, satellite.id)

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, tree.id, [
        %{"category_id" => core.id, "target_weight" => "0.3"},
        %{"category_id" => satellite.id, "target_weight" => "0.1"}
      ])

    {:ok, _} = Portfolios.set_cash_target(Actor.owner_ui(), world.portfolio, Decimal.new("0.6"))
    tree
  end

  # User story:
  # As the operator reading „Wertentwicklung“ on the template,
  # I want its return and its stacked chart by category to be the figures
  # the agent reads for the same scope and period,
  # so that the widget and Wealth's chart never disagree.
  #
  # Acceptance criteria:
  # - L (the template's): the TTWROR equals GET /api/v1/performance for
  #   the dashboard's period (1J), and every band of the legend its value
  #   in GET /api/v1/performance/bands?level=category for the same period.
  # - Compact: the TTWROR equals the same answer.
  # - „Ganze Ansicht →“ opens Wealth's chart at „Kategorien“.
  test "„Wertentwicklung“ L draws the performance read and its bands", %{conn: conn} do
    world = seed()
    steer!(world)
    doc = loaded(conn)

    perf = api("/api/v1/performance?period=1y")
    bands = api("/api/v1/performance/bands?period=1y&level=category&base_currency=EUR")

    wide = wide(doc, "dashboard-performance")
    assert text(Floki.find(wide, "[data-role='performance-ttwror']")) == percent(perf["ttwror"])

    legend = Floki.find(wide, "[data-role='stack-legend'] tbody tr")
    assert length(legend) == length(bands["bands"])

    for band <- bands["bands"] do
      [row] = Floki.find(legend, "tr[data-band='#{band["key"]}']")

      assert hd(Floki.attribute(row, "data-end-value")) ==
               band["end_value"]
               |> Decimal.new()
               |> Decimal.normalize()
               |> Format.amount_attribute()

      assert text(Floki.find(row, "[data-role='stack-value']")) == money(band["end_value"])
    end

    compact = compact(doc, "dashboard-performance")

    assert text(Floki.find(compact, ".widget-figure__value")) == percent(perf["ttwror"])

    assert [href] =
             doc
             |> Floki.find("#dashboard-performance [data-role='performance-full-view']")
             |> Floki.attribute("href")

    assert href == "/portfolio?level=category"
  end

  # User story:
  # As the operator who placed „Wertentwicklung“ at S and at L (Sprint 31's
  # M, read as L since Sprint 32 E4),
  # I want the S figure and the L line to be the performance read's,
  # so that each size shows the agent's figures.
  #
  # Acceptance criteria:
  # - S: the TTWROR equals GET /api/v1/performance?period=1y, with a
  #   sparkline of the period's value.
  # - L: the TTWROR and the end value equal the same answer; the line's
  #   first and last date are its start_date and end_date, its lowest and
  #   highest label the series' lowest and highest value.
  test "„Wertentwicklung“ S and L draw the performance read", %{conn: conn} do
    seed()
    store!([{"performance", "S", 1, 1}, {"performance", "L", 4, 1}])
    doc = loaded(conn)

    perf = api("/api/v1/performance?period=1y&series=true")
    values = Enum.map(perf["series"], &Decimal.new(&1["value"]))

    small = wide(doc, "dashboard-performance")
    assert text(Floki.find(small, "[data-role='performance-ttwror']")) == percent(perf["ttwror"])
    assert Floki.find(small, "svg[data-role='performance-spark']") != []

    medium = wide(doc, "dashboard-performance-2")
    assert text(Floki.find(medium, "[data-role='performance-ttwror']")) == percent(perf["ttwror"])

    assert text(Floki.find(medium, "[data-role='performance-end-value'] .num")) ==
             money(perf["end_value"])

    assert text(Floki.find(medium, "[data-role='line-first']")) ==
             Format.date(Date.from_iso8601!(perf["start_date"]))

    assert text(Floki.find(medium, "[data-role='line-last']")) ==
             Format.date(Date.from_iso8601!(perf["end_date"]))

    assert text(Floki.find(medium, "[data-role='line-high']")) ==
             Format.money(Enum.max(values, Decimal))

    assert text(Floki.find(medium, "[data-role='line-low']")) ==
             Format.money(Enum.min(values, Decimal))

    for widget <- ["dashboard-performance", "dashboard-performance-2"] do
      assert text(Floki.find(compact(doc, widget), ".widget-figure__value")) ==
               percent(perf["ttwror"])
    end
  end

  # User story:
  # As the operator switching the dashboard's period,
  # I want „Wertentwicklung“ to read the period as the route reads it,
  # so that a short period is the trailing range, not a translated one.
  #
  # Acceptance criteria:
  # - For 3M the widget's read equals GET /api/v1/performance with from=
  #   three months back and to= today; for YTD equals ?period=ytd.
  # - Wealth's link carries the same period's pairs.
  test "„Wertentwicklung“ reads each period as its route does" do
    seed()
    today = Clock.today()
    # The span ADR-0061 §3 gives a money window, written out here rather
    # than asked of the registry: the days after the date three months
    # back, the range's baseline that date's close.
    from = today |> Date.shift(month: -3) |> Date.add(1) |> Date.to_iso8601()

    quarter = api("/api/v1/performance?from=#{from}&to=#{Date.to_iso8601(today)}")
    assert %{result: result} = PerformanceWidget.read(nil, "3m", "EUR")
    assert Decimal.equal?(result.ttwror, Decimal.new(quarter["ttwror"]))
    assert Decimal.equal?(result.end_value, Decimal.new(quarter["end_value"]))

    ytd = api("/api/v1/performance?period=ytd")
    assert %{result: result} = PerformanceWidget.read(nil, "ytd", "EUR")
    assert Decimal.equal?(result.ttwror, Decimal.new(ytd["ttwror"]))

    assert PerformanceWidget.wealth_href("3m", "L") ==
             "/portfolio?from=#{from}&to=#{Date.to_iso8601(today)}"

    assert PerformanceWidget.wealth_href("ytd", "XL") == "/portfolio?level=category&period=ytd"
    assert PerformanceWidget.wealth_href("1y", "S") == "/portfolio"
  end

  # User story:
  # As the operator reading the dashboard on 1T,
  # I want „Wertentwicklung“ and „Gesamtwert“ to show today's change alone,
  # so that one day reads as one day, as „Tops und Flops“ reads it.
  #
  # Acceptance criteria (Sprint 31 closing act, correctness lens C1, money
  # lens MO1):
  # - 1T reads today's close against the one before: closes 100, 110 and
  #   121 on T − 2, T − 1 and T read +10 % (Python decimal, prec 34:
  #   121 / 110 − 1 = 0.1), not the two days' +21 % (121 / 100 − 1).
  # - „Gesamtwert“ at S says the same change for 1T, and its links to
  #   Wealth carry the item's period, as „Wertentwicklung“'s link does.
  test "1T is one day: today's close against the one before", %{conn: conn} do
    world = base_world()
    today = Clock.today()
    fund = create_security!(name: "Day Fund", ticker: nil)
    deliver_untraded!(world, fund, "1", date: Date.add(today, -30))

    put_quotes!(fund, [
      {Date.add(today, -30), "100"},
      {Date.add(today, -2), "100"},
      {Date.add(today, -1), "110"},
      {today, "121"}
    ])

    assert %{result: result} = PerformanceWidget.read(nil, "1d", "EUR")
    assert result.start_date == today
    assert Decimal.equal?(result.ttwror, Decimal.new("0.1"))

    store!([{"total_value", "S", 1, 1}, {"performance", "S", 4, 1}])
    doc = loaded(conn, "/?period=1d")

    assert text(Floki.find(wide(doc, "dashboard-wealth"), "[data-role='card-period-change']")) ==
             percent("0.1") <> " TTWROR · 1D"

    day = "/portfolio?from=#{Date.to_iso8601(today)}&to=#{Date.to_iso8601(today)}"
    assert PerformanceWidget.wealth_href("1d", "S") == day
    assert Floki.attribute(Floki.find(doc, "#dashboard-wealth-card"), "href") == [day]
    assert Floki.attribute(Floki.find(doc, "#dashboard-wealth .widget__foot a"), "href") == [day]
  end

  # User story (Sprint 31 UAT, finding 5):
  # As the operator reading „Wertentwicklung“ on 1T,
  # I want no empty plot where one day gives no line, and a quiet word
  # saying so,
  # so that an axis from 0 with one date at both ends does not read as a
  # chart.
  #
  # Acceptance criteria:
  # - At 1T (one point) L draws no value line and XL no stacked chart; each
  #   says „One day: no line“ quietly.
  # - The TTWROR figure stays at both sizes.
  test "1T draws no plot and says so; the figure stays", %{conn: conn} do
    world = base_world()
    today = Clock.today()
    fund = create_security!(name: "Day Fund", ticker: nil)
    deliver_untraded!(world, fund, "1", date: Date.add(today, -30))

    put_quotes!(fund, [
      {Date.add(today, -30), "100"},
      {Date.add(today, -1), "110"},
      {today, "121"}
    ])

    store!([{"performance", "L", 1, 1}, {"performance", "XL", 1, 5}])
    doc = loaded(conn, "/?period=1d")

    for id <- ["dashboard-performance", "dashboard-performance-2"] do
      wide = wide(doc, id)
      assert text(Floki.find(wide, "[data-role='performance-ttwror']")) == percent("0.1"), id
      assert Floki.find(wide, "svg") == [], id <> " draws a plot of one day"
      assert text(Floki.find(wide, "[data-role='performance-one-day']")) == "One day: no line", id
    end
  end

  # User story:
  # As the operator reading „Allokation und Drift“,
  # I want its table and its arithmetic to be the allocation read's,
  # so that the drift I see is the drift the agent reads.
  #
  # Acceptance criteria:
  # - Wide (T, the template's) and compact: each top-level category and
  #   cash with its actual and target weight and its drift equal to
  #   GET /api/v1/portfolios/:id/allocation for the default tree.
  # - „Rechnerisch zum Soll“ lists exactly the rows beyond ±5 pp, each
  #   with its drift_value, sign turned, in the base currency; no order
  #   word.
  # - „Ziele bearbeiten →“ opens Wealth's „Allokation & Ziele“.
  test "„Allokation und Drift“ draws the allocation read", %{conn: conn} do
    world = seed()
    tree = steer!(world)
    doc = loaded(conn)

    answer =
      api("/api/v1/portfolios/#{world.portfolio.id}/allocation?classification_id=#{tree.id}")

    expected =
      answer["categories"]
      |> Enum.filter(&(&1["depth"] == 0))
      |> Enum.map(&{&1["name"], &1})
      |> Kernel.++([{"Cash", answer["cash"]}])

    wide = wide(doc, "dashboard-allocation-drift")
    rows = Floki.find(wide, "[data-role='allocation-drift-row']")

    assert Enum.map(rows, &hd(Floki.attribute(&1, "data-name"))) ==
             Enum.map(expected, &elem(&1, 0))

    for {name, row} <- expected do
      [drawn] = Floki.find(wide, "[data-role='allocation-drift-row'][data-name='#{name}']")
      assert text(Floki.find(drawn, "[data-role='drift-actual']")) == weight(row["actual_weight"])
      assert text(Floki.find(drawn, "[data-role='drift-target']")) == weight(row["target_weight"])

      drift = Decimal.new(row["drift_weight"])
      sign = if Decimal.negative?(drift), do: "−", else: "+"

      assert text(Floki.find(drawn, "[data-role='drift-points']")) ==
               sign <> Format.percent(Decimal.abs(drift)) <> " pp"
    end

    beyond =
      for {name, row} <- expected,
          Decimal.compare(Decimal.abs(Decimal.new(row["drift_weight"])), Decimal.new("0.05")) ==
            :gt,
          do: {name, row}

    assert beyond != []
    arithmetic = Floki.find(wide, "[data-role='drift-arithmetic']")

    assert Enum.map(arithmetic, &hd(Floki.attribute(&1, "data-name"))) ==
             Enum.map(beyond, &elem(&1, 0))

    for {name, row} <- beyond do
      [hint] = Floki.find(wide, "[data-role='drift-arithmetic'][data-name='#{name}']")

      assert text(Floki.find(hint, ".num")) ==
               Format.signed_decimal(Decimal.negate(Decimal.new(row["drift_value"])), 2)

      assert text(hint) =~ answer["base_currency"]
    end

    arithmetic_line = text(Floki.find(wide, "[data-role='allocation-drift-arithmetic']"))
    refute arithmetic_line =~ ~r/\b(buy|sell|kaufen|verkaufen)\b/i

    compact = compact(doc, "dashboard-allocation-drift")

    for {name, row} <- expected do
      [drawn] =
        Floki.find(compact, "[data-compact-role='allocation-drift-row'][data-name='#{name}']")

      assert text(Floki.find(drawn, ".widget-row__sub")) =~ weight(row["actual_weight"])
      assert text(Floki.find(drawn, ".widget-row__sub")) =~ weight(row["target_weight"])
    end

    assert ["/portfolio?tab=allocation"] ==
             doc
             |> Floki.find("#dashboard-allocation-drift [data-role='allocation-edit-targets']")
             |> Floki.attribute("href")
  end

  # User story:
  # As the operator reading „Snapshots“,
  # I want its date, its count and the change since to be the snapshots'
  # list and comparison the agent reads,
  # so that the widget shows what the Snapshots page compares.
  #
  # Acceptance criteria:
  # - S (the template's) and M (Sprint 31's W): the latest as-of date and the count equal
  #   GET /api/v1/snapshots; „seitdem“ equals real_ttwror of
  #   GET /api/v1/portfolios/:id/snapshots/:id/comparison.
  # - Compact: the count and the date, the change beside the date.
  # - „Vergleichen →“ opens the latest snapshot's comparison.
  test "„Snapshots“ draws the snapshots' list and the latest comparison", %{conn: conn} do
    world = seed()

    for {name, days} <- [{"Before the sale", -60}, {"Spring", -200}] do
      {:ok, _} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{
          name: name,
          as_of: Date.add(world.today, days)
        })
    end

    store!([{"snapshots", "S", 1, 1}, {"snapshots", "M", 4, 1}])
    doc = loaded(conn)

    list = api("/api/v1/snapshots")["snapshots"]
    [latest | _] = list

    comparison =
      api("/api/v1/portfolios/#{world.portfolio.id}/snapshots/#{latest["id"]}/comparison")

    date = Format.date(Date.from_iso8601!(latest["as_of"]))

    for widget <- ["dashboard-snapshots", "dashboard-snapshots-2"] do
      wide = wide(doc, widget)
      assert text(Floki.find(wide, "[data-role='snapshots-latest']")) == date

      assert text(Floki.find(wide, "[data-role='snapshots-count']")) ==
               "latest of #{length(list)}"

      assert text(Floki.find(wide, "[data-role='snapshots-since']")) ==
               percent(comparison["real_ttwror"])

      compact = compact(doc, widget)

      assert text(
               Floki.find(compact, "[data-compact-role='snapshots-count'] .widget-row__figure")
             ) ==
               "#{length(list)}"

      assert text(Floki.find(compact, "[data-compact-role='snapshots-latest'] .widget-row__name")) =~
               date

      assert text(
               Floki.find(compact, "[data-compact-role='snapshots-latest'] .widget-row__figure")
             ) =~
               percent(comparison["real_ttwror"])

      assert ["/snapshots?snapshot=#{latest["id"]}"] ==
               doc
               |> Floki.find("##{widget} [data-role='snapshots-compare']")
               |> Floki.attribute("href")
    end

    assert text(Floki.find(wide(doc, "dashboard-snapshots-2"), "[data-role='snapshots-name']")) =~
             latest["name"]
  end

  # User story (Sprint 32 E4; board ux-design-2026-11-25-sprint32/01 ④;
  # the owner, 2026-11-25: „Gesamtwert auf M ist total unübersichtlich“):
  # As the operator who places „Gesamtwert“ larger than S,
  # I want each larger size to show more of the same figure, never a
  # second widget in its frame,
  # so that the larger tile is read as quickly as the small one.
  #
  # Acceptance criteria:
  # - M: the total with two companions side by side, each the API's for
  #   the item's period — the value (GET /api/v1/valuation), the period's
  #   TTWROR and its result, end value less start value less net external
  #   flows of GET /api/v1/performance for the same period — 1J by
  #   default, 3M on ?period=3m; no chart, no strip.
  # - L: the total, its change over the period (the same TTWROR) and the
  #   value's course over the period as a line; no strip.
  # - Sprint 31's strip of four answers is drawn at no size.
  # - S (the template's): dashboard_widget_figures_test.exs.
  test "„Gesamtwert“ at M draws three figures and at L the figure with its course",
       %{conn: conn} do
    seed()
    store!([{"total_value", "M", 1, 1}, {"total_value", "L", 7, 1}])
    doc = loaded(conn)

    valuation = api("/api/v1/valuation?include_positions=false")
    one_year = api("/api/v1/performance?period=1y")

    result = fn read ->
      read["end_value"]
      |> Decimal.new()
      |> Decimal.sub(Decimal.new(read["start_value"]))
      |> Decimal.sub(Decimal.new(read["net_external_flows"]))
      |> Format.signed_decimal(2)
    end

    m = wide(doc, "dashboard-wealth")

    assert text(Floki.find(m, "[data-role='total-figure-value']")) ==
             money(valuation["total_with_cash"]) <> " " <> valuation["base_currency"]

    assert text(Floki.find(m, "[data-role='total-figure-ttwror']")) == percent(one_year["ttwror"])

    assert text(Floki.find(m, "[data-role='total-figure-result']")) ==
             result.(one_year) <> " " <> one_year["base_currency"]

    assert text(Floki.find(m, "dt")) == "Value TTWROR · 1Y Result · 1Y"
    assert Floki.find(m, "svg") == []
    assert Floki.find(doc, "#dashboard-kpi-strip, [data-role^='kpi-']") == []

    l = wide(doc, "dashboard-wealth-2")
    assert text(Floki.find(l, "[data-count-digits]")) == money(valuation["total_with_cash"])

    assert text(Floki.find(l, "[data-role='card-period-change']")) ==
             percent(one_year["ttwror"]) <> " TTWROR · 1Y"

    assert [_line] = Floki.find(l, "svg[id^='dashboard-wealth-line']")

    today = Clock.today()
    from = today |> Date.shift(month: -3) |> Date.add(1) |> Date.to_iso8601()
    quarter = api("/api/v1/performance?from=#{from}&to=#{Date.to_iso8601(today)}")
    doc = loaded(conn, "/?period=3m")
    m = wide(doc, "dashboard-wealth")

    assert text(Floki.find(m, "[data-role='total-figure-ttwror']")) == percent(quarter["ttwror"])

    assert text(Floki.find(m, "[data-role='total-figure-result']")) ==
             result.(quarter) <> " " <> quarter["base_currency"]

    assert text(Floki.find(wide(doc, "dashboard-wealth-2"), "[data-role='card-period-change']")) ==
             percent(quarter["ttwror"]) <> " TTWROR · 3M"

    assert text(
             Floki.find(
               compact(doc, "dashboard-wealth"),
               "[data-compact-role='total'] .widget-total__sub"
             )
           ) ==
             percent(quarter["ttwror"]) <> " TTWROR · 3M"
  end

  # User story (Sprint 31 D4, the orchestrator's follow-up 2; board ①):
  # As the operator glancing at „Datenqualität“,
  # I want each finding as one short counted line at S and the full
  # sentences at L (Sprint 31's M),
  # so that the small widget is read at a glance and the larger one
  # explains.
  #
  # Acceptance criteria:
  # - S: one link per finding, its count and a short noun, the same list
  #   behind it as at L; the footer „Check →“.
  # - M: the line's full sentences, as the Overview drew them.
  # User story (Sprint 31 closing act, DS1's follow-up; board
  # ux-design-2026-11-21-sprint31/02 ⑨):
  # As the operator reading „Datenqualität“ at S,
  # I want the most severe points first, three at most, and how many more,
  # so that the small widget fits its row and still says what is open.
  #
  # Acceptance criteria:
  # - At S at most three counted lines, problems before attention before
  #   notes; the footer says „+n more“ beside „Check →“.
  # - At M every finding, in the full sentences, no count of more.
  test "„Datenqualität“ at S shows the three most severe and how many more", %{conn: conn} do
    world = seed()

    # A held bond on two price scales (a problem) whose last quote is ten
    # days old (attention), and one without an asset class, beside the
    # securities without a logo (notes): four findings.
    {:ok, bond} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{
        name: "Kestrel Anleihe 2030 2,75%",
        currency_code: "EUR",
        asset_class: "bond"
      })

    buy!(world, bond, quantity: "100", price: "0.985", date: Date.add(world.today, -40))
    put_quote!(bond, Date.add(world.today, -10), "97.25")

    {:ok, plain} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{
        name: "Nordwind Holz",
        currency_code: "EUR"
      })

    buy!(world, plain, quantity: "5", price: "20", date: Date.add(world.today, -40))
    put_quote!(plain, world.today, "21")

    store!([{"data_quality", "S", 1, 1}, {"data_quality", "L", 4, 1}])
    doc = loaded(conn)

    small = wide(doc, "dashboard-data-quality")
    lines = Floki.find(small, ".widget-findings__item")
    assert length(lines) <= 3

    severities =
      Enum.map(lines, fn line ->
        line |> Floki.attribute("class") |> hd() |> String.split() |> List.last()
      end)

    rank = %{"is-problem" => 0, "is-attention" => 1, "is-note" => 2}
    assert severities == Enum.sort_by(severities, &rank[&1])

    all = doc |> compact("dashboard-data-quality") |> Floki.find("[data-compact-role^='dq-']")
    more = length(all) - length(lines)
    assert more > 0

    # Sprint 32 L2: the count of the rest is the list's last line, not
    # the footer's scope.
    assert text(Floki.find(doc, "#dashboard-data-quality [data-role='data-quality-more']")) ==
             "+#{more} more"

    assert text(Floki.find(doc, "#dashboard-data-quality [data-role='widget-scope']")) == ""

    assert text(Floki.find(doc, "#dashboard-data-quality .widget__foot a")) ==
             "Check securities →"

    assert text(Floki.find(doc, "#dashboard-data-quality-2 [data-role='widget-scope']")) == ""
  end

  test "„Datenqualität“ is short at S and in full sentences at L", %{conn: conn} do
    world = seed()
    put_quote!(world.beta, Date.add(world.today, -20), "51")
    store!([{"data_quality", "S", 1, 1}, {"data_quality", "L", 4, 1}])
    doc = loaded(conn)

    small = wide(doc, "dashboard-data-quality")
    medium = wide(doc, "dashboard-data-quality-2")

    assert text(Floki.find(small, "[data-role='dq-logo']")) == "2 securities without a logo"
    assert text(Floki.find(medium, "[data-role='dq-logo']")) =~ "2 held securities without a logo"

    assert Floki.attribute(Floki.find(small, "[data-role='dq-logo']"), "href") ==
             Floki.attribute(Floki.find(medium, "[data-role='dq-logo']"), "href")

    assert Floki.find(small, "[data-role='data-quality-line']") == []

    assert text(Floki.find(doc, "#dashboard-data-quality .widget__foot a")) ==
             "Check securities →"

    # Sprint 32 L2 (board 07 ① 7): one link, named for its target, at
    # every size.
    assert text(Floki.find(doc, "#dashboard-data-quality-2 .widget__foot a")) ==
             "Check securities →"
  end

  # User story (Sprint 31 D4, the orchestrator's follow-up 3):
  # As the operator whose dashboard has nothing to report in a widget,
  # I want that widget drawn with a quiet line,
  # so that the grid keeps its shape and I know the widget looked.
  #
  # Acceptance criteria:
  # - With no finding, nothing due, no sale, no security with the cycle
  #   view and no snapshot, each of „Datenqualität“, „Fällig“,
  #   „Verkaufsrückblick“, „Bitcoin-Zyklus“ and „Snapshots“ is drawn with
  #   its quiet line, in German too.
  test "a widget with nothing to say keeps its frame and a quiet line", %{conn: conn} do
    world = base_world()
    clean = create_security!(name: "Clean Co", ticker: "CLN")
    {:ok, _} = Portfolixir.Catalog.put_logo_attributes(clean, %{"logo_path" => "logos/cln.png"})
    deposit!(world, "1000", Date.add(Clock.today(), -40))
    buy!(world, clean, quantity: "2", price: "100", date: Date.add(Clock.today(), -30))
    put_quote!(clean, Clock.today(), "101")

    doc = loaded(conn, "/?locale=de")

    for {widget, role, line} <- [
          {"dashboard-data-quality", "data-quality-empty", "Keine offenen Punkte."},
          {"dashboard-upcoming", "upcoming-empty", "Nichts fällig in den nächsten 30 Tagen."},
          {"dashboard-trades", "trades-card-empty",
           "Noch keine abgeschlossenen Verkäufe gebucht."},
          {"dashboard-cycles", "cycles-empty", "Noch kein Wertpapier mit Zyklus-Ansicht."},
          {"dashboard-snapshots", "snapshots-empty", "Noch kein Snapshot."}
        ] do
      assert text(Floki.find(doc, "##{widget} [data-role='#{role}']")) == line, widget
    end
  end

  # User story (DESIGN.md → the privacy mode; found by the privacy walk):
  # As the operator with the privacy mode on,
  # I want the four widgets to hide every amount and keep their
  # percentages,
  # so that a glance over my shoulder reads no money.
  #
  # Acceptance criteria:
  # - With the privacy mode on, the page renders every widget (no read
  #   crashes on a masked amount); „Rechnerisch zum Soll“ shows no digit of
  #   an amount, wide or compact; the drift's points stay.
  test "the privacy mode masks the widgets' amounts and keeps their percentages",
       %{conn: conn} do
    world = seed()
    steer!(world)

    {:ok, view, _html} = conn |> put_preference_cookie("portfolixir_privacy", "on") |> live("/")
    render_async(view)
    doc = view |> render() |> Floki.parse_document!()

    answer =
      api(
        "/api/v1/portfolios/#{world.portfolio.id}/allocation?classification_id=" <>
          to_string(Classifications.default_classification().id)
      )

    assert answer["categories"] != []

    for role <- [
          "data-role='allocation-drift-arithmetic'",
          "data-compact-role='allocation-drift-arithmetic'"
        ] do
      line = text(Floki.find(doc, "[#{role}]"))
      assert line =~ "Core"
      refute line =~ ~r/\d/
    end

    assert Floki.find(doc, "[data-role='drift-points']") != []
    assert Floki.find(doc, "#dashboard-performance [data-role='performance-ttwror']") != []
  end

  # User story (Sprint 31 D4, the orchestrator's follow-up 1; board ①):
  # As the operator reading „Gesamtwert“ at S,
  # I want what the total leaves out said in one short line with its link,
  # so that the small widget warns without the full note.
  #
  # Acceptance criteria:
  # - S (the template's): one line with the left-out groups' counts and
  #   „Details in Wealth →“, no full note naming the accounts.
  # - L: the full note, as the Overview drew it (Sprint 31's M, read as L;
  #   M, the three figures, keeps the short line).
  test "„Gesamtwert“ says what the total leaves out in one line at S", %{conn: conn} do
    world = seed()

    {:ok, account} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "USD Settlement",
        currency_code: "USD",
        liquidity_role: "free_cash"
      })

    {:ok, _} =
      Portfolixir.Ledger.set_cash_balance(Actor.owner_ui(), account, %{
        date: Date.add(world.today, -5),
        amount: "1850"
      })

    doc = loaded(conn)
    short = Floki.find(doc, "#dashboard-wealth [data-role='wealth-card-excluded-short']")
    assert text(short) =~ "Not in the total: 1 cash account."
    # Wealth on the item's period, 1J here, the dashboard's default
    # (Sprint 31 closing act, C2/MO1).
    assert ["/portfolio"] == short |> Floki.find("a") |> Floki.attribute("href")
    assert Floki.find(doc, "#dashboard-wealth [data-role='wealth-card-excluded']") == []
    refute text(Floki.find(doc, "#dashboard-wealth")) =~ "USD Settlement"

    store!([{"total_value", "L", 1, 1}])
    doc = loaded(conn)

    assert text(Floki.find(doc, "#dashboard-wealth [data-role='wealth-card-excluded']")) =~
             "USD Settlement"

    assert Floki.find(doc, "#dashboard-wealth [data-role='wealth-card-excluded-short']") == []
  end

  # User story (Sprint 31 closing act, DS2; board
  # ux-design-2026-11-21-sprint31/02 ①, as planning board 01 ① draws it):
  # As the operator reading „Gesamtwert“ at S,
  # I want the figure drawn in the widget itself,
  # so that a small widget is not a card inside a card.
  #
  # Acceptance criteria:
  # - At S the wide form draws no `.stat` card: the total with its
  #   currency, the change over the item's period and the sparkline, the
  #   figure a link to Wealth named with the widget's scope.
  # - The short note on what the total leaves out stands after them.
  test "„Gesamtwert“ at S draws its figure without a card", %{conn: conn} do
    seed()
    doc = loaded(conn)
    wide = wide(doc, "dashboard-wealth")

    assert Floki.find(wide, ".stat") == []
    [figure] = Floki.find(wide, "a#dashboard-wealth-card.widget-total")
    assert Floki.attribute([figure], "href") == ["/portfolio"]
    assert text(Floki.find([figure], ".visually-hidden")) == "Everything"
    assert text(Floki.find([figure], ".widget-total__figure")) =~ "EUR"
    assert Floki.find([figure], "[data-role='card-period-change']") != []
    assert Floki.find(wide, "[data-role='total-spark']") != []
  end

  # User story (Sprint 31 D4 on D5's period, ADR-0062 §5):
  # As the operator switching the period above the dashboard,
  # I want „Wertentwicklung“ to read the new period, and a widget whose
  # ⋯ menu pinned its own to keep it,
  # so that each widget's figures are always for the period it names.
  #
  # Acceptance criteria:
  # - After a switch to 3M the following widget's TTWROR equals
  #   GET /api/v1/performance for the trailing three months, at S and at
  #   M, and „Gesamtwert“ at S reads the same change.
  # - A widget pinned to Max keeps GET /api/v1/performance?period=max.
  # - A pin set from the ⋯ menu after the switch re-reads that widget for
  #   its pin.
  test "a period switch re-reads „Wertentwicklung“; a pin keeps its own", %{conn: conn} do
    # A price that rose for a year and fell in the last quarter, so the
    # periods' returns differ.
    world = base_world()
    today = Clock.today()
    gamma = create_security!(name: "Gamma Rise", ticker: "GMR")
    deposit!(world, "3000", Date.add(today, -420))
    buy!(world, gamma, quantity: "10", price: "100", date: Date.add(today, -400))

    put_quotes!(
      gamma,
      for(days <- -400..0//10, do: {Date.add(today, days), rise_and_fall(days)})
    )

    {:ok, _} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Periods",
        "layout" => [
          %{"kind" => "performance", "size" => "S", "col" => 1, "row" => 1},
          %{
            "kind" => "performance",
            "size" => "L",
            "col" => 4,
            "row" => 1,
            "settings" => %{"period" => "max"}
          },
          %{"kind" => "total_value", "size" => "S", "col" => 10, "row" => 1},
          %{"kind" => "performance", "size" => "S", "col" => 1, "row" => 3}
        ]
      })

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    pick_period(view, "3m")
    render_async(view)

    from = today |> Date.shift(month: -3) |> Date.add(1) |> Date.to_iso8601()
    quarter = api("/api/v1/performance?from=#{from}&to=#{Date.to_iso8601(today)}")
    max = api("/api/v1/performance?period=max")
    assert quarter["ttwror"] != max["ttwror"]

    doc = view |> render() |> Floki.parse_document!()

    ttwror = fn doc, widget ->
      text(Floki.find(wide(doc, widget), "[data-role='performance-ttwror']"))
    end

    assert ttwror.(doc, "dashboard-performance") == percent(quarter["ttwror"])
    assert ttwror.(doc, "dashboard-performance-2") == percent(max["ttwror"])

    assert text(Floki.find(compact(doc, "dashboard-performance"), ".widget-figure__value")) ==
             percent(quarter["ttwror"])

    assert text(Floki.find(wide(doc, "dashboard-wealth"), "[data-role='card-period-change']")) ==
             percent(quarter["ttwror"]) <> " TTWROR · 3M"

    # The third item, the second S one (row 3), pinned from its menu.
    pin_widget_period(view, "#dashboard-performance-3", "max")

    render_async(view)
    doc = view |> render() |> Floki.parse_document!()
    assert ttwror.(doc, "dashboard-performance-3") == percent(max["ttwror"])
    assert ttwror.(doc, "dashboard-performance") == percent(quarter["ttwror"])
  end

  defp rise_and_fall(days) when days <= -100, do: Integer.to_string(200 + div(days + 100, 3))
  defp rise_and_fall(days), do: Integer.to_string(200 + div(days + 100, -2))
end
