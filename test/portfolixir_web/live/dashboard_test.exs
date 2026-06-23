defmodule PortfolixirWeb.DashboardTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.Format

  defp seed_holding do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Main",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-10],
        quantity: Decimal.new("10"),
        price: Decimal.new("100.00"),
        fees: Decimal.new("0"),
        taxes: Decimal.new("0"),
        currency_code: "EUR"
      })

    {:ok, _} =
      Quotes.upsert_many(security.id, [
        %{date: Date.utc_today(), close: "120.00", source: "manual"}
      ])

    %{portfolio: portfolio, security: security}
  end

  # User story (Steve UAT #337):
  # As a brand-new user with an empty database,
  # I want the dashboard to be the onboarding wizard (workflow path + counts),
  # so that I am guided to create my first portfolio.
  #
  # Acceptance criteria:
  # - With no transactions, the dashboard shows the workflow-path wizard.
  # - The wealth overview is absent (there is nothing to value yet).
  test "the empty dashboard is the onboarding wizard", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#workflow-path")
    refute has_element?(view, "#dashboard-overview")
  end

  # User story (Steve UAT #337):
  # As a user who already has transactions,
  # I want the dashboard to answer "how is my wealth doing?" instead of the
  # setup wizard,
  # so that the dashboard stays useful as the daily entry page.
  #
  # Acceptance criteria:
  # - Once any transaction exists, the workflow-path wizard is gone.
  # - The dashboard shows a wealth overview: a per-portfolio value card (loaded
  #   async, with the portfolio's base-currency total) and recent activity.
  test "a populated dashboard shows the wealth overview, not the wizard", %{conn: conn} do
    %{portfolio: portfolio} = seed_holding()

    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "#workflow-path")
    assert has_element?(view, "#dashboard-overview")

    html = render_async(view)

    # Per-portfolio value card shows the portfolio's total incl. cash in its own
    # base currency (10 shares @ 120 = 1200 securities, less the 1000 the buy
    # took from cash = 200 total incl. cash).
    expected = Format.money(Valuation.for_portfolio(portfolio.id).total_with_cash)
    assert html =~ "Main"
    assert has_element?(view, "a#dashboard-portfolio-#{portfolio.id}[href='/portfolio']")
    assert html =~ "#{expected} EUR"

    # Recent activity surfaces the buy and links to the transactions surface.
    assert has_element?(view, "#dashboard-recent [data-role='recent-transaction']")
    assert has_element?(view, "#dashboard-recent a[href='/transactions']")
  end
end
