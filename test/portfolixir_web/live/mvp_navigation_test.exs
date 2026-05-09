defmodule PortfolixirWeb.MVPNavigationTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog

  # User story:
  # As a local portfolio maintainer,
  # I want the dashboard navigation to show only the reboot MVP workflow,
  # so that prototype import, document, taxonomy, and report surfaces do not guide my work.
  #
  # Acceptance criteria:
  # - The dashboard exposes securities, portfolios, and transactions as primary navigation.
  # - Prototype routes for imports, documents, taxonomies, and reports are absent.
  # - The dashboard describes the manual MVP path in order.
  test "dashboard renders only the reboot MVP navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#nav-dashboard[href='/']")
    assert has_element?(view, "#nav-securities[href='/securities']")
    assert has_element?(view, "#nav-portfolios[href='/portfolios']")
    assert has_element?(view, "#nav-transactions[href='/transactions']")

    refute has_element?(view, "a[href='/imports']")
    refute has_element?(view, "a[href='/documents/new']")
    refute has_element?(view, "a[href='/taxonomies']")
    refute has_element?(view, "a[href='/reports/fund-allocations']")

    assert has_element?(view, "#mvp-path", "Create securities")
    assert has_element?(view, "#mvp-path", "Create one portfolio")
    assert has_element?(view, "#mvp-path", "Link one depot to one cash account")
    assert has_element?(view, "#mvp-path", "Record manual buy and sell transactions")
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a security detail page to display stored quote history as a chart,
  # so that I can inspect manual price history without import or market sync features.
  #
  # Acceptance criteria:
  # - A security with a stored quote renders its detail page.
  # - The detail page shows a price chart.
  # - The quote history table includes the stored close price.
  test "security detail displays quote history chart", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Synthetic Global ETF",
        symbol: "SYN",
        currency_code: "EUR"
      })

    {:ok, _quote} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2026-01-02],
        close: Decimal.new("100.25"),
        currency_code: "EUR",
        source: "manual"
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-price-chart")
    assert has_element?(view, "#security-quote-history", "100.25")
  end
end
