defmodule PortfolixirWeb.AppShellLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  test "root route renders the product app shell", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#app-shell")
    assert has_element?(view, "#sidebar-toggle")
    assert has_element?(view, "img[src='/images/logo-mark.svg']")
    assert has_element?(view, "img[alt='Portfolixir']")
    refute has_element?(view, "img[src='/images/logo-wordmark.svg']")
    assert has_element?(view, "a[href=\"/securities\"]")
    assert has_element?(view, "a[href=\"/taxonomies\"]")
    assert has_element?(view, "a[title='Securities']")
    assert has_element?(view, "a[title='Classifications']")
    assert has_element?(view, "#theme-toggle")
    assert html =~ "Portfolixir"
  end

  test "official sidebar logo asset is served", %{conn: conn} do
    response = get(conn, "/images/logo-mark.svg")

    assert response.status == 200
    assert get_resp_header(response, "content-type") == ["image/svg+xml"]
    assert response.resp_body =~ "Portfolixir logo mark"
  end

  test "static logo assets are served", %{conn: conn} do
    mark = get(conn, "/images/logo-mark.svg")
    light = get(conn, "/images/logo-light.svg")
    dark = get(conn, "/images/logo-dark.svg")
    favicon_svg = get(conn, "/favicon.svg")
    favicon_ico = get(conn, "/favicon.ico")

    assert mark.status == 200
    assert light.status == 200
    assert dark.status == 200
    assert favicon_svg.status == 200
    assert favicon_ico.status == 200
  end

  test "navigation is usable in compact sidebar mode markup", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "app-shell-nav-icon"
    assert html =~ ">S<"
    assert html =~ ">C<"
    assert html =~ "aria-label=\"Securities\""
    assert html =~ "aria-label=\"Classifications\""
    assert html =~ "title=\"Securities\""
    assert html =~ "title=\"Classifications\""
    assert html =~ "app-shell-theme-toggle"
    assert html =~ "app-shell-theme-label"
  end

  test "theme toggle uses the dedicated theme toggle class", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#theme-toggle.app-shell-theme-toggle")
    assert has_element?(view, "#theme-toggle")
    refute has_element?(view, "#theme-toggle.app-shell-toggle")
  end

  test "securities route is usable", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/securities")

    assert html =~ "No securities yet"
    assert html =~ "Add your first security to start building your portfolio."
  end

  test "taxonomies route is reachable", %{conn: conn} do
    {:ok, view, html} = live(conn, "/taxonomies")

    assert html =~ "Classifications"
    assert html =~ "Create Taxonomy"
    assert has_element?(view, "a[href=\"/taxonomies\"]")
  end

  test "theme toggle keeps a compact sidebar mark source", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#app-shell-brand-mark")
    assert has_element?(view, ".app-shell-logo-frame")
    assert html =~ "/images/logo-mark.svg"
    refute html =~ "/images/logo-dark.svg"
  end
end
