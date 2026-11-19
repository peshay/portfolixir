defmodule PortfolixirWeb.WealthAxisStartLiveTest do
  # I43 (Sprint 30 W1; board `ux-design-2026-11-15-sprint30/01-axis-start`,
  # answer C; plan D-6, D-1 criterion 2): Wealth's Total says where its axis
  # starts. In „Wert“ at „Gesamt“ without a filter the bar carries „Achse:
  # Ausschnitt · ab 0“, default „Ausschnitt“ (today's chart plus the
  # axis-break mark), „ab 0“ on the address as `axis=zero`; at „ab 0“ the
  # line meets the stack's top edge at „Kategorien“ day by day. The API is
  # not touched: an axis is not a figure.
  #
  # group: :builtin_classifications -- seeds the built-in trees, whose
  # classification key is unique; the async modules that seed them never run
  # at the same time (#1047, see Portfolixir.ClassificationsTest).
  use PortfolixirWeb.ConnCase, async: true, group: :builtin_classifications

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Clock

  setup do
    Classifications.ensure_builtins()
    :ok
  end

  # -- the synthetic world ------------------------------------------------------
  #
  # Invented names and figures only. Deposit 10,000 and buy Alpha 10 @ 100
  # and Beta 20 @ 50, 400 days back; each closes every 30 days inside the
  # 1Y window at its own invented price, so the total moves inside the
  # window and its axis does not start at 0. The tree "Strategy" files
  # Alpha under Growth and Beta under Income.
  defp today, do: Clock.today()
  defp days_ago(days), do: Date.add(today(), -days)

  defp axis_world do
    world = base_world(name: "Axis World", cash_name: "Giro", depot_name: "Depot")
    d0 = days_ago(400)
    deposit!(world, "10000", d0)

    alpha = create_security!(name: "Alpha Synthetic AG")
    beta = create_security!(name: "Beta Synthetic SE")
    buy!(world, alpha, quantity: "10", price: "100", date: d0)
    buy!(world, beta, quantity: "20", price: "50", date: d0)

    steps = Enum.to_list(0..11)

    put_quotes!(
      alpha,
      [{d0, "100"}] ++
        Enum.map(steps, &{days_ago(360 - 30 * &1), Integer.to_string(100 + rem(&1 * 37, 61))})
    )

    put_quotes!(
      beta,
      [{d0, "50"}] ++
        Enum.map(steps, &{days_ago(355 - 30 * &1), Integer.to_string(40 + rem(&1 * 23, 29))})
    )

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})
    growth = category!(tree, "Growth")
    income = category!(tree, "Income")
    assign!(alpha, tree, growth)
    assign!(beta, tree, income)

    %{world: world, tree: tree, growth: growth, income: income}
  end

  # The same world with an overdraft (Sprint 30 closing act, design critic,
  # finding 1; the review seed's step 25 has one): 9,000 removed 45 days
  # back puts the cash 1,000 below 0 until 9,000 come back 43 days back, so
  # the stack draws a cash band below 0 on those two days.
  defp overdraft_world do
    w = axis_world()

    {:ok, _} =
      Portfolixir.Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.world.portfolio.id,
        cash_account_id: w.world.cash.id,
        type: "removal",
        date: days_ago(45),
        gross_amount: "9000",
        currency_code: "EUR"
      })

    deposit!(w.world, "9000", days_ago(43))
    w
  end

  defp category!(tree, name) do
    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{classification_id: tree.id, name: name})

    category
  end

  defp assign!(security, tree, category) do
    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), security.id, tree.id, category.id)
  end

  # -- reading the page and the API ---------------------------------------------------

  defp settle(view), do: Enum.each(1..4, fn _round -> render_async(view) end)

  defp doc(view), do: view |> render() |> Floki.parse_document!()

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    settle(view)
    view
  end

  defp attrs(view, selector, name),
    do: view |> doc() |> Floki.find(selector) |> Enum.flat_map(&Floki.attribute(&1, name))

  defp masked(conn), do: put_preference_cookie(conn, "portfolixir_privacy", "on")

  defp figure(view) do
    view
    |> element("#performance-figure")
    |> render()
    |> String.replace(~r/chart-[0-9a-f]{12}/, "chart-ID")
  end

  defp ticks(view) do
    view
    |> doc()
    |> Floki.find("#performance-figure .chart-axis-y")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end

  defp mark?(view, scope), do: has_element?(view, "#{scope} g.chart-axis-break")

  defp switch?(view), do: has_element?(view, "[data-role='stack-axis']")

  defp href(view, selector), do: view |> attrs(selector, "href") |> List.first()

  defp api(conn, query) do
    conn
    |> recycle()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get("/api/v1/performance/bands?" <> URI.encode_query(query))
    |> json_response(200)
    |> Map.fetch!("data")
  end

  # The line's y per drawn day, from the chart's own payload: `[iso date,
  # display, x, y, date]` per point.
  defp line_ys(view) do
    [json] =
      Regex.run(
        ~r/data-chart-payload[^>]*>(.*?)<\/script>/s,
        view |> element("#performance-figure") |> render(),
        capture: :all_but_first
      )

    json
    |> Jason.decode!()
    |> Map.fetch!("points")
    |> Map.new(fn [date, _display, _x, y | _rest] -> {date, y} end)
  end

  # The stack's top edge per drawn day: the highest upper edge (the least
  # y) of its areas above zero, read from the SVG; a path's first `points`
  # vertices are its upper edge from left to right.
  defp stack_top(view) do
    [points] = attrs(view, "#performance-figure-stack svg", "data-points")
    points = String.to_integer(points)

    view
    |> doc()
    |> Floki.find("#performance-figure-stack path.stack-band:not([data-part='negative'])")
    |> Enum.map(fn path ->
      [d] = Floki.attribute(path, "d")

      ~r/[ML]\s*(-?[\d.]+),(-?[\d.]+)/
      |> Regex.scan(d)
      |> Enum.map(fn [_, _x, y] -> String.to_float(y) end)
      |> Enum.take(points)
    end)
    |> Enum.zip_with(&Enum.min/1)
  end

  # User story (I43; board 01 ④, answer C):
  # As the operator reading my wealth at „Gesamt“,
  # I want the value chart to say that its axis does not start at 0, and
  # a switch that draws it from 0,
  # so that a dent does not read as a crash and I need not open the
  # categories to compare.
  #
  # Acceptance criteria:
  # - At „Gesamt“ without a filter in „Wert“ the bar carries „Axis“ after
  #   „Level“, „Window · From 0“, „Window“ chosen; the chart carries the
  #   axis-break mark, its lowest tick above 0.
  # - The switch is absent in „% (TTWROR)“, at a stacked level, under a
  #   filter at „Gesamt“ and in the privacy mode; the privacy mode's percent
  #   axis keeps the mark.
  # - The stack, which starts at 0, carries no mark.
  test "the switch stands at Total in Value only; the mark wherever the axis is cut",
       %{conn: conn} do
    w = axis_world()

    total = open(conn, "/portfolio?level=total")
    assert switch?(total)
    assert has_element?(total, "[data-role='stack-axis'] a.is-active[data-axis='window']")
    assert has_element?(total, "[data-role='stack-axis'] a[data-axis='zero']", "From 0")
    assert has_element?(total, "#stack-axis-label", "Axis")
    assert mark?(total, "#performance-figure")
    refute hd(ticks(total)) == "0"

    assert attrs(total, "[data-role='stack-bar'] [data-role]", "data-role") ==
             ["stack-level", "stack-axis"]

    for path <- [
          "/portfolio",
          "/portfolio?level=total&scale=ttwror",
          "/portfolio?level=total&scale=ttwror&axis=zero",
          "/portfolio?level=category&axis=zero",
          "/portfolio?level=total&category=#{w.growth.id}"
        ] do
      view = open(conn, path)
      refute switch?(view), path
      refute mark?(view, "#performance-figure-stack"), path
    end

    stack = open(conn, "/portfolio?level=category")
    assert has_element?(stack, "#performance-figure-stack")
    refute mark?(stack, "#performance-figure-stack")

    for path <- ["/portfolio?level=total", "/portfolio?level=total&axis=zero"] do
      private = open(masked(conn), path)
      refute switch?(private), path
      assert mark?(private, "#performance-figure"), path
      assert Enum.all?(ticks(private), &String.ends_with?(&1, "%")), path

      assert private |> attrs("#performance-figure svg", "aria-label") |> hd() =~
               ~r/^Value over time · axis from -?[\d.]+%, not from 0$/
    end

    german =
      open(put_preference_cookie(conn, "portfolixir_locale", "de"), "/portfolio?level=total")

    assert has_element?(german, "#stack-axis-label", "Achse")
    assert has_element?(german, "[data-role='stack-axis'] a[data-axis='window']", "Ausschnitt")
    assert has_element?(german, "[data-role='stack-axis'] a[data-axis='zero']", "ab 0")

    assert german |> attrs("#performance-figure svg", "aria-label") |> hd() =~
             ~r/^Wert im Zeitverlauf · Achse ab [\d.]+, nicht ab 0$/
  end

  # User story (I43; board 01 ④, „ab 0“; story workflow: a link handed over):
  # As the operator who switches the axis to „ab 0“ and sends the link,
  # I want the choice on the address,
  # so that the link, a reload and a period switch keep it.
  #
  # Acceptance criteria:
  # - A click on „From 0“ patches `axis=zero` after the level; the axis
  #   starts at „0“ and the mark is gone.
  # - The address opened fresh draws the same chart.
  # - A period chip and the bar's level links keep `axis=zero`; back at
  #   „Gesamt“ the choice is there.
  # - „Window“ drops the parameter: the default is never on the address.
  # - An unknown value falls back to „Window“, and no link carries it.
  test "From 0 rides the address, a link handed over reopens it", %{conn: conn} do
    axis_world()

    view = open(conn, "/portfolio?level=total")
    window_figure = figure(view)

    view |> element("[data-role='stack-axis'] a[data-axis='zero']") |> render_click()
    assert_patch(view, "/portfolio?level=total&axis=zero")
    settle(view)

    assert has_element?(view, "[data-role='stack-axis'] a.is-active[data-axis='zero']")
    assert hd(ticks(view)) == "0"
    refute mark?(view, "#performance-figure")
    zero_figure = figure(view)
    refute zero_figure == window_figure

    fresh = open(conn, "/portfolio?level=total&axis=zero")
    assert figure(fresh) == zero_figure

    assert href(fresh, "[data-role='stack-level'] a[data-level='category']") ==
             "/portfolio?level=category&axis=zero"

    fresh |> element("button[phx-value-period='ytd']") |> render_click()
    assert_patch(fresh, "/portfolio?level=total&axis=zero&period=ytd")

    fresh |> element("[data-role='stack-level'] a[data-level='category']") |> render_click()
    assert_patch(fresh, "/portfolio?level=category&axis=zero&period=ytd")
    settle(fresh)
    refute switch?(fresh)

    fresh |> element("[data-role='stack-level'] a[data-level='total']") |> render_click()
    assert_patch(fresh, "/portfolio?level=total&axis=zero&period=ytd")
    settle(fresh)
    assert has_element?(fresh, "[data-role='stack-axis'] a.is-active[data-axis='zero']")

    fresh |> element("[data-role='stack-axis'] a[data-axis='window']") |> render_click()
    assert_patch(fresh, "/portfolio?level=total&period=ytd")

    for value <- ["foo", "window", "ZERO"] do
      odd = open(conn, "/portfolio?level=total&axis=#{value}")
      assert has_element?(odd, "[data-role='stack-axis'] a.is-active[data-axis='window']")
      assert figure(odd) == window_figure

      assert href(odd, "[data-role='stack-level'] a[data-level='category']") ==
               "/portfolio?level=category"
    end
  end

  # User story (I43; D-1 criterion 2; board 01 ③):
  # As the operator comparing „Gesamt“ at „ab 0“ with the stack at
  # „Kategorien“,
  # I want the line exactly where the stack's top edge is,
  # so that the two charts of one window read the same.
  #
  # Acceptance criteria:
  # - For the same window (1Y), on every day both charts draw, the line's
  #   height at `axis=zero` is the stack's top edge at `level=category`,
  #   to a hundredth of a viewBox unit (each chart prints two places).
  # - Both draw every day of the window the bands read answers.
  # - The axis is the stack's: the same round ticks at the same heights.
  test "at From 0 the Total line meets the stack's top edge day by day", %{conn: conn} do
    axis_world()

    line = conn |> open("/portfolio?level=total&axis=zero") |> line_ys()
    stack_view = open(conn, "/portfolio?level=category")
    top = stack_top(stack_view)
    dates = api(conn, %{"level" => "category", "period" => "1y"})["dates"]

    assert length(top) == length(dates)
    assert length(dates) > 300

    pairs = for {date, edge} <- Enum.zip(dates, top), do: {date, Map.fetch!(line, date), edge}

    off = for {date, y, edge} <- pairs, abs(y - edge) > 0.01, do: {date, y, edge}
    assert off == []

    # Not a flat line: the window moves.
    assert pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() > 10

    zero_view = open(conn, "/portfolio?level=total&axis=zero")

    stack_ticks =
      for tick <- stack_view |> doc() |> Floki.find("#performance-figure-stack .chart-axis-y"),
          do: {tick |> Floki.text() |> String.trim(), tick |> Floki.attribute("y") |> hd()}

    line_ticks =
      for tick <- zero_view |> doc() |> Floki.find("#performance-figure .chart-axis-y"),
          do: {tick |> Floki.text() |> String.trim(), tick |> Floki.attribute("y") |> hd()}

    assert Enum.map(line_ticks, &elem(&1, 0)) == Enum.map(stack_ticks, &elem(&1, 0))

    for {{_, a}, {_, b}} <- Enum.zip(line_ticks, stack_ticks),
        do: assert(abs(String.to_float(a) - String.to_float(b)) <= 0.01)
  end

  # The depth of the stack's bands below 0 per drawn day, in viewBox units:
  # a negative part's path is its upper edge left to right, then its lower
  # edge right to left, so each day's depth is the lower edge's y less the
  # upper edge's; the parts below 0 add up.
  defp negative_depth(view) do
    [points] = attrs(view, "#performance-figure-stack svg", "data-points")
    points = String.to_integer(points)

    parts =
      view
      |> doc()
      |> Floki.find("#performance-figure-stack path.stack-band[data-part='negative']")
      |> Enum.map(fn path ->
        [d] = Floki.attribute(path, "d")

        ys =
          ~r/[ML]\s*(-?[\d.]+),(-?[\d.]+)/
          |> Regex.scan(d)
          |> Enum.map(fn [_, _x, y] -> String.to_float(y) end)

        {upper, lower} = Enum.split(ys, points)
        Enum.zip_with(upper, Enum.reverse(lower), fn u, l -> l - u end)
      end)

    case parts do
      [] -> List.duplicate(0.0, points)
      parts -> Enum.zip_with(parts, &Enum.sum/1)
    end
  end

  # User story (I43; D-1 criterion 2; Sprint 30 closing act, design critic,
  # finding 1):
  # As the operator comparing „Gesamt“ at „ab 0“ with the stack at
  # „Kategorien“ in a window with an overdrawn day,
  # I want the line on the stack's own axis, its floor included,
  # so that the two charts of one window still read the same.
  #
  # Acceptance criteria:
  # - The axis is the stack's: the same round ticks at the same heights,
  #   one step below 0 included.
  # - On every day without a band below 0, the line's height at
  #   `axis=zero` is the stack's top edge at `level=category`, to a
  #   hundredth of a viewBox unit.
  # - On a day with a band below 0, the line runs that band's depth below
  #   the top edge (the total is the bands above 0 less the one below).
  test "at From 0 the Total line takes the stack's floor on a window with an overdraft",
       %{conn: conn} do
    overdraft_world()

    zero_view = open(conn, "/portfolio?level=total&axis=zero")
    line = line_ys(zero_view)
    stack_view = open(conn, "/portfolio?level=category")
    top = stack_top(stack_view)
    depth = negative_depth(stack_view)
    dates = api(conn, %{"level" => "category", "period" => "1y"})["dates"]

    assert length(top) == length(dates)
    assert length(depth) == length(dates)

    rows =
      for {date, edge, deep} <- Enum.zip([dates, top, depth]),
          do: {date, Map.fetch!(line, date), edge, deep}

    {below, clear} = Enum.split_with(rows, fn {_date, _y, _edge, deep} -> deep > 0.005 end)

    # The overdraft's two days draw a band below 0.
    assert length(below) == 2

    off = for {date, y, edge, _deep} <- clear, abs(y - edge) > 0.01, do: {date, y, edge}
    assert off == []

    deep_off =
      for {date, y, edge, deep} <- below,
          abs(y - (edge + deep)) > 0.02,
          do: {date, y, edge, deep}

    assert deep_off == []

    stack_ticks =
      for tick <- stack_view |> doc() |> Floki.find("#performance-figure-stack .chart-axis-y"),
          do: {tick |> Floki.text() |> String.trim(), tick |> Floki.attribute("y") |> hd()}

    line_ticks =
      for tick <- zero_view |> doc() |> Floki.find("#performance-figure .chart-axis-y"),
          do: {tick |> Floki.text() |> String.trim(), tick |> Floki.attribute("y") |> hd()}

    assert Enum.map(line_ticks, &elem(&1, 0)) == Enum.map(stack_ticks, &elem(&1, 0))
    assert hd(Enum.map(stack_ticks, &elem(&1, 0))) =~ ~r/^-/

    for {{_, a}, {_, b}} <- Enum.zip(line_ticks, stack_ticks),
        do: assert(abs(String.to_float(a) - String.to_float(b)) <= 0.01)
  end

  # User story (I43; board 01 ④, the price chart):
  # As the operator reading a security's price chart,
  # I want the mark where its axis does not start at 0, without a switch,
  # so that the price chart says the same as Wealth's Total.
  #
  # Acceptance criteria:
  # - A security closing between 100 and 160 draws the mark on its chart,
  #   and no axis switch.
  test "a security's price chart carries the mark and no switch", %{conn: conn} do
    security = create_security!(name: "Gamma Synthetic NV")
    put_quotes!(security, [{days_ago(60), "100"}, {days_ago(30), "160"}, {today(), "130"}])

    view = open(conn, "/securities/#{security.id}?tab=chart")
    assert mark?(view, "svg.security-chart")
    refute switch?(view)

    assert view |> attrs("svg.security-chart", "aria-label") |> hd() =~
             ~r/ · axis from [\d.,]+, not from 0$/
  end
end
