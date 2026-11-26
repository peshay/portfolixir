defmodule PortfolixirWeb.DashboardAllocationWidgetsTest do
  # Sprint 32 W2 (I57; ADR-0062's amendment of 2026-11-25, points 3, 5 and
  # 7; plan D-7; planning board ux-design-2026-11-25-sprint32/02 ②): the
  # sections of Wealth's tab „Allokation & Ziele“ as section widgets, and
  # the starter „Allokation & Ziele“. Each widget's module draws its section
  # on Wealth and on a dashboard, so one code path draws both, and every
  # figure it draws is compared with its route's for the same scope and
  # period. The rebalancing hints stay display-only (ADR-0023): nothing is
  # stored and no order is made; the targets are edited on their page,
  # linked. Synthetic data only.
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Starters
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Repo
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

  defp dashboard!(items) do
    layout =
      items
      |> Enum.with_index()
      |> Enum.map(fn {{kind, size}, index} ->
        %{"kind" => kind, "size" => size, "col" => 1, "row" => 1 + index * 4}
      end)

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Allokation",
        "layout" => layout
      })

    dashboard
  end

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    render_async(view)
    view
  end

  defp doc(view), do: view |> render() |> Floki.parse_document!()

  # A depot with cash, two securities filed into two categories of an own
  # tree and one filed nowhere; a plan putting 40 % on each category, so
  # the plan allocates 80 % and the drift measures against that portion
  # (ADR-0040 §2). A second tree exists, unplanned.
  defp world do
    today = Clock.today()
    world = base_world(name: "Allokation")
    deposit!(world, "10000", Date.add(today, -200))

    gold = create_security!(name: "Corvid Physical Test ETC", ticker: "CPT")
    kestrel = create_security!(name: "Kestrel Industrial Test NV", ticker: "KIT")
    loose = create_security!(name: "Loose Test Fund", ticker: "LTF")

    buy!(world, gold, quantity: "5", price: "1000", date: Date.add(today, -190))
    buy!(world, kestrel, quantity: "30", price: "100", date: Date.add(today, -190))
    buy!(world, loose, quantity: "2", price: "50", date: Date.add(today, -190))
    put_quotes!(gold, [{Date.add(today, -190), "1000"}, {today, "1100"}])
    put_quotes!(kestrel, [{Date.add(today, -190), "100"}, {today, "90"}])
    put_quotes!(loose, [{Date.add(today, -190), "50"}, {today, "55"}])

    owner = Actor.owner_ui()
    {:ok, tree} = Classifications.create_classification(owner, %{name: "Strategy"})

    {:ok, commodities} =
      Classifications.create_category(owner, %{classification_id: tree.id, name: "Commodities"})

    {:ok, growth} =
      Classifications.create_category(owner, %{classification_id: tree.id, name: "Growth"})

    {:ok, _} = Classifications.assign_security(owner, gold.id, tree.id, commodities.id)
    {:ok, _} = Classifications.assign_security(owner, kestrel.id, tree.id, growth.id)

    {:ok, _} =
      Targets.set_targets(owner, world.portfolio.id, tree.id, [
        %{category_id: commodities.id, target_weight: "0.4"},
        %{category_id: growth.id, target_weight: "0.4"}
      ])

    {:ok, other} = Classifications.create_classification(owner, %{name: "Regions"})

    {:ok, europe} =
      Classifications.create_category(owner, %{classification_id: other.id, name: "Europe"})

    {:ok, _} = Classifications.assign_security(owner, kestrel.id, other.id, europe.id)

    Map.merge(world, %{
      tree: tree,
      other: other,
      gold: gold,
      kestrel: kestrel,
      commodities: commodities,
      growth: growth
    })
  end

  describe "the registry" do
    # User story:
    # As the operator, or the agent I run, composing a dashboard,
    # I want the two sections of „Allokation & Ziele“ registered as kinds,
    # so that a layout can name them and the API and MCP catalogue lists
    # them with the reads they draw.
    #
    # Acceptance criteria:
    # - `summary_line` („Kennzahlen-Zeile“; never W1's `wealth_key_figures`
    #   nor W4's `key_figures`) and `allocation` („Allokation“) are
    #   registered, group allocation, in the size „Zeile“ alone, with the
    #   routes they draw; the line follows the dashboard's period by the
    #   performance rule, the allocation takes none; both take a view.
    # - GET /api/v1/widgets names both with their routes.
    test "names the summary line and the allocation with their sizes and routes" do
      {:ok, line} = Widgets.fetch("summary_line")
      {:ok, allocation} = Widgets.fetch("allocation")
      {:ok, performance} = Widgets.fetch("performance")

      assert line.sizes == ~w(row)
      assert line.group == "allocation"
      assert line.scope == :view
      assert line.period == performance.period
      assert "GET /api/v1/valuation" in line.source.routes
      assert "GET /api/v1/performance" in line.source.routes

      assert allocation.sizes == ~w(row)
      assert allocation.group == "allocation"
      assert allocation.scope == :view
      assert allocation.period == :none
      assert allocation.source.routes == ["GET /api/v1/portfolios/:portfolio_id/allocation"]

      Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
        assert Widgets.title("summary_line") == "Kennzahlen-Zeile"
        assert Widgets.title("allocation") == "Allokation"
      end)

      catalogue = api("/api/v1/widgets")["widgets"]

      for key <- ~w(summary_line allocation) do
        assert Enum.any?(catalogue, &(&1["key"] == key)), key
      end
    end
  end

  describe "Kennzahlen-Zeile (summary_line)" do
    # User story:
    # As the operator who keeps „Allokation & Ziele“ as a dashboard,
    # I want its summary line as a widget,
    # so that the total, the cash quote and the period's TTWROR head my
    # allocation as they head Wealth's tab, each figure the API's.
    #
    # Acceptance criteria:
    # - The total incl. cash and the cash quote equal GET
    #   /api/v1/valuation's; the TTWROR equals GET
    #   /api/v1/performance?period=1y's, under the dashboard's 1J.
    # - Wealth's tab draws the same line with the same module: its figures
    #   read the same.
    # - The line links to all key figures on Holdings.
    test "draws the total, the cash quote and the period's TTWROR as the API and Wealth do",
         %{conn: conn} do
      world()
      dashboard!([{"summary_line", "row"}])
      valuation = api("/api/v1/valuation")
      perf = api("/api/v1/performance?period=1y")

      widget = conn |> open("/") |> doc() |> Floki.find("#dashboard-summary-line")
      figures = widget |> Floki.find("[data-role='kpi-summary'] strong") |> Enum.map(&text/1)

      assert figures == [
               Format.money(Decimal.new(valuation["total_with_cash"])) <>
                 " " <> valuation["base_currency"],
               Format.percent(Decimal.new(valuation["cash_quote"])) <> "%",
               Format.signed_percent(Decimal.new(perf["ttwror"])) <> "%"
             ]

      assert text(Floki.find(widget, "[data-role='kpi-summary']")) =~ "TTWROR 1Y"
      assert [_] = Floki.find(widget, "a[href='/portfolio']")

      wealth = conn |> open("/portfolio?tab=allocation") |> doc()

      assert wealth |> Floki.find("[data-role='kpi-summary'] strong") |> Enum.map(&text/1) ==
               figures
    end
  end

  describe "Allokation (allocation)" do
    # User story:
    # As the operator who steers the allocation from a dashboard,
    # I want Wealth's section „Allokation“ as a widget — tree or positions,
    # the sunburst, the drift table with the display-only hints, the
    # classification choice —
    # so that it reads as Wealth's tab reads, each figure the API's.
    #
    # Acceptance criteria:
    # - On the default tree (the own one), each category row of the drift
    #   table shows the name, value, actual and target weight and the drift
    #   value GET /api/v1/portfolios/:id/allocation?classification_id=
    #   answers; Wealth's tab shows the same rows with the same module.
    # - The sunburst and its legend are drawn; the plan line names the
    #   tree; the targets are edited on the Classifications page, linked.
    # - „Positionen“ switches to the flat worklist; a category's toggle
    #   opens its securities with the display-only hint („Kauf ≈ … Stück“);
    #   the drift chip filters as the API's min_drift= does; picking the
    #   second tree reads its allocation. Nothing is stored: the stored
    #   layout is unchanged after every click.
    test "draws the drift table, the sunburst and the controls as Wealth and the API do",
         %{conn: conn} do
      w = world()
      dashboard = dashboard!([{"allocation", "row"}])

      allocation =
        api("/api/v1/portfolios/#{w.portfolio.id}/allocation?classification_id=#{w.tree.id}")

      view = open(conn, "/")
      widget = view |> doc() |> Floki.find("#dashboard-allocation")
      rows = Floki.find(widget, "table.drift-table tbody tr")

      for category <- allocation["categories"] do
        row = Enum.find(rows, &(text(&1) =~ category["name"]))
        assert row, category["name"]
        cells = row |> Floki.find("td") |> Enum.map(&text/1)

        assert Enum.drop(cells, 1) == [
                 Format.money(Decimal.new(category["market_value"])),
                 Format.percent(Decimal.new(category["actual_weight"])) <> "%",
                 Format.percent(Decimal.new(category["target_weight"])) <> "%",
                 Format.money(Decimal.new(category["drift_value"])) <>
                   " " <> allocation["base_currency"]
               ]
      end

      assert [_] = Floki.find(widget, "svg.sunburst")
      assert Floki.find(widget, ".donut-legend li") != []
      assert text(Floki.find(widget, "[data-role='allocation-basis']")) =~ "Strategy"
      assert [_] = Floki.find(widget, "a[href='/portfolio?tab=allocation']")

      wealth = conn |> open("/portfolio?tab=allocation") |> doc()

      assert wealth |> Floki.find("#portfolio-allocation table.drift-table tbody tr") |> text() ==
               text(rows)

      # The controls, each on this widget alone; nothing is stored.
      view
      |> element("#dashboard-allocation [data-role='toggle-all-categories']")
      |> render_click()

      opened = view |> doc() |> Floki.find("#dashboard-allocation")
      assert Floki.find(opened, "[data-role='allocation-position']") != []
      assert text(Floki.find(opened, "[data-role='rebalance-hint']")) =~ "≈"

      view
      |> element("#dashboard-allocation [data-role='allocation-mode-flat']")
      |> render_click()

      flat = view |> doc() |> Floki.find("#dashboard-allocation [data-role='flat-positions']")
      assert text(flat) =~ "Kestrel Industrial Test NV"

      view
      |> element("#dashboard-allocation [data-role='allocation-mode-tree']")
      |> render_click()

      view
      |> element("#dashboard-allocation [data-role='drift-chip']", "5")
      |> render_click()

      filtered =
        api(
          "/api/v1/portfolios/#{w.portfolio.id}/allocation?classification_id=#{w.tree.id}&min_drift=0.05"
        )

      assert text(
               Floki.find(doc(view), "#dashboard-allocation [data-role='drift-filter-summary']")
             ) =~
               "Showing #{length(filtered["categories"])} of #{filtered["categories_total"]}"

      view
      |> form("#dashboard-allocation-allocation-classification-form", %{
        "classification_id" => w.other.id
      })
      |> render_change()

      render_async(view)
      other = view |> doc() |> Floki.find("#dashboard-allocation")
      assert text(Floki.find(other, "table.drift-table")) =~ "Europe"
      refute text(Floki.find(other, "table.drift-table")) =~ "Commodities"

      assert Repo.get!(Dashboard, dashboard.id).layout == dashboard.layout
      assert Repo.get!(Dashboard, dashboard.id).lock_version == dashboard.lock_version
    end

    # User story (Sprint 32 closing act, PR 2, coverage):
    # As the operator who works through the allocation on a dashboard,
    # I want a category's toggle, a slice of the sunburst and the
    # worklist's column heads to act on this widget as they do on Wealth,
    # so that I can open a category, read a slice and rank the positions
    # without leaving the dashboard.
    #
    # Acceptance criteria:
    # - The toggle of „Growth“ opens its securities alone, each with the
    #   drift GET /api/v1/portfolios/:id/allocation answers for it; a
    #   second toggle closes it again.
    # - A tap on a slice names it in the sunburst's centre; a tap on the
    #   centre brings the total back, the allocation's total_value.
    # - In „Positionen“ a column head sorts by it, a second tap the other
    #   way: „Wert“ starts with the largest market value, then the
    #   smallest; „Kategorie“ starts alphabetical.
    # - Nothing is stored.
    test "a category's toggle, a slice and the worklist's sort act on the widget",
         %{conn: conn} do
      w = world()
      dashboard = dashboard!([{"allocation", "row"}])

      allocation =
        api("/api/v1/portfolios/#{w.portfolio.id}/allocation?classification_id=#{w.tree.id}")

      growth = Enum.find(allocation["categories"], &(&1["name"] == "Growth"))
      view = open(conn, "/")
      widget = "#dashboard-allocation"

      toggle =
        "#{widget} button[data-role='toggle-positions'][phx-value-category-id='#{w.growth.id}']"

      view |> element(toggle) |> render_click()

      positions = view |> doc() |> Floki.find("#{widget} [data-role='allocation-position']")

      assert Enum.map(positions, &text(Floki.find(&1, "[data-role='position-name']"))) ==
               Enum.map(growth["positions"], & &1["security_name"])

      for {row, position} <- Enum.zip(positions, growth["positions"]) do
        assert text(row) =~
                 Format.money(Decimal.new(position["drift_value"])) <>
                   " " <> allocation["base_currency"]
      end

      view |> element(toggle) |> render_click()
      assert view |> doc() |> Floki.find("#{widget} [data-role='allocation-position']") == []

      centre = fn -> view |> doc() |> Floki.find("#{widget} [data-role='sunburst-centre']") end

      view
      |> element("#{widget} path.sunburst-seg[phx-value-name='Growth']")
      |> render_click()

      assert text(Floki.find(centre.(), ".sunburst-centre__label")) == "Growth"

      view |> element("#{widget} [data-role='sunburst-figure']") |> render_click()

      assert text(Floki.find(centre.(), ".sunburst-centre__value")) ==
               Format.money(Decimal.new(allocation["total_value"])) <>
                 " " <> allocation["base_currency"]

      view |> element("#{widget} [data-role='allocation-mode-flat']") |> render_click()

      names = fn ->
        view
        |> doc()
        |> Floki.find("#{widget} [data-role='flat-position'] [data-role='position-name']")
        |> Enum.map(&text/1)
      end

      by_value =
        allocation["categories"]
        |> Enum.flat_map(& &1["positions"])
        |> Kernel.++((allocation["unassigned"] || %{"positions" => []})["positions"])
        |> Enum.sort_by(&Decimal.new(&1["market_value"]), {:desc, Decimal})
        |> Enum.map(& &1["security_name"])

      view |> element("#{widget} [data-role='flat-sort-value']") |> render_click()
      assert names.() == by_value
      assert text(Floki.find(doc(view), "#{widget} [data-role='flat-sort-value']")) =~ "↓"

      view |> element("#{widget} [data-role='flat-sort-value']") |> render_click()
      assert names.() == Enum.reverse(by_value)
      assert text(Floki.find(doc(view), "#{widget} [data-role='flat-sort-value']")) =~ "↑"

      view |> element("#{widget} [data-role='flat-sort-category']") |> render_click()
      assert text(Floki.find(doc(view), "#{widget} [data-role='flat-sort-category']")) =~ "↑"

      assert Repo.get!(Dashboard, dashboard.id).lock_version == dashboard.lock_version
    end

    # User story (Sprint 32 closing act, PR 2, coverage):
    # As the operator whose position target outlived its filing,
    # I want the widget's unassigned row to open onto that position with
    # its stale target and drift, as the API answers them,
    # so that the target still counting there is never hidden.
    #
    # Acceptance criteria:
    # - Kestrel carries a position target in Growth and is then unassigned:
    #   the stale-target note names Growth; the unassigned row opens onto
    #   Kestrel with the target weight and the drift value of GET
    #   /api/v1/portfolios/:id/allocation's unassigned position, and its
    #   display-only hint.
    test "the unassigned row opens onto a stale position target as the API answers it",
         %{conn: conn} do
      w = world()
      owner = Actor.owner_ui()

      {:ok, _} =
        Targets.set_targets(owner, w.portfolio.id, w.tree.id, [
          %{"category_id" => w.growth.id, "security_id" => w.kestrel.id, "target_weight" => "0.2"}
        ])

      {:ok, _} = Classifications.unassign_security(owner, w.kestrel.id, w.tree.id)
      dashboard!([{"allocation", "row"}])

      allocation =
        api("/api/v1/portfolios/#{w.portfolio.id}/allocation?classification_id=#{w.tree.id}")

      position =
        Enum.find(allocation["unassigned"]["positions"], &(&1["security_id"] == w.kestrel.id))

      assert position["stale"]
      view = open(conn, "/")
      widget = "#dashboard-allocation"

      assert text(Floki.find(doc(view), "#{widget} [data-role='stale-target-note']")) =~ "Growth"

      view
      |> element(
        "#{widget} button[data-role='toggle-positions'][phx-value-category-id='unassigned']"
      )
      |> render_click()

      row =
        view
        |> doc()
        |> Floki.find("#{widget} [data-role='allocation-position']")
        |> Enum.find(&(text(&1) =~ "Kestrel Industrial Test NV"))

      cells = row |> Floki.find("td") |> Enum.map(&text/1)
      assert Enum.at(cells, 3) == Format.percent(Decimal.new(position["target_weight"])) <> "%"

      assert Enum.at(cells, 4) =~
               Format.money(Decimal.new(position["drift_value"])) <>
                 " " <> allocation["base_currency"]

      assert text(Floki.find(row, "[data-role='rebalance-hint']")) =~ "≈"
    end

    # User story (Sprint 32 closing act, PR 2, coverage):
    # As the operator who reads the worklist on the currency tree,
    # I want the cash counted inside its currency's bucket and not twice,
    # so that the worklist's rows sum to the allocation the API answers.
    #
    # Acceptance criteria:
    # - On the built-in tree „Currency“ GET
    #   /api/v1/portfolios/:id/allocation answers the cash distributed; the
    #   widget's „Positionen“ then lists the securities without a cash row,
    #   while on „Strategy“ it lists one.
    test "on the currency tree the worklist draws no separate cash row", %{conn: conn} do
      w = world()
      Classifications.ensure_builtins()
      currency = Enum.find(Classifications.list_classifications(), &(&1.key == "currency"))
      dashboard!([{"allocation", "row"}])

      allocation =
        api("/api/v1/portfolios/#{w.portfolio.id}/allocation?classification_id=#{currency.id}")

      assert allocation["cash"]["distributed"]
      view = open(conn, "/")

      view
      |> element("#dashboard-allocation [data-role='allocation-mode-flat']")
      |> render_click()

      flat = "#dashboard-allocation [data-role='flat-positions']"
      assert [_] = Floki.find(doc(view), flat <> " [data-role='flat-cash']")

      view
      |> form("#dashboard-allocation-allocation-classification-form", %{
        "classification_id" => currency.id
      })
      |> render_change()

      render_async(view)
      assert Floki.find(doc(view), flat <> " [data-role='flat-cash']") == []
      assert Floki.find(doc(view), flat <> " [data-role='flat-position']") != []
    end

    # User story (Sprint 32 closing act, PR 2, coverage):
    # As the operator who picked a tree that was deleted since,
    # I want the widget to read the default tree rather than fail,
    # so that the allocation stays on the dashboard.
    #
    # Acceptance criteria:
    # - The page still offers „Regions“ after it was deleted; picking it
    #   reads the default tree „Strategy“, its categories the API's.
    test "a tree deleted since the page read it reads the default tree", %{conn: conn} do
      w = world()
      dashboard!([{"allocation", "row"}])
      view = open(conn, "/")
      {:ok, _} = Classifications.delete_classification(Actor.owner_ui(), w.other)

      view
      |> form("#dashboard-allocation-allocation-classification-form", %{
        "classification_id" => w.other.id
      })
      |> render_change()

      render_async(view)
      table = view |> doc() |> Floki.find("#dashboard-allocation table.drift-table") |> text()

      allocation =
        api("/api/v1/portfolios/#{w.portfolio.id}/allocation?classification_id=#{w.tree.id}")

      for category <- allocation["categories"], do: assert(table =~ category["name"])
      refute table =~ "Europe"
    end

    # User story (Sprint 32 closing act, PR 2, coverage):
    # As the operator whose dashboard reads one view,
    # I want the allocation's and the summary line's way out to keep it,
    # so that Wealth opens on the view the widget showed.
    #
    # Acceptance criteria:
    # - On a dashboard scoped to a view, „Ganze Ansicht“ of the allocation
    #   opens /portfolio?tab=allocation&view=<id>, and the summary line's
    #   link /portfolio?view=<id>; the basis line names the view.
    test "on a view, the way to Wealth keeps the view", %{conn: conn} do
      world()

      {:ok, scope} =
        Buckets.create_view(Actor.owner_ui(), %{name: "Alles drin", include_all: true})

      {:ok, _} =
        Dashboards.create_dashboard(Actor.owner_ui(), %{
          "name" => "Ansicht",
          "view_id" => scope.id,
          "layout" => [
            %{"kind" => "summary_line", "size" => "row", "col" => 1, "row" => 1},
            %{"kind" => "allocation", "size" => "row", "col" => 1, "row" => 5}
          ]
        })

      page = conn |> open("/") |> doc()
      query = URI.encode_query([{"tab", "allocation"}, {"view", scope.id}])

      assert [_] = Floki.find(page, "#dashboard-allocation a[href='/portfolio?#{query}']")

      assert [_] =
               Floki.find(page, "#dashboard-summary-line a[href='/portfolio?view=#{scope.id}']")

      assert text(Floki.find(page, "#dashboard-allocation [data-role='allocation-basis']")) =~
               "Alles drin"
    end

    # User story:
    # As the operator whose instance holds no classification yet,
    # I want the widget to say so and lead to where a tree is made,
    # so that it never waits for an allocation that cannot come.
    test "without a classification it says so and links to the Classifications page",
         %{conn: conn} do
      world = base_world(name: "Leer")
      deposit!(world, "100", Date.add(Clock.today(), -10))
      dashboard!([{"allocation", "row"}])

      widget = conn |> open("/") |> doc() |> Floki.find("#dashboard-allocation")

      assert text(Floki.find(widget, "[data-role='allocation-no-tree']")) =~
               "No classification yet"

      assert [_] = Floki.find(widget, "a[href='/classifications']")
    end
  end

  describe "the starter „Allokation & Ziele“" do
    # User story:
    # As the operator after the update,
    # I want „Allokation & Ziele“ among my dashboards, stored once,
    # so that the tab is there as a dashboard I can change.
    #
    # Acceptance criteria:
    # - The template `allocation_targets` is a starter and lists exactly
    #   board 02 ②'s widgets in order: the summary line, the allocation,
    #   each in the size „Zeile“, one under the other.
    # - The boot stores it once with its template key; its title is
    #   „Allokation & Ziele“ in German.
    test "lists exactly the board's widgets in order and is stored once" do
      assert {:ok, template} = Templates.fetch("allocation_targets")
      assert template.starter
      refute template.asks_scope

      assert Enum.map(template.layout, &{&1["kind"], &1["size"], &1["col"], &1["row"]}) == [
               {"summary_line", "row", 1, 1},
               {"allocation", "row", 1, 2}
             ]

      assert "allocation_targets" in Enum.map(Templates.starters(), & &1.key)

      Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
        assert Templates.title("allocation_targets") == "Allokation & Ziele"
      end)

      assert {:ok, %{stored: stored}} = Starters.seed()
      assert "allocation_targets" in stored
      assert {:ok, %{stored: []}} = Starters.seed()

      assert [stored_one] =
               Dashboards.list_dashboards()
               |> Enum.filter(&(&1.template_key == "allocation_targets"))

      assert Enum.map(stored_one.layout, & &1["kind"]) == ~w(summary_line allocation)
    end
  end
end
