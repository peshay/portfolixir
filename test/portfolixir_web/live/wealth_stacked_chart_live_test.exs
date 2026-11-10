defmodule PortfolixirWeb.WealthStackedChartLiveTest do
  # I23, FR-53 (Sprint 27 S3; idea board 01, variant A; plan D-4, D-5): the
  # value chart on Wealth → Holdings → Performance stacked by category or by
  # security, under one bar above the chart (level, classification, sort),
  # every choice on the address so a link handed over reopens it.
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
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.Portfolio.StackedChart

  # The app's category palette and its cash and unclassified colours, as the
  # allocation sunburst draws them.
  @palette ["#2563eb", "#0d9488", "#d97706", "#db2777", "#65a30d", "#7c3aed"]
  @cash "#0ea5e9"
  @unclassified "#9ca3af"

  # A test tagged `:bare` runs on a database without any classification,
  # the built-in trees included.
  setup context do
    unless context[:bare], do: Classifications.ensure_builtins()
    :ok
  end

  # -- the synthetic world ------------------------------------------------------
  #
  # Invented names and figures only. Every booking lies 500 days back, before
  # the default 1Y window, so each band has a start value and a change:
  #
  #   deposit 10000; buy Alpha 10 @ 100, Beta 20 @ 50, Gamma 5 @ 200,
  #   Delta 4 @ 100. Closes today: Alpha 120, Beta 45, Gamma 210, Delta 110.
  #
  # The tree "Strategy": Dormant (no holding, no target, first in tree
  # order), Growth (Alpha), Income (Beta) with its child Dividends (Gamma).
  # Delta is filed nowhere. On the window's last day:
  #
  #   Cash 6600 (±0), Income 900 + 1050 = 1950 (−2.5 %), Growth 1200
  #   (+20 %), Unclassified 440 (+10 %); the total 10190.
  defp today, do: Clock.today()
  defp days_ago(days), do: Date.add(today(), -days)

  defp stack_world do
    world = base_world(name: "Stack World", cash_name: "Giro", depot_name: "Depot")
    d0 = days_ago(500)
    deposit!(world, "10000", d0)

    held =
      for {name, quantity, price, close} <- [
            {"Alpha Synthetic AG", "10", "100", "120"},
            {"Beta Synthetic SE", "20", "50", "45"},
            {"Gamma Synthetic NV", "5", "200", "210"},
            {"Delta Synthetic plc", "4", "100", "110"}
          ],
          into: %{} do
        security = create_security!(name: name)
        buy!(world, security, quantity: quantity, price: price, date: d0)
        put_quotes!(security, [{d0, price}, {today(), close}])
        {name |> String.split() |> hd() |> String.downcase() |> key(), security}
      end

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})
    dormant = category!(tree, "Dormant")
    growth = category!(tree, "Growth")
    income = category!(tree, "Income", color: "#112233")
    dividends = category!(tree, "Dividends", parent_id: income.id)
    assign!(held.alpha, tree, growth)
    assign!(held.beta, tree, income)
    assign!(held.gamma, tree, dividends)

    Map.merge(held, %{
      world: world,
      tree: tree,
      dormant: dormant,
      growth: growth,
      income: income,
      dividends: dividends
    })
  end

  defp key("alpha"), do: :alpha
  defp key("beta"), do: :beta
  defp key("gamma"), do: :gamma
  defp key("delta"), do: :delta

  # Nine positions, filed nowhere: at the securities level with the cash ten
  # bands, so the two smallest merge into "Other".
  defp nine_world do
    world = base_world(name: "Nine World", cash_name: "Giro", depot_name: "Depot")
    d0 = days_ago(30)
    deposit!(world, "10000", d0)

    for k <- 1..9 do
      security = create_security!(name: "Position #{k}")
      buy!(world, security, quantity: "1", price: Integer.to_string(100 * k), date: d0)
      put_quotes!(security, [{d0, Integer.to_string(100 * k)}])
    end

    world
  end

  defp category!(tree, name, opts \\ []) do
    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: name,
        color: Keyword.get(opts, :color),
        parent_id: Keyword.get(opts, :parent_id)
      })

    category
  end

  defp assign!(security, tree, category) do
    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), security.id, tree.id, category.id)
  end

  # -- reading the page and the API --------------------------------------------------

  defp api(conn, query) do
    conn
    |> recycle()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get("/api/v1/performance/bands?" <> URI.encode_query(query))
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp settle(view), do: Enum.each(1..4, fn _round -> render_async(view) end)

  defp doc(view), do: view |> render() |> Floki.parse_document!()

  defp attrs(view, selector, name),
    do: view |> doc() |> Floki.find(selector) |> Enum.flat_map(&Floki.attribute(&1, name))

  defp text_of(view, selector) do
    view
    |> doc()
    |> Floki.find(selector)
    |> Floki.text(sep: " ")
    |> String.split()
    |> Enum.join(" ")
  end

  defp legend_keys(view), do: attrs(view, "#stack-legend tbody tr", "data-band")

  defp href(view, selector), do: view |> attrs(selector, "href") |> List.first()

  defp signed_pct(nil), do: "—"

  defp signed_pct(raw), do: Format.signed_percent(Decimal.new(raw)) <> "%"

  defp figure(view) do
    view
    |> element("#performance-figure")
    |> render()
    |> String.replace(~r/chart-[0-9a-f]{12}/, "chart-ID")
  end

  # User story (I23, FR-53; board 01 A):
  # As a local portfolio maintainer reading my wealth on Wealth,
  # I want the value chart stacked by the categories of my classification,
  # with a legend that says each band's value, share and change,
  # so that I see what my wealth is made of, not only how much it is.
  #
  # Acceptance criteria:
  # - `/portfolio?level=category` opens the value chart stacked by category,
  #   for the period 1Y (the page's default), with the bar's level on
  #   "Categories" and the sort on "Size".
  # - The legend reads like the stack, the top band first: the API's bands
  #   for the same request and period (`GET /api/v1/performance/bands
  #   ?level=category&period=1y`) in reverse, the largest at the bottom.
  # - On the window's last day, the API's end date, each row's value is the
  #   API's end value, as the data attribute and as the shown amount; its
  #   share and its change are the API's.
  # - The basis line names the classification the stack uses.
  test "the category stack shows the API's bands for the same period, the largest at the bottom",
       %{conn: conn} do
    w = stack_world()

    {:ok, view, _html} = live(conn, "/portfolio?level=category")
    settle(view)

    assert has_element?(view, "#performance-figure-stack[data-level='category']")
    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='category']")
    assert has_element?(view, "[data-role='stack-sort'] a.is-active[data-sort='size']")

    data = api(conn, %{"level" => "category", "period" => "1y"})
    api_keys = Enum.map(data["bands"], & &1["key"])

    assert api_keys == [
             "cash",
             "category:#{w.income.id}",
             "category:#{w.growth.id}",
             "unclassified"
           ]

    assert legend_keys(view) == Enum.reverse(api_keys)
    assert attrs(view, "#stack-legend", "data-date") == [data["end_date"]]

    for band <- data["bands"] do
      row = "#stack-legend tr[data-band='#{band["key"]}']"
      assert attrs(view, row, "data-end-value") == [band["end_value"]]

      assert text_of(view, row <> " td[data-role='stack-value']") ==
               Format.money(Decimal.new(band["end_value"]))

      assert text_of(view, row <> " td[data-role='stack-share']") ==
               Format.percent(Decimal.new(band["share"])) <> "%"

      assert text_of(view, row <> " td[data-role='stack-change']") == signed_pct(band["change"])
    end

    assert text_of(view, "#stack-legend tr[data-band='cash'] td[data-role='stack-value']") ==
             "6,600.00"

    assert text_of(view, "#stack-legend tr[data-band='category:#{w.growth.id}']") =~ "+20.0%"
    assert text_of(view, "[data-role='stack-basis']") =~ "Strategy"
  end

  # User story (I23, FR-53; the closing act's money lens, M1):
  # As a local portfolio maintainer whose portfolio is kept in US dollars,
  # I want the stack and the bands read to answer the same figures for the
  # same request,
  # so that my agent and I talk about the same numbers.
  #
  # Acceptance criteria:
  # - With a USD base portfolio, the stack's basis line names USD, and each
  #   legend row's value, share and change are the view-less bands read's
  #   asked with `base_currency=USD`, the screen's currency.
  # - The same read without it answers in EUR, so the figures differ: the
  #   screen's currency is the one to ask for.
  test "a USD base portfolio's stack shows the API's bands asked in USD", %{conn: conn} do
    world =
      base_world(name: "Dollar World", currency: "USD", cash_currency: "EUR", depot_name: "Depot")

    d0 = days_ago(500)

    {:ok, _} =
      Portfolixir.Fx.upsert_many([
        %{base_currency: "EUR", quote_currency: "USD", date: d0, rate: "1.0832", source: "manual"}
      ])

    deposit!(world, "10000", d0)
    security = create_security!(name: "Alpha Synthetic AG")
    buy!(world, security, quantity: "10", price: "100", date: d0)
    put_quotes!(security, [{d0, "100"}, {today(), "120"}])

    {:ok, view, _html} = live(conn, "/portfolio?level=category")
    settle(view)

    usd = api(conn, %{"level" => "category", "period" => "1y", "base_currency" => "USD"})
    eur = api(conn, %{"level" => "category", "period" => "1y"})

    assert usd["base_currency"] == "USD"
    assert text_of(view, "[data-role='stack-basis']") =~ "in USD"
    assert legend_keys(view) == usd["bands"] |> Enum.map(& &1["key"]) |> Enum.reverse()

    for band <- usd["bands"] do
      row = "#stack-legend tr[data-band='#{band["key"]}']"
      assert attrs(view, row, "data-end-value") == [band["end_value"]]

      assert text_of(view, row <> " td[data-role='stack-share']") ==
               Format.percent(Decimal.new(band["share"])) <> "%"

      assert text_of(view, row <> " td[data-role='stack-change']") == signed_pct(band["change"])
    end

    refute Enum.map(eur["bands"], & &1["end_value"]) ==
             Enum.map(usd["bands"], & &1["end_value"])
  end

  # User story (I23, FR-53; story workflow: a link handed over):
  # As a local portfolio maintainer who sends a colleague the address,
  # I want every choice of the bar on the address,
  # so that the link reopens the same stack.
  #
  # Acceptance criteria:
  # - Each choice is a link that patches: the sort "Change" adds
  #   `sort=change`, another classification `tree=…`; the TTWROR series
  #   chosen first does not stop a link from opening the value chart.
  # - The address after a filter's click, opened fresh, shows the same
  #   level, sort, filter and legend order; no choice lives only in the page
  #   process.
  # - "Total" drops the sort, keeps the filter (FR-56, board 02 ③) and names
  #   its level („Kategorien“ is the default, so the address names it).
  test "the stack's state is on the address, and a link handed over reopens it", %{conn: conn} do
    w = stack_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    settle(view)

    # FR-57 (S4): the TTWROR series has the bar too, at „Gesamt“.
    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='total']")
    view |> element("[data-role='chart-series'] button[phx-value-mode='value']") |> render_click()
    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='category']")

    view |> element("[data-role='stack-level'] a[data-level='category']") |> render_click()
    assert_patch(view, "/portfolio?level=category")
    settle(view)

    view |> element("[data-role='stack-sort'] a[data-sort='change']") |> render_click()
    assert_patch(view, "/portfolio?level=category&sort=change")
    settle(view)

    # By change: Growth +20 %, Unclassified +10 %, Cash ±0, Income −2.5 %;
    # the largest at the bottom, so the legend reads from the smallest.
    assert legend_keys(view) == [
             "category:#{w.income.id}",
             "cash",
             "unclassified",
             "category:#{w.growth.id}"
           ]

    view
    |> form("#stack-classification-form", %{"tree" => Integer.to_string(w.tree.id)})
    |> render_change()

    assert_patch(view, "/portfolio?level=category&tree=#{w.tree.id}&sort=change")
    settle(view)

    view
    |> element("#performance-figure-stack path[data-band='category:#{w.income.id}']")
    |> render_click()

    handed_over =
      "/portfolio?level=category&tree=#{w.tree.id}&category=#{w.income.id}&sort=change"

    assert_patch(view, handed_over)
    settle(view)
    shown = legend_keys(view)

    {:ok, fresh, _html} = live(build_conn(), handed_over)
    settle(fresh)

    assert has_element?(
             fresh,
             "[data-role='chart-series'] button.is-active[phx-value-mode='value']"
           )

    assert has_element?(fresh, "[data-role='stack-level'] a.is-active[data-level='category']")
    assert has_element?(fresh, "[data-role='stack-sort'] a.is-active[data-sort='change']")
    assert text_of(fresh, "[data-role='stack-crumbs']") == "All categories › Income"
    assert legend_keys(fresh) == shown
    # Dividends (Gamma) +5 %, Income (direct) (Beta) −10 %: the larger
    # change at the bottom.
    assert shown == ["direct:#{w.income.id}", "category:#{w.dividends.id}"]

    assert href(fresh, "[data-role='stack-crumbs'] a") ==
             "/portfolio?level=category&tree=#{w.tree.id}&sort=change"

    fresh |> element("[data-role='stack-level'] a[data-level='total']") |> render_click()
    assert_patch(fresh, "/portfolio?level=total&tree=#{w.tree.id}&category=#{w.income.id}")
  end

  # User story (I23, FR-53; plan D-4: "Gesamt is today's chart"):
  # As a local portfolio maintainer,
  # I want the level "Total" to be the value chart I know, unchanged,
  # so that the bar adds a choice and takes nothing away.
  #
  # Acceptance criteria:
  # - In the value series, "Total" chosen (no longer the default, FR-56),
  #   the bar stands above the chart with no classification or sort control.
  # - The figure under it is byte for byte the value chart without the bar's
  #   parameters, after a trip through the category stack and back too.
  # - The TTWROR series keeps the bar and its level (FR-57, Sprint 28 S4):
  #   at „Gesamt“ it is today's TTWROR line.
  test "Total is today's value chart, unchanged", %{conn: conn} do
    stack_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    settle(view)
    view |> element("[data-role='chart-series'] button[phx-value-mode='value']") |> render_click()
    view |> element("[data-role='stack-level'] a[data-level='total']") |> render_click()
    settle(view)
    before = figure(view)

    assert before =~ ~s(class="security-chart)
    refute has_element?(view, "#performance-figure-stack")
    refute has_element?(view, "#stack-classification-form")
    refute has_element?(view, "[data-role='stack-sort']")

    view |> element("[data-role='stack-level'] a[data-level='category']") |> render_click()
    settle(view)
    refute has_element?(view, "#performance-figure")

    view |> element("[data-role='stack-level'] a[data-level='total']") |> render_click()
    settle(view)

    assert figure(view) == before

    view
    |> element("[data-role='chart-series'] button[phx-value-mode='ttwror']")
    |> render_click()

    assert_patch(view, "/portfolio?level=total&scale=ttwror")
    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='total']")
    assert has_element?(view, "#performance-figure[data-chart-mode='ttwror']")
  end

  # User story (I23, FR-53; board 01; the owner's colours of 2026-11-07):
  # As a local portfolio maintainer,
  # I want a category to wear the same colour on the stack as on the
  # allocation sunburst,
  # so that I recognise it on both tabs.
  #
  # Acceptance criteria:
  # - Each category band and its legend swatch take the colour the sunburst
  #   draws the category in for the same tree: the operator's colour, else
  #   the palette in the sunburst's order (Growth is the first category the
  #   sunburst draws, though Dormant comes first in the tree).
  # - Cash is the cash colour, the unclassified band grey.
  # - A drilled category's securities take the palette's hues in order of
  #   size, not shades of the category's colour.
  # - "Other" is drawn in a neutral token, not a palette colour.
  test "a category is drawn in the sunburst's colour; drilled securities in the palette's hues",
       %{conn: conn} do
    w = stack_world()

    {:ok, alloc, _html} = live(conn, "/portfolio?tab=allocation&classification=#{w.tree.id}")
    settle(alloc)

    sunburst = fn name ->
      alloc |> attrs("path.sunburst-seg[data-label='#{name}']", "fill") |> List.first()
    end

    assert sunburst.("Growth") == hd(@palette)
    assert sunburst.("Income") == "#112233"

    {:ok, view, _html} = live(conn, "/portfolio?level=category&tree=#{w.tree.id}")
    settle(view)

    fill = fn key -> view |> attrs("path[data-band='#{key}']", "fill") |> List.first() end

    swatch = fn key ->
      view |> attrs("#stack-legend tr[data-band='#{key}'] .stack-swatch", "style") |> List.first()
    end

    for {name, category} <- [{"Growth", w.growth}, {"Income", w.income}] do
      assert fill.("category:#{category.id}") == sunburst.(name)
      assert swatch.("category:#{category.id}") == "background: #{sunburst.(name)}"
    end

    assert fill.("cash") == @cash
    assert fill.("unclassified") == @unclassified

    {:ok, drilled, _html} = live(conn, "/portfolio?level=security&category=#{w.income.id}")
    settle(drilled)

    # Gamma 1050 before Beta 900.
    assert drilled |> attrs("path[data-band='security:#{w.gamma.id}']", "fill") == [
             Enum.at(@palette, 0)
           ]

    assert drilled |> attrs("path[data-band='security:#{w.beta.id}']", "fill") == [
             Enum.at(@palette, 1)
           ]

    nine_world()
    {:ok, many, _html} = live(conn, "/portfolio?level=security")
    settle(many)

    assert has_element?(many, "path.stack-band--other[data-band='other']")
    assert many |> attrs("path[data-band='other']", "fill") == []
    assert has_element?(many, "#stack-legend tr[data-band='other'] .stack-swatch--other")
  end

  # --- Sprint 28 S6 begin ---
  # The privacy mode keeps the stack's shape (#1433, plan amendment D-A2,
  # board 06): the same picture as without the mode, the axis in percent of
  # the bands' total on the window's first day, no amount anywhere.

  defp masked(conn), do: put_preference_cookie(conn, "portfolixir_privacy", "on")

  # The bands read's query for a stack address.
  defp bands_query(address) do
    params = address |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    query = %{"level" => params["level"], "period" => "1y"}

    case params["category"] do
      nil -> query
      filter -> Map.put(query, "category_id", filter)
    end
  end

  # The bands' total on the window's first day whose total is above zero,
  # as the API answers it, and that day.
  defp index_basis(data) do
    data["dates"]
    |> Enum.with_index()
    |> Enum.find_value(fn {date, i} ->
      total =
        data["bands"]
        |> Enum.map(&Decimal.new(Enum.at(&1["values"], i)))
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

      if Decimal.gt?(total, 0), do: {date, Decimal.to_float(total)}
    end)
  end

  defp tick_texts(view) do
    view
    |> doc()
    |> Floki.find("#performance-figure-stack .chart-axis-y")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end

  # A value tick as the English page prints it ("10,700", "2,674.88").
  defp tick_value(text), do: text |> String.replace(",", "") |> Float.parse() |> elem(0)

  # A percent tick ("107%", "-8%").
  defp tick_percent(text), do: text |> String.trim_trailing("%") |> tick_value()

  # Each axis tick as {its number, its y}.
  defp ticks(view, parse) do
    view
    |> doc()
    |> Floki.find("#performance-figure-stack .chart-axis-y")
    |> Enum.map(fn tick ->
      [y] = Floki.attribute(tick, "y")
      {tick |> Floki.text() |> String.trim() |> parse.(), String.to_float(y)}
    end)
  end

  # The amount at a height of the value mode's plot, read off two of its
  # ticks: the axis is linear.
  defp amount_at(plain) do
    [{v1, y1}, {v2, y2} | _] = ticks(plain, &tick_value/1)
    fn y -> v1 + (y - y1) * (v2 - v1) / (y2 - y1) end
  end

  # The axis reads round steps (D2): equal steps of 1, 2, 2.5 or 5 times a
  # power of ten, 0 among them when the plot reaches below zero.
  defp assert_round_ticks(numbers, label) do
    assert length(numbers) >= 2, label

    [step | _] =
      steps = numbers |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> b - a end)

    assert Enum.all?(steps, &(abs(&1 - step) < 1.0e-6)), "#{label}: #{inspect(numbers)}"
    mantissa = step / :math.pow(10, Float.floor(:math.log10(step)))
    assert Enum.any?([1.0, 2.0, 2.5, 5.0], &(abs(&1 - mantissa) < 1.0e-6)), "#{label}: #{step}"
    assert Enum.all?(numbers, &(abs(&1 / step - Float.round(&1 / step)) < 1.0e-6)), label
  end

  # Each drawn area's height per drawn day, by key and part.
  defp heights(view) do
    for {key, part, days} <- polygons(view) do
      {{key, part}, Enum.map(days, fn {upper, lower} -> lower - upper end)}
    end
  end

  defp refute_amounts(view, address) do
    section = text_of(view, "#portfolio-performance")
    titles = view |> doc() |> Floki.find("#performance-figure-stack title") |> Floki.text()
    ticks = Enum.join(tick_texts(view), " ")

    for shown <- [section, titles, ticks] do
      assert Regex.scan(~r/\d{1,3}(?:,\d{3})*\.\d{2}(?!\d|%)/u, shown) == [],
             "#{address} names an amount: #{shown}"

      refute shown =~ PortfolixirWeb.PrivacyMode.text()
    end

    for tick <- tick_texts(view), do: assert(tick =~ ~r/^-?[\d,]+%$/u, "#{address}: #{tick}")

    refute has_element?(view, "#stack-legend th", "Value")
    refute has_element?(view, "#stack-legend td[data-role='stack-value']")
    assert attrs(view, "[data-end-value]", "data-end-value") == []
  end

  # User story (#1433, D-A2, board 06; FR-53 amended):
  # As the operator sharing my screen with the privacy mode on,
  # I want the stacked chart to look as it does without the mode, only
  # without amounts,
  # so that I still see how my wealth and each band grew, while nobody can
  # tell 10,000 from 10 million.
  #
  # Acceptance criteria:
  # - At every level, with a filter (a category, the unassigned rest) and
  #   without, the picture is the value mode's: every band's height on
  #   every drawn day is the value mode's times one factor.
  # - Each axis tick reads in percent of the bands' total on the window's
  #   first day (with a filter, the filtered stack's total): the amount at
  #   its height over that total, a whole percent, in round steps (the
  #   closing act's design critic, D2).
  # - No tick, legend cell or tooltip names an amount; the legend drops the
  #   value column and its share is the API's net share; the ⓘ says what
  #   the axis reads.
  test "in the privacy mode the stack keeps its shape and its axis reads in percent of the first day",
       %{conn: conn} do
    w = stack_world()

    for address <- [
          "/portfolio?level=total&category=#{w.income.id}",
          "/portfolio?level=category",
          "/portfolio?level=category&category=#{w.income.id}",
          "/portfolio?level=category&category=unclassified",
          "/portfolio?level=security",
          "/portfolio?level=security&category=#{w.income.id}"
        ] do
      {:ok, plain, _html} = live(conn, address)
      settle(plain)
      {:ok, view, _html} = live(masked(conn), address)
      settle(view)

      data = api(conn, bands_query(address))
      {_date, base} = index_basis(data)

      # One picture: each height the value mode's times one factor.
      shown = heights(view)
      value = heights(plain)
      assert Enum.map(shown, &elem(&1, 0)) == Enum.map(value, &elem(&1, 0)), address

      factors =
        for {{_key, hs}, {_k, vs}} <- Enum.zip(shown, value),
            {h, v} <- Enum.zip(hs, vs),
            v > 0.5,
            do: h / v

      assert factors != [], address
      assert Enum.max(factors) - Enum.min(factors) < 0.02, "#{address}: #{inspect(factors)}"

      # Each tick in percent of the first day's total, in round steps.
      amount = amount_at(plain)

      for {percent, y} <- ticks(view, &tick_percent/1) do
        assert abs(percent - amount.(y) / base * 100) <= 0.51,
               "#{address}: #{percent} % is not #{amount.(y)} over #{base}"
      end

      assert_round_ticks(view |> ticks(&tick_percent/1) |> Enum.map(&elem(&1, 0)), address)

      refute_amounts(view, address)

      for band <- data["bands"] do
        assert text_of(
                 view,
                 "#stack-legend tr[data-band='#{band["key"]}'] td[data-role='stack-share']"
               ) ==
                 Format.percent(Decimal.new(band["share"])) <> "%",
               "#{address}: #{band["key"]}"
      end

      assert text_of(view, "[data-role='stack-basis'] [data-role='section-info']") =~
               "In the privacy mode the axis reads in percent of the bands’ total on the window’s first day"
    end
  end

  # User story (#1433, D-A2; the closing act's money lens of Sprint 27, M3,
  # retired):
  # As the operator sharing the screen with an overdrawn cash account,
  # I want the legend's share in the privacy mode to be the share the API
  # and the screen without the mode give,
  # so that one band reads one share whatever the mode.
  #
  # Acceptance criteria:
  # - Deposit 100, buy 300: on the last day the security is 300 and the
  #   cash −200; with the mode on, the legend reads the API's net shares,
  #   300.0 % and −200.0 %, as without it.
  test "in the privacy mode the legend's share is the API's net share", %{conn: conn} do
    world = base_world(name: "Overdrawn World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "100", days_ago(30))
    security = create_security!(name: "Alpha Synthetic AG")
    buy!(world, security, quantity: "3", price: "100", date: days_ago(30))
    put_quotes!(security, [{days_ago(30), "100"}])

    data = api(conn, %{"level" => "security", "period" => "1y"})
    shares = Map.new(data["bands"], &{&1["key"], &1["share"]})
    assert shares == %{"security:#{security.id}" => "3", "cash" => "-2"}

    {:ok, view, _html} = live(masked(conn), "/portfolio?level=security")
    settle(view)

    share = fn key ->
      text_of(view, "#stack-legend tr[data-band='#{key}'] td[data-role='stack-share']")
    end

    assert share.("security:#{security.id}") == Format.percent(Decimal.new(3)) <> "%"
    assert share.("cash") == Format.percent(Decimal.new(-2)) <> "%"
  end

  # User story (#1433, D-A2; #1426's drawing):
  # As the operator whose cash was overdrawn for two days, with the privacy
  # mode on,
  # I want the band that changes sign drawn as without the mode,
  # so that the mode changes the labels, never the picture.
  #
  # Acceptance criteria:
  # - At „Wertpapiere“ and „Kategorien“ the masked picture is the value
  #   mode's, the cash's part below zero a separate area next to the zero
  #   line, no two areas crossing; no tick, legend cell or tooltip names an
  #   amount.
  test "in the privacy mode a band that changes sign is drawn as without it", %{conn: conn} do
    sign_world()

    for address <- ["/portfolio?level=security", "/portfolio?level=category"] do
      {:ok, plain, _html} = live(conn, address)
      settle(plain)
      {:ok, view, _html} = live(masked(conn), address)
      settle(view)

      assert polygons(view) == polygons(plain), address
      assert crossings(polygons(view)) == []

      assert has_element?(
               view,
               "path.stack-band--negative[data-band='cash'][data-part='negative']"
             )

      assert has_element?(view, "#performance-figure-stack line.chart-zeroline")
      refute_amounts(view, address)
    end
  end

  # User story (#1433, D-A2; the edge the amendment left open):
  # As the operator whose window starts on a day the bands add up to zero
  # (a buy booked before the money that pays it),
  # I want the axis indexed to the first day whose total is above zero, and
  # told so,
  # so that no axis divides by zero or turns upside down.
  #
  # Acceptance criteria:
  # - Buy 300 thirty days ago with no money (total 0), deposit 500 twenty
  #   days ago (total 500): the ticks read in percent of 500, and the ⓘ
  #   names that day as the first one above zero.
  test "in the privacy mode a first day without a positive total indexes to the first that has one",
       %{conn: conn} do
    world = base_world(name: "Late World", cash_name: "Giro", depot_name: "Depot")
    security = create_security!(name: "Alpha Synthetic AG")
    buy!(world, security, quantity: "3", price: "100", date: days_ago(30))
    put_quotes!(security, [{days_ago(30), "100"}])
    deposit!(world, "500", days_ago(20))

    data = api(conn, %{"level" => "category", "period" => "1y"})
    assert hd(data["dates"]) == Date.to_iso8601(days_ago(30))
    {date, base} = index_basis(data)
    assert date == Date.to_iso8601(days_ago(20))
    assert base == 500.0

    {:ok, plain, _html} = live(conn, "/portfolio?level=category")
    settle(plain)
    {:ok, view, _html} = live(masked(conn), "/portfolio?level=category")
    settle(view)

    amount = amount_at(plain)

    for {percent, y} <- ticks(view, &tick_percent/1) do
      assert abs(percent - amount.(y) / base * 100) <= 0.51
    end

    assert text_of(view, "[data-role='stack-basis'] [data-role='section-info']") =~
             "the bands’ total on #{Format.date(days_ago(20))}, the first day it is above zero"

    refute_amounts(view, "/portfolio?level=category")
  end

  # User story (#1433, D-A2; the same edge, with no day to index to):
  # As the operator whose bands add up to zero or less on every day of the
  # window,
  # I want an axis without labels rather than one in percent of nothing,
  # so that the mode never invents a scale.
  #
  # Acceptance criteria:
  # - Buy 300 with no money thirty days ago, the close falling to 90
  #   today: the total is 0, then −30. The masked chart draws its bands and
  #   axis lines but no tick label, and the ⓘ says why.
  test "in the privacy mode a window without a positive total draws no tick labels", %{conn: conn} do
    world = base_world(name: "Short World", cash_name: "Giro", depot_name: "Depot")
    security = create_security!(name: "Alpha Synthetic AG")
    buy!(world, security, quantity: "3", price: "100", date: days_ago(30))
    put_quotes!(security, [{days_ago(30), "100"}, {today(), "90"}])

    assert index_basis(api(conn, %{"level" => "category", "period" => "1y"})) == nil

    {:ok, view, _html} = live(masked(conn), "/portfolio?level=category")
    settle(view)

    assert has_element?(view, "#performance-figure-stack path.stack-band")
    assert has_element?(view, "#performance-figure-stack .chart-axes line")
    assert tick_texts(view) == []

    assert text_of(view, "[data-role='stack-basis'] [data-role='section-info']") =~
             "the axis has no labels: the bands’ total is above zero on no day of the window"

    refute_amounts(view, "/portfolio?level=category")
  end

  # --- Sprint 28 S6 end ---

  # User story (I23, board 01 A; the closing act's design critic, D3):
  # As the operator reading the stack in German,
  # I want the sort and the legend's column to say „Veränderung“ as the
  # board and the basis line do,
  # so that one word names one figure.
  #
  # Acceptance criteria:
  # - In German the sort control reads „Veränderung“ and the legend's
  #   column header „Veränd.“; the basis line keeps its „Veränderung“.
  # - In English both read "Change".
  test "the sort and the change column say Veränderung in German", %{conn: conn} do
    stack_world()

    {:ok, view, _html} = live(conn, "/portfolio?level=category")
    settle(view)
    assert text_of(view, "[data-role='stack-sort'] a[data-sort='change']") == "Change"
    assert text_of(view, "#stack-legend th:last-child") == "Change"

    german = put_preference_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(german, "/portfolio?level=category")
    settle(view)
    assert text_of(view, "[data-role='stack-sort'] a[data-sort='change']") == "Veränderung"
    assert text_of(view, "#stack-legend th:last-child") == "Veränd."
    assert text_of(view, "[data-role='stack-basis']") =~ "Veränderung"
  end

  # User story (I23, board 01 A; the closing act's design critic, D4):
  # As the operator reading a stack of many positions,
  # I want "Other" always on top of the stack, the legend's first row,
  # so that the rest never sits at the base where the largest band belongs.
  #
  # Acceptance criteria:
  # - With ten bands the two smallest merge into "Other", which the legend
  #   lists first (the top band) and the stack draws last, by size and by
  #   change alike; the order is the API's.
  # - The basis line says that "Other" always sits on top.
  test "Other sits on top of the stack whatever the sort", %{conn: conn} do
    nine_world()

    for {address, sort} <- [
          {"/portfolio?level=security", "size"},
          {"/portfolio?level=security&sort=change", "change"}
        ] do
      {:ok, view, _html} = live(conn, address)
      settle(view)

      data = api(conn, %{"level" => "security", "period" => "1y", "sort" => sort})
      assert List.last(data["bands"])["key"] == "other"
      assert legend_keys(view) == data["bands"] |> Enum.map(& &1["key"]) |> Enum.reverse()
      assert hd(legend_keys(view)) == "other"

      assert view |> attrs("#performance-figure-stack path", "data-band") |> List.last() ==
               "other"

      assert text_of(view, "[data-role='stack-basis']") =~ "“Other”, which always sits on top"
    end
  end

  # User story (I23; the closing act's design critic, D5):
  # As the operator drilling into a category by keyboard,
  # I want the focus on the breadcrumb's current item after the drill,
  # so that it does not fall back to the top of the page.
  #
  # Acceptance criteria:
  # - The breadcrumb's current item is focusable by script
  #   (`#stack-crumbs-current`, `tabindex="-1"`).
  # - A drill by the legend's link or by the band, and the breadcrumb's way
  #   back, ask the page to move the focus there (`focus-into-view`).
  # - Opening a drilled address, and a change of sort, move no focus.
  test "after a drill the focus moves to the breadcrumb's current item", %{conn: conn} do
    w = stack_world()

    {:ok, view, _html} = live(conn, "/portfolio?level=category")
    settle(view)
    assert has_element?(view, "#stack-crumbs-current[tabindex='-1'][aria-current='location']")

    view
    |> element("#stack-legend tr[data-band='category:#{w.income.id}'] a", "Income")
    |> render_click()

    settle(view)
    assert_push_event(view, "focus-into-view", %{id: "stack-crumbs-current"})
    assert text_of(view, "#stack-crumbs-current") == "Income"

    view |> element("[data-role='stack-crumbs'] a", "All categories") |> render_click()
    settle(view)
    assert_push_event(view, "focus-into-view", %{id: "stack-crumbs-current"})

    view
    |> element("#performance-figure-stack path[data-band='category:#{w.income.id}']")
    |> render_click()

    settle(view)
    assert_push_event(view, "focus-into-view", %{id: "stack-crumbs-current"})

    {:ok, fresh, _html} = live(conn, "/portfolio?level=security&category=#{w.income.id}")
    settle(fresh)
    fresh |> element("[data-role='stack-sort'] a[data-sort='change']") |> render_click()
    settle(fresh)
    refute_push_event(fresh, "focus-into-view", %{id: "stack-crumbs-current"})
  end

  # Polish: Wealth (#1366), the line of 2026-11-06: "/portfolio?tab=allocation
  # crashes in default_classification_id/1 on a database without any
  # classification".
  #
  # User story:
  # As a local portfolio maintainer on a fresh database without any
  # classification,
  # I want Wealth to open on both tabs and its stack to draw,
  # so that a missing tree is an empty allocation, not a crash.
  #
  # Acceptance criteria:
  # - With no classification at all, `/portfolio`, `/portfolio?tab=allocation`
  #   and `/portfolio?level=category` render; the category stack holds only
  #   cash and the unclassified rest.
  @tag :bare
  test "Wealth opens without any classification", %{conn: conn} do
    assert Classifications.list_classifications() == []
    world = base_world(name: "Bare World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "1000", days_ago(30))
    security = create_security!(name: "Lone Synthetic Fund")
    buy!(world, security, quantity: "1", price: "100", date: days_ago(30))
    put_quotes!(security, [{days_ago(30), "100"}])

    for address <- ["/portfolio", "/portfolio?tab=allocation"] do
      {:ok, view, _html} = live(conn, address)
      settle(view)
      assert has_element?(view, "#portfolio-overview")
    end

    {:ok, view, _html} = live(conn, "/portfolio?level=category")
    settle(view)
    assert legend_keys(view) == ["unclassified", "cash"]
  end

  # --- Sprint 28 S1 begin ---
  # User story (FR-56, board 02: „‹Name› (direkt)“):
  # As the operator reading a filtered category,
  # I want the band of the securities filed in the category itself named
  # „‹Name› (direkt)“ in my language,
  # so that I tell it from the category as a whole.
  #
  # Acceptance criteria:
  # - The API names a band of kind direct by the category's plain name; the
  #   screen names it "‹name› (direct)" in English and „‹Name› (direkt)“ in
  #   German, and gives it a class of its own.
  test "a direct band reads ‹name› (direkt)" do
    band = %{kind: :direct, name: "Aktien", key: "direct:1"}

    assert StackedChart.band_name(band) == "Aktien (direct)"

    assert Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
             StackedChart.band_name(band)
           end) ==
             "Aktien (direkt)"
  end

  # User story (FR-56, I29: „Gesamt“ should not be the default; plan D-6):
  # As a local portfolio maintainer switching Wealth's chart to its value,
  # I want the stack by categories first, not the single line,
  # so that I see what my wealth is made of without a further click, while
  # my agent's read without a level answers as it always has.
  #
  # Acceptance criteria:
  # - `/portfolio` still opens the TTWROR series (its bar at „Gesamt“ since
  #   FR-57, S4); switched to the value series, the bar's level is
  #   „Kategorien“ and the stack
  #   shows the API's bands of a read without `level` (period 1Y), the
  #   largest at the bottom.
  # - „Gesamt“ is a link to `level=total`, which opens the single value
  #   line, fresh too; „Kategorien“ links `level=category`, so a link
  #   handed over always opens the value series.
  # - A locale or privacy switch from the TTWROR series keeps the plain
  #   address, so it reopens the TTWROR series.
  test "Kategorien is the screen's default level; the API's stays as it was", %{conn: conn} do
    w = stack_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    settle(view)

    assert has_element?(view, "#performance-figure[data-chart-mode='ttwror']")
    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='total']")
    switches = attrs(view, "a[href*='locale=']", "href")
    assert switches != []
    refute Enum.any?(switches, &(&1 =~ "level"))

    view |> element("[data-role='chart-series'] button[phx-value-mode='value']") |> render_click()
    settle(view)

    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='category']")
    assert has_element?(view, "#performance-figure-stack[data-level='category']")

    data = api(conn, %{"period" => "1y"})
    assert data["level"] == "category"
    assert legend_keys(view) == data["bands"] |> Enum.map(& &1["key"]) |> Enum.reverse()
    assert "category:#{w.income.id}" in legend_keys(view)

    assert href(view, "[data-role='stack-level'] a[data-level='total']") ==
             "/portfolio?level=total"

    assert href(view, "[data-role='stack-level'] a[data-level='category']") ==
             "/portfolio?level=category"

    view |> element("[data-role='stack-level'] a[data-level='total']") |> render_click()
    assert_patch(view, "/portfolio?level=total")
    assert figure(view) =~ ~s(class="security-chart)

    {:ok, fresh, _html} = live(build_conn(), "/portfolio?level=total")
    settle(fresh)
    assert has_element?(fresh, "#performance-figure[data-chart-mode='value']")
    assert has_element?(fresh, "[data-role='stack-level'] a.is-active[data-level='total']")
  end

  # --- Sprint 28 S1 end ---

  # --- Sprint 28 S2 begin ---
  defp crumbs(view), do: text_of(view, "[data-role='stack-crumbs']")

  defp api_keys(data), do: data["bands"] |> Enum.map(& &1["key"]) |> Enum.reverse()

  # One day's figure, the window's last, on the screen and in the API's
  # answer for the same request: each legend row's value as its attribute
  # and as the shown amount.
  defp assert_same_figures(view, data) do
    assert legend_keys(view) == api_keys(data)
    assert attrs(view, "#stack-legend", "data-date") == [data["end_date"]]

    for band <- data["bands"] do
      row = "#stack-legend tr[data-band='#{band["key"]}']"
      assert attrs(view, row, "data-end-value") == [band["end_value"]]

      assert text_of(view, row <> " td[data-role='stack-value']") ==
               Format.money(Decimal.new(band["end_value"]))
    end
  end

  # User story (FR-56, I29; board 02 ① to ③):
  # As the operator looking into one category of my wealth,
  # I want a click on its band or its legend row to filter the stack to it
  # while the level stays, and a breadcrumb that leads up one level at a
  # time,
  # so that I walk down my tree and back without losing the level I read.
  #
  # Acceptance criteria:
  # - At „Kategorien“ a click on the band „Income“ patches to
  #   `level=category&category=<Income>`: the level stays, the stack holds
  #   Income's sub-category „Dividends“ and „Income (direct)“, as the API
  #   answers `level=category&category_id=<Income>` for the same period, on
  #   the window's last day to the cent.
  # - The breadcrumb reads „All categories › Income“. „Dividends“ is a
  #   filter link again, „Income (direct)“ is not. Its click reads
  #   „All categories › Income › Dividends“, one band, its own, which opens
  #   nothing more.
  # - The breadcrumb's „Income“ leads one level up, „All categories“ to the
  #   unfiltered stack, each at the level shown.
  # - A level chosen with a filter keeps it: „Wertpapiere“ shows Income's
  #   securities as the API answers them; there no band is a filter, and
  #   „All categories“ leads to all securities. „Gesamt“ with the filter
  #   draws Income's own line, the API's band at `level=total`, a category
  #   in the legend's head.
  # - The address after each step, opened fresh, shows the same filter,
  #   level, breadcrumb and legend.
  test "a click on a band or legend row sets the filter and keeps the level; the breadcrumb leads up one level at a time",
       %{conn: conn} do
    w = stack_world()
    income = "/portfolio?level=category&category=#{w.income.id}"
    dividends = "/portfolio?level=category&category=#{w.dividends.id}"

    {:ok, view, _html} = live(conn, "/portfolio?level=category")
    settle(view)

    view
    |> element("#performance-figure-stack path[data-band='category:#{w.income.id}']")
    |> render_click()

    assert_patch(view, income)
    settle(view)

    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='category']")
    assert crumbs(view) == "All categories › Income"

    data = api(conn, %{"level" => "category", "category_id" => w.income.id, "period" => "1y"})
    assert_same_figures(view, data)
    assert legend_keys(view) == ["direct:#{w.income.id}", "category:#{w.dividends.id}"]

    assert text_of(view, "#stack-legend tr[data-band='direct:#{w.income.id}']") =~
             "Income (direct)"

    refute has_element?(view, "#stack-legend tr[data-band='direct:#{w.income.id}'] a")
    refute has_element?(view, "path[data-band='direct:#{w.income.id}'][phx-click]")

    view
    |> element("#stack-legend tr[data-band='category:#{w.dividends.id}'] a", "Dividends")
    |> render_click()

    assert_patch(view, dividends)
    settle(view)

    assert crumbs(view) == "All categories › Income › Dividends"

    data =
      api(conn, %{"level" => "category", "category_id" => w.dividends.id, "period" => "1y"})

    assert_same_figures(view, data)
    assert legend_keys(view) == ["category:#{w.dividends.id}"]
    refute has_element?(view, "#stack-legend a")
    refute has_element?(view, "#performance-figure-stack path[phx-click]")

    {:ok, fresh, _html} = live(build_conn(), dividends)
    settle(fresh)
    assert crumbs(fresh) == "All categories › Income › Dividends"
    assert has_element?(fresh, "[data-role='stack-level'] a.is-active[data-level='category']")
    assert legend_keys(fresh) == ["category:#{w.dividends.id}"]

    view |> element("[data-role='stack-crumbs'] a", "Income") |> render_click()
    assert_patch(view, income)
    settle(view)
    assert crumbs(view) == "All categories › Income"

    view |> element("[data-role='stack-level'] a[data-level='security']") |> render_click()
    assert_patch(view, "/portfolio?level=security&category=#{w.income.id}")
    settle(view)

    assert crumbs(view) == "All categories › Income"
    data = api(conn, %{"level" => "security", "category_id" => w.income.id, "period" => "1y"})
    assert_same_figures(view, data)
    refute has_element?(view, "#stack-legend a")
    refute has_element?(view, "#performance-figure-stack path[phx-click]")

    view |> element("[data-role='stack-level'] a[data-level='total']") |> render_click()
    assert_patch(view, "/portfolio?level=total&category=#{w.income.id}")
    settle(view)

    assert crumbs(view) == "All categories › Income"
    data = api(conn, %{"level" => "total", "category_id" => w.income.id, "period" => "1y"})
    assert_same_figures(view, data)
    assert legend_keys(view) == ["category:#{w.income.id}"]
    assert text_of(view, "#stack-legend th:first-child") == "Category"

    view |> element("[data-role='stack-level'] a[data-level='security']") |> render_click()
    settle(view)
    view |> element("[data-role='stack-crumbs'] a", "All categories") |> render_click()
    assert_patch(view, "/portfolio?level=security")
    settle(view)
    assert crumbs(view) == "All categories"
    assert "cash" in legend_keys(view)

    {:ok, fresh, _html} =
      live(build_conn(), "/portfolio?level=security&category=#{w.income.id}")

    settle(fresh)
    assert has_element?(fresh, "[data-role='stack-level'] a.is-active[data-level='security']")
    assert crumbs(fresh) == "All categories › Income"
    assert legend_keys(fresh) == ["security:#{w.beta.id}", "security:#{w.gamma.id}"]
  end

  # User story (FR-56, I29; board 02 ① and ④):
  # As the operator who wants to see what my tree files nowhere,
  # I want „Nicht zugeordnet“ to filter like a category, and cash and
  # „Sonstige“ to stay what they are,
  # so that I find the securities still missing a category.
  #
  # Acceptance criteria:
  # - At „Kategorien“ the unassigned band and its legend row are a filter:
  #   `category=unclassified`, the level kept, one band „Unassigned“ as the
  #   API answers `category_id=unclassified`; at „Wertpapiere“ its
  #   securities (Delta). The breadcrumb reads „All categories › Unassigned“.
  # - Cash is no filter, nor is „Other“ when more than eight bands merge.
  test "Unassigned is a filter; cash and Other are not", %{conn: conn} do
    w = stack_world()

    {:ok, view, _html} = live(conn, "/portfolio?level=category")
    settle(view)

    refute has_element?(view, "#performance-figure-stack path[data-band='cash'][phx-click]")
    refute has_element?(view, "#stack-legend tr[data-band='cash'] a")
    assert has_element?(view, "#stack-legend tr[data-band='unclassified'] a")

    view
    |> element("#performance-figure-stack path[data-band='unclassified']")
    |> render_click()

    assert_patch(view, "/portfolio?level=category&category=unclassified")
    settle(view)

    assert crumbs(view) == "All categories › Unassigned"

    assert_same_figures(
      view,
      api(conn, %{"level" => "category", "category_id" => "unclassified", "period" => "1y"})
    )

    assert legend_keys(view) == ["unclassified"]
    refute has_element?(view, "#stack-legend a")

    view |> element("[data-role='stack-level'] a[data-level='security']") |> render_click()
    assert_patch(view, "/portfolio?level=security&category=unclassified")
    settle(view)
    assert legend_keys(view) == ["security:#{w.delta.id}"]
    assert crumbs(view) == "All categories › Unassigned"

    nine_world()
    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Nine Tree"})

    for k <- 1..9 do
      security = Enum.find(Portfolixir.Catalog.list_securities(), &(&1.name == "Position #{k}"))
      assign!(security, tree, category!(tree, "Bucket #{k}"))
    end

    {:ok, nine, _html} = live(conn, "/portfolio?level=category&tree=#{tree.id}")
    settle(nine)
    assert "other" in legend_keys(nine)
    refute has_element?(nine, "#stack-legend tr[data-band='other'] a")
    refute has_element?(nine, "#performance-figure-stack path[data-band='other'][phx-click]")
  end

  # User story (FR-56; plan D-6, board 02 ②):
  # As the operator reading a filtered category,
  # I want its sub-categories in the palette's colours in order of size and
  # „‹Name› (direkt)“ last,
  # so that the filtered stack reads like a drilled one and the direct
  # securities never take the first colour.
  #
  # Acceptance criteria:
  # - Filtered to Income, whose direct securities (Beta, Epsilon: 2,400)
  #   are worth more than its sub-category Dividends (1,050), Dividends
  #   takes the palette's first colour and „Income (direct)“ the next, the
  #   last one in use.
  test "a filter's sub-categories take the palette in order, (direct) the last colour",
       %{conn: conn} do
    w = stack_world()
    epsilon = create_security!(name: "Epsilon Synthetic AB")
    buy!(w.world, epsilon, quantity: "10", price: "100", date: days_ago(500))
    put_quotes!(epsilon, [{days_ago(500), "100"}, {today(), "150"}])
    assign!(epsilon, w.tree, w.income)

    {:ok, view, _html} = live(conn, "/portfolio?level=category&category=#{w.income.id}")
    settle(view)

    assert legend_keys(view) == ["category:#{w.dividends.id}", "direct:#{w.income.id}"]

    fill = fn key ->
      view |> attrs("#performance-figure-stack path[data-band='#{key}']", "fill") |> Enum.uniq()
    end

    assert fill.("category:#{w.dividends.id}") == [Enum.at(@palette, 0)]
    assert fill.("direct:#{w.income.id}") == [Enum.at(@palette, 1)]
  end

  # -- #1426: a band that changes sign -----------------------------------------------

  # Deposit 1,500 and buy Alpha for 1,000 (cash 500); 50 days ago buy Beta
  # for 800 before the money that pays it (cash −300 for two days), then
  # deposit 800 (cash 500 again). Every booking lies inside the 1Y window.
  defp sign_world do
    world = base_world(name: "Sign World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "1500", days_ago(100))
    alpha = create_security!(name: "Alpha Synthetic AG")
    buy!(world, alpha, quantity: "10", price: "100", date: days_ago(100))
    put_quotes!(alpha, [{days_ago(100), "100"}, {today(), "110"}])
    beta = create_security!(name: "Beta Synthetic SE")
    buy!(world, beta, quantity: "8", price: "100", date: days_ago(50))
    put_quotes!(beta, [{days_ago(50), "100"}])
    deposit!(world, "800", days_ago(48))
    %{world: world, alpha: alpha, beta: beta}
  end

  # Each drawn area of the stack as {key, part, [{upper_y, lower_y}]}, one
  # pair per drawn day, read from the SVG the component emits: a path's
  # first `points` vertices are its upper edge left to right, the rest its
  # lower edge right to left.
  defp polygons(view) do
    [points] = attrs(view, "#performance-figure-stack svg", "data-points")
    points = String.to_integer(points)

    view
    |> doc()
    |> Floki.find("#performance-figure-stack path.stack-band")
    |> Enum.map(fn path ->
      [d] = Floki.attribute(path, "d")
      [key] = Floki.attribute(path, "data-band")
      part = path |> Floki.attribute("data-part") |> List.first("positive")

      ys =
        ~r/[ML]\s*(-?[\d.]+),(-?[\d.]+)/
        |> Regex.scan(d)
        |> Enum.map(fn [_, _x, y] -> String.to_float(y) end)

      {upper, lower} = Enum.split(ys, points)
      {key, part, Enum.zip(upper, Enum.reverse(lower))}
    end)
  end

  # Two areas cross when one lies above the other on one day and below it
  # on another (screen y grows downwards), or when they overlap on a day;
  # touching is neither.
  defp crossings(polygons) do
    pairs =
      for {a, ia} <- Enum.with_index(polygons),
          {b, ib} <- Enum.with_index(polygons),
          ia < ib,
          do: {a, b}

    for {{ka, pa, da}, {kb, pb, db}} <- pairs,
        relations = Enum.zip_with(da, db, &relation/2),
        :overlap in relations or (:above in relations and :below in relations),
        do: {{ka, pa}, {kb, pb}}
  end

  defp relation({ua, la}, {ub, lb}) do
    cond do
      la <= ub + 0.01 and ua < lb - 0.01 and la - ua > 0.01 -> :above
      lb <= ua + 0.01 and ub < la - 0.01 and lb - ub > 0.01 -> :below
      la <= ub + 0.01 or lb <= ua + 0.01 -> :touch
      true -> :overlap
    end
  end

  # User story (#1426; board 02 ⑤ and ⑥):
  # As the operator whose cash account was overdrawn for two days (a buy
  # booked before the money that pays it),
  # I want the cash band drawn next to the zero line, its negative part as
  # a separate, lighter area under it,
  # so that the stack does not read as a crash of every position between.
  #
  # Acceptance criteria:
  # - At „Wertpapiere“, with the cash negative on two days of the window,
  #   no two drawn areas cross or overlap on any day, read from the SVG the
  #   page emits.
  # - The cash band, which changes sign, is drawn first: its positive part
  #   rests on the zero line on every day and its negative part hangs from
  #   it, a separate path (`data-part="negative"`) with the lighter class;
  #   the zero line is drawn.
  # - The legend reads like the stack, the top band first: the drawn order
  #   reversed, so the cash band, drawn first at the zero line, is its last
  #   row (the closing act's design critic, D1), its rows the API's bands.
  test "a band that changes sign sits next to the zero line and crosses no other band",
       %{conn: conn} do
    sign_world()

    {:ok, view, _html} = live(conn, "/portfolio?level=security")
    settle(view)

    data = api(conn, %{"level" => "security", "period" => "1y"})
    assert Enum.sort(legend_keys(view)) == Enum.sort(api_keys(data))

    drawn =
      view |> attrs("#performance-figure-stack path.stack-band", "data-band") |> Enum.dedup()

    assert legend_keys(view) == Enum.reverse(drawn)
    assert List.last(legend_keys(view)) == "cash"
    cash = Enum.find(data["bands"], &(&1["key"] == "cash"))
    assert Enum.count(cash["values"], &Decimal.negative?(Decimal.new(&1))) == 2

    shapes = polygons(view)
    assert crossings(shapes) == []

    assert [{"cash", "positive", positive}, {"cash", "negative", negative}] =
             Enum.filter(shapes, fn {key, _part, _days} -> key == "cash" end)

    assert has_element?(
             view,
             "path.stack-band--negative[data-band='cash'][data-part='negative']"
           )

    [zero] = attrs(view, "#performance-figure-stack line.chart-zeroline", "y1")
    zero = String.to_float(zero)

    assert Enum.all?(positive, fn {_upper, lower} -> abs(lower - zero) < 0.01 end)
    assert Enum.all?(negative, fn {upper, _lower} -> abs(upper - zero) < 0.01 end)
    assert Enum.count(negative, fn {upper, lower} -> lower - upper > 0.01 end) == 2

    assert view |> attrs("#performance-figure-stack path.stack-band", "data-band") |> hd() ==
             "cash"
  end

  # User story (board 02 ⑥ and 06 ②; the closing act's design critic, D2):
  # As the operator reading a stack that reaches below zero,
  # I want the zero line labelled and the axis in round steps, in money and
  # in the privacy mode's percent,
  # so that I read a band's height without dividing an odd range by four.
  #
  # Acceptance criteria:
  # - With the cash overdrawn for two days, at „Wertpapiere“ and
  #   „Kategorien“, the value mode's ticks are equal steps of 1, 2, 2.5 or 5
  #   times a power of ten, every tick a multiple of the step, „0“ among
  #   them and on the zero line.
  # - In the privacy mode the same holds in whole percents, „0%“ among
  #   them and on the zero line.
  test "the stack's axis reads round steps with 0 among them, in money and in percent",
       %{conn: conn} do
    sign_world()

    for address <- ["/portfolio?level=security", "/portfolio?level=category"] do
      {:ok, plain, _html} = live(conn, address)
      settle(plain)
      {:ok, view, _html} = live(masked(conn), address)
      settle(view)

      [zero] = attrs(plain, "#performance-figure-stack line.chart-zeroline", "y1")
      zero = String.to_float(zero)

      for {mode, parse} <- [{plain, &tick_value/1}, {view, &tick_percent/1}] do
        shown = ticks(mode, parse)
        assert_round_ticks(Enum.map(shown, &elem(&1, 0)), address)
        {_zero, y} = Enum.find(shown, &(elem(&1, 0) == 0)) || flunk("#{address}: no 0 tick")
        assert abs(y - zero) < 0.01, address
      end

      assert "0" in tick_texts(plain)
      assert "0%" in tick_texts(view)
    end
  end

  # -- #1366's lines: the basis behind its ⓘ ---------------------------------------

  # User story (#1366, 2026-11-08; amendment D-A4, board 07 ① to ③; I1):
  # As the operator reading the stacked chart,
  # I want one short basis line under it and the method behind its ⓘ,
  # so that the chart is not followed by five open sentences.
  #
  # Acceptance criteria:
  # - Under the stack one line reads what it shows, the window and when it
  #   was computed: „Market value per category of “Strategy” · ‹start› –
  #   ‹end› · computed ‹as of›“, the API's dates and as-of; the section's
  #   own window line is not repeated.
  # - The line ends in the section's ⓘ (`data-role="section-info"`), which
  #   holds the method: the currency, the change without flows, the order,
  #   what a click does.
  # - Filtered, the line names the filter.
  test "the stack's basis is one line, its method behind the ⓘ at its end", %{conn: conn} do
    w = stack_world()

    {:ok, view, _html} = live(conn, "/portfolio?level=category")
    settle(view)

    data = api(conn, %{"level" => "category", "period" => "1y"})
    {:ok, as_of, _offset} = DateTime.from_iso8601(data["as_of"])

    assert text_of(view, "[data-role='stack-basis'] [data-role='stack-basis-line']") ==
             "Market value per category of “Strategy” · " <>
               Format.date(Date.from_iso8601!(data["start_date"])) <>
               " – " <>
               Format.date(Date.from_iso8601!(data["end_date"])) <>
               " · computed " <> Format.utc_instant(as_of)

    refute has_element?(view, "[data-role='performance-basis']")

    tip = text_of(view, "[data-role='stack-basis'] [data-role='section-info'] [role='tooltip']")
    assert tip =~ "in EUR"
    assert tip =~ "Change without deposits and withdrawals."
    assert tip =~ "The largest band at the bottom"
    assert tip =~ "A click on a category filters the stack to it"

    {:ok, filtered, _html} = live(conn, "/portfolio?level=security&category=#{w.income.id}")
    settle(filtered)

    assert text_of(filtered, "[data-role='stack-basis-line']") =~
             "Market value per security of “Income”"
  end

  # User story (FR-56; a stale link):
  # As the operator following a link to a filter whose category was
  # deleted since,
  # I want the same level without the filter,
  # so that the page never shows a stack its address does not name.
  #
  # Acceptance criteria:
  # - `/portfolio?level=security&category=<a deleted id>` replaces the
  #   address once with `/portfolio?level=security` and shows all
  #   securities; a `category` that is no id filters nothing.
  test "a link to a filter that is gone keeps its level without the filter", %{conn: conn} do
    w = stack_world()

    {:ok, gone} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: w.tree.id,
        name: "Gone"
      })

    {:ok, _} = Classifications.delete_category(Actor.owner_ui(), gone)

    {:ok, view, _html} = live(conn, "/portfolio?level=security&category=#{gone.id}")
    settle(view)
    assert_patch(view, "/portfolio?level=security")
    settle(view)
    assert "cash" in legend_keys(view)
    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='security']")

    {:ok, view, _html} = live(conn, "/portfolio?level=security&category=abc")
    settle(view)
    assert crumbs(view) == "All categories"
    assert "cash" in legend_keys(view)
  end

  # --- Sprint 28 S2 end ---

  # --- Sprint 28 S4 begin ---
  # FR-57 (I28; board 03): the TTWROR series keeps the level bar and the
  # filter and draws one line per band, each band's own TTWROR (S3's
  # `scale=ttwror`), the view's or the filter's line bold.
  #
  # The synthetic world: the stack world's tree, but Gamma (Dividends,
  # under Income) is bought 100 days ago, inside the 1Y window, so its band
  # starts late; Alpha's quote moves inside the window.
  defp lines_world do
    world = base_world(name: "Lines World", cash_name: "Giro", depot_name: "Depot")
    d0 = days_ago(500)
    deposit!(world, "20000", d0)

    held =
      for {name, quantity, price, bought, quotes} <- [
            {"Alpha Synthetic AG", "10", "100", d0,
             [{d0, "100"}, {days_ago(200), "110"}, {today(), "120"}]},
            {"Beta Synthetic SE", "20", "50", d0, [{d0, "50"}, {today(), "45"}]},
            {"Gamma Synthetic NV", "5", "200", days_ago(100),
             [{days_ago(100), "200"}, {days_ago(50), "190"}, {today(), "210"}]},
            {"Delta Synthetic plc", "4", "100", d0, [{d0, "100"}, {today(), "110"}]}
          ],
          into: %{} do
        security = create_security!(name: name)
        buy!(world, security, quantity: quantity, price: price, date: bought)
        put_quotes!(security, quotes)
        {name |> String.split() |> hd() |> String.downcase() |> key(), security}
      end

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})
    growth = category!(tree, "Growth")
    income = category!(tree, "Income")
    dividends = category!(tree, "Dividends", parent_id: income.id)
    assign!(held.alpha, tree, growth)
    assign!(held.beta, tree, income)
    assign!(held.gamma, tree, dividends)

    Map.merge(held, %{tree: tree, growth: growth, income: income, dividends: dividends})
  end

  defp lines_api(conn, query), do: api(conn, Map.put(query, "scale", "ttwror"))

  defp line_keys(view), do: attrs(view, "#lines-legend tbody tr", "data-band")

  # The lines on the screen and in the API's answer for the same request:
  # the legend's rows, the bold line (the API's parent) first, then the
  # lines in the API's order; each row's TTWROR the API's, the line's last
  # point; each line drawn, the parent's bold.
  defp assert_same_lines(view, data) do
    parent = data["parent"]
    lines = Enum.reject(data["bands"], &(&1["key"] == parent["key"]))
    assert line_keys(view) == [parent["key"] | Enum.map(lines, & &1["key"])]
    assert attrs(view, "#lines-legend", "data-date") == [data["end_date"]]

    for line <- [parent | lines] do
      row = "#lines-legend tr[data-band='#{line["key"]}']"
      assert text_of(view, row <> " td[data-role='line-ttwror']") == signed_pct(line["ttwror"])
      assert line["ttwror"] == line["returns"] |> Enum.reject(&is_nil/1) |> List.last()

      assert has_element?(
               view,
               "#performance-figure-lines g.stack-line[data-band='#{line["key"]}']"
             )
    end

    assert attrs(view, "#performance-figure-lines g.stack-line--bold", "data-band") == [
             parent["key"]
           ]

    assert has_element?(view, "#lines-legend tbody tr:first-child.lines-legend__parent")
    refute has_element?(view, "#lines-legend [data-role='stack-value']")
    assert attrs(view, "[data-end-value]", "data-end-value") == []
  end

  # The bands whose line starts after the window's first day, by the API.
  defp late_keys(data) do
    for line <- [data["parent"] | data["bands"]],
        index = Enum.find_index(line["returns"], &(not is_nil(&1))),
        index > 0,
        uniq: true,
        do: line["key"]
  end

  defp start_dots(view),
    do:
      view
      |> attrs("#performance-figure-lines circle.stack-line-start", "data-band")
      |> Enum.uniq()

  # User story (FR-57, I28; board 03 ① and ②):
  # As the operator comparing the parts of my wealth by their return,
  # I want the „% (TTWROR)“ series to keep the level and the filter I chose
  # and to draw one line per band, the view's line bold among them,
  # so that I see which part earned what, not only how the whole did.
  #
  # Acceptance criteria:
  # - From the value stack at „Kategorien“, „% (TTWROR)“ keeps the level
  #   and patches `scale=ttwror`: one line per category (no cash, no
  #   unassigned rest), the view's own line bold; the legend lists the bold
  #   line first, „View (bold)“, then the lines, each with its TTWROR only,
  #   the API's `scale=ttwror` answer for the same request and period on the
  #   window's last day; no amount, no share.
  # - A click on a line filters as in the value mode and keeps the level:
  #   Income's sub-category and „Income (direct)“ as lines, „Income“ bold,
  #   the breadcrumb „All categories › Income“; Dividends, bought inside
  #   the window, starts at 0 % with a dot, the others do not.
  # - A legend row's link filters too; „Wertpapiere“ keeps the filter
  #   (Gamma's line starts with a dot); „Gesamt“ with the filter draws the
  #   filter's line alone, bold.
  # - „Wert“ keeps the level and the filter (`scale` leaves the address);
  #   „Gesamt“ without a filter in TTWROR is today's single line.
  # - Each address, opened fresh, shows the same lines.
  test "the TTWROR series keeps the level and the filter and draws one line per band, the view's bold",
       %{conn: conn} do
    w = lines_world()
    income = "/portfolio?level=category&category=#{w.income.id}&scale=ttwror"

    {:ok, view, _html} = live(conn, "/portfolio?level=category")
    settle(view)

    view
    |> element("[data-role='chart-series'] button[phx-value-mode='ttwror']")
    |> render_click()

    assert_patch(view, "/portfolio?level=category&scale=ttwror")
    settle(view)

    assert has_element?(
             view,
             "[data-role='chart-series'] button.is-active[phx-value-mode='ttwror']"
           )

    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='category']")
    assert has_element?(view, "#performance-figure-lines[data-level='category']")
    refute has_element?(view, "#performance-figure-stack")
    refute has_element?(view, "#performance-figure")

    data = lines_api(conn, %{"level" => "category", "period" => "1y"})
    assert_same_lines(view, data)

    assert line_keys(view) == [
             "total",
             "category:#{w.income.id}",
             "category:#{w.growth.id}"
           ]

    assert text_of(view, "#lines-legend tr[data-band='total'] .lines-legend__name") ==
             "View (bold)"

    assert start_dots(view) == []

    # A click on Income's line filters, the level kept.
    view
    |> element("#performance-figure-lines g.stack-line[data-band='category:#{w.income.id}']")
    |> render_click()

    assert_patch(view, income)
    settle(view)

    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='category']")
    assert crumbs(view) == "All categories › Income"

    data =
      lines_api(conn, %{"level" => "category", "category_id" => w.income.id, "period" => "1y"})

    assert_same_lines(view, data)

    assert line_keys(view) == [
             "category:#{w.income.id}",
             "category:#{w.dividends.id}",
             "direct:#{w.income.id}"
           ]

    assert text_of(view, "#lines-legend tr:first-child .lines-legend__name") == "Income (bold)"
    assert late_keys(data) == ["category:#{w.dividends.id}"]
    assert start_dots(view) == ["category:#{w.dividends.id}"]

    {:ok, fresh, _html} = live(build_conn(), income)
    settle(fresh)
    assert_same_lines(fresh, data)
    assert crumbs(fresh) == "All categories › Income"

    # The legend row's link filters as the line does.
    view
    |> element("#lines-legend tr[data-band='category:#{w.dividends.id}'] a", "Dividends")
    |> render_click()

    assert_patch(view, "/portfolio?level=category&category=#{w.dividends.id}&scale=ttwror")
    settle(view)
    assert crumbs(view) == "All categories › Income › Dividends"

    data =
      lines_api(conn, %{
        "level" => "category",
        "category_id" => w.dividends.id,
        "period" => "1y"
      })

    assert_same_lines(view, data)
    assert line_keys(view) == ["category:#{w.dividends.id}"]

    view |> element("[data-role='stack-crumbs'] a", "Income") |> render_click()
    assert_patch(view, income)
    settle(view)

    view |> element("[data-role='stack-level'] a[data-level='security']") |> render_click()
    assert_patch(view, "/portfolio?level=security&category=#{w.income.id}&scale=ttwror")
    settle(view)

    data =
      lines_api(conn, %{"level" => "security", "category_id" => w.income.id, "period" => "1y"})

    assert_same_lines(view, data)
    assert start_dots(view) == ["security:#{w.gamma.id}"]
    refute has_element?(view, "#performance-figure-lines g.stack-line[phx-click]")

    view |> element("[data-role='stack-level'] a[data-level='total']") |> render_click()
    assert_patch(view, "/portfolio?level=total&category=#{w.income.id}&scale=ttwror")
    settle(view)

    data =
      lines_api(conn, %{"level" => "total", "category_id" => w.income.id, "period" => "1y"})

    assert_same_lines(view, data)
    assert line_keys(view) == ["category:#{w.income.id}"]

    # „Wert“ keeps the level and the filter.
    view
    |> element("[data-role='chart-series'] button[phx-value-mode='value']")
    |> render_click()

    assert_patch(view, "/portfolio?level=total&category=#{w.income.id}")
    settle(view)
    assert has_element?(view, "#performance-figure-stack[data-level='total']")
    assert crumbs(view) == "All categories › Income"

    view |> element("[data-role='stack-crumbs'] a", "All categories") |> render_click()
    assert_patch(view, "/portfolio?level=total")
    settle(view)

    view
    |> element("[data-role='chart-series'] button[phx-value-mode='ttwror']")
    |> render_click()

    assert_patch(view, "/portfolio?level=total&scale=ttwror")
    settle(view)
    assert has_element?(view, "#performance-figure[data-chart-mode='ttwror']")
    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='total']")
    refute has_element?(view, "#performance-figure-lines")
  end

  # User story (FR-57, I28; S1's default kept):
  # As the operator opening Wealth,
  # I want the page to open on the TTWROR line I know, with the level bar
  # above it, and the value series still to open at „Kategorien“,
  # so that the bar adds a choice and takes nothing away.
  #
  # Acceptance criteria:
  # - `/portfolio` shows the bar in the TTWROR series at „Gesamt“, and the
  #   figure under it is byte for byte the one at `level=total&scale=ttwror`.
  # - From there „Wert“ opens the value series at „Kategorien“
  #   (`level=category`), and „Kategorien“ in the TTWROR series links
  #   `level=category&scale=ttwror`.
  # - A period on the address is kept by every switch: from
  #   `level=category&period=3y` „% (TTWROR)“ patches
  #   `level=category&scale=ttwror&period=3y`, the API's lines for 3Y.
  test "Wealth opens on the TTWROR line at Gesamt; a switch keeps the period", %{conn: conn} do
    lines_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    settle(view)

    assert has_element?(view, "[data-role='stack-bar']")
    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='total']")

    assert href(view, "[data-role='stack-level'] a[data-level='category']") ==
             "/portfolio?level=category&scale=ttwror"

    bare = figure(view)

    {:ok, total, _html} = live(build_conn(), "/portfolio?level=total&scale=ttwror")
    settle(total)
    assert figure(total) == bare

    view
    |> element("[data-role='chart-series'] button[phx-value-mode='value']")
    |> render_click()

    assert_patch(view, "/portfolio?level=category")

    {:ok, view, _html} = live(conn, "/portfolio?level=category&period=3y")
    settle(view)

    view
    |> element("[data-role='chart-series'] button[phx-value-mode='ttwror']")
    |> render_click()

    assert_patch(view, "/portfolio?level=category&scale=ttwror&period=3y")
    settle(view)
    assert_same_lines(view, lines_api(conn, %{"level" => "category", "period" => "3y"}))
  end

  # User story (FR-57; #1366's pattern, amendment D-A4; I1):
  # As the operator reading the TTWROR lines,
  # I want one line saying what they show and the method behind its ⓘ,
  # so that I know how a band's return is measured before I compare two.
  #
  # Acceptance criteria:
  # - Under the lines one line reads „TTWROR per category of “Strategy” ·
  #   ‹start› – ‹end› · computed ‹as of›“; filtered, it names the filter.
  # - The ⓘ says, in short sentences: each band's own time-weighted
  #   return; its flows are its buys, sells and deliveries, an inflow at
  #   the day's start and an outflow at its end; a price return, dividends
  #   no flow; a late band starts at 0 % at a dot; a day opening at or
  #   below zero (a short) adds no return (ML1); at most eight lines by
  #   value, no cash and no unassigned rest; which line is bold, and that
  #   the view's line counts every flow at the day's start while the bands
  #   count an outflow at its end (ML2); a click filters.
  # - In German the legend's first row reads „Ansicht (fett)“ and the
  #   column „TTWROR“.
  test "the TTWROR lines' basis is one line, the method behind its ⓘ", %{conn: conn} do
    w = lines_world()

    {:ok, view, _html} = live(conn, "/portfolio?level=category&scale=ttwror")
    settle(view)

    data = lines_api(conn, %{"level" => "category", "period" => "1y"})
    {:ok, as_of, _offset} = DateTime.from_iso8601(data["as_of"])

    assert text_of(view, "[data-role='stack-basis'] [data-role='stack-basis-line']") ==
             "TTWROR per category of “Strategy” · " <>
               Format.date(Date.from_iso8601!(data["start_date"])) <>
               " – " <>
               Format.date(Date.from_iso8601!(data["end_date"])) <>
               " · computed " <> Format.utc_instant(as_of)

    refute has_element?(view, "[data-role='performance-basis']")

    tip = text_of(view, "[data-role='stack-basis'] [data-role='section-info'] [role='tooltip']")
    assert tip =~ "Each band's own time-weighted return over the window"
    assert tip =~ "buys, sells and deliveries"
    assert tip =~ "an inflow at the day's start, an outflow at its end"
    assert tip =~ "Dividends and interest are no flow"
    assert tip =~ "starts at 0 % on that day, at a dot"
    assert tip =~ "A day on which a band opens at or below zero, a short, adds no return"
    assert tip =~ "At most eight lines"
    assert tip =~ "The bold line is the view's own TTWROR"

    assert tip =~
             "The view's line counts every flow at the day's start; the bands count an outflow at the day's end, so a band that holds the whole view can differ from it on a day with a sale."

    assert tip =~ "A click on a category filters the lines to it"

    {:ok, filtered, _html} =
      live(conn, "/portfolio?level=security&category=#{w.income.id}&scale=ttwror")

    settle(filtered)

    assert text_of(filtered, "[data-role='stack-basis-line']") =~
             "TTWROR per security of “Income”"

    assert text_of(filtered, "[data-role='section-info'] [role='tooltip']") =~
             "The bold line is “Income”, the filter's"

    german = put_preference_cookie(conn, "portfolixir_locale", "de")
    {:ok, de, _html} = live(german, "/portfolio?level=category&scale=ttwror")
    settle(de)
    assert text_of(de, "#lines-legend tr:first-child .lines-legend__name") == "Ansicht (fett)"
    assert text_of(de, "#lines-legend th:last-child") == "TTWROR"
  end

  # User story (FR-57; I22, DESIGN.md's privacy rule: percentages stay):
  # As the operator sharing my screen with the privacy mode on,
  # I want the TTWROR lines exactly as without the mode,
  # so that I can compare the parts' returns while no amount shows.
  #
  # Acceptance criteria:
  # - At „Kategorien“, filtered and not, and at „Wertpapiere“, the lines,
  #   the dots, the axis and the legend's percentages are the same with
  #   the mode on as without it.
  # - No amount in the section's text, a line's tooltip or an attribute.
  test "in the privacy mode the TTWROR lines stay as they are and name no amount", %{conn: conn} do
    w = lines_world()

    for address <- [
          "/portfolio?level=category&scale=ttwror",
          "/portfolio?level=category&category=#{w.income.id}&scale=ttwror",
          "/portfolio?level=security&scale=ttwror"
        ] do
      {:ok, plain, _html} = live(conn, address)
      settle(plain)
      {:ok, view, _html} = live(masked(conn), address)
      settle(view)

      picture = fn v -> v |> element("#performance-figure-lines svg") |> render() end
      assert picture.(view) == picture.(plain), address
      assert text_of(view, "#lines-legend") == text_of(plain, "#lines-legend"), address

      section = text_of(view, "#portfolio-performance")
      titles = view |> doc() |> Floki.find("#performance-figure-lines title") |> Floki.text()

      for shown <- [section, titles] do
        assert Regex.scan(~r/\d{1,3}(?:,\d{3})*\.\d{2}(?!\d|%)/u, shown) == [],
               "#{address} names an amount: #{shown}"
      end

      assert attrs(view, "[data-end-value]", "data-end-value") == []
    end
  end

  # --- Sprint 28 S4 end ---
end
