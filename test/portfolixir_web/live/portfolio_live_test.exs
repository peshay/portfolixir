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
  # - The page shows total incl. cash, the cash quote, and the period TTWROR.
  # - The donut renders one slice per category in the category colour, and the
  #   drift table compares actual vs. target.
  # - Switching the period re-computes the performance.
  # - Submitting the set-balance form records a snapshot and refreshes the
  #   shown balances.
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

    %{portfolio: portfolio, cash: cash, classification: classification}
  end

  test "shows totals, cash quote, TTWROR, donut and drift", %{conn: conn} do
    seed_world()

    {:ok, _view, html} = live(conn, "/portfolio")

    # Securities 8 × 110 = 880, cash 200, total 1080, cash quote 18.5%.
    assert html =~ "1080.00"
    assert html =~ "880.00"
    assert html =~ "18.5"
    # TTWROR: 1000 -> 1080 with the deposit neutralised = 8%.
    assert html =~ "8.0"
    # Donut slice in the category colour, legend and drift row.
    assert html =~ ~s(stroke="#2563eb")
    assert html =~ "Core"
    assert html =~ "100.0"
    assert html =~ "60.0"
    # Drift: (0.6 - 1.0) * 880 = -352.
    assert html =~ "-352.00"
  end

  test "switches the performance period", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")

    assert view |> element(~s(button[phx-value-period="max"])) |> render() =~ "is-active"

    view |> element(~s(button[phx-value-period="1y"])) |> render_click()

    assert view |> element(~s(button[phx-value-period="1y"])) |> render() =~ "is-active"
    assert render(view) =~ "8.0"
  end

  test "records a balance snapshot from the cash section", %{conn: conn} do
    %{cash: cash} = seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")

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
    # Cash 500 + securities 880 = 1380.
    assert html =~ "500.00"
    assert html =~ "1380.00"
  end

  test "points to portfolio creation when none exists", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/portfolio")

    assert html =~ "Create one portfolio"
  end
end
