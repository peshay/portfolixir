defmodule PortfolixirWeb.DashboardLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "root route renders the product dashboard", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "h1", "Dashboard")
    assert has_element?(view, "#nav-dashboard.app-shell-nav-link.is-active")
    assert has_element?(view, "#dashboard-primary-action")
    assert has_element?(view, "#dashboard-securities-card")
    assert has_element?(view, "#dashboard-transactions-card")
    assert has_element?(view, "#dashboard-imports-card")
    assert has_element?(view, "#dashboard-chart-placeholder")
    refute has_element?(view, "#security-listing")
    refute has_element?(view, "h1", "All Securities")
    assert html =~ "Dashboard"
  end

  test "dashboard has exactly one visually dominant primary action when no data exists", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, "/")

    primary_action_matches =
      Regex.scan(
        ~r/id=\"dashboard-primary-action\"[^>]*class=\"[^\"]*app-shell-primary[^\"]*\"/,
        html
      )

    assert length(primary_action_matches) == 1
    assert has_element?(view, "#dashboard-primary-action", "Import portfolio data")
  end

  test "dashboard shows product status cards with persisted counts", %{conn: conn} do
    {:ok, _security} =
      Catalog.create_security(%{
        name: "Seeded security",
        symbol: "SEED",
        currency_code: "EUR"
      })

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Portfolio One", base_currency_code: "EUR"})

    {:ok, deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio.id,
        name: "Portfolio One Cash",
        currency_code: "EUR"
      })

    {:ok, _transaction} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "deposit",
        date: ~D[2026-05-01],
        currency_code: "EUR",
        amount: Decimal.new("50.00")
      })

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#dashboard-securities-card", "1")
    assert has_element?(view, "#dashboard-transactions-card", "1")
    assert has_element?(view, "#dashboard-imports-card")
    assert has_element?(view, "#dashboard-primary-action", "Add document")
  end

  test "dashboard shows the chart placeholder and no fake value cards", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#dashboard-chart-placeholder")

    assert has_element?(
             view,
             "#dashboard-chart-placeholder",
             "Portfolio value chart will appear here once valuations are available."
           )

    refute String.contains?(html, "P&L")
    refute String.contains?(html, "€")
    refute String.contains?(html, "$")
  end

  test "secondary routes still work from the dashboard baseline", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Baseline Portfolio", base_currency_code: "EUR"})

    {:ok, deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio.id,
        name: "Baseline cash",
        currency_code: "EUR"
      })

    {:ok, _security_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        reference_deposit_account_id: deposit_account.id,
        name: "Baseline depot",
        currency_code: "EUR"
      })

    {:ok, _view, html} = live(conn, "/securities")
    assert html =~ "All Securities"

    {:ok, _view, html} = live(conn, "/transactions")
    assert html =~ "Transactions"
    assert html =~ "No transactions yet"

    {:ok, _view, html} = live(conn, "/taxonomies")
    assert html =~ "Classifications"
    assert html =~ "Taxonomies"
  end

  test "German locale renders translated dashboard action and placeholder", %{conn: conn} do
    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Portfoliodaten importieren"
    assert html =~ "Der Portfolio-Wert-Chart erscheint hier, sobald Bewertungen verfügbar sind."
  end
end
