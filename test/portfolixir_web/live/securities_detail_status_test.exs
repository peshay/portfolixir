defmodule PortfolixirWeb.SecuritiesDetailStatusTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  @status_selector ~s([data-role="detail-valuation-status"])

  defp deliver!(world, security, quantity, currency) do
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: security.id,
        type: "inbound_delivery",
        date: ~D[2026-01-05],
        quantity: quantity,
        currency_code: currency
      })
  end

  # User story (#406):
  # As a local portfolio maintainer,
  # I want the security detail to state whether the position is counted in
  # the portfolio totals and, if not, why — with the same price-resolution
  # semantics the totals use,
  # so that the detail and the portfolio page can never contradict each
  # other about whether a price exists.
  #
  # Acceptance criteria:
  # - A held security with a price but no FX path to EUR shows a status with
  #   the native price and currency and the missing-rate reason.
  # - A held security with no resolvable price shows a "no price" status.
  # - A held quote-less security priced by the global trade fallback shows a
  #   trade-priced status (counted in totals, stale price flagged).
  # - A security valued from a current quote shows no status line.
  # - A security that is not held shows no status line.

  test "held security with a quote but no FX path shows the missing-rate status",
       %{conn: conn} do
    world = WorldFixtures.base_world()

    {:ok, spacey} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Space Exploration Co.",
        ticker_symbol: "SPACE",
        currency_code: "USD",
        asset_class: "equity"
      })

    deliver!(world, spacey, "5", "USD")
    WorldFixtures.put_quote!(spacey, ~D[2026-06-01], "120")

    {:ok, view, _html} = live(conn, "/securities/#{spacey.id}")

    status = view |> element(@status_selector) |> render()
    assert status =~ "Not counted"
    assert status =~ "120.00"
    assert status =~ "USD"
    assert status =~ "no exchange rate to EUR"
  end

  test "held security with no resolvable price shows the no-price status", %{conn: conn} do
    world = WorldFixtures.base_world()

    {:ok, dark} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Delivered Co.",
        ticker_symbol: "DLVR",
        currency_code: "EUR",
        asset_class: "equity"
      })

    deliver!(world, dark, "3", "EUR")

    {:ok, view, _html} = live(conn, "/securities/#{dark.id}")

    status = view |> element(@status_selector) |> render()
    assert status =~ "Not counted"
    assert status =~ "no price"
  end

  test "held quote-less security priced by a trade shows the trade-priced status",
       %{conn: conn} do
    world = WorldFixtures.base_world()
    quiet = WorldFixtures.create_security!(name: "Quiet Co.", ticker: "QUIET")
    WorldFixtures.buy!(world, quiet, quantity: "2", price: "30")

    {:ok, view, _html} = live(conn, "/securities/#{quiet.id}")

    status = view |> element(@status_selector) |> render()
    assert status =~ "last own trade price"
    assert status =~ "30.00"
    assert status =~ "EUR"
  end

  test "a quote-valued or not-held security shows no status line", %{conn: conn} do
    world = WorldFixtures.base_world()

    valued = WorldFixtures.create_security!(name: "World ETF", ticker: "WLD")
    WorldFixtures.buy!(world, valued, quantity: "8", price: "100")
    WorldFixtures.put_quote!(valued, Date.utc_today(), "110")

    not_held = WorldFixtures.create_security!(name: "Watchlist Co.", ticker: "WTCH")

    {:ok, view, _html} = live(conn, "/securities/#{valued.id}")
    refute has_element?(view, @status_selector)

    {:ok, view, _html} = live(conn, "/securities/#{not_held.id}")
    refute has_element?(view, @status_selector)
  end
end
