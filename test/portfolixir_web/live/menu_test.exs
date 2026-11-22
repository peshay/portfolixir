defmodule PortfolixirWeb.MenuTest do
  # Sprint 31 D7 (FR-60; ADR-0022's amendment of 2026-11-21, points 1 to 5;
  # ADR-0062 §6, §9; planning board ux-design-2026-11-21-sprint31/01 ① and
  # ④; idea board ux-design-2026-11-21-idea-i56/02, A): the menu of three
  # groups — Dashboards, Entdecken, Pflege at the foot — and, on a compact
  # window, the tab bar with „Mehr“ and the dashboard switcher in the
  # title. Which layout shows is CSS's choice by the window's size
  # (test/browser/tab_bar_test.exs measures it); this file holds the markup.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable`); every module that creates one
  # joins this group.
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards

  defp groups(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#app-sidebar .nav-group")
    |> Enum.map(fn group ->
      {group |> Floki.find(".nav-group-head") |> Floki.text() |> String.trim(),
       group |> Floki.find("a.nav-link") |> Enum.flat_map(&Floki.attribute(&1, "id"))}
    end)
  end

  defp active(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#app-sidebar a.nav-link[aria-current='page']")
    |> Enum.flat_map(&Floki.attribute(&1, "id"))
  end

  @discover ~w(nav-portfolio nav-securities nav-news nav-widgets)
  @maintenance ~w(nav-transactions nav-portfolios nav-buckets nav-classifications nav-journal)

  # User story:
  # As the operator opening a fresh instance,
  # I want the menu to list the dashboards first, then what I explore,
  # then the maintenance pages quietly at the foot,
  # so that what I read comes first and what the agent mostly keeps does
  # not take the top.
  #
  # Acceptance criteria:
  # - Three groups in this order: „Dashboards“, „Entdecken“, „Pflege“.
  # - With none stored, „Dashboards“ holds the template „Überblick“ marked
  #   „Vorlage“ (it opens /), then „Neues Dashboard“ (/dashboards/new).
  # - „Entdecken“ holds Vermögen, Wertpapiere, Nachrichten, „Alle Widgets“
  #   (/widgets); „Pflege“, marked quiet, Transaktionen, Konten & Depots,
  #   Ansichten, Klassifizierungen, Audit-Journal.
  test "a fresh instance's menu: the template, Entdecken, Pflege at the foot", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?locale=de")

    assert groups(view) == [
             {"Dashboards", ["nav-dashboard", "nav-new-dashboard"]},
             {"Entdecken", @discover},
             {"Pflege", @maintenance}
           ]

    assert has_element?(view, "#nav-dashboard[href='/']", "Überblick")
    assert has_element?(view, "#nav-dashboard .nav-badge", "Vorlage")
    assert has_element?(view, "#nav-new-dashboard[href='/dashboards/new']", "Neues Dashboard")
    assert has_element?(view, "#nav-portfolio[href='/portfolio']", "Vermögen")
    assert has_element?(view, "#nav-widgets[href='/widgets']", "Alle Widgets")
    assert has_element?(view, "#app-sidebar .nav-group--quiet #nav-journal")
    refute has_element?(view, "#app-sidebar .nav-group--quiet #nav-securities")
    assert active(view) == ["nav-dashboard"]

    # Each group is a group named by its title, so a screen reader says
    # which group a link is in (Sprint 31 closing act, the a11y lens).
    doc = view |> render() |> Floki.parse_document!()

    for group <- Floki.find(doc, "#app-sidebar .nav-group") do
      assert Floki.attribute(group, "role") == ["group"]
      [labelled_by] = Floki.attribute(group, "aria-labelledby")
      assert [_head] = Floki.find(group, ".nav-group-head ##{labelled_by}")
    end
  end

  # User story:
  # As the operator with dashboards of my own,
  # I want them in the menu in the order I gave them, and the one I read
  # marked,
  # so that I switch between them in one step.
  #
  # Acceptance criteria:
  # - The stored dashboards in `position` order, each linking
  #   /dashboards/:id under its name; no template entry and no „Vorlage“.
  # - On / the first is the current entry; on /dashboards/:id that one,
  #   and no other.
  test "stored dashboards in their order, the one read marked", %{conn: conn} do
    {:ok, alpha} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Alpha"})
    {:ok, beta} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Beta"})
    {:ok, gamma} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Gamma"})
    {:ok, _} = Dashboards.reposition_dashboard(Actor.owner_ui(), gamma.id, 1)
    {:ok, _} = Dashboards.reposition_dashboard(Actor.owner_ui(), alpha.id, 2)
    {:ok, _} = Dashboards.reposition_dashboard(Actor.owner_ui(), beta.id, 3)

    {:ok, view, _html} = live(conn, "/?locale=de")

    ids = Enum.map([gamma, alpha, beta], &"nav-dashboard-#{&1.id}")
    assert hd(groups(view)) == {"Dashboards", ids ++ ["nav-new-dashboard"]}
    assert has_element?(view, "#nav-dashboard-#{beta.id}[href='/dashboards/#{beta.id}']", "Beta")
    refute has_element?(view, "#nav-dashboard")
    refute has_element?(view, "#app-sidebar .nav-badge")
    assert active(view) == ["nav-dashboard-#{gamma.id}"]

    {:ok, view, _html} = live(conn, "/dashboards/#{beta.id}?locale=de")
    assert active(view) == ["nav-dashboard-#{beta.id}"]
  end

  # User story:
  # As the operator on any page,
  # I want the menu to mark the entry the page belongs to, as before,
  # so that I always see where I am.
  #
  # Acceptance criteria:
  # - „Alle Widgets“ on /widgets, „Neues Dashboard“ on /dashboards/new,
  #   Vermögen on its tabs (/cashflow, /snapshots, /tax, /risk,
  #   /predictions), Transaktionen on /imports, each the one current entry.
  test "the entry a page belongs to is the one marked", %{conn: conn} do
    for {path, id} <- [
          {"/widgets", "nav-widgets"},
          {"/dashboards/new", "nav-new-dashboard"},
          {"/portfolio", "nav-portfolio"},
          {"/cashflow", "nav-portfolio"},
          {"/snapshots", "nav-portfolio"},
          {"/tax", "nav-portfolio"},
          {"/risk", "nav-portfolio"},
          {"/predictions", "nav-portfolio"},
          {"/securities", "nav-securities"},
          {"/news", "nav-news"},
          {"/transactions", "nav-transactions"},
          {"/imports", "nav-transactions"},
          {"/portfolios", "nav-portfolios"},
          {"/buckets", "nav-buckets"},
          {"/classifications", "nav-classifications"},
          {"/journal", "nav-journal"}
        ] do
      {:ok, view, _html} = live(conn, path)
      assert active(view) == [id], "#{path} marks #{inspect(active(view))}"
    end
  end

  # User story:
  # As the operator with a bookmark or a docs link to a page of the old
  # menu,
  # I want every one of them to answer as before,
  # so that the new menu breaks no link (ADR-0022's amendment, D-7).
  #
  # Acceptance criteria:
  # - Every route the old menu and its area tabs opened answers 200; the
  #   renamed /income still redirects to /cashflow.
  test "every route of the old menu still answers", %{conn: conn} do
    for path <-
          ~w(/ /portfolio /portfolio?tab=allocation /cashflow /snapshots /tax /risk /predictions /securities /news /transactions /imports /portfolios /buckets /classifications /classifications/new /journal) do
      assert conn |> get(path) |> html_response(200), "#{path} did not answer"
    end

    assert conn |> get("/income") |> redirected_to() == "/cashflow"
  end

  # User story:
  # As the operator on a phone,
  # I want the menu as a tab bar at the foot — Dashboards, Wertpapiere,
  # Nachrichten, Mehr — with the rest in „Mehr“,
  # so that I reach every page with a thumb (ADR-0022's amendment, point 5).
  #
  # Acceptance criteria:
  # - #app-tabbar holds four entries: „Dashboards“ (/), „Wertpapiere“,
  #   „Nachrichten“ and „Mehr“, a button opening the sheet #app-more.
  # - The sheet holds the rest of „Entdecken“ (Vermögen, „Alle Widgets“)
  #   and all of „Pflege“, under their group names.
  # - The tab the page belongs to is current: Dashboards on a dashboard
  #   and on „Neues Dashboard“, Wertpapiere on a security, „Mehr“ on a
  #   page of the sheet.
  test "the compact tab bar and its „Mehr“ sheet", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?locale=de")

    tabs =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#app-tabbar .app-tab")
      |> Enum.map(&String.trim(Floki.text(&1)))

    assert tabs == ["Dashboards", "Wertpapiere", "Nachrichten", "Mehr"]
    assert has_element?(view, "#app-tabbar a#tab-dashboards[href='/'][aria-current='page']")
    assert has_element?(view, "#app-tabbar a#tab-securities[href='/securities']")
    assert has_element?(view, "#app-tabbar a#tab-news[href='/news']")
    assert has_element?(view, "#app-tabbar button#tab-more[popovertarget='app-more']")

    sheet =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#app-more[popover]")

    assert sheet |> Floki.find("h3") |> Enum.map(&String.trim(Floki.text(&1))) == [
             "Entdecken",
             "Pflege"
           ]

    assert sheet |> Floki.find("a") |> Enum.flat_map(&Floki.attribute(&1, "href")) ==
             ~w(/portfolio /widgets /transactions /portfolios /buckets /classifications /journal)

    for {path, tab} <- [
          {"/dashboards/new", "tab-dashboards"},
          {"/securities", "tab-securities"},
          {"/news", "tab-news"},
          {"/widgets", "tab-more"},
          {"/cashflow", "tab-more"},
          {"/journal", "tab-more"}
        ] do
      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, "#app-tabbar ##{tab}.is-active"), "#{path} marks no #{tab}"

      assert view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find("#app-tabbar .is-active")
             |> length() == 1
    end
  end

  # User story:
  # As the operator on a phone reading a dashboard,
  # I want to switch dashboards from the title, „Überblick ▾“,
  # so that the tab „Dashboards“ needs no list of its own.
  #
  # Acceptance criteria:
  # - On a dashboard the title is also a button that opens
  #   #dashboard-switcher, which lists the menu's dashboard entries, the
  #   one read marked, then „Neues Dashboard“.
  # - Another page's title is no switcher.
  test "the dashboard switcher in the title", %{conn: conn} do
    {:ok, alpha} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Alpha"})
    {:ok, beta} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Beta"})

    {:ok, view, _html} = live(conn, "/dashboards/#{beta.id}?locale=de")

    assert has_element?(
             view,
             "#app-topbar-title button.topbar-switcher[popovertarget='dashboard-switcher']",
             "Beta"
           )

    links =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#dashboard-switcher[popover] a")

    assert Enum.flat_map(links, &Floki.attribute(&1, "href")) ==
             ["/dashboards/#{alpha.id}", "/dashboards/#{beta.id}", "/dashboards/new"]

    assert has_element?(view, "#dashboard-switcher a[aria-current='page']", "Beta")

    {:ok, other, _html} = live(conn, "/securities?locale=de")
    refute has_element?(other, ".topbar-switcher")
    refute has_element?(other, "#dashboard-switcher")
  end
end
