defmodule PortfolixirWeb.AppShellLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  test "root route renders the product app shell", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#app-shell[data-sidebar-collapsed='false']")
    assert has_element?(view, "#sidebar-toggle")
    assert has_element?(view, "img#app-shell-brand-light-wordmark[src='/images/logo-light.svg']")
    assert has_element?(view, "img#app-shell-brand-mark[src='/images/logo-mark.svg']")
    assert has_element?(view, "img[alt='Portfolixir']")
    refute has_element?(view, "img[src='/images/logo-wordmark.svg']")
    assert has_element?(view, "img#app-shell-brand-dark-wordmark[src='/images/logo-dark.svg']")
    assert has_element?(view, "a[href=\"/securities\"]")
    assert has_element?(view, "a[href=\"/accounts\"]")
    assert has_element?(view, "a[href=\"/taxonomies\"]")
    assert has_element?(view, "p.app-shell-nav-group-title", "Securities")
    assert has_element?(view, "p.app-shell-nav-group-title", "Master data")
    assert has_element?(view, "p.app-shell-nav-group-title", "Classifications")
    assert has_element?(view, "p.app-shell-nav-group-title", "Reports")
    assert has_element?(view, "#theme-toggle")
    assert has_element?(view, "span.app-shell-visually-hidden", "Portfolixir")
    refute has_element?(view, ".app-shell-brand-label")

    [style_block] =
      Regex.run(~r/<style id="app-shell-styles">(.*?)<\/style>/s, html, capture: :all_but_first)

    assert Regex.match?(
             ~r/#app-shell:not\(\[data-sidebar-collapsed="true"\]\)\[data-theme="light"\]\s+\.app-shell-logo-wordmark-light\s*\{\s*display:\s*block;/s,
             style_block
           )

    assert Regex.match?(
             ~r/#app-shell:not\(\[data-sidebar-collapsed="true"\]\)\[data-theme="dark"\]\s+\.app-shell-logo-wordmark-dark\s*\{\s*display:\s*block;/s,
             style_block
           )

    assert Regex.match?(
             ~r/#app-shell\[data-sidebar-collapsed="true"\]\s+\.app-shell-logo-mark\s*\{\s*display:\s*block;/s,
             style_block
           )

    assert Regex.match?(
             ~r/#app-shell\s+\.app-shell-logo-wordmark-light,\s*#app-shell\s+\.app-shell-logo-wordmark-dark,\s*#app-shell\s+\.app-shell-logo-mark\s*\{\s*display:\s*none;/s,
             style_block
           )

    refute Regex.match?(
             ~r/#app-shell:not\(\[data-sidebar-collapsed="true"\]\)\.?\s*\.app-shell-logo-wordmark-light,\s*#app-shell:not\(\[data-sidebar-collapsed="true"\]\)\.?\s*\.app-shell-logo-wordmark-dark/s,
             style_block
           )

    assert html =~ "Portfolixir"
  end

  test "official logo assets are served", %{conn: conn} do
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

  test "navigation shows grouped labels and disabled placeholders", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             "span[aria-label='Watchlist'][aria-disabled='true'][title='Coming soon']"
           )

    assert has_element?(view, "a[aria-label='Accounts'][href='/accounts'][title='Accounts']")

    assert has_element?(
             view,
             "span[aria-label='Securities accounts'][aria-disabled='true'][title='Coming soon']"
           )

    assert has_element?(
             view,
             "span[aria-label='Deposit accounts'][aria-disabled='true'][title='Coming soon']"
           )

    assert has_element?(
             view,
             "span[aria-label='Holdings'][aria-disabled='true'][title='Coming soon']"
           )

    assert has_element?(
             view,
             "span[aria-label='Performance'][aria-disabled='true'][title='Coming soon']"
           )

    assert html =~ "app-shell-nav-icon"
    assert html =~ ">W<"
    assert html =~ "aria-label=\"All Securities\""
    assert html =~ "aria-label=\"Classifications\""
  end

  test "theme toggle uses dedicated theme toggle class", %{conn: conn} do
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

  test "taxonomies route is reachable and titled as classifications", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/taxonomies")

    assert html =~ "Classifications"
    assert html =~ "Create Taxonomy"
    assert has_element?(live(conn, "/taxonomies") |> elem(1), "a[href=\"/taxonomies\"]")
  end
end
