defmodule PortfolixirWeb.IncomeLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  defp dividend!(world, security, opts) do
    {:ok, tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: WorldFixtures.security_id_for(security),
        type: "dividend",
        date: Keyword.fetch!(opts, :date),
        gross_amount: Keyword.fetch!(opts, :net),
        taxes: Keyword.get(opts, :tax, "0"),
        currency_code: "EUR"
      })

    tx
  end

  defp interest!(world, opts) do
    {:ok, tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "interest",
        date: Keyword.fetch!(opts, :date),
        gross_amount: Keyword.fetch!(opts, :amount),
        currency_code: "EUR"
      })

    tx
  end

  # User story:
  # As a local portfolio maintainer,
  # I want an income page showing the dividends and interest already booked,
  # by year and per position, with a year drilldown into the single payments,
  # so that the retrospective income view works in the app, not only over the
  # API.
  #
  # Acceptance criteria:
  # - The page renders an annual year x month matrix split into dividends and
  #   interest with a totals column, and a per-position table.
  # - Clicking a year shows the per-transaction detail for that year.
  # - Money is formatted for the locale (en: 1,100.00).

  test "renders the annual matrix and per-position table, with a year drilldown", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Mein Depot", currency: "EUR")
    security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")

    dividend!(world, security, date: ~D[2025-03-15], net: "1080", tax: "20")
    interest!(world, date: ~D[2025-06-30], amount: "15")

    {:ok, view, html} = live(conn, "/income")

    # Annual matrix with the dividends series and totals column.
    assert html =~ "income-annual"
    assert html =~ "2025"
    # Gross dividends 1080 + 20 = 1100, formatted for the en locale.
    assert html =~ "1,100.00"

    # Per-position table.
    assert html =~ "income-positions"
    assert html =~ "Payer Inc"

    # Drilling into the year reveals the per-transaction detail.
    detail_html =
      view
      |> element("[phx-click='select_year'][phx-value-year='2025']")
      |> render_click()

    assert detail_html =~ "income-detail"
    assert detail_html =~ "Payer Inc"

    # Closing the drilldown hides the detail section again.
    closed_html =
      view
      |> element("[phx-click='clear_year']")
      |> render_click()

    refute closed_html =~ "income-detail"
  end

  # User story:
  # As a German-locale portfolio maintainer,
  # I want the income page's currency-conversion note to be translated,
  # so that the page is fully German and does not leak an English sentence
  # built by the domain layer.
  #
  # Acceptance criteria:
  # - With ?locale=de the conversion note renders in German.
  # - The raw English domain note is not shown in the German UI.
  test "translates the conversion note for the German locale", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Mein Depot", currency: "EUR")
    security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")
    dividend!(world, security, date: ~D[2025-03-15], net: "100", tax: "0")

    {:ok, _view, html} = live(conn, "/income?locale=de")

    assert html =~ "Originalwährung beibehalten"
    refute html =~ "original currency retained"
  end

  test "shows an empty state when the portfolio has no income yet", %{conn: conn} do
    WorldFixtures.base_world(name: "Empty Depot", currency: "EUR")

    {:ok, _view, html} = live(conn, "/income")

    assert html =~ "income-annual"
    assert html =~ "No dividends or interest booked yet."
  end

  test "points to creating a portfolio when none exists", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/income")

    assert html =~ "/portfolios"
  end
end
