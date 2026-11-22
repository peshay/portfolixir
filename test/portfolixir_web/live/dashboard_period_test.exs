defmodule PortfolixirWeb.DashboardPeriodTest do
  # Sprint 31 D5 (FR-60; ADR-0062 §5, §6; idea board
  # ux-design-2026-11-21-idea-i56 05, A; planning board
  # ux-design-2026-11-21-sprint31/01 ①): one period above every dashboard.
  # The selector in the top bar, `period=` in the address when it is not
  # 1J, kept when the operator switches dashboards; every widget says
  # whether it follows, has pinned its own, translates the period or has
  # none; the pin is stored in the item's settings through the journaled
  # replace. The per-browser memory is read in a real browser by
  # test/browser/dashboard_period_test.exs; here the server's half (the
  # hook's element, the event it sends and the one it receives).
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable` row 30); every module that creates
  # one joins this group.
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  @layout [
    %{"kind" => "performance", "size" => "L", "col" => 1, "row" => 1},
    %{"kind" => "movers", "size" => "M", "col" => 1, "row" => 4},
    %{"kind" => "crashes", "size" => "M", "col" => 7, "row" => 4}
  ]

  defp seed do
    world = base_world()

    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-10])
    put_quote!(security, Portfolixir.Clock.today(), "120")
    world
  end

  defp german(conn), do: put_preference_cookie(conn, "portfolixir_locale", "de")

  defp dashboard!(name, layout \\ @layout) do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => name, "layout" => layout})

    dashboard
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp document(view), do: view |> render() |> Floki.parse_document!()

  defp selected(view) do
    view
    |> document()
    |> Floki.find("[data-role='dashboard-period'] [aria-pressed='true']")
    |> Enum.flat_map(&Floki.attribute(&1, "data-period"))
  end

  defp period_tag(view, kind) do
    view
    |> document()
    |> Floki.find("[data-widget-kind='#{kind}'] [data-role='widget-period']")
  end

  defp tag_text(view, kind), do: view |> period_tag(kind) |> text()

  defp tag_state(view, kind),
    do: view |> period_tag(kind) |> Floki.attribute("data-period-state") |> List.first()

  defp pick(view, period) do
    view
    |> element("[data-role='dashboard-period'] button[data-period='#{period}']")
    |> render_click()
  end

  defp pin(view, kind, period) do
    view
    |> element("[data-widget-kind='#{kind}'] [data-role='pin-period'][data-period='#{period}']")
    |> render_click()
  end

  defp stored_settings(id, kind) do
    id
    |> Dashboards.get_dashboard()
    |> Map.fetch!(:layout)
    |> Enum.find(&(&1["kind"] == kind))
    |> Map.fetch!("settings")
  end

  # User story:
  # As the operator reading a dashboard,
  # I want one period in the top bar that every widget follows,
  # so that one click moves every figure to the same span.
  #
  # Acceptance criteria:
  # - The top bar holds the eight periods 1T, 1W, 1M, 3M, YTD, 1J, 3J,
  #   Max (board 05 A), 1J pressed on an address that names none.
  # - A pick moves the address (`?period=3m`; 1J names none) and tells the
  #   browser's memory (`period-memory`, the pick's key).
  # - The page keeps the hook that remembers it per browser.
  test "the top bar's selector offers the eight periods, 1J first, and a pick moves the address",
       %{conn: conn} do
    seed()
    {:ok, view, _html} = conn |> german() |> live("/")

    assert view
           |> document()
           |> Floki.find("[data-role='dashboard-period'] button")
           |> Enum.map(&text/1) ==
             ~w(1T 1W 1M 3M YTD 1J 3J Max)

    assert selected(view) == ["1y"]

    assert has_element?(
             view,
             "#dashboard-period-memory[phx-hook='PeriodMemory'][data-storage-key='dashboard.period'][data-addressed='false']"
           )

    pick(view, "3m")
    assert_patch(view, "/?period=3m")
    assert_push_event(view, "period-memory", %{period: %{"period" => "3m"}})
    assert selected(view) == ["3m"]

    pick(view, "1y")
    assert_patch(view, "/")
    assert_push_event(view, "period-memory", %{period: %{"period" => "1y"}})
    assert selected(view) == ["1y"]
  end

  # User story:
  # As the operator handing over a link,
  # I want the link to open the dashboard on its period,
  # so that the reader sees the span I saw.
  #
  # Acceptance criteria:
  # - `/?period=3m` opens on 3M; the scope's choices keep it.
  # - A value that is no period opens 1J and nothing breaks.
  test "a link opens the dashboard on its period; an invalid one opens 1J", %{conn: conn} do
    seed()
    {:ok, view, _html} = conn |> german() |> live("/?period=3m")
    assert selected(view) == ["3m"]
    assert tag_text(view, "performance") == "folgt · 3M"

    [href] =
      view
      |> document()
      |> Floki.find("[data-role='dashboard-scope'] a[data-scope='total']")
      |> Floki.attribute("href")

    assert URI.decode_query(URI.parse(href).query) == %{"scope" => "total", "period" => "3m"}

    {:ok, view, _html} = conn |> german() |> live("/?period=decade")
    assert selected(view) == ["1y"]
    assert tag_text(view, "performance") == "folgt · 1J"
  end

  # User story:
  # As the operator reading a widget,
  # I want it to say quietly which period its figures are for,
  # so that no figure is read for another span than its own.
  #
  # Acceptance criteria:
  # - A widget that takes the period says „folgt · 3M“.
  # - Tops und Flops, which knows Tag, Woche, Monat, Quartal, YTD and 1J,
  #   says what it reads instead („folgt · 3M → Quartal“, „folgt · 1W →
  #   Woche“: its calendar windows to date; 3J and Max read 1J) and reads
  #   that window; YTD and 1J, its own, say no arrow.
  # - A widget without a period says „ohne Zeitraum“.
  # - The widget's own period chips are gone: the dashboard's drives it.
  test "a widget follows, translates, or has no period, and says so", %{conn: conn} do
    seed()
    {:ok, view, _html} = conn |> german() |> live("/?period=3m")
    render_async(view)

    assert tag_text(view, "performance") == "folgt · 3M"
    assert tag_state(view, "performance") == "follows"
    assert tag_text(view, "movers") == "folgt · 3M → Quartal"
    assert has_element?(view, "#dashboard-movers[data-window='quarter']")
    refute has_element?(view, "[data-role='movers-period']")

    # „Gesamtwert“ at S draws the period's change, so it follows too.
    assert tag_text(view, "total_value") == "folgt · 3M"
    assert tag_state(view, "total_value") == "follows"

    for kind <- ~w(crashes snapshots) do
      assert tag_text(view, kind) == "ohne Zeitraum", kind
      assert tag_state(view, kind) == "none", kind
    end

    pick(view, "1w")
    render_async(view)
    # Tops und Flops reads the calendar week to date, not performance's
    # seven trailing days, and says so (Sprint 31 closing act, C1).
    assert tag_text(view, "movers") == "folgt · 1W → Woche"
    assert has_element?(view, "#dashboard-movers[data-window='week']")

    pick(view, "max")
    render_async(view)
    assert tag_text(view, "movers") == "folgt · Max → 1J"
    assert has_element?(view, "#dashboard-movers[data-window='1y']")
  end

  # User story:
  # As the operator who wants one widget beside the others on its own span,
  # I want to pin its period in its ⋯ menu,
  # so that it keeps that span whatever the top bar says, marked so.
  #
  # Acceptance criteria:
  # - The ⋯ menu offers „Zeitraum festlegen“ with the kind's periods and
  #   „Folgt dem Dashboard (3M)“.
  # - A pin is stored in the item's `settings.period` by one journaled
  #   replace under the UI's actor; the widget says „📌 eigener: Max“ in
  #   the accent and keeps it when the top bar changes.
  # - A pinned Tops und Flops reads its own window.
  # - Unpinning stores the item without the pin and the widget follows.
  test "a pin is stored in the item's settings, drawn in the accent, and undone", %{conn: conn} do
    seed()
    dashboard = dashboard!("Alpha")
    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{dashboard.id}?period=3m")
    render_async(view)

    menu =
      view
      |> document()
      |> Floki.find("[data-widget-kind='performance'] [data-role='widget-menu']")

    assert text(menu) =~ "Folgt dem Dashboard (3M)"
    assert text(menu) =~ "Zeitraum festlegen"

    assert menu |> Floki.find("[data-role='pin-period']") |> Enum.map(&text/1) ==
             ~w(1T 1W 1M 3M YTD 1J 3J Max)

    pin(view, "performance", "max")

    assert stored_settings(dashboard.id, "performance") == %{"period" => "max"}
    assert Dashboards.get_dashboard(dashboard.id).lock_version == dashboard.lock_version + 1

    assert [%{operation: :create}, %{operation: :update, actor_type: :owner_ui}] =
             Journal.list_entries(resource_type: "dashboard") |> Enum.sort_by(& &1.id)

    assert tag_text(view, "performance") == "📌 eigener: Max"
    assert tag_state(view, "performance") == "pinned"
    assert has_element?(view, "[data-widget-kind='performance'] .widget__period--pinned")

    pick(view, "1w")
    assert tag_text(view, "performance") == "📌 eigener: Max"
    assert tag_text(view, "movers") == "folgt · 1W → Woche"

    pin(view, "movers", "1m")
    render_async(view)
    assert stored_settings(dashboard.id, "movers") == %{"period" => "1m"}
    assert tag_text(view, "movers") == "📌 eigener: 1M → Monat"
    assert has_element?(view, "#dashboard-movers[data-window='month']")

    view
    |> element("[data-widget-kind='performance'] [data-role='unpin-period']")
    |> render_click()

    assert stored_settings(dashboard.id, "performance") == %{}
    assert tag_text(view, "performance") == "folgt · 1W"
    assert tag_state(view, "performance") == "follows"
  end

  # User story (Sprint 31 D8, the width walk's finding 3):
  # As the operator reading „Gesamtwert“ at S,
  # I want its head to name the period its change line is for, and its ⋯
  # menu to pin one,
  # so that the head never says „ohne Zeitraum“ above a figure for a span.
  #
  # Acceptance criteria:
  # - It follows the top bar: „folgt · 3M“ over „TTWROR · 3M“.
  # - Its ⋯ menu offers the eight periods; a pin is stored in its settings,
  #   the head says „📌 eigener: Max“ and the line „TTWROR · Max“, and a
  #   change of the top bar leaves both.
  test "„Gesamtwert“ at S follows the period, and a pin moves its change line", %{conn: conn} do
    seed()
    layout = [%{"kind" => "total_value", "size" => "S", "col" => 1, "row" => 1}]
    dashboard = dashboard!("Total", layout)
    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{dashboard.id}?period=3m")
    render_async(view)

    line = fn ->
      view |> document() |> Floki.find("[data-role='card-period-change']") |> text()
    end

    assert tag_text(view, "total_value") == "folgt · 3M"
    assert line.() =~ "TTWROR · 3M"

    assert view
           |> document()
           |> Floki.find("[data-widget-kind='total_value'] [data-role='pin-period']")
           |> Enum.map(&text/1) == ~w(1T 1W 1M 3M YTD 1J 3J Max)

    pin(view, "total_value", "max")
    render_async(view)
    assert stored_settings(dashboard.id, "total_value") == %{"period" => "max"}
    assert tag_text(view, "total_value") == "📌 eigener: Max"
    assert line.() =~ "TTWROR · Max"

    pick(view, "1w")
    render_async(view)
    assert tag_text(view, "total_value") == "📌 eigener: Max"
    assert line.() =~ "TTWROR · Max"
  end

  # User story:
  # As the operator on the shipped template,
  # I want its ⋯ menu to offer „Anpassen“ rather than a pin,
  # so that the read-only template stays as shipped.
  #
  # Acceptance criteria:
  # - The template's menus hold no pin, and „Anpassen“.
  # - A pin sent to the template stores nothing.
  test "on the template the pin is not offered; the menu offers „Anpassen“", %{conn: conn} do
    seed()
    {:ok, view, _html} = conn |> german() |> live("/")

    refute has_element?(view, "[data-role='pin-period']")

    assert has_element?(
             view,
             "[data-widget-kind='performance'] [data-role='widget-menu'] [data-role='menu-customize']",
             "Anpassen"
           )

    render_click(view, "pin_period", %{"index" => "4", "period" => "max"})
    assert Repo.aggregate(Dashboards.Dashboard, :count) == 0
    assert Journal.list_entries(resource_type: "dashboard") == []
  end

  # User story:
  # As the operator pinning while my agent changed the same dashboard,
  # I want the stored dashboard shown rather than my pin written over it,
  # so that neither change is lost unseen.
  #
  # Acceptance criteria:
  # - A pin read at a lock_version another write has passed stores
  #   nothing; the page draws the stored layout and says it was changed
  #   elsewhere, without crashing.
  # - A pin that names no item, or a period the kind lacks, stores nothing.
  test "a stale lock_version on the pin's save shows the stored state", %{conn: conn} do
    seed()
    dashboard = dashboard!("Alpha")
    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{dashboard.id}")

    layout =
      Enum.map(dashboard.layout, fn
        %{"kind" => "movers"} = item -> Map.put(item, "settings", %{"period" => "1w"})
        item -> item
      end)

    {:ok, _elsewhere} =
      Dashboards.replace_dashboard(Actor.api_token_rw("test-agent"), dashboard.id, %{
        "name" => dashboard.name,
        "layout" => layout,
        "lock_version" => dashboard.lock_version
      })

    pin(view, "performance", "max")

    assert stored_settings(dashboard.id, "performance") == %{}
    assert stored_settings(dashboard.id, "movers") == %{"period" => "1w"}
    assert tag_text(view, "movers") == "📌 eigener: 1W → Woche"
    assert tag_text(view, "performance") == "folgt · 1J"
    assert has_element?(view, "[data-role='period-pin-status']", "anderswo geändert")

    before = Dashboards.get_dashboard(dashboard.id).lock_version
    render_click(view, "pin_period", %{"index" => "99", "period" => "max"})
    render_click(view, "pin_period", %{"index" => "2", "period" => "max"})
    render_click(view, "pin_period", %{"index" => "0", "period" => "5y"})
    assert Dashboards.get_dashboard(dashboard.id).lock_version == before
  end

  # User story:
  # As the operator switching from one dashboard to another,
  # I want the period to stay,
  # so that two dashboards never show two spans unasked.
  #
  # Acceptance criteria:
  # - On one LiveView, a switch to another dashboard keeps the period and
  #   the address names it; the same dashboard's address without a period
  #   (Back from ?period=3m) opens 1J.
  # - On a fresh page, the browser's memory asks for its kept period
  #   (`restore_period`) and the page opens on it; an address that names a
  #   period wins, and a kept value that is no period changes nothing.
  test "the period stays when switching dashboards", %{conn: conn} do
    seed()
    a = dashboard!("Alpha")
    b = dashboard!("Beta")

    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{a.id}")
    pick(view, "3m")
    assert_patch(view, "/dashboards/#{a.id}?period=3m")

    render_patch(view, "/dashboards/#{b.id}")
    assert_patch(view, "/dashboards/#{b.id}?period=3m")
    assert has_element?(view, "#app-topbar-title", "Beta")
    assert selected(view) == ["3m"]
    assert tag_text(view, "performance") == "folgt · 3M"

    # Back to the same dashboard's address without a period (the
    # browser's history, a patch on this page) opens 1J, as the address
    # says: only a switch to another dashboard keeps the period (Sprint 31
    # closing act, correctness lens C5).
    render_patch(view, "/dashboards/#{b.id}")
    assert selected(view) == ["1y"]
    assert tag_text(view, "performance") == "folgt · 1J"

    {:ok, fresh, _html} = conn |> german() |> live("/dashboards/#{b.id}")

    fresh
    |> element("#dashboard-period-memory")
    |> render_hook("restore_period", %{"period" => "3m"})

    assert_patch(fresh, "/dashboards/#{b.id}?period=3m")
    assert selected(fresh) == ["3m"]

    {:ok, linked, _html} = conn |> german() |> live("/dashboards/#{b.id}?period=1w")
    assert has_element?(linked, "#dashboard-period-memory[data-addressed='true']")

    linked
    |> element("#dashboard-period-memory")
    |> render_hook("restore_period", %{"period" => "3m"})

    assert selected(linked) == ["1w"]

    {:ok, odd, _html} = conn |> german() |> live("/dashboards/#{b.id}")

    odd
    |> element("#dashboard-period-memory")
    |> render_hook("restore_period", %{"period" => "decade"})

    assert selected(odd) == ["1y"]
  end
end
