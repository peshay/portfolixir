defmodule PortfolixirWeb.PortfolioLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.AllocationExcludeFixtures, only: [buy!: 5, manual_quote!: 2]

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.WorldFixtures

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
  # - The page shows total incl. cash, the cash quote, the period TTWROR and
  #   the money-weighted IRR, formatted for the locale (en: 1,080.00).
  # - The donut renders one slice per category in the category colour, and the
  #   drift table compares actual vs. target.
  # - Switching the period re-chains the cached daily series instantly.
  # - Submitting the set-balance form records a snapshot and refreshes the
  #   shown balances.
  # - Data-quality hints expose unpriced and trade-priced positions.
  # - Without a portfolio the page points to creating one.

  defp seed_world do
    %{portfolio: portfolio} =
      world = WorldFixtures.base_world(name: "Mein Depot", cash_name: "Giro", depot_name: "Depot")

    security = WorldFixtures.create_security!(name: "World ETF", ticker: "WLD")

    today = Date.utc_today()
    start = Date.add(today, -10)

    WorldFixtures.deposit!(world, "1000", start)
    WorldFixtures.buy!(world, security, quantity: "8", price: "100", date: start)

    WorldFixtures.put_quotes!(security, [{start, "100"}, {today, "110"}])

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

    Map.merge(world, %{classification: classification, core: core})
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
    # The money-weighted IRR KPI renders next to the TTWROR KPI.
    assert html =~ ~s(id="kpi-irr")
    assert html =~ "IRR"
    # Sunburst slice in the category colour, legend and drift row.
    assert html =~ ~s(fill="#2563eb")
    assert html =~ "Core"
    # Cash now joins the allocation's 100% basis (securities 880 + counting cash
    # 200 = 1080), so Core's actual share is 880/1080 = 81.5%, not 100%, and the
    # cash row reports the 200 EUR / 18.5% share (issue #335).
    assert html =~ "81.5"
    assert html =~ "60.0"
    # Drift: 0.6 * 1080 - 880 = -232.
    assert html =~ "-232.00"
    # The dedicated cash row in the drift table.
    assert html =~ ~s(data-role="allocation-cash")
    assert html =~ "Cash"
  end

  # User story:
  # As a local portfolio maintainer who steers a cash quote (issue #335),
  # I want the cash row to show its SOLL target and drift (not a dash) when a
  # cash target is set, and the sunburst to carry a neutral cash segment,
  # so that I can read how far the actual cash share is from my target.
  #
  # Acceptance criteria:
  # - With a cash target set, the cash row renders the target percent and a
  #   drift amount in the base currency (the non-zero-target branch), not "—".
  # - The sunburst carries the neutral cash colour for the cash segment.
  test "renders the cash row target and drift when a cash target is set", %{conn: conn} do
    world = seed_world()

    # Steer a 10% cash quote: actual cash 200/1080 = 18.5% vs. 10% target.
    {:ok, _} = Portfolios.set_cash_target(world.portfolio, Decimal.new("0.10"))

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    cash_row = view |> element(~s([data-role="allocation-cash"])) |> render()
    # The non-zero-target branch: the target percent renders instead of a dash.
    assert cash_row =~ "10.0"
    # The drift cell renders an amount in the base currency, not a dash.
    assert cash_row =~ "EUR"
    refute cash_row =~ "—"

    # The neutral cash colour is used for the cash segment / swatch.
    assert html =~ "#0ea5e9"
  end

  # User story:
  # As a local portfolio maintainer with no spare cash counting toward the quote,
  # I want the allocation to omit the cash sunburst segment (and legend entry)
  # while still showing the cash row at zero,
  # so that an empty cash quote does not draw a phantom slice (issue #335).
  #
  # Acceptance criteria:
  # - With zero counting cash, the cash row still renders at a 0 value.
  # - The cash row shows the dash for target and drift (the zero-target branch).
  test "omits the cash sunburst segment when there is no counting cash", %{conn: conn} do
    %{portfolio: portfolio} =
      world = WorldFixtures.base_world(name: "No Cash Depot")

    security = WorldFixtures.create_security!(name: "Solo ETF", ticker: "SOLO")

    today = Date.utc_today()
    start = Date.add(today, -10)

    # Deposit exactly the buy cost so the cash account ends at zero: counting
    # cash is 0, so the sunburst carries no cash segment.
    WorldFixtures.deposit!(world, "800", start)
    WorldFixtures.buy!(world, security, quantity: "8", price: "100", date: start)
    WorldFixtures.put_quotes!(security, [{start, "100"}, {today, "110"}])

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
        %{"category_id" => core.id, "target_weight" => "1.0"}
      ])

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    # The cash row still renders, at zero value and with the dash (zero-target
    # branch); there is no counting cash to steer.
    cash_row = view |> element(~s([data-role="allocation-cash"])) |> render()
    assert cash_row =~ "0.00"
    assert cash_row =~ "—"
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

  # User story:
  # As a local portfolio maintainer hovering the allocation sunburst,
  # I want an instant custom tooltip with the slice's name, value and
  # percentage,
  # so that I see the details immediately rather than after the browser's
  # native <title> delay.
  #
  # Acceptance criteria:
  # - The sunburst container carries the SunburstTooltip JS hook so the client
  #   can render an instant tooltip on hover.
  # - Each slice is server-rendered with stable data-label, data-value and
  #   data-percent attributes the hook reads, and keeps a native <title> as a
  #   no-JS fallback.
  test "the sunburst carries the tooltip hook and per-slice data attributes", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    # The container opts into the instant-tooltip hook.
    assert html =~ ~s(phx-hook="SunburstTooltip")
    # Slices carry the data the hook reads, plus the native <title> fallback.
    assert html =~ ~s(data-label="Core")
    assert html =~ ~s(data-percent=)
    assert html =~ ~s(data-value=)
    assert html =~ "<title>"
  end

  # User story:
  # As a local portfolio maintainer setting target weights across a
  # hierarchical classification tree,
  # I want subtle consistency hints showing whether my sub-category targets add
  # up to their parent's target and whether the top-level targets add up to
  # 100%,
  # so that I can spot diverging targets at a glance without the app blocking me
  # from saving freely chosen weights.
  #
  # Acceptance criteria:
  # - The allocation header shows "Σ target top level: Z%", highlighted when
  #   Z ≠ 100%.
  # - A parent category with child targets shows "subcategories: X% of Y%",
  #   shown yellow when X ≠ Y.
  # - The hints are advisory only; the target save path stays unchanged.
  test "shows top-level and parent target consistency hints when targets diverge",
       %{conn: conn} do
    world = seed_world()

    # Core has a 60% target (top level sum = 60% ≠ 100% → header highlighted).
    {:ok, tech} =
      Classifications.create_category(%{
        classification_id: world.classification.id,
        name: "Core Tech",
        color: "#10b981",
        parent_id: world.core.id
      })

    {:ok, bonds} =
      Classifications.create_category(%{
        classification_id: world.classification.id,
        name: "Core Bonds",
        color: "#f59e0b",
        parent_id: world.core.id
      })

    # Children target 0.3 + 0.2 = 0.5 ≠ Core's 0.6 → parent hint yellow.
    {:ok, _} =
      Targets.set_targets(world.portfolio.id, world.classification.id, [
        %{"category_id" => tech.id, "target_weight" => "0.3"},
        %{"category_id" => bonds.id, "target_weight" => "0.2"}
      ])

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    # Top-level Σ hint, highlighted because 60% ≠ 100%.
    top = view |> element(~s([data-role="target-sum-top-level"])) |> render()
    assert top =~ "60.0"
    assert top =~ "is-target-mismatch"

    # Parent hint under Core: subcategories 50% of 60%, yellow.
    parent = view |> element(~s([data-role="target-consistency-hint"])) |> render()
    assert parent =~ "50.0"
    assert parent =~ "60.0"
    assert parent =~ "is-target-mismatch"
    assert html =~ "subcategories"
  end

  # User story (consistency, continued):
  # When the targets are consistent (children sum to the parent and the top
  # level sums to 100%) the hints carry no highlight.
  #
  # Acceptance criteria:
  # - With consistent targets the header hint shows 100% without the mismatch
  #   class.
  # - A parent whose children sum to its target shows the hint without the
  #   mismatch class.
  test "shows consistent target hints without highlight when targets add up",
       %{conn: conn} do
    world = seed_world()

    # Reset Core to a full 100% target so the top level sums to 100%.
    {:ok, _} =
      Targets.set_targets(world.portfolio.id, world.classification.id, [
        %{"category_id" => world.core.id, "target_weight" => "1.0"}
      ])

    {:ok, tech} =
      Classifications.create_category(%{
        classification_id: world.classification.id,
        name: "Core Tech",
        color: "#10b981",
        parent_id: world.core.id
      })

    {:ok, bonds} =
      Classifications.create_category(%{
        classification_id: world.classification.id,
        name: "Core Bonds",
        color: "#f59e0b",
        parent_id: world.core.id
      })

    # Children target 0.6 + 0.4 = 1.0 = Core's 1.0 → consistent.
    {:ok, _} =
      Targets.set_targets(world.portfolio.id, world.classification.id, [
        %{"category_id" => tech.id, "target_weight" => "0.6"},
        %{"category_id" => bonds.id, "target_weight" => "0.4"}
      ])

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    top = view |> element(~s([data-role="target-sum-top-level"])) |> render()
    assert top =~ "100.0"
    refute top =~ "is-target-mismatch"

    parent = view |> element(~s([data-role="target-consistency-hint"])) |> render()
    assert parent =~ "100.0"
    refute parent =~ "is-target-mismatch"
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
  # As a local portfolio maintainer with a reserve account,
  # I want the Portfolio page to mark cash accounts excluded from the cash
  # quote,
  # so that I see the account and its balance without it distorting my
  # deployable cash.
  #
  # Acceptance criteria:
  # - A reserve account stays listed in the cash section with its balance.
  # - The reserve account's row is marked as not counting toward the quote.
  # - The cash-quote KPI ignores the reserve account's balance.
  test "marks accounts excluded from the cash quote but keeps them listed", %{conn: conn} do
    world = seed_world()

    {:ok, business} =
      Portfolios.create_cash_account(%{
        portfolio_id: world.portfolio.id,
        name: "Business Account",
        currency_code: "EUR",
        liquidity_role: "reserve"
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
    assert html =~ "reserve"
  end

  # User story:
  # As a local portfolio maintainer with a credit line and an overdrawn account,
  # I want each non-deployable cash row labelled with its reason,
  # so that I can tell a drawn/standing credit line and an overdrawn account
  # apart from genuine deployable cash.
  #
  # Acceptance criteria:
  # - A credit_line account is labelled "credit line" (never deployable, even
  #   when its balance is positive — type beats sign).
  # - An overdrawn free_cash account is labelled "not in cash quote".
  test "labels non-deployable cash rows by their liquidity role", %{conn: conn} do
    world = seed_world()

    {:ok, lombard} =
      Portfolios.create_cash_account(%{
        portfolio_id: world.portfolio.id,
        name: "Lombard Loan",
        currency_code: "EUR",
        liquidity_role: "credit_line"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: world.portfolio.id,
        cash_account_id: lombard.id,
        type: "deposit",
        date: Date.add(Date.utc_today(), -5),
        gross_amount: "100",
        currency_code: "EUR"
      })

    {:ok, overdrawn} =
      Portfolios.create_cash_account(%{
        portfolio_id: world.portfolio.id,
        name: "Overdrawn Giro",
        currency_code: "EUR",
        liquidity_role: "free_cash"
      })

    {:ok, _} =
      Ledger.set_cash_balance(overdrawn, %{date: Date.add(Date.utc_today(), -5), amount: "-50"})

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    # A positive credit line is still non-deployable (type beats sign).
    assert html =~ "Lombard Loan"
    assert html =~ "credit line"
    # An overdrawn free_cash account renders the catch-all hint.
    assert html =~ "Overdrawn Giro"
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

  # User story:
  # As a local portfolio maintainer holding a store-of-value position,
  # I want the Portfolio page to mark a security excluded from allocation
  # targets,
  # so that it stays in my totals but is shown outside the allocation steering
  # basis instead of distorting the drift table.
  #
  # Acceptance criteria:
  # - The excluded position is rendered in a separate "Outside the steering
  #   basis" block with its summed value.
  # - The remaining category's actual weight rises to 100% of the steered part.
  # - The total portfolio value is unchanged by the flag.
  test "renders an excluded allocation block outside the steering basis", %{conn: conn} do
    world = seed_world()

    {:ok, bitcoin} =
      Catalog.create_security(%{
        name: "Bitcoin",
        ticker_symbol: "BTC",
        currency_code: "EUR",
        asset_class: "crypto",
        excluded_from_allocation_targets: true
      })

    # Fund the Bitcoin buy so the cash account stays at its 200 EUR balance (no
    # overdraft) — counting cash then enters the allocation basis cleanly.
    WorldFixtures.deposit!(world, "400", Date.add(Date.utc_today(), -6))
    buy!(world, bitcoin.id, "4", "100", Date.add(Date.utc_today(), -5))
    manual_quote!(bitcoin.id, "100")

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    excluded = view |> element(~s([data-role="allocation-excluded"])) |> render()
    assert excluded =~ "Outside the steering basis"
    assert excluded =~ "400.00"

    # The steering basis excludes Bitcoin (400) but now INCLUDES the counting
    # cash (200): basis = ETF 880 + cash 200 = 1080, so Core is 880/1080 = 81.5%
    # and the cash row is 200/1080 = 18.5% (issues #329 + #335 together).
    assert html =~ "81.5"
    assert html =~ ~s(data-role="allocation-cash")
    # The total is unchanged by the exclude flag: ETF 880 + BTC 400 + cash 200
    # (200 start + 400 deposit - 400 Bitcoin buy) = 1,480.
    assert html =~ "1,480.00"
  end

  test "points to portfolio creation when none exists", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/portfolio")

    assert html =~ "Create one portfolio"
  end
end
