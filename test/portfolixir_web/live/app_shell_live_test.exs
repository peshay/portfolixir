defmodule PortfolixirWeb.AppShellLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  test "root route renders the product app shell", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#app-shell")
    assert has_element?(view, "#sidebar-toggle")
    assert has_element?(view, "img[src='/images/logo-mark.svg']")
    assert has_element?(view, "img[alt='Portfolixir']")
    assert has_element?(view, "a[href=\"/securities\"]")
    assert has_element?(view, "a[href=\"/taxonomies\"]")
    assert has_element?(view, "a[title='Securities']")
    assert has_element?(view, "a[title='Categories']")
    assert has_element?(view, "#theme-toggle")
    assert html =~ "Portfolixir"
  end

  test "navigation is usable in compact sidebar mode markup", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "app-shell-nav-icon"
    assert html =~ ">S<"
    assert html =~ ">C<"
    assert html =~ "aria-label=\"Securities\""
    assert html =~ "aria-label=\"Categories\""
    assert html =~ "title=\"Securities\""
    assert html =~ "title=\"Categories\""
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

    assert html =~ "Category Management"
    assert html =~ "Create Taxonomy"
    assert has_element?(view, "a[href=\"/taxonomies\"]")
  end
end
