defmodule PortfolixirWeb.AppShellLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  test "root route renders the product app shell", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#app-shell")
    assert has_element?(view, "#sidebar-toggle")
    assert has_element?(view, "img[alt='Portfolixir']")
    assert has_element?(view, "img[alt='Portfolixir mark']")
    assert has_element?(view, "a[href=\"/securities\"]")
    assert has_element?(view, "a[href=\"/taxonomies\"]")
    assert has_element?(view, "#theme-toggle")
    assert html =~ "Securities"
  end

  test "securities route is usable", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/securities")

    assert html =~ "No securities yet."
  end

  test "taxonomies route is reachable", %{conn: conn} do
    {:ok, view, html} = live(conn, "/taxonomies")

    assert html =~ "Category Management"
    assert html =~ "Create Taxonomy"
    assert has_element?(view, "a[href=\"/taxonomies\"]")
  end
end
