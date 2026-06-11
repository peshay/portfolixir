defmodule PortfolixirWeb.PortfolioLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets

  # User story:
  # As a local portfolio maintainer,
  # I want one Portfolio page showing value, cash quote, TTWROR and the
  # value-weighted allocation donut with drift, plus a way to set a cash
  # balance,
  # so that the weekly check works in the app, not only over the API.
  #
  # Acceptance criteria:
  # - The page paints immediately; the heavy figures load asynchronously and
  #   fill in (no blocking dead render, no double computation).
  # - The page shows total incl. cash, the cash quote, and the period TTWROR,
  #   formatted for the locale (en: 1,080.00).
  # - The donut renders one slice per category in the category colour, and the
  #   drift table compares actual vs. target.
  # - Switching the period re-chains the cached daily series instantly.
  # - Submitting the set-balance form records a snapshot and refreshes the
  #   shown balances.
  # - Data-quality hints expose unpriced and trade-priced positions.
  # - Without a portfolio the page points to creating one.

  defp seed_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Mein Depot", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, security} =
      Catalog.create_security(%{
        name: "World ETF",
        ticker_symbol: "WLD",
        currency_code: "EUR",
        asset_class: "etf"
      })

    today = Date.utc_today()
    start = Date.add(today, -10)

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: start,
        gross_amount: "1000",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: start,
        quantity: "8",
        price: "100",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    {:ok, _} =
      Quotes.upsert_many(security.id, [
        %{date: start, close: "100", source: "manual"},
        %{date: today, close: "110", source: "manual"}
      ])

    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Core",
        color: "#2563eb"
      })

    {:ok, _} = Classifications.assign_security(security.id, classification.id, core.id)

    {:ok, _} =
      Targets.set_targets(portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"}
      ])

    %{
      portfolio: portfolio,
      cash: cash,
      depot: depot,
      classification: classification,
      core: core
    }
  end

  test "loads the figures asynchronously and shows totals, donut and drift", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")

    html = render_async(view)

    # Securities 8 × 110 = 880, cash 200, total 1080, cash quote 18.5%.
    assert html =~ "1,080.00"
    assert html =~ "880.00"
    assert html =~ "18.5"
    # TTWROR: 1000 -> 1080 with the deposit neutralised = 8%.
    assert html =~ "8.0"
    # Sunburst slice in the category colour, legend and drift row.
    assert html =~ ~s(fill="#2563eb")
    assert html =~ "Core"
    assert html =~ "100.0"
    assert html =~ "60.0"
    # Drift: (0.6 - 1.0) * 880 = -352.
    assert html =~ "-352.00"
  end

  test "renders a nested sunburst and an indented, rolled-up child row", %{conn: conn} do
    world = seed_world()

    # Add a sub-category under Core and assign a second holding to it; Core's
    # IST must roll the child up, and the child row must render indented.
    {:ok, sub} =
      Classifications.create_category(%{
        classification_id: world.classification.id,
        name: "Core Tech",
        color: "#10b981",
        parent_id: world.core.id
      })

    {:ok, second} =
      Catalog.create_security(%{
        name: "Tech ETF",
        ticker_symbol: "TEC",
        currency_code: "EUR",
        asset_class: "etf"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: second.id,
        type: "buy",
        date: Date.add(Date.utc_today(), -10),
        quantity: "2",
        price: "50",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    {:ok, _} =
      Quotes.upsert_many(second.id, [%{date: Date.utc_today(), close: "50", source: "manual"}])

    {:ok, _} = Classifications.assign_security(second.id, world.classification.id, sub.id)

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    # Two rings: the parent ring and the child ring at different radii.
    assert html =~ ~s(class="donut sunburst")
    assert html =~ ~s(fill="#10b981")
    # The outermost ring carries the individual positions as shaded arcs
    # (PP style): no in-chart text, the security name is the tooltip title.
    assert html =~ ~s(fill-opacity)
    assert html =~ "Tech ETF"
    assert html =~ "World ETF"
    # Child row carries the nested class and the sub-category name.
    assert html =~ "is-child"
    assert html =~ "Core Tech"
  end

  test "tapping a slice echoes its details below the chart (mobile hover)", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    assert html =~ "Tap or hover a slice for details."

    html =
      render_click(view, "select_segment", %{
        "name" => "Core",
        "percent" => "100.0",
        "value" => "880.00",
        "color" => "#2563eb"
      })

    assert html =~ ~s(class="sunburst-detail")
    assert html =~ "Core"
    assert html =~ "880.00"
    refute html =~ "Tap or hover a slice for details."

    # A non-hex colour cannot reach the style attribute.
    html =
      render_click(view, "select_segment", %{
        "name" => "X",
        "percent" => "1.0",
        "value" => "1.00",
        "color" => "red;background:url(x)"
      })

    refute html =~ "url(x)"
  end

  test "switches the performance period from the cached analysis", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert view |> element(~s(button[phx-value-period="max"])) |> render() =~ "is-active"

    html = view |> element(~s(button[phx-value-period="1y"])) |> render_click()

    # No new async round needed — the cached daily series is re-chained.
    assert view |> element(~s(button[phx-value-period="1y"])) |> render() =~ "is-active"
    assert html =~ "8.0"
  end

  test "records a balance snapshot from the cash section", %{conn: conn} do
    %{cash: cash} = seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    html =
      view
      |> form("#portfolio-cash form", %{
        "balance" => %{
          "cash_account_id" => to_string(cash.id),
          "date" => Date.to_iso8601(Date.utc_today()),
          "amount" => "500"
        }
      })
      |> render_submit()

    assert html =~ "Balance updated"

    html = render_async(view)
    # Cash 500 + securities 880 = 1380.
    assert html =~ "500.00"
    assert html =~ "1,380.00"
  end

  # User story:
  # As a local portfolio maintainer with a business account,
  # I want the Portfolio page to mark cash accounts excluded from the cash
  # quote,
  # so that I see the account and its balance without it distorting my
  # private quote.
  #
  # Acceptance criteria:
  # - An excluded account stays listed in the cash section with its balance.
  # - The excluded account's row is marked as not counting toward the quote.
  # - The cash-quote KPI ignores the excluded account's balance.
  test "marks accounts excluded from the cash quote but keeps them listed", %{conn: conn} do
    world = seed_world()

    {:ok, business} =
      Portfolios.create_cash_account(%{
        portfolio_id: world.portfolio.id,
        name: "Business Account",
        currency_code: "EUR",
        counts_toward_cash_quote: false
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: world.portfolio.id,
        cash_account_id: business.id,
        type: "deposit",
        date: Date.add(Date.utc_today(), -5),
        gross_amount: "500",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    # Totals include the business cash (880 + 200 + 500 = 1,580)...
    assert html =~ "1,580.00"
    # ...but the cash quote stays 200 / 1,080 = 18.5%.
    assert html =~ "18.5"

    assert html =~ "Business Account"
    assert html =~ "not in cash quote"
  end

  test "surfaces trade-priced and unpriced positions as data-quality hints", %{conn: conn} do
    world = seed_world()

    # Bought but never quoted: valued at the trade price, flagged stale.
    {:ok, unquoted} =
      Catalog.create_security(%{
        name: "Quiet Co.",
        ticker_symbol: "QUIET",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: unquoted.id,
        type: "buy",
        date: Date.add(Date.utc_today(), -5),
        quantity: "2",
        price: "30",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    # Delivered without any price observation: cannot be valued at all.
    {:ok, unpriced} =
      Catalog.create_security(%{
        name: "Delivered Co.",
        ticker_symbol: "DLVR",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: unpriced.id,
        type: "inbound_delivery",
        date: Date.add(Date.utc_today(), -5),
        quantity: "3",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    assert html =~ "Data quality"
    assert html =~ "valued at their last trade price"
    assert html =~ "no price at all"
    assert html =~ "Delivered Co."
  end

  test "points to portfolio creation when none exists", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/portfolio")

    assert html =~ "Create one portfolio"
  end
end
