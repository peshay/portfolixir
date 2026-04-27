defmodule PortfolixirWeb.SecurityManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog

  test "visiting /securities renders shared app shell", %{conn: conn} do
    {:ok, view, html} = live(conn, "/securities")

    assert has_element?(view, "a[href=\"/securities\"]")
    assert has_element?(view, "a[href=\"/taxonomies\"]")
    assert has_element?(view, "img[alt='Portfolixir']")
    assert has_element?(view, "img[alt='Portfolixir mark']")
    assert has_element?(view, "#sidebar-toggle")
    assert has_element?(view, "#theme-toggle")
    assert html =~ "id=\"theme-toggle-script\""
    assert html =~ "Securities"
  end

  test "renders an empty state when there are no securities", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/securities")

    assert html =~ "Securities"
    assert html =~ "No securities yet."
  end

  test "creates a security with name, symbol, currency_code, isin and wkn", %{conn: conn} do
    assert {:ok, _} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    {:ok, view, _html} = live(conn, "/securities")

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

    assert html =~ "Apple Inc."
    assert html =~ "AAPL"
    assert html =~ "USD"
    assert html =~ "US0378331005"
    assert html =~ "865985"
  end

  test "shows validation error when name is missing", %{conn: conn} do
    assert {:ok, _} = Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})

    {:ok, view, _html} = live(conn, "/securities")

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

    assert html =~ "name can"
    assert html =~ "blank"
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
