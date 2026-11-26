defmodule PortfolixirWeb.DashboardSnapshotWidgetsTest do
  # Sprint 32 W3 (I57; ADR-0062's amendment of 2026-11-25, points 3, 5 and
  # 7; plan D-7; planning board ux-design-2026-11-25-sprint32/02 ②): the
  # sections of Wealth's tab „Snapshots“ as section widgets, and the
  # starter „Snapshots“. Each widget's module draws its section on the tab
  # and on a dashboard, so one code path draws both, and every figure it
  # draws is compared with its route's. A snapshot is made and deleted on
  # the tab, linked from the widget („Neuer Snapshot →“). Synthetic data
  # only.
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Starters
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios.Snapshots
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
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Snapshots", "layout" => layout})

    dashboard
  end

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    render_async(view)
    view
  end

  defp doc(view), do: view |> render() |> Floki.parse_document!()

  # A depot bought into 200 days back, its quotes since, and two
  # snapshots: 150 days back („Vor dem Umbau“) and 60 („Nach dem Umbau“).
  defp world do
    today = Clock.today()
    world = base_world(name: "Snapshots")
    deposit!(world, "10000", Date.add(today, -200))
    alpha = create_security!(name: "Alpha Werke", ticker: "ALW")
    beta = create_security!(name: "Beta Linien", ticker: "BTL")
    buy!(world, alpha, quantity: "40", price: "100", date: Date.add(today, -190))
    buy!(world, beta, quantity: "20", price: "50", date: Date.add(today, -100))

    put_quotes!(alpha, [
      {Date.add(today, -190), "100"},
      {Date.add(today, -150), "104"},
      {Date.add(today, -60), "98"},
      {today, "112"}
    ])

    put_quotes!(beta, [{Date.add(today, -100), "50"}, {Date.add(today, -60), "55"}, {today, "51"}])

    owner = Actor.owner_ui()

    {:ok, before} =
      Snapshots.create_snapshot(owner, %{name: "Vor dem Umbau", as_of: Date.add(today, -150)})

    {:ok, later} =
      Snapshots.create_snapshot(owner, %{name: "Nach dem Umbau", as_of: Date.add(today, -60)})

    Map.merge(world, %{before: before, later: later})
  end

  describe "the registry" do
    # User story:
    # As the operator, or the agent I run, composing a dashboard,
    # I want the two sections of „Snapshots“ registered as kinds,
    # so that a layout can name them and the catalogue lists the reads
    # they draw.
    #
    # Acceptance criteria:
    # - `snapshot_comparison` („Vergleich gegen einen Snapshot“) and
    #   `snapshot_list` („Snapshot-Liste“) are registered, group
    #   performance, in the size „Zeile“ alone, with the routes they draw;
    #   neither takes a period or a view (a snapshot carries its own).
    # - GET /api/v1/widgets names both.
    test "names the comparison and the list with their sizes and routes" do
      {:ok, comparison} = Widgets.fetch("snapshot_comparison")
      {:ok, list} = Widgets.fetch("snapshot_list")

      for kind <- [comparison, list] do
        assert kind.sizes == ~w(row)
        assert kind.group == "performance"
        assert kind.period == :none
        assert kind.scope == :none
        assert "GET /api/v1/snapshots" in kind.source.routes
      end

      assert "GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison" in comparison.source.routes

      Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
        assert Widgets.title("snapshot_comparison") == "Vergleich gegen einen Snapshot"
        assert Widgets.title("snapshot_list") == "Snapshot-Liste"
      end)

      catalogue = api("/api/v1/widgets")["widgets"]

      for key <- ~w(snapshot_comparison snapshot_list) do
        assert Enum.any?(catalogue, &(&1["key"] == key)), key
      end
    end
  end

  describe "Vergleich gegen einen Snapshot and Snapshot-Liste" do
    # User story:
    # As the operator who keeps the tab „Snapshots“ as a dashboard,
    # I want the comparison and the list as widgets,
    # so that the newest snapshot's comparison stands on my dashboard as
    # the tab shows it, and a name in the list picks another, each figure
    # the API's.
    #
    # Acceptance criteria:
    # - The comparison compares the newest snapshot: its real TTWROR and
    #   the frozen return equal GET
    #   /api/v1/portfolios/:id/snapshots/:id/comparison's; the footer
    #   names the snapshot; the tab draws the same figures with the same
    #   module; „Ganze Ansicht“ opens the tab on that snapshot.
    # - The list's rows are GET /api/v1/snapshots' in its order, each
    #   name, scope and as-of date as the tab lists them; the newest is
    #   marked „In comparison“. It carries no row menu and no form:
    #   „Neuer Snapshot →“ leads to the tab, which keeps them.
    # - A click on the older name makes the comparison compare it, its
    #   figures the route's for that snapshot; nothing is stored.
    test "compare the newest snapshot, list every one, and a name picks the one compared",
         %{conn: conn} do
      w = world()
      dashboard = dashboard!([{"snapshot_comparison", "row"}, {"snapshot_list", "row"}])
      pid = w.portfolio.id

      newest = api("/api/v1/portfolios/#{pid}/snapshots/#{w.later.id}/comparison")
      view = open(conn, "/")
      page = doc(view)
      widget = Floki.find(page, "#dashboard-snapshot-comparison")

      assert text(Floki.find(widget, "[data-role='kpi-real'] strong")) ==
               Format.signed_percent(Decimal.new(newest["real_ttwror"])) <> "%"

      assert text(Floki.find(widget, "[data-role='kpi-frozen'] strong")) ==
               Format.signed_percent(Decimal.new(newest["snapshot_return"])) <> "%"

      assert text(Floki.find(widget, "[data-role='comparison-scope']")) =~ "Nach dem Umbau"
      assert [_] = Floki.find(widget, "a[href='/snapshots?snapshot=#{w.later.id}']")

      tab = conn |> open("/snapshots") |> doc()

      for role <- ~w(kpi-real kpi-frozen comparison-basis comparison-table) do
        assert text(Floki.find(tab, "[data-role='snapshot-comparison'] [data-role='#{role}']")) ==
                 text(Floki.find(widget, "[data-role='#{role}']")),
               role
      end

      list = Floki.find(page, "#dashboard-snapshot-list")
      rows = Floki.find(list, "[data-role='snapshot-row']")
      listed = api("/api/v1/snapshots")["snapshots"]

      assert Enum.map(rows, &text(Floki.find(&1, "[data-role='snapshot-select']"))) ==
               Enum.map(listed, & &1["name"])

      for {row, snapshot} <- Enum.zip(rows, listed) do
        assert text(row) =~ Format.date(Date.from_iso8601!(snapshot["as_of"]))
      end

      tab_rows = Floki.find(tab, "[data-role='snapshot-row']")

      assert Enum.map(tab_rows, &(&1 |> Floki.find("td") |> Enum.take(3) |> text())) ==
               Enum.map(rows, &(&1 |> Floki.find("td") |> text()))

      assert text(Floki.find(hd(rows), "[data-role='in-comparison']")) == "In comparison"
      assert Floki.find(list, "[data-role='snapshot-kebab'], .row-actions, form") == []
      assert [_] = Floki.find(list, "a[href='/snapshots'][data-role='snapshot-new']")

      view
      |> element("#dashboard-snapshot-list [data-role='snapshot-select']", "Vor dem Umbau")
      |> render_click()

      render_async(view)
      older = api("/api/v1/portfolios/#{pid}/snapshots/#{w.before.id}/comparison")
      picked = view |> doc() |> Floki.find("#dashboard-snapshot-comparison")

      assert text(Floki.find(picked, "[data-role='kpi-real'] strong")) ==
               Format.signed_percent(Decimal.new(older["real_ttwror"])) <> "%"

      assert text(Floki.find(picked, "[data-role='comparison-scope']")) =~ "Vor dem Umbau"

      marked = view |> doc() |> Floki.find("#dashboard-snapshot-list [data-role='in-comparison']")
      assert length(marked) == 1

      assert Repo.get!(Dashboard, dashboard.id).lock_version == dashboard.lock_version
      assert length(Snapshots.list_snapshots()) == 2
    end

    # User story (Sprint 32 closing act, PR 2, coverage):
    # As the operator who froze one view,
    # I want the comparison to name that view beside the snapshot,
    # so that I read whose holdings were frozen.
    #
    # Acceptance criteria:
    # - The newest snapshot is frozen on the view „Alles drin“: the
    #   comparison's scope line names it and the snapshot, and its real
    #   TTWROR is GET /api/v1/portfolios/:id/snapshots/:id/comparison's.
    test "a snapshot of a view names the view beside the snapshot", %{conn: conn} do
      w = world()

      {:ok, scope} =
        Buckets.create_view(Actor.owner_ui(), %{name: "Alles drin", include_all: true})

      {:ok, frozen} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{
          name: "Ansicht eingefroren",
          as_of: Date.add(Clock.today(), -30),
          view_id: scope.id
        })

      dashboard!([{"snapshot_comparison", "row"}])
      comparison = api("/api/v1/portfolios/#{w.portfolio.id}/snapshots/#{frozen.id}/comparison")
      widget = conn |> open("/") |> doc() |> Floki.find("#dashboard-snapshot-comparison")
      scope_line = text(Floki.find(widget, "[data-role='comparison-scope']"))

      assert scope_line =~ "Ansicht eingefroren"
      assert scope_line =~ "Alles drin"

      assert text(Floki.find(widget, "[data-role='kpi-real'] strong")) ==
               Format.signed_percent(Decimal.new(comparison["real_ttwror"])) <> "%"
    end

    # User story:
    # As the operator who has made no snapshot yet,
    # I want both widgets to say so and lead to the tab's form,
    # so that neither waits for a comparison that cannot come.
    test "without a snapshot both say so and the list leads to the form", %{conn: conn} do
      world = base_world(name: "Leer")
      deposit!(world, "100", Date.add(Clock.today(), -10))
      dashboard!([{"snapshot_comparison", "row"}, {"snapshot_list", "row"}])

      page = conn |> open("/") |> doc()

      assert text(Floki.find(page, "#dashboard-snapshot-comparison")) =~ "No snapshots yet."
      assert text(Floki.find(page, "#dashboard-snapshot-list")) =~ "No snapshots yet."
      assert [_] = Floki.find(page, "#dashboard-snapshot-list a[href='/snapshots']")
    end
  end

  # --- S32 W5 begin ---
  describe "the comparison's table (#1366, R-047)" do
    # User story (Wealth's polish list #1366, line R-047):
    # As the operator reading the comparison's table on a German page,
    # I want its two return columns printed by the rule every other figure
    # uses,
    # so that „+1,2 %“ reads as the card beside it reads, never „1.2%“.
    #
    # Acceptance criteria:
    # - On /snapshots in German, each row's frozen and real return is
    #   `Format.signed_percent(indexed − 1) <> "%"` of the API's series for
    #   that date (a comma, a sign, no „-0.0%“); a point without a value
    #   reads „—“.
    # - The dashboard's widget draws the same cells.
    test "prints both returns by Format, as the API's series gives them", %{conn: conn} do
      w = world()
      dashboard!([{"snapshot_comparison", "row"}])

      series =
        api("/api/v1/portfolios/#{w.portfolio.id}/snapshots/#{w.later.id}/comparison")["series"]

      by_date = Map.new(series, &{&1["date"], &1})

      cell = fn
        nil -> "—"
        indexed -> Format.signed_percent(Decimal.sub(Decimal.new(indexed), 1), "de") <> "%"
      end

      for path <- ["/snapshots?locale=de", "/?locale=de"] do
        rows =
          conn
          |> open(path)
          |> doc()
          |> Floki.find("[data-role='comparison-table'] tbody tr")

        assert rows != [], path

        for row <- rows do
          [date, _value, frozen, real] = row |> Floki.find("td") |> Enum.map(&text/1)
          point = Enum.find(series, &(Format.date(Date.from_iso8601!(&1["date"]), "de") == date))
          assert point, "#{path}: no point for #{date} in #{map_size(by_date)}"

          assert frozen == cell.(point["snapshot_indexed"]),
                 "#{path} #{date}: #{frozen} drawn, #{cell.(point["snapshot_indexed"])} the rule"

          assert real == cell.(point["real_indexed"]),
                 "#{path} #{date}: #{real} drawn, #{cell.(point["real_indexed"])} the rule"
        end
      end
    end
  end

  describe "the result note's × on Snapshots (#1366, R-157)" do
    # User story (Wealth's polish list #1366, line R-157):
    # As the operator who read a problem note on Snapshots,
    # I want its × to close it,
    # so that the page does not keep a note I dismissed.
    #
    # Acceptance criteria:
    # - A comparison that cannot be read (an address naming no snapshot)
    #   shows its problem note; its × removes it, and the page stays.
    test "the × closes the problem note", %{conn: conn} do
      w = world()
      view = open(conn, "/snapshots?snapshot=#{w.later.id + 1_000}")

      note = "#snapshots-action-result-alert [data-role='result-dismiss']"
      assert has_element?(view, note)
      view |> element(note) |> render_click()
      refute has_element?(view, note)
      assert has_element?(view, "[data-role='snapshot-list']")
    end
  end

  describe "the comparison's „Nicht enthalten“ names (Sprint 32 W5)" do
    # User story (Sprint 32 W4's finding; the gallery's unstable picture):
    # As the operator reading which positions the comparison leaves out,
    # I want them named in one order every time,
    # so that the note reads the same on every visit, as Wealth's unvalued
    # note does.
    #
    # Acceptance criteria:
    # - With 40 positions without a quote at the as-of date (more than a
    #   small map keeps in order), GET …/comparison answers
    #   gaps.unvalued_securities by security id, the rule Wealth's
    #   valuation lists its positions by; the note names them in that
    #   order.
    test "names the left-out positions by security id", %{conn: conn} do
      today = Clock.today()
      world = base_world(name: "Lücken")
      deposit!(world, "100000", Date.add(today, -100))

      for n <- 1..40 do
        security = create_security!(name: "Unquoted #{String.pad_leading("#{41 - n}", 2, "0")}")
        buy!(world, security, quantity: "1", price: "10", date: Date.add(today, -90))
      end

      {:ok, snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Viele", as_of: Date.add(today, -60)})

      gaps =
        api("/api/v1/portfolios/#{world.portfolio.id}/snapshots/#{snapshot.id}/comparison")[
          "gaps"
        ]["unvalued_securities"]

      assert length(gaps) == 40
      ids = Enum.map(gaps, & &1["security_id"])
      assert ids == Enum.sort(ids)

      note = conn |> open("/snapshots") |> doc() |> Floki.find("[data-role='comparison-gaps']")
      names = Enum.map(gaps, & &1["security_name"])
      assert text(note) =~ Enum.join(Enum.take(names, 3), ", ")
    end
  end

  # --- S32 W5 end ---

  describe "the starter „Snapshots“" do
    # User story:
    # As the operator after the update,
    # I want „Snapshots“ among my dashboards, stored once,
    # so that the tab is there as a dashboard I can change.
    #
    # Acceptance criteria:
    # - The template `snapshots` is a starter and lists exactly board 02
    #   ②'s widgets in order: the comparison, the list, each in the size
    #   „Zeile“, one under the other.
    # - The boot stores it once with its template key.
    test "lists exactly the board's widgets in order and is stored once" do
      assert {:ok, template} = Templates.fetch("snapshots")
      assert template.starter
      refute template.asks_scope

      assert Enum.map(template.layout, &{&1["kind"], &1["size"], &1["col"], &1["row"]}) == [
               {"snapshot_comparison", "row", 1, 1},
               {"snapshot_list", "row", 1, 2}
             ]

      Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
        assert Templates.title("snapshots") == "Snapshots"
      end)

      assert {:ok, %{stored: stored}} = Starters.seed()
      assert "snapshots" in stored
      assert {:ok, %{stored: []}} = Starters.seed()

      assert [stored_one] =
               Enum.filter(Dashboards.list_dashboards(), &(&1.template_key == "snapshots"))

      assert Enum.map(stored_one.layout, & &1["kind"]) == ~w(snapshot_comparison snapshot_list)
    end
  end
end
