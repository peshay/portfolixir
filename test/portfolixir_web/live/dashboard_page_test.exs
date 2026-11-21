defmodule PortfolixirWeb.DashboardPageTest do
  # Sprint 31 D3 (FR-60; ADR-0062 §2, §3, §4, §12; ADR-0022's amendment of
  # 2026-11-21, point 4; planning board ux-design-2026-11-21-sprint31/01 ①;
  # idea boards ux-design-2026-11-21-idea-i56 01, 03): the dashboard page
  # at `/`. A fresh instance shows the template „Überblick“ read-only and a
  # read stores nothing; „Anpassen“ copies it; stored dashboards open by
  # position or by id; every item is a widget in its frame, in reading
  # order, placed on the grid; an item's view overrides the dashboard's
  # scope, a dangling one reads the dashboard's and says so.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable` row 28); every module that creates
  # one joins this group.
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, sell!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  defp seed do
    world = base_world()

    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-10])
    put_quote!(security, Portfolixir.Clock.today(), "120")
    Map.put(world, :security, security)
  end

  defp stored_count, do: Repo.aggregate(Dashboard, :count)

  defp kinds(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("[data-role='dashboard-grid'] > [data-widget-kind]")
    |> Enum.map(fn node -> {hd(Floki.attribute(node, "data-widget-kind")), node} end)
  end

  # User story:
  # As the operator opening the app on a fresh instance,
  # I want the shipped template „Überblick“ shown read-only, with
  # „Anpassen“ to make it mine,
  # so that I see the dashboard at once and nothing is stored until I ask.
  #
  # Acceptance criteria:
  # - `/` on an empty dashboards table shows the template's title, the
  #   banner „Vorlage · mitgeliefert, nur lesend“ and „Anpassen“.
  # - A read never writes: after the static and the connected render and
  #   every background read, the table is still empty and the journal holds
  #   no dashboard entry.
  test "a fresh instance shows the template read-only and stores nothing", %{conn: conn} do
    seed()
    assert stored_count() == 0

    {:ok, view, html} = live(conn, "/?locale=de")
    render_async(view)

    assert html =~ "Überblick"
    assert has_element?(view, "#app-topbar-title", "Überblick")
    assert has_element?(view, "[data-role='template-banner']", "Vorlage")
    assert has_element?(view, "[data-role='template-banner']", "mitgeliefert, nur lesend")
    assert has_element?(view, "[data-role='customize']", "Anpassen")

    assert stored_count() == 0
    assert Journal.list_entries(resource_type: "dashboard") == []
  end

  # User story:
  # As the operator who wants the Overview arranged their own way,
  # I want „Anpassen“ to copy the template into a dashboard of mine,
  # so that I can change it while the template stays as shipped.
  #
  # Acceptance criteria:
  # - „Anpassen“ stores one dashboard with the template's layout under the
  #   template's title, journaled once under the UI's actor.
  # - The page opens the copy at /dashboards/:id, without the banner.
  test "„Anpassen“ copies the template and opens the copy", %{conn: conn} do
    seed()
    {:ok, view, _html} = live(conn, "/?locale=de")

    assert {:error, {:live_redirect, %{to: "/dashboards/" <> id}}} =
             view |> element("[data-role='customize']") |> render_click()

    [dashboard] = Dashboards.list_dashboards()
    assert to_string(dashboard.id) == id
    assert dashboard.name == "Überblick"
    {:ok, template} = Templates.fetch("overview")
    assert dashboard.layout == Enum.map(template.layout, &Map.put_new(&1, "settings", %{}))

    assert [%{actor_type: :owner_ui, operation: :create}] =
             Journal.list_entries(resource_type: "dashboard")

    {:ok, copy, _html} = live(conn, "/dashboards/#{id}?locale=de")
    refute has_element?(copy, "[data-role='template-banner']")
    assert has_element?(copy, "#app-topbar-title", "Überblick")
  end

  # User story:
  # As the operator with dashboards of my own,
  # I want `/` to open the first by its place in the menu and
  # `/dashboards/:id` the one I name,
  # so that my first dashboard is where the Overview was.
  #
  # Acceptance criteria:
  # - With two stored dashboards, `/` opens the one at the lower position.
  # - `/dashboards/:id` opens the other; an unknown id opens `/`.
  test "stored dashboards open by position and by id", %{conn: conn} do
    seed()
    due = [%{"kind" => "due", "size" => "S", "col" => 1, "row" => 1}]

    {:ok, a} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Alpha", "layout" => due})

    {:ok, b} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Beta", "layout" => due})
    {:ok, _b} = Dashboards.reposition_dashboard(Actor.owner_ui(), b.id, 1)
    {:ok, _a} = Dashboards.reposition_dashboard(Actor.owner_ui(), a.id, 2)

    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#app-topbar-title", "Beta")
    refute has_element?(view, "[data-role='template-banner']")

    {:ok, view, _html} = live(conn, "/dashboards/#{a.id}")
    assert has_element?(view, "#app-topbar-title", "Alpha")

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/dashboards/#{b.id + 1000}")
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/dashboards/nope")
  end

  # User story:
  # As the operator reading the dashboard,
  # I want every widget in its frame — title, ⓘ, ⋯, body, footer — in the
  # order the layout reads (row, then col) and at its place on the grid,
  # so that the wide grid, the columns below it and a screen reader meet
  # the widgets in one order.
  #
  # Acceptance criteria:
  # - The template's eleven items are eleven frames, in reading order, each
  #   with its kind, size, col and row, and its grid span in its style.
  # - Each frame has a heading, a ⋯ menu, and the kinds the Overview drew
  #   carry their ⓘ.
  test "the template's items are widgets in reading order, placed on the grid", %{conn: conn} do
    world = seed()
    sell!(world, world.security, quantity: "2", price: "130", date: ~D[2026-02-10])

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    {:ok, template} = Templates.fetch("overview")

    # Sprint 31 D4: every widget is drawn, Due and the cycle too while
    # they have nothing to say (no dated fact, no security with the cycle
    # view), each with its quiet line.
    expected =
      template.layout
      |> Enum.sort_by(&{&1["row"], &1["col"]})
      |> Enum.map(& &1["kind"])

    found = kinds(view)
    assert Enum.map(found, &elem(&1, 0)) == expected

    for {kind, node} <- found do
      item = Enum.find(template.layout, &(&1["kind"] == kind))
      assert Floki.attribute(node, "data-size") == [item["size"]]
      assert Floki.attribute(node, "data-col") == [to_string(item["col"])]
      assert Floki.attribute(node, "data-row") == [to_string(item["row"])]
      [style] = Floki.attribute(node, "style")
      assert style =~ "--widget-col: #{item["col"]};"
      assert style =~ "--widget-row: #{item["row"]};"
      assert [_heading] = Floki.find(node, ".widget__head h2")
      assert [_menu] = Floki.find(node, "[data-role='widget-menu']")
    end

    for kind <- ~w(total_value data_quality off_target movers sale_review) do
      {_kind, node} = List.keyfind(found, kind, 0)
      assert [_info] = Floki.find(node, ".widget__head [data-role='section-info']"), kind
    end
  end

  # User story:
  # As the operator with a dashboard whose widget reads another view,
  # I want that widget to read its own view, and where its view was
  # deleted, the dashboard's, saying so,
  # so that no widget shows another scope's figure unnamed.
  #
  # Acceptance criteria:
  # - An item with `settings.view_id` of an existing view reads that view
  #   (its card names it); the dashboard's scope is Everything.
  # - After the view is deleted, the item reads the dashboard's scope and
  #   its footer says its view no longer exists.
  test "an item's view overrides the scope; a dangling one reads the dashboard's", %{
    conn: conn
  } do
    seed()
    {:ok, mine} = Buckets.create_view(Actor.owner_ui(), %{name: "Mine", include_all: true})

    layout = [
      %{"kind" => "total_value", "size" => "S", "col" => 1, "row" => 1},
      %{
        "kind" => "total_value",
        "size" => "S",
        "col" => 4,
        "row" => 1,
        "settings" => %{"view_id" => mine.id}
      }
    ]

    {:ok, board} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Views", "layout" => layout})

    {:ok, view, _html} = live(conn, "/dashboards/#{board.id}")
    render_async(view)

    assert has_element?(view, "#dashboard-wealth-card", "Everything")
    assert has_element?(view, "#dashboard-wealth-card-2", "Mine")
    assert has_element?(view, "#dashboard-wealth-2 [data-role='widget-scope']", "View Mine")

    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), mine)

    {:ok, view, _html} = live(conn, "/dashboards/#{board.id}")
    render_async(view)

    assert has_element?(view, "#dashboard-wealth-card-2", "Everything")

    assert has_element?(
             view,
             "#dashboard-wealth-2 [data-role='widget-scope']",
             "Its view no longer exists · reads Everything"
           )
  end

  # User story:
  # As the operator looking at the dashboard through another view,
  # I want the scope above the widgets to pick it for this address only,
  # so that a link can open the dashboard on a view and my default stays.
  #
  # Acceptance criteria:
  # - `?scope=<id>` reads that view; the scope's name stands above the
  #   widgets; the default view setting is unchanged.
  # - `?scope=total` reads Everything.
  test "the scope above the widgets is read from the address, never stored", %{conn: conn} do
    seed()
    {:ok, mine} = Buckets.create_view(Actor.owner_ui(), %{name: "Mine", include_all: true})

    {:ok, view, _html} = live(conn, "/?scope=#{mine.id}")
    render_async(view)

    assert has_element?(view, "[data-role='dashboard-scope-name']", "Mine")
    assert has_element?(view, "#dashboard-wealth-card", "Mine")
    assert Portfolixir.Settings.default_view_id() == nil

    view |> element("[data-scope='total']") |> render_click()
    render_async(view)
    assert has_element?(view, "[data-role='dashboard-scope-name']", "Everything")
    assert has_element?(view, "#dashboard-wealth-card", "Everything")
    assert stored_count() == 0
  end

  # User story (the Overview's polish list #1358: the privacy walk's log
  # noise from a widget's background read; Sprint 31 D3):
  # As the owner who trusts the browser walks,
  # I want the page to say it is busy while any of its background reads
  # runs, even one whose widget draws no skeleton,
  # so that a walk never leaves the page, and ends its test, with a read
  # still running against the test's database.
  #
  # Acceptance criteria:
  # - A dashboard holding only „Datenqualität“ marks its grid aria-busy
  #   while the read runs, and not once it has landed (since Sprint 31 D4
  #   the widget is drawn while it waits, its skeleton in place).
  test "the grid is busy while a read runs that draws no skeleton", %{conn: conn} do
    seed()

    {:ok, board} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Quality",
        "layout" => [%{"kind" => "data_quality", "size" => "S", "col" => 1, "row" => 1}]
      })

    {:ok, view, _html} = live(conn, "/dashboards/#{board.id}")
    assert has_element?(view, "[data-role='dashboard-grid'][aria-busy='true']")

    assert has_element?(
             view,
             "[data-widget-kind='data_quality'] [data-role='data-quality-skeleton']"
           )

    render_async(view)
    refute has_element?(view, "[data-role='dashboard-grid'][aria-busy]")

    refute has_element?(
             view,
             "[data-widget-kind='data_quality'] [data-role='data-quality-skeleton']"
           )
  end
end
