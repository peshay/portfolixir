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
      |> element(".link-button[phx-value-year='2025']")
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

  # User story (Steve UAT, reconsolidation):
  # As a German-locale maintainer reading the annual matrix,
  # I want the month column headers in my language,
  # so that the German UI does not leak English month abbreviations
  # (Mär/Mai/Okt/Dez, not Mar/May/Oct/Dec).
  test "localizes the month column headers", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Mein Depot", currency: "EUR")
    security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")
    dividend!(world, security, date: ~D[2025-03-15], net: "100", tax: "0")

    {:ok, _view, german} = live(conn, "/income?locale=de")

    assert german =~ "Mär"
    assert german =~ "Okt"
    assert german =~ "Dez"
    refute german =~ ">Oct<"
    refute german =~ ">Dec<"

    {:ok, _view, english} = live(conn, "/income?locale=en")
    assert english =~ "Oct"
    assert english =~ "Dec"
  end

  test "shows an empty state when the portfolio has no income yet", %{conn: conn} do
    WorldFixtures.base_world(name: "Empty Depot", currency: "EUR")

    {:ok, _view, html} = live(conn, "/income")

    assert html =~ "income-annual"
    assert html =~ "No dividends or interest booked yet."
  end

  test "points to creating a depot and cash account when no accounts exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/income")

    assert html =~ "/portfolios"
    assert html =~ "Create a depot and cash account"
    refute html =~ "Create one portfolio"
  end

  # User story (Steve UAT #415):
  # As a maintainer reading the income report,
  # I want a visual overview of income per year and the top contributors,
  # so that I can see at a glance what I earn and whether it is growing,
  # instead of only reading a wall of matrix rows.
  #
  # Acceptance criteria:
  # - A server-rendered SVG bar chart shows total income per year (role="img"
  #   + aria-label), one labelled bar per year.
  # - A top-contributors view lists the highest-earning positions first.
  # - The annual matrix stays as the backing data (chart-as-table, UX-DR10).
  test "renders a per-year income chart and a top-contributors view (#415)", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Mein Depot", currency: "EUR")
    big = WorldFixtures.create_security!(name: "Big Payer", ticker: "BIG")
    small = WorldFixtures.create_security!(name: "Small Payer", ticker: "SML")

    dividend!(world, big, date: ~D[2024-05-15], net: "800", tax: "0")
    dividend!(world, big, date: ~D[2025-05-15], net: "1000", tax: "0")
    dividend!(world, small, date: ~D[2025-05-15], net: "100", tax: "0")

    {:ok, view, _html} = live(conn, "/income")

    # Server-rendered, accessible SVG chart with one bar per year.
    assert has_element?(view, "#income-chart svg[role='img'][aria-label]")
    assert has_element?(view, "#income-chart [data-year='2024']")
    assert has_element?(view, "#income-chart [data-year='2025']")

    # Top contributors lead with the biggest earner (Big Payer: 1800 > 100).
    assert has_element?(view, "#income-top-contributors li:first-child", "Big Payer")

    # The annual matrix is still present as the backing data (UX-DR10).
    assert has_element?(view, "#income-annual table")
  end

  # User story (#560, mobile defect):
  # As a maintainer reading the income chart on a phone,
  # I want every year bar and its label reachable on a 375px viewport,
  # so that the chart is usable on mobile instead of being cut off to the
  # right with no way to scroll to the missing bars.
  #
  # Acceptance criteria:
  # - The chart content (SVG + labels) sits inside a track wrapped by a
  #   scrollable container (own overflow-x scroller, UX-DR15).
  # - The track never compresses below its labels' intrinsic width, so on a
  #   narrow viewport the container scrolls instead of clipping.
  # - Desktop is unaffected: the track still spans the full width when the
  #   container is wide enough.
  test "income charts scroll horizontally on narrow viewports (#560)", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Mein Depot", currency: "EUR")
    sec = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")

    dividend!(world, sec, date: ~D[2024-05-15], net: "800", tax: "0")
    dividend!(world, sec, date: ~D[2025-03-15], net: "100", tax: "0")

    {:ok, view, _html} = live(conn, "/income")

    # Annual chart: SVG and labels share one scrollable track.
    assert has_element?(view, "#income-chart .income-chart-track svg.income-bars")
    assert has_element?(view, "#income-chart .income-chart-track .income-bar-labels")

    # The month drilldown chart takes the same treatment.
    view |> element("#income-chart button[data-year='2025']") |> render_click()
    assert has_element?(view, "#income-month-chart .income-chart-track svg.income-bars")

    # The scroller/track pair is backed by CSS: the container scrolls,
    # the track keeps its intrinsic minimum width and full-width default.
    app_css = File.read!("priv/static/app.css")
    assert app_css =~ ~r/\.income-chart\s*\{[^}]*overflow-x:\s*auto/s
    assert app_css =~ ~r/\.income-chart-track\s*\{[^}]*min-width:\s*max-content/s

    # UX-DR15's affordance clause: the scrolled block sits in a bordered,
    # radiused container so its edge reads as an edge, not as a cut
    # (review finding; mirrors .data-table-wrapper).
    assert app_css =~ ~r/\.income-chart\s*\{[^}]*border:\s*1px solid var\(--color-border\)/s
    assert app_css =~ ~r/\.income-chart\s*\{[^}]*border-radius:\s*var\(--radius-md\)/s
  end

  # User story (Steve UAT #415 follow-up):
  # As a maintainer who spots a strong year in the overview chart,
  # I want to click that year's bar to drill into a per-month breakdown,
  # so that I can see when within the year the income landed without hunting
  # through the matrix.
  #
  # Acceptance criteria:
  # - Each year bar is a drill control (button) carrying its year.
  # - Clicking it opens that year's detail with a per-month SVG breakdown
  #   (role="img" + aria-label), the payments table staying as backing data.
  test "drilling a year bar opens its per-month breakdown (#415 follow-up)", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Mein Depot", currency: "EUR")
    sec = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")

    dividend!(world, sec, date: ~D[2025-03-15], net: "100", tax: "0")
    dividend!(world, sec, date: ~D[2025-09-20], net: "200", tax: "0")

    {:ok, view, _html} = live(conn, "/income")

    # The year bar is a drill button.
    assert has_element?(view, "#income-chart button[data-year='2025']")
    refute has_element?(view, "#income-detail")

    # Clicking it opens the year detail with a per-month breakdown chart.
    view |> element("#income-chart button[data-year='2025']") |> render_click()

    assert has_element?(view, "#income-detail")
    assert has_element?(view, "#income-month-chart svg[role='img'][aria-label]")
    # Twelve month slots, including the two paid months.
    assert has_element?(view, "#income-month-chart .income-month-bar[data-month='3']")
    assert has_element?(view, "#income-month-chart .income-month-bar[data-month='9']")
  end
end
