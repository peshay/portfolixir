defmodule PortfolixirWeb.PortfolioDataQualityTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  defp seed_world do
    world = WorldFixtures.base_world(name: "Mein Depot", cash_name: "Giro", depot_name: "Depot")

    {:ok, _} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    security = WorldFixtures.create_security!(name: "World ETF", ticker: "WLD")
    WorldFixtures.deposit!(world, "1000", Date.add(Date.utc_today(), -10))
    WorldFixtures.buy!(world, security, quantity: "8", price: "100")
    WorldFixtures.put_quote!(security, Date.utc_today(), "110")

    Map.put(world, :security, security)
  end

  defp deliver!(world, security, quantity, currency) do
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: security.id,
        type: "inbound_delivery",
        date: Date.add(Date.utc_today(), -5),
        quantity: quantity,
        currency_code: currency
      })
  end

  # User story (#406):
  # As a local portfolio maintainer,
  # I want the data-quality warning to distinguish "no price at all" from
  # "price known, but no exchange rate to EUR stored",
  # so that the warning tells the truth: a priced USD position is not claimed
  # to have "no price at all" while its detail page shows one.
  #
  # Acceptance criteria:
  # - A position with no resolvable price is listed under "no price at all".
  # - A position with a native price but no FX path is listed separately,
  #   showing the price with its currency (owner decision 2026-07-31).
  # - Neither position appears in the other list.
  test "distinguishes no-price from missing-FX positions in the data-quality warning",
       %{conn: conn} do
    world = seed_world()

    # No price at all: delivered, never quoted, never traded.
    {:ok, dark} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Delivered Co.",
        ticker_symbol: "DLVR",
        currency_code: "EUR",
        asset_class: "equity"
      })

    deliver!(world, dark, "3", "EUR")

    # Priced (quote) but no USD->EUR rate stored.
    {:ok, spacey} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Space Exploration Co.",
        ticker_symbol: "SPACE",
        currency_code: "USD",
        asset_class: "equity"
      })

    deliver!(world, spacey, "5", "USD")
    WorldFixtures.put_quote!(spacey, Date.add(Date.utc_today(), -1), "120")

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    no_price = view |> element(~s([data-role="dq-no-price"])) |> render()
    assert no_price =~ "no price at all"
    assert no_price =~ "Delivered Co."
    refute no_price =~ "Space Exploration Co."

    missing_fx = view |> element(~s([data-role="dq-missing-fx"])) |> render()
    assert missing_fx =~ "Space Exploration Co."
    assert missing_fx =~ "120.00"
    assert missing_fx =~ "USD"
    assert missing_fx =~ "no exchange rate to EUR"
    refute missing_fx =~ "Delivered Co."
  end

  # User story (#561):
  # As a local portfolio maintainer reading the Wealth data-quality list,
  # I want each finding to link to the surface where it can be fixed,
  # so that a count is a path to act, not just a fact.
  #
  # Acceptance criteria:
  # - The "no price at all" finding links to the securities list pre-filtered
  #   to securities without any quote.
  # - The "valued at last trade price" finding links to the securities list
  #   pre-filtered to stale quotes.
  test "data-quality findings link to the pre-filtered securities list", %{conn: conn} do
    world = seed_world()

    {:ok, dark} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Delivered Co.",
        ticker_symbol: "DLVR",
        currency_code: "EUR",
        asset_class: "equity"
      })

    deliver!(world, dark, "3", "EUR")

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert has_element?(
             view,
             ~s([data-role="dq-no-price"] a[href="/securities?dq=missing_quote"])
           )
  end

  # User story (#406):
  # As a local portfolio maintainer,
  # I want a position that is priced only by a trade in another portfolio to
  # be valued in the totals instead of being warned about,
  # so that the totals and the security detail agree on the global
  # trade-price fallback (owner decision 2026-07-31).
  #
  # Acceptance criteria:
  # - A quote-less security delivered into one portfolio but traded in
  #   another is valued (trade-priced hint), not listed as unpriced.
  test "values a position priced only by another portfolio's trade", %{conn: conn} do
    world = seed_world()

    other = WorldFixtures.base_world(name: "Zweitdepot", cash_name: "Z Cash", depot_name: "Z")
    ghost = WorldFixtures.create_security!(name: "Ghost Co.", ticker: "GHST")
    WorldFixtures.deposit!(other, "500", Date.add(Date.utc_today(), -10))
    WorldFixtures.buy!(other, ghost, quantity: "2", price: "30")

    deliver!(world, ghost, "7", "EUR")

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    assert html =~ "valued at their last trade price"
    refute html =~ "no price at all"
  end

  # User story (#570):
  # As a local portfolio maintainer with an imported history,
  # I want the data-quality report to list securities whose derived holding
  # quantity is negative — per depot and in total — with a link to the
  # security's transactions,
  # so that import debris from unmodeled corporate actions is surfaced for
  # repair instead of flowing silently into holdings and valuation.
  #
  # Acceptance criteria:
  # - The data-quality section lists the negative position with its depot
  #   name, the negative quantity and the security's total across depots.
  # - The entry links to the security's transactions
  #   (/securities/:id?tab=transactions). No repair wizard is offered
  #   (rescope 2026-07-31; wizards beyond splits stay gated by ADR-0028).
  test "lists negative holdings per depot with totals, linking to the transactions",
       %{conn: conn} do
    world = seed_world()

    {:ok, doomed} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Doomed Co.",
        ticker_symbol: "DOOM",
        currency_code: "EUR",
        asset_class: "equity"
      })

    deliver!(world, doomed, "100", "EUR")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: doomed.id,
        type: "outbound_delivery",
        date: Date.add(Date.utc_today(), -2),
        quantity: "500",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    negative = view |> element(~s([data-role="dq-negative-holdings"])) |> render()
    assert negative =~ "Doomed Co."
    assert negative =~ "Depot"
    assert negative =~ "-400"
    assert negative =~ ~s(href="/securities/#{doomed.id}?tab=transactions")
    refute negative =~ "wizard"
  end

  # User story (#570):
  # As a local portfolio maintainer,
  # I want negative-quantity positions visibly marked on the allocation
  # surfaces instead of blending in,
  # so that a valued-but-impossible position is recognisable as import
  # debris wherever its value shows up.
  #
  # Acceptance criteria:
  # - The flat allocation worklist marks the negative position with a
  #   text chip (no colour-only signal, UX-DR7).
  test "marks negative-quantity positions in the allocation worklist", %{conn: conn} do
    world = seed_world()

    {:ok, doomed} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Doomed Co.",
        ticker_symbol: "DOOM",
        currency_code: "EUR",
        asset_class: "equity"
      })

    deliver!(world, doomed, "100", "EUR")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: doomed.id,
        type: "outbound_delivery",
        date: Date.add(Date.utc_today(), -2),
        quantity: "500",
        currency_code: "EUR"
      })

    # A quote makes the negative position valued, so it reaches allocation.
    WorldFixtures.put_quote!(doomed, Date.utc_today(), "10")

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)

    view |> element(~s([data-role="allocation-mode-flat"])) |> render_click()
    flat = view |> element(~s([data-role="flat-positions"])) |> render()

    assert flat =~ "Doomed Co."
    assert flat =~ ~s(data-role="negative-holding")
    assert flat =~ "negative quantity"
  end
end
