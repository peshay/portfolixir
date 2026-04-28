defmodule PortfolixirWeb.SecurityManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog

  test "visiting / renders All Securities", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "All Securities"
  end

  test "visiting /securities renders shared app shell", %{conn: conn} do
    {:ok, view, html} = live(conn, "/securities")

    assert has_element?(view, "a[href=\"/securities\"]")
    assert has_element?(view, "a[href=\"/taxonomies\"]")
    assert has_element?(view, "img#app-shell-brand-mark[src='/images/logo-mark.svg']")
    assert has_element?(view, ".app-shell-brand-text", "Portfolixir")
    assert has_element?(view, "#sidebar-toggle")
    assert has_element?(view, "#theme-toggle")
    assert html =~ "id=\"theme-toggle-script\""
    assert html =~ "All Securities"
  end

  test "securities workspace uses primary list and secondary form layout", %{conn: conn} do
    assert {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Synthetic ETF",
               symbol: "SYN",
               currency_code: "USD"
             })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-workspace.app-shell-workspace-stack")
    assert has_element?(view, "#security-listing[data-priority='primary']")
    assert has_element?(view, "#security-listing .app-shell-table-wrapper")
    assert has_element?(view, "#security-kpis .app-shell-stat-card", "Total Securities")
    assert has_element?(view, "#security-kpis .app-shell-stat-card", "Currencies")
    assert has_element?(view, "#security-kpis .app-shell-stat-card", "Classifications")
    assert has_element?(view, "#security-kpis .app-shell-stat-card", "Last Updated")
    assert has_element?(view, "#security-actions.app-shell-action-row")

    assert has_element?(
             view,
             "#security-search[disabled][placeholder='Search securities...'][title='Search coming soon']"
           )

    assert has_element?(
             view,
             "#security-filter[disabled][aria-disabled='true'][title='Filter coming soon']"
           )

    assert has_element?(view, "#security-add-toggle")
    refute has_element?(view, "#security-create")

    view |> element("#security-add-toggle") |> render_click()

    assert has_element?(view, "#security-create[data-priority='secondary']")
    assert has_element?(view, "#security-form.app-shell-form-grid")
    assert has_element?(view, "#security-create .app-shell-panel-intro")
  end

  test "renders an empty state when there are no securities", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/securities")

    assert html =~ "All Securities"
    assert html =~ "No securities yet"
    assert html =~ "Add your first security to start building your portfolio."
  end

  test "creates a security with success feedback", %{conn: conn} do
    assert {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#security-add-toggle") |> render_click()

    html =
      view
      |> form("#security-form", %{
        "security" => %{
          "name" => "Apple Inc.",
          "symbol" => "AAPL",
          "currency_code" => "USD",
          "isin" => "US0378331005",
          "wkn" => "865985"
        }
      })
      |> render_submit()

    assert html =~ "Security added."
    assert html =~ "Apple Inc."
    assert html =~ "AAPL"
    assert html =~ "USD"
    assert html =~ "US0378331005"
    assert html =~ "865985"
  end

  test "renders optional fields as em dashes when omitted", %{conn: conn} do
    assert {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "No IDs Security",
               symbol: "NIS",
               currency_code: "USD"
             })

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-list tbody tr")
    assert has_element?(view, "#security-list tbody tr td:nth-child(4)", "—")
    assert has_element?(view, "#security-list tbody tr td:nth-child(5)", "—")
    assert has_element?(view, "#security-list tbody tr td:nth-child(6)", "—")
    assert has_element?(view, "#security-list tbody tr td:nth-child(7)", "—")
  end

  test "shows validation error when name is missing", %{conn: conn} do
    assert {:ok, _} = Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})

    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#security-add-toggle") |> render_click()

    html =
      view
      |> form("#security-form", %{
        "security" => %{
          "name" => "",
          "symbol" => "AAPL",
          "currency_code" => "EUR"
        }
      })
      |> render_submit()

    assert html =~ "id=\"security-form-error\""
    assert has_element?(view, "#security-form-error[role='alert']")
    assert html =~ "name"
  end

  test "shows understandable currency validation error and keeps field values", %{conn: conn} do
    assert {:ok, _} = Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})

    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#security-add-toggle") |> render_click()

    html =
      view
      |> form("#security-form", %{
        "security" => %{
          "name" => "Bad Currency",
          "symbol" => "BCY",
          "currency_code" => ""
        }
      })
      |> render_submit()

    assert html =~ "id=\"security-form-error\""
    assert html =~ "currency"
    assert html =~ "value=\"Bad Currency\""
    assert html =~ "value=\"BCY\""
  end

  test "lists existing securities", %{conn: conn} do
    assert {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Zebra Holdings",
               symbol: "ZB",
               currency_code: "USD"
             })

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apple Inc.",
               symbol: "AAPL",
               currency_code: "USD"
             })

    assert {:ok, _} =
             Catalog.create_security(%{
               name: "Apex Fund",
               symbol: "AXP",
               currency_code: "USD"
             })

    {:ok, _view, html} = live(conn, "/securities")

    assert html =~ "Apex Fund"
    assert html =~ "Apple Inc."
    assert html =~ "Zebra Holdings"
    assert html =~ "security-list"
  end
end
