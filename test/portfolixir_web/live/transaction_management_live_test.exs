defmodule PortfolixirWeb.TransactionManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  # User story (#471):
  # As a maintainer with several portfolios,
  # I want the Transactions page to name the active portfolio and let me switch,
  # so that I never record a buy/sell into the wrong portfolio unknowingly.
  #
  # Acceptance criteria:
  # - The page renders a portfolio strip naming the active portfolio and the
  #   other portfolios as switchable chips.
  # - Switching changes which portfolio is active (its depots are offered).
  # - A transaction recorded after switching books into the switched-to
  #   portfolio, not the one that happened to be first.
  test "names the active portfolio and switches which portfolio books a transaction",
       %{conn: conn} do
    alpha =
      WorldFixtures.base_world(name: "Alpha", depot_name: "Alpha Depot", cash_name: "Alpha Cash")

    beta =
      WorldFixtures.base_world(name: "Beta", depot_name: "Beta Depot", cash_name: "Beta Cash")

    security = WorldFixtures.create_security!(name: "Switch Co", ticker: "SWC")

    {:ok, view, html} = live(conn, "/transactions")

    # The strip names both portfolios; the first-created one is active.
    assert html =~ "Alpha"
    assert html =~ "Beta"
    assert has_element?(view, "#portfolio-switch-#{alpha.portfolio.id}.is-active")
    refute has_element?(view, "#portfolio-switch-#{beta.portfolio.id}.is-active")

    # Switching to Beta exposes Beta's depot, not Alpha's.
    switched = view |> element("#portfolio-switch-#{beta.portfolio.id}") |> render_click()
    assert switched =~ "Beta Depot"
    refute switched =~ "Alpha Depot"
    assert has_element?(view, "#portfolio-switch-#{beta.portfolio.id}.is-active")

    # A transaction recorded now books into Beta, not the first portfolio.
    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-02-01",
        "securities_account_id" => to_string(beta.depot.id),
        "security_id" => to_string(WorldFixtures.security_id_for(security)),
        "quantity" => "3",
        "price" => "100",
        "currency_code" => "EUR"
      }
    })

    assert Ledger.list_transactions_for_portfolio(beta.portfolio.id) != []
    assert Ledger.list_transactions_for_portfolio(alpha.portfolio.id) == []
  end

  # A single-portfolio install still names the active portfolio (no ambiguity,
  # but the user should see which one they are booking into).
  test "names the only portfolio when there is just one", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Solo")

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(view, "#portfolio-switch-#{world.portfolio.id}.is-active")
  end

  # An unknown portfolio id (e.g. one deleted in another tab) is a no-op: the
  # active portfolio is left unchanged rather than blanking the page.
  test "selecting an unknown portfolio leaves the active one unchanged", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Solo")

    {:ok, view, _html} = live(conn, "/transactions")

    render_hook(view, "select_portfolio", %{"id" => "999999"})

    assert has_element?(view, "#portfolio-switch-#{world.portfolio.id}.is-active")
  end
end
