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

    {:ok, view, html} = live(conn, "/cashflow")

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
  # User story:
  # As a maintainer scanning the income surface,
  # I want the EUR-hub conversion explanation behind an on-demand ⓘ tooltip,
  # so that the sightline keeps a terse basis line and the methodology stays
  # reachable without permanent prose (UX-DR11, Sprint 5 Lane D).
  #
  # Acceptance criteria:
  # - The full conversion sentence renders inside a role="tooltip" body
  #   behind an ⓘ summary, not as free-standing prose.
  # - A terse visible line still names the display currency.
  test "the EUR-hub conversion note is an on-demand tooltip", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Mein Depot", currency: "EUR")
    security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")
    dividend!(world, security, date: ~D[2025-03-15], net: "100", tax: "0")

    {:ok, view, _html} = live(conn, "/cashflow")

    note = view |> element(~s([data-role="income-conversion"])) |> render()
    assert note =~ "ⓘ"
    assert note =~ ~s(role="tooltip")
    assert note =~ "original currency retained"
  end

  test "translates the conversion note for the German locale", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Mein Depot", currency: "EUR")
    security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")
    dividend!(world, security, date: ~D[2025-03-15], net: "100", tax: "0")

    {:ok, _view, html} = live(conn, "/cashflow?locale=de")

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

    {:ok, _view, german} = live(conn, "/cashflow?locale=de")

    assert german =~ "Mär"
    assert german =~ "Okt"
    assert german =~ "Dez"
    refute german =~ ">Oct<"
    refute german =~ ">Dec<"

    {:ok, _view, english} = live(conn, "/cashflow?locale=en")
    assert english =~ "Oct"
    assert english =~ "Dec"
  end

  test "shows an empty state when the portfolio has no income yet", %{conn: conn} do
    WorldFixtures.base_world(name: "Empty Depot", currency: "EUR")

    {:ok, _view, html} = live(conn, "/cashflow")

    assert html =~ "income-annual"
    assert html =~ "No dividends or interest booked yet."
  end

  test "points to creating a depot and cash account when no accounts exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/cashflow")

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

    {:ok, view, _html} = live(conn, "/cashflow")

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

    {:ok, view, _html} = live(conn, "/cashflow")

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

    {:ok, view, _html} = live(conn, "/cashflow")

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

  # User story (#672, UX-DR4 and the 2026-08-05 design session):
  # As a local portfolio maintainer,
  # I want the Income page to live under a Cash flow area,
  # so that realized gains, external flows and costs have somewhere to land
  # that is not called "income" — the Portfolio Performance ambiguity the whole
  # rename exists to remove.
  #
  # Acceptance criteria:
  # - `/cashflow` serves the surface; `/income` permanently redirects to it, so
  #   existing links survive.
  # - The Wealth tab reads "Cash flow" and is current on the new route.
  # - The sidebar's Wealth entry claims `/cashflow` (UX-DR4 reachability).
  # - An unknown facet falls back to the default rather than erroring.
  describe "the /cashflow parent (#672)" do
    defp cashflow_world do
      world = WorldFixtures.base_world(name: "Cashflow", currency: "EUR")
      security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")

      dividend!(world, security, date: ~D[2026-02-10], net: "100", tax: "0")
      dividend!(world, security, date: ~D[2026-03-10], net: "50", tax: "0")
      interest!(world, date: ~D[2026-02-20], amount: "10")

      world
    end

    test "/cashflow serves the surface and names the area", %{conn: conn} do
      cashflow_world()

      {:ok, view, html} = live(conn, "/cashflow")

      assert html =~ "Cash flow"
      assert has_element?(view, "#income-annual")

      # The Wealth tab row points at the new route and marks it current.
      assert has_element?(view, ".area-tab[href='/cashflow'][aria-current='page']")
    end

    test "/income redirects to /cashflow so old links survive", %{conn: conn} do
      cashflow_world()

      assert conn |> get("/income") |> redirected_to() == "/cashflow"
    end

    test "the sidebar's Wealth entry is current on /cashflow", %{conn: conn} do
      cashflow_world()

      {:ok, _view, html} = live(conn, "/cashflow")

      assert html =~ ~r/nav-link[^>]*is-active[^>]*href="\/portfolio"/ or
               html =~ ~r/href="\/portfolio"[^>]*aria-current="page"/
    end

    test "an unknown facet falls back to the default instead of erroring", %{conn: conn} do
      cashflow_world()

      {:ok, view, _html} = live(conn, "/cashflow?tab=__nope__")

      assert has_element?(view, "#income-annual")
    end
  end

  # User story (#672, EXPERIENCE.md "Every aggregate names what it aggregates"):
  # As a maintainer reading a number on this page,
  # I want each figure to say what it contains and what it leaves out,
  # so that "income" stops being the ambiguous word the rename was supposed to
  # fix.
  #
  # Acceptance criteria:
  # - The surface states its composition once, in the operator's terms.
  # - It states what it EXCLUDES, since those omissions are the reason the
  #   other facets exist.
  # - Aggregated figures read alone (chart aria-labels) name their content
  #   rather than saying "income".
  # - The chart and the matrix do not disagree: bars carry the same
  #   dividends/interest split the table shows.
  describe "naming what is aggregated (#672)" do
    test "the surface states its composition and its exclusions once", %{conn: conn} do
      world = WorldFixtures.base_world(name: "Naming", currency: "EUR")
      security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")
      dividend!(world, security, date: ~D[2026-02-10], net: "100", tax: "0")

      {:ok, view, _html} = live(conn, "/cashflow")

      composition = view |> element("[data-role='facet-composition']") |> render()
      assert composition =~ "Dividends and interest"

      # The omissions are named, because they are the reason the sibling facets
      # exist at all.
      assert composition =~ "realized gains"
      assert composition =~ "deposits"
    end

    test "the charts name what they aggregate rather than saying 'income'", %{conn: conn} do
      world = WorldFixtures.base_world(name: "Labels", currency: "EUR")
      security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")
      dividend!(world, security, date: ~D[2026-02-10], net: "100", tax: "0")

      {:ok, view, _html} = live(conn, "/cashflow")

      chart = view |> element("#income-chart svg") |> render()
      assert chart =~ "Dividends and interest per year"
      refute chart =~ "Total income per year"
    end

    test "the year bars carry the same split the matrix shows", %{conn: conn} do
      world = WorldFixtures.base_world(name: "Split", currency: "EUR")
      security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")

      dividend!(world, security, date: ~D[2026-02-10], net: "100", tax: "0")
      interest!(world, date: ~D[2026-02-20], amount: "25")

      {:ok, view, _html} = live(conn, "/cashflow")

      # Two segments per year, not one bar silently summing them.
      assert has_element?(view, "#income-chart [data-series='dividends'][data-year='2026']")
      assert has_element?(view, "#income-chart [data-series='interest'][data-year='2026']")
    end
  end

  # User story (#672, the owner's Portfolio Performance walkthrough of
  # 2026-08-05 — the chart they called "great as a chart"):
  # As a maintainer looking at a year of payments,
  # I want the running total across the months of that year,
  # so that I can see how the year built up rather than reading twelve
  # unrelated bars.
  #
  # Acceptance criteria:
  # - Drilling a year shows an accumulated-per-month series alongside the
  #   per-month bars.
  # - It accumulates: each month carries the sum of that month and every month
  #   before it in the year.
  # - It states what it accumulates (UX-DR21), like every other figure here.
  test "a drilled year shows the accumulated-per-month series (#672)", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Accum", currency: "EUR")
    security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")

    dividend!(world, security, date: ~D[2026-02-10], net: "100", tax: "0")
    dividend!(world, security, date: ~D[2026-04-10], net: "50", tax: "0")
    interest!(world, date: ~D[2026-04-20], amount: "25")

    {:ok, view, _html} = live(conn, "/cashflow")
    view |> element("button.income-bar-label[phx-value-year='2026']") |> render_click()

    assert has_element?(view, "#income-accumulated-chart")

    # Feb: 100. Mar: still 100 (nothing booked). Apr: 100 + 75 = 175, and it
    # stays there for the rest of the year.
    assert has_element?(view, "#income-accumulated-chart [data-month='2'][data-total='100']")
    assert has_element?(view, "#income-accumulated-chart [data-month='3'][data-total='100']")
    assert has_element?(view, "#income-accumulated-chart [data-month='4'][data-total='175']")
    assert has_element?(view, "#income-accumulated-chart [data-month='12'][data-total='175']")

    label = view |> element("#income-accumulated-chart svg") |> render()
    assert label =~ "Accumulated dividends and interest"
  end

  # User story (issue #724):
  # As a local portfolio maintainer,
  # I want the Realized-gains facet on /cashflow,
  # so that what selling actually made is readable by period — converted on
  # a stated basis, with the unconvertible sales named instead of guessed.
  #
  # Acceptance criteria:
  # - /cashflow?tab=realized renders the facet with its composition line
  #   (UX-DR21) and the facet tab row (income stays the default).
  # - The converted roll-up shows per period; a sale with no close-date rate
  #   is excluded from the totals and named in an attention data note.
  test "the realized facet shows the converted roll-up and names exclusions (#724)",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Realized", currency: "EUR")

    eur = WorldFixtures.create_security!(name: "Euro Equity", ticker: "EEQ", currency: "EUR")
    WorldFixtures.buy!(world, eur, quantity: "10", price: "100", date: ~D[2026-01-05])

    WorldFixtures.sell!(world, eur,
      quantity: "10",
      price: "120",
      fees: "9.90",
      date: ~D[2026-03-10]
    )

    gbp = WorldFixtures.create_security!(name: "Pound Equity", ticker: "PGB", currency: "GBP")

    gbp_world =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    WorldFixtures.buy!(gbp_world, gbp,
      quantity: "2",
      price: "10",
      date: ~D[2026-01-09],
      currency: "GBP"
    )

    WorldFixtures.sell!(gbp_world, gbp,
      quantity: "2",
      price: "30",
      date: ~D[2026-02-20],
      currency: "GBP"
    )

    {:ok, view, html} = live(conn, "/cashflow?tab=realized")

    # The facet tab row exists now that more than one facet has a read, and
    # the active facet is marked.
    assert has_element?(view, ~s([data-role="cashflow-facets"]))

    assert view |> element(~s([data-role="cashflow-facets"] [aria-current])) |> render() =~
             "Realized"

    assert html =~ ~s(data-role="facet-composition")
    composition = view |> element(~s([data-role="facet-composition"])) |> render()
    assert composition =~ "Excludes dividends and interest"

    # The EUR round-trip: 1190.10 proceeds − 1000 basis = 190.10.
    table = view |> element("#realized-annual") |> render()
    assert table =~ "190.10"

    # The GBP sale has no stored rate at its close date: excluded and named.
    note = view |> element(~s([data-role="realized-excluded"])) |> render()
    assert note =~ "Pound Equity"
    assert note =~ "data-note--attention"

    # Income stays the default facet, and a garbled tab degrades to it.
    {:ok, _view, default_html} = live(conn, "/cashflow")
    assert default_html =~ ~s(id="income-annual")

    {:ok, _view, garbled} = live(conn, "/cashflow?tab=nonsense")
    assert garbled =~ ~s(id="income-annual")
  end

  # User story (issue #725):
  # As a local portfolio maintainer,
  # I want the Deposits & withdrawals facet on /cashflow,
  # so that what I put in and took out is readable per period, separate
  # from what the portfolio earned — with the invested-capital difference
  # stated instead of discoverable.
  #
  # Acceptance criteria:
  # - /cashflow?tab=flows renders the facet with its composition line
  #   naming what it excludes (deliveries, balance snapshots).
  # - Deposits and withdrawals show as two series with a net; an
  #   unconvertible flow is excluded and named by its account.
  test "the flows facet shows deposits and withdrawals with the stated difference (#725)",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Flows", currency: "EUR")
    WorldFixtures.deposit!(world, "1000.00", ~D[2026-01-10])

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "removal",
        date: ~D[2026-02-20],
        gross_amount: "200.00",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/cashflow?tab=flows")

    assert view |> element(~s([data-role="cashflow-facets"] [aria-current])) |> render() =~
             "Deposits"

    composition = view |> element(~s([data-role="facet-composition"])) |> render()
    assert composition =~ "delivered"

    table = view |> element("#flows-annual") |> render()
    assert table =~ "1,000.00"
    assert table =~ "200.00"
    assert table =~ "800.00"
  end

  # User story (issue #726):
  # As a local portfolio maintainer,
  # I want the Costs facet on /cashflow,
  # so that what the portfolio cost to run — fees and taxes per period —
  # is one readable figure at overview level, not a per-transaction
  # ledger.
  #
  # Acceptance criteria:
  # - /cashflow?tab=costs renders the facet with its composition line
  #   stating the legs-not-gross series.
  # - Fees and taxes show as two series with a total; a tax refund nets
  #   against taxes; an unconvertible cost is excluded and named by its
  #   currency.
  test "the costs facet shows fees and taxes on the stated legs basis (#726)",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Costs", currency: "EUR")
    security = WorldFixtures.create_security!(name: "Charged ETF", ticker: "CHG")

    WorldFixtures.buy!(world, security,
      quantity: "10",
      price: "100",
      fees: "9.90",
      taxes: "2.10",
      date: ~D[2026-01-15]
    )

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "tax_refund",
        date: ~D[2026-03-05],
        gross_amount: "10.00",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/cashflow?tab=costs")

    assert view |> element(~s([data-role="cashflow-facets"] [aria-current])) |> render() =~
             "Costs"

    composition = view |> element(~s([data-role="facet-composition"])) |> render()
    assert composition =~ "gross"

    table = view |> element("#costs-annual") |> render()
    assert table =~ "9.90"
    assert table =~ "-10.00"
    assert table =~ "2.00"
  end

  # User story (#724 D-1 / #726, and the two rules the Sprint 8 design
  # amendment records as UX-DR25 and UX-DR26):
  # As a local portfolio maintainer whose figure is incomplete,
  # I want the exclusion named WITHOUT a control that cannot help, and a
  # deliberate limit stated where I would look for the missing detail,
  # so that the page never turns a stated limit into a failed attempt, and
  # never reads as unfinished when it is finished by decision.
  #
  # Acceptance criteria:
  # - The realized-gains exclusion note names the gap and offers no link:
  #   rate sync fetches the daily feed and cannot fill a past booking date
  #   (issue #737), so a "store the missing rates" control would fail.
  # - The Costs facet states that overview level is on purpose.
  test "an exclusion names the gap without a control that cannot act", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Depot", currency: "EUR")
    today = Date.utc_today()

    dollar = WorldFixtures.create_security!(name: "Dollar ETF", ticker: "USE", currency: "USD")

    usd =
      WorldFixtures.add_depot(world.portfolio,
        currency: "USD",
        cash_name: "USD Cash",
        depot_name: "USD Depot"
      )

    usd_world = %{portfolio: world.portfolio, depot: usd.depot, cash: usd.cash}

    WorldFixtures.buy!(usd_world, dollar,
      quantity: "10",
      price: "100",
      date: Date.add(today, -100),
      currency: "USD"
    )

    WorldFixtures.sell!(usd_world, dollar,
      quantity: "10",
      price: "120",
      date: Date.add(today, -5),
      currency: "USD"
    )

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    note = view |> element(~s([data-role="realized-excluded"])) |> render()
    assert note =~ "Dollar ETF"
    refute note =~ "<a ", "the note must not offer a control that cannot fill a past date"

    {:ok, view, _html} = live(conn, "/cashflow?tab=costs")
    composition = view |> element(~s([data-role="facet-composition"])) |> render()
    assert composition =~ "on purpose"
  end
end
