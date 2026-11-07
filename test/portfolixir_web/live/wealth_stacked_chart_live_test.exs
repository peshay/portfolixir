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

  # User story (I23, FR-53; board 01 A):
  # As a local portfolio maintainer,
  # I want a click on a category's band or on its legend row to show that
  # category alone, stacked by its securities, and a breadcrumb back,
  # so that I can look inside one level without losing my way.
  #
  # Acceptance criteria:
  # - A click on the category's band patches to `level=security` with the
  #   category; the stack then holds its securities, as the API answers
  #   `level=security&category_id=…` for the same period, and no cash.
  # - The breadcrumb reads "All categories › Income"; its link leads back
  #   to the category stack.
  # - The legend row's link opens the same view as the band.
  # - Cash, unclassified and other bands open nothing.
  test "a click on a band or its legend row opens the category by its securities; the breadcrumb leads back",
       %{conn: conn} do
    w = stack_world()
    drilled = "/portfolio?level=security&category=#{w.income.id}"

    {:ok, view, _html} = live(conn, "/portfolio?level=category")
    settle(view)

    refute has_element?(view, "#performance-figure-stack path[data-band='cash'][phx-click]")
    refute has_element?(view, "#stack-legend tr[data-band='unclassified'] a")

    view
    |> element("#performance-figure-stack path[data-band='category:#{w.income.id}']")
    |> render_click()

    assert_patch(view, drilled)
    settle(view)

    data =
      api(conn, %{"level" => "security", "category_id" => w.income.id, "period" => "1y"})

    assert legend_keys(view) == data["bands"] |> Enum.map(& &1["key"]) |> Enum.reverse()
    assert legend_keys(view) == ["security:#{w.beta.id}", "security:#{w.gamma.id}"]
    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='security']")
    assert text_of(view, "[data-role='stack-crumbs']") == "All categories › Income"

    view |> element("[data-role='stack-crumbs'] a", "All categories") |> render_click()
    assert_patch(view, "/portfolio?level=category")
    settle(view)
    assert length(legend_keys(view)) == 4

    view
    |> element("#stack-legend tr[data-band='category:#{w.income.id}'] a", "Income")
    |> render_click()

    assert_patch(view, drilled)
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
  # - The address after a drill, opened fresh, shows the same level, sort,
  #   category and legend order; no choice lives only in the page process.
  # - "Total" drops the stack's parameters again.
  test "the stack's state is on the address, and a link handed over reopens it", %{conn: conn} do
    w = stack_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    settle(view)

    refute has_element?(view, "[data-role='stack-bar']")
    view |> element("[data-role='chart-series'] button[phx-value-mode='value']") |> render_click()
    assert has_element?(view, "[data-role='stack-level'] a.is-active[data-level='total']")

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
      "/portfolio?level=security&tree=#{w.tree.id}&category=#{w.income.id}&sort=change"

    assert_patch(view, handed_over)
    settle(view)
    shown = legend_keys(view)

    {:ok, fresh, _html} = live(build_conn(), handed_over)
    settle(fresh)

    assert has_element?(
             fresh,
             "[data-role='chart-series'] button.is-active[phx-value-mode='value']"
           )

    assert has_element?(fresh, "[data-role='stack-level'] a.is-active[data-level='security']")
    assert has_element?(fresh, "[data-role='stack-sort'] a.is-active[data-sort='change']")
    assert text_of(fresh, "[data-role='stack-crumbs']") == "All categories › Income"
    assert legend_keys(fresh) == shown
    # Gamma +5 %, Beta −10 %: the larger change at the bottom.
    assert shown == ["security:#{w.beta.id}", "security:#{w.gamma.id}"]

    assert href(fresh, "[data-role='stack-crumbs'] a") ==
             "/portfolio?level=category&tree=#{w.tree.id}&sort=change"

    fresh |> element("[data-role='stack-level'] a[data-level='total']") |> render_click()
    assert_patch(fresh, "/portfolio")
  end

  # User story (I23, FR-53; plan D-4: "Gesamt is today's chart"):
  # As a local portfolio maintainer,
  # I want the level "Total" to be the value chart I know, unchanged,
  # so that the bar adds a choice and takes nothing away.
  #
  # Acceptance criteria:
  # - In the value series the bar stands above the chart with the level
  #   "Total" chosen and no classification or sort control.
  # - The figure under it is byte for byte the value chart without the bar's
  #   parameters, after a trip through the category stack and back too.
  # - The TTWROR series shows no bar.
  test "Total is today's value chart, unchanged", %{conn: conn} do
    stack_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    settle(view)
    view |> element("[data-role='chart-series'] button[phx-value-mode='value']") |> render_click()
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

    refute has_element?(view, "[data-role='stack-bar']")
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

  # User story (I23, FR-53; I22's privacy mode; plan D-8 carry-forward 2):
  # As the operator who shares the screen with the privacy mode on,
  # I want the stack drawn as a 100 % stack by itself and the legend to keep
  # share and change but no value,
  # so that the bands show my mix and never its size.
  #
  # Acceptance criteria:
  # - With the mode on, the category stack's axis reads 0 % to 100 % and
  #   the top band's upper edge lies on the plot's top on every drawn day.
  # - The legend has no value column and no value attribute; share and
  #   change stay. No band's tooltip and no text of the section names an
  #   amount, and no hidden figure is drawn as its stand-in text.
  # - The drilled category reads the same way.
  test "in the privacy mode the stack is a 100 % stack and names no amount", %{conn: conn} do
    w = stack_world()

    masked =
      conn
      |> put_preference_cookie("portfolixir_privacy", "on")

    for address <- [
          "/portfolio?level=category",
          "/portfolio?level=security&category=#{w.income.id}"
        ] do
      {:ok, view, _html} = live(masked, address)
      settle(view)

      assert has_element?(view, "#performance-figure-stack[data-scale='percent']")
      assert text_of(view, "#performance-figure-stack .chart-axis-y.is-top") == "100%"
      assert text_of(view, "#performance-figure-stack .chart-axis-y:not(.is-top)") =~ "0%"

      top = view |> legend_keys() |> hd()
      [d] = attrs(view, "path[data-band='#{top}']", "d")
      [points] = attrs(view, "#performance-figure-stack svg", "data-points")
      [plot_top] = attrs(view, "#performance-figure-stack svg", "data-plot-top")

      upper =
        ~r/[ML]\s*([\d.]+),([\d.]+)/
        |> Regex.scan(d)
        |> Enum.take(String.to_integer(points))
        |> Enum.map(fn [_, _x, y] -> y end)

      assert Enum.uniq(upper) == [plot_top]

      refute has_element?(view, "#stack-legend th", "Value")
      refute has_element?(view, "#stack-legend td[data-role='stack-value']")
      assert attrs(view, "[data-end-value]", "data-end-value") == []
      assert text_of(view, "#stack-legend td[data-role='stack-share']") =~ "%"

      section = text_of(view, "#portfolio-performance")
      titles = view |> doc() |> Floki.find("#performance-figure-stack title") |> Floki.text()

      for shown <- [section, titles] do
        assert Regex.scan(~r/\d{1,3}(?:,\d{3})*\.\d{2}(?!\d|%)/u, shown) == [],
               "#{address} names an amount: #{shown}"

        refute shown =~ PortfolixirWeb.PrivacyMode.text()
      end
    end
  end

  # User story (I23, FR-53; I22's privacy mode; the closing act's money
  # lens, M3):
  # As the operator sharing the screen with an overdrawn cash account,
  # I want the legend's shares in the privacy mode to read like the 100 %
  # stack drawn beside them,
  # so that a band that fills the picture does not read 300 %.
  #
  # Acceptance criteria:
  # - Deposit 100, buy 300: on the last day the security is 300 and the
  #   cash −200. With the privacy mode on, the stack fills 0 to 100 % with
  #   the security, and its legend share reads 100.0 %; the cash reads
  #   −66.7 %, its value over the day's positive bands, as it is drawn.
  # - The API's share keeps its net definition (the security "3", the cash
  #   "-2"), and its basis says a share can exceed 100 % or be negative when
  #   a band is negative.
  test "in the privacy mode the legend's share is taken on the stack's own basis", %{conn: conn} do
    world = base_world(name: "Overdrawn World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "100", days_ago(30))
    security = create_security!(name: "Alpha Synthetic AG")
    buy!(world, security, quantity: "3", price: "100", date: days_ago(30))
    put_quotes!(security, [{days_ago(30), "100"}])

    data = api(conn, %{"level" => "security", "period" => "1y"})
    shares = Map.new(data["bands"], &{&1["key"], &1["share"]})
    assert shares == %{"security:#{security.id}" => "3", "cash" => "-2"}
    assert data["computation_basis"]["assumptions"] =~ "can exceed 1 or be negative"

    masked = put_preference_cookie(conn, "portfolixir_privacy", "on")
    {:ok, view, _html} = live(masked, "/portfolio?level=security")
    settle(view)

    share = fn key ->
      text_of(view, "#stack-legend tr[data-band='#{key}'] td[data-role='stack-share']")
    end

    assert share.("security:#{security.id}") == Format.percent(Decimal.new(1)) <> "%"

    assert share.("cash") ==
             Format.percent(Decimal.div(Decimal.new(-200), Decimal.new(300))) <> "%"
  end

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
end
