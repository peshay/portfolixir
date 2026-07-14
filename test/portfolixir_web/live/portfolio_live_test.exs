defmodule PortfolixirWeb.PortfolioLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Classifications
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.WorldFixtures

  # An exchange-rate provider that always fails, to drive the sync error path
  # from the LiveView process (the per-process Fake can't be primed there).
  defmodule UnreachableFx do
    @moduledoc false
    @behaviour Portfolixir.Fx.RateSync.Provider
    @impl true
    def id, do: :unreachable
    @impl true
    def fetch(_opts), do: {:error, :unreachable}
  end

  # User story:
  # As a local portfolio maintainer,
  # I want one Wealth area showing value, cash quote, TTWROR on the Holdings
  # tab and the value-weighted allocation donut with drift on the
  # Allocation & targets tab (ADR-0022), plus a way to set a cash balance,
  # so that the weekly check works in the app, not only over the API.
  #
  # Acceptance criteria:
  # - The page paints immediately; the heavy figures load asynchronously and
  #   fill in (no blocking dead render, no double computation).
  # - The page shows total incl. cash, the cash quote, the period TTWROR and
  #   the money-weighted IRR, formatted for the locale (en: 1,080.00).
  # - On the Allocation & targets tab the donut renders one slice per category
  #   in the category colour, and the drift table compares actual vs. target.
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

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core",
        color: "#2563eb"
      })

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        security.id,
        classification.id,
        core.id
      )

    {:ok, _} =
      Targets.set_targets(portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"}
      ])

    Map.merge(world, %{classification: classification, core: core})
  end

  test "loads the holdings figures asynchronously and shows the totals", %{conn: conn} do
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
  end

  # User story (fix round, UAT merge condition):
  # As a local portfolio maintainer with more than one internal portfolio,
  # I want the performance card and chart to say which portfolio they cover,
  # so that I never read the first portfolio's TTWROR as the whole instance's.
  #
  # Acceptance criteria:
  # - With two portfolios, the performance card/section carries a visible
  #   scope hint naming the covered portfolio.
  # - With a single portfolio (the common migrated case) no hint renders.
  test "the performance figures carry a scope hint on multi-portfolio instances",
       %{conn: conn} do
    seed_world()

    second =
      WorldFixtures.base_world(name: "Zweitdepot", cash_name: "Giro 2", depot_name: "Depot 2")

    WorldFixtures.deposit!(second, "500", Date.add(Date.utc_today(), -5))

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    assert has_element?(view, "[data-role='performance-scope-hint']")
    assert html =~ "Performance covers Mein Depot only"
  end

  test "no performance scope hint on a single-portfolio instance", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    refute has_element?(view, "[data-role='performance-scope-hint']")
  end

  test "the Allocation & targets tab shows the donut and drift (ADR-0022)", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")

    html = render_async(view)

    # Sunburst slice in the category colour, legend and drift row.
    assert html =~ ~s(fill="#2563eb")
    assert html =~ "Core"
    # Cash now joins the allocation's 100% basis (securities 880 + counting cash
    # 200 = 1080), so Core's actual share is 880/1080 = 81.5%, not 100%, and the
    # cash row reports the 200 EUR / 18.5% share (issue #335).
    assert html =~ "81.5"
    assert html =~ "60.0"
    # Drift (actual - target, ADR-0023): 880 - 0.6 * 1080 = +232 (overweight).
    assert html =~ "232.00"
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

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
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

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core",
        color: "#2563eb"
      })

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        security.id,
        classification.id,
        core.id
      )

    {:ok, _} =
      Targets.set_targets(portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "1.0"}
      ])

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
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
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: world.classification.id,
        name: "Core Tech",
        color: "#10b981",
        parent_id: world.core.id
      })

    {:ok, second} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Tech ETF",
        ticker_symbol: "TEC",
        currency_code: "EUR",
        asset_class: "etf"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
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

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        second.id,
        world.classification.id,
        sub.id
      )

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    html = render_async(view)

    # Two rings: the parent ring and the child ring at different radii.
    assert html =~ ~s(class="donut sunburst")
    assert html =~ ~s(fill="#10b981")
    # The outermost ring carries the individual positions as shaded arcs
    # (PP style): no in-chart text, the security name is the tooltip title.
    assert html =~ ~s(fill-opacity)
    assert html =~ "Tech ETF"
    assert html =~ "World ETF"

    # The tree starts at the top level (owner request); expanding reveals the
    # child row with its nested class and sub-category name.
    view |> element(~s([data-role="toggle-all-categories"])) |> render_click()
    expanded = view |> element(".drift-table") |> render()
    assert expanded =~ "is-child"
    assert expanded =~ "Core Tech"
  end

  test "tapping a slice echoes its details below the chart (mobile hover)", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
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

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
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
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: world.classification.id,
        name: "Core Tech",
        color: "#10b981",
        parent_id: world.core.id
      })

    {:ok, bonds} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
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

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
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
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: world.classification.id,
        name: "Core Tech",
        color: "#10b981",
        parent_id: world.core.id
      })

    {:ok, bonds} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
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

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
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

    # The default period is 1y (UAT fix round) — "max" grows unreadable as
    # the history accumulates.
    assert view |> element(~s(button[phx-value-period="1y"])) |> render() =~ "is-active"

    html = view |> element(~s(button[phx-value-period="max"])) |> render_click()

    # No new async round needed — the cached daily series is re-chained.
    assert view |> element(~s(button[phx-value-period="max"])) |> render() =~ "is-active"
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

    # No success toast on balance update — the in-place figure refresh below
    # is the confirmation (button feedback covers the in-flight state).
    refute html =~ "Balance updated"

    html = render_async(view)
    # Cash 500 + securities 880 = 1380.
    assert html =~ "500.00"
    assert html =~ "1,380.00"
  end

  # User story:
  # As a local portfolio maintainer with a foreign-currency cash account,
  # I want a button to refresh exchange rates from the portfolio page,
  # so that I can pull a missing rate and have the cash valued without leaving
  # the app or waiting for the 12 h background sync (issue #432).
  #
  # Acceptance criteria (UAT fix rounds: background run, inline status — no
  # toast; tactile button feedback because the sub-second sync made the
  # disabled state invisible):
  # - A "Sync exchange rates" button is shown in the cash section.
  # - Clicking it starts a background sync: while it runs the button is
  #   disabled and shows an inline spinner with "Syncing…".
  # - On success the button itself confirms — disabled, "✓ Up to date" — for a
  #   flash window that a :clear_fx_flash message ends, then returns to its
  #   normal label.
  # - The result line is compact: "N rates updated" plus a local HH:MM time,
  #   not a verbose sentence, and no status toast.
  test "syncs exchange rates in the background with inline status", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    assert html =~ "Sync exchange rates"

    syncing =
      view
      |> element("#portfolio-cash button", "Sync exchange rates")
      |> render_click()

    # While the background run is in flight: disabled button with an inline
    # spinner and label. (Asserted on the click-time render — the fake sync
    # completes instantly, so a fresh element query would race completion.)
    assert syncing =~ "Syncing exchange rates…"
    assert syncing =~ ~r/<button[^>]*phx-click="sync_rates"[^>]*\sdisabled/
    assert syncing =~ ~r/<button[^>]*phx-click="sync_rates"[^>]*>[\s\S]*?class="spinner"/
    assert syncing =~ "Syncing…"

    # Drain the sync and the figure reloads it kicks off.
    render_async(view)
    html = render_async(view)

    # During the flash window the button stays disabled and confirms inline.
    button = view |> element(~s(#portfolio-cash button[phx-click="sync_rates"])) |> render()
    assert button =~ "Up to date"
    assert button =~ "✓"
    assert button =~ ~r/<button[^>]*\sdisabled/

    # Compact inline result line instead of a toast: count + local HH:MM.
    result = view |> element(~s([data-role="fx-sync-result"])) |> render()
    assert result =~ ~r/\d+ rates updated/
    assert result =~ ~r/\d{2}:\d{2}/
    refute result =~ "Recalculating figures"
    refute html =~ "status-toast--success"

    # The flash timer clears the confirmation and re-arms the button.
    send(view.pid, :clear_fx_flash)
    cleared = view |> element(~s(#portfolio-cash button[phx-click="sync_rates"])) |> render()
    assert cleared =~ "Sync exchange rates"
    refute cleared =~ "Up to date"
    refute cleared =~ ~r/<button[^>]*\sdisabled/
    refute has_element?(view, ~s(#portfolio-cash button[disabled]), "Sync exchange rates")
  end

  test "shows an inline error when the exchange-rate sync fails", %{conn: conn} do
    seed_world()

    previous = Application.get_env(:portfolixir, Portfolixir.Fx.RateSync)
    Application.put_env(:portfolixir, Portfolixir.Fx.RateSync, provider: UnreachableFx)
    on_exit(fn -> Application.put_env(:portfolixir, Portfolixir.Fx.RateSync, previous) end)

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    view
    |> element("#portfolio-cash button", "Sync exchange rates")
    |> render_click()

    html = render_async(view)

    result = view |> element(~s([data-role="fx-sync-result"])) |> render()
    assert result =~ "reach the exchange-rate provider"
    refute html =~ "status-toast--error"

    # No success flash on failure: the button re-arms immediately.
    button = view |> element(~s(#portfolio-cash button[phx-click="sync_rates"])) |> render()
    assert button =~ "Sync exchange rates"
    refute button =~ "Up to date"
    refute button =~ ~r/<button[^>]*\sdisabled/
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
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Business Account",
        currency_code: "EUR",
        liquidity_role: "reserve"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
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
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Lombard Loan",
        currency_code: "EUR",
        liquidity_role: "credit_line"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: lombard.id,
        type: "deposit",
        date: Date.add(Date.utc_today(), -5),
        gross_amount: "100",
        currency_code: "EUR"
      })

    {:ok, overdrawn} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Overdrawn Giro",
        currency_code: "EUR",
        liquidity_role: "free_cash"
      })

    {:ok, _} =
      Ledger.set_cash_balance(Portfolixir.Actor.owner_ui(), overdrawn, %{
        date: Date.add(Date.utc_today(), -5),
        amount: "-50"
      })

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
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Quiet Co.",
        ticker_symbol: "QUIET",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
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
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Delivered Co.",
        ticker_symbol: "DLVR",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
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
  # As a local portfolio maintainer reading the allocation/drift table,
  # I want numeric columns right-aligned with tabular figures,
  # so that digit places, decimal separators and signs align vertically,
  # and I want negative drift values coloured red while keeping the − sign,
  # so that underweight categories (actual - target < 0, ADR-0023) are
  # visually distinct without relying on colour alone (UX-DR7 / WCAG 1.4.1).
  #
  # Acceptance criteria:
  # - Numeric cells (value, actual %, target %, drift) carry the "num" class.
  # - A drift cell with a negative value carries the "is-negative" class.
  # - The − sign character is still present in a negative drift cell (not
  #   stripped or replaced), so the information is available without colour.
  test "drift table numeric cells are right-aligned and negative drift is coloured red",
       %{conn: conn} do
    world = seed_world()

    # Raise Core's target to 90% so the row is underweight under ADR-0023:
    # drift = 880 − 0.9 × 1080 = −92.00 → negative.
    {:ok, _} =
      Targets.set_targets(world.portfolio.id, world.classification.id, [
        %{"category_id" => world.core.id, "target_weight" => "0.9"}
      ])

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)

    # The first body row is Core; select the whole drift table to inspect it.
    drift_table = view |> element(".drift-table") |> render()

    # Numeric header cells carry the "num" class for right-align/tabular-nums.
    assert drift_table =~ ~s(th class="num")

    # Numeric data cells carry the "num" class.
    assert drift_table =~ ~s(td class="num")

    # The negative drift cell carries both "num" and "is-negative".
    assert drift_table =~ ~s(is-negative)

    # The − sign character is present in the rendered output (colour is not
    # the only indicator — UX-DR7).
    assert drift_table =~ "-92.00"
  end

  # User story:
  # As a local portfolio maintainer with a foreign-currency cash account,
  # I want the data-quality section to name any cash account that is excluded
  # from the totals because no FX rate exists,
  # so that I know which accounts are missing and can sync exchange rates to
  # include them.
  #
  # Acceptance criteria:
  # - With a USD cash account and no EUR/USD rate, the data-quality section
  #   appears and names that account as uncounted.
  # - With a EUR/USD rate seeded, the warning is absent (the account is valued).
  test "surfaces unvalued foreign-currency cash accounts in data-quality section",
       %{conn: conn} do
    Classifications.ensure_builtins()

    %{portfolio: portfolio} =
      WorldFixtures.base_world(name: "FX Test Portfolio", cash_name: "EUR Giro")

    # Create a USD cash account — with no EUR/USD rate it will be unvalued.
    {:ok, usd_cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "USD Account",
        currency_code: "USD",
        liquidity_role: "free_cash"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: usd_cash.id,
        type: "deposit",
        date: Date.add(Date.utc_today(), -5),
        gross_amount: "1000",
        currency_code: "USD"
      })

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    # The data-quality section should warn about the unvalued USD account.
    assert html =~ "Data quality"
    assert html =~ "USD Account"
    assert html =~ "USD"
    assert html =~ "exchange rate"
  end

  test "no unvalued-cash warning when EUR/USD rate is present", %{conn: conn} do
    Classifications.ensure_builtins()

    %{portfolio: portfolio} =
      WorldFixtures.base_world(name: "FX OK Portfolio", cash_name: "EUR Giro")

    {:ok, usd_cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "USD Account",
        currency_code: "USD",
        liquidity_role: "free_cash"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: usd_cash.id,
        type: "deposit",
        date: Date.add(Date.utc_today(), -5),
        gross_amount: "1000",
        currency_code: "USD"
      })

    # Seed a EUR/USD rate so the account is now valued.
    {:ok, _} =
      Portfolixir.Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: Date.add(Date.utc_today(), -10),
          rate: Decimal.new("1.1"),
          source: "manual"
        }
      ])

    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    # The warning must be absent — the account is now fully valued. Match the
    # warning's own phrasing, not a bare "exchange rate": the cash section's
    # sync-rates hint also contains that string.
    refute html =~ "are not counted in the totals"
  end

  # User story (ADR-0024):
  # As a new user opening the Wealth page before any bookkeeping entities
  # exist,
  # I want the empty state to point me at creating a depot and cash account,
  # so that no screen asks for a portfolio — grouping is buckets and views.
  #
  # Acceptance criteria:
  # - With an empty database the empty state links to /portfolios and asks for
  #   a depot + cash account, never a portfolio.
  # - A portfolio record without any depots/cash accounts still shows the
  #   empty state (the record is internal; the accounts are the prerequisite).
  test "points to depot and cash-account creation when no accounts exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/portfolio")

    assert html =~ "Create a depot and cash account"
    refute html =~ "Create one portfolio"

    # An internal compatibility record alone does not unlock the page.
    {:ok, _} =
      Portfolixir.Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Ghost",
        base_currency_code: "EUR"
      })

    {:ok, _view, html} = live(conn, "/portfolio")
    assert html =~ "Create a depot and cash account"
  end

  # User story:
  # As a local portfolio maintainer reading the KPI cards,
  # I want focusable ⓘ info tooltips next to TTWROR, IRR, SOLL-IST (drift) and
  # cash quote,
  # so that I can understand what each metric measures without leaving the page
  # (WCAG 1.4.13: content is dismissible, hoverable, and persistent).
  #
  # Acceptance criteria:
  # - An ⓘ affordance (summary inside a details element) is rendered next to
  #   TTWROR, IRR, the drift table heading (SOLL-IST), and cash quote.
  # - Each tooltip body carries the explanatory text describing the metric's
  #   basis (time-weighted / annualized / target vs actual / cash ratio).
  # - The details element carries role="group" so screen readers announce the
  #   association, and aria-describedby links the KPI label to the tooltip body.
  # - All copy is delivered through gettext so it switches locale with the page.
  test "renders focusable info tooltips for TTWROR, IRR, SOLL-IST and cash quote",
       %{conn: conn} do
    seed_world()

    # The Allocation & targets tab (ADR-0022) carries the drift table; the KPI
    # cards render on both Wealth tabs.
    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    html = render_async(view)

    # TTWROR tooltip: basis must state "selected period", not annualized.
    ttwror_kpi = view |> element(~s(#kpi-ttwror)) |> render()
    assert ttwror_kpi =~ "ⓘ"
    assert ttwror_kpi =~ "selected period"
    assert ttwror_kpi =~ ~s(role="group")
    assert ttwror_kpi =~ "aria-describedby"

    # IRR tooltip: basis must state "annualized".
    irr_kpi = view |> element(~s(#kpi-irr)) |> render()
    assert irr_kpi =~ "ⓘ"
    assert irr_kpi =~ "annualized"
    assert irr_kpi =~ ~s(role="group")
    assert irr_kpi =~ "aria-describedby"

    # Cash-quote tooltip: formula must mention deployable cash.
    cash_kpi = view |> element(~s(#kpi-cash)) |> render()
    assert cash_kpi =~ "ⓘ"
    assert cash_kpi =~ "deployable cash"
    assert cash_kpi =~ ~s(role="group")
    assert cash_kpi =~ "aria-describedby"

    # SOLL-IST tooltip on the drift table: mentions target and actual weights.
    drift_section = view |> element(~s(#portfolio-allocation)) |> render()
    assert drift_section =~ "ⓘ"
    assert drift_section =~ "target"
    assert drift_section =~ "actual"
    assert drift_section =~ "drift"

    # Tooltip content is present in the rendered HTML (not hidden server-side).
    assert html =~ "time-weighted return"
    assert html =~ "money-weighted"
    assert html =~ "deployable cash"
  end

  # User story:
  # As a local portfolio maintainer clicking "Set balance",
  # I want the page to show stable placeholders while the overview and
  # performance sections reload, and the "Set balance" button to indicate
  # it is working immediately after I click it,
  # so that the page does not jump and I can tell my click was registered
  # (issue #402).
  #
  # Acceptance criteria:
  # - Before the async data arrives the performance section (Holdings tab)
  #   shows a skeleton placeholder (data-role="performance-skeleton") that
  #   reserves height.
  # - Before the async data arrives the allocation section (Allocation &
  #   targets tab, ADR-0022) shows a skeleton placeholder
  #   (data-role="allocation-skeleton") that reserves height.
  # - After async data arrives the skeletons are replaced by real content.
  # - The "Set balance" button carries phx-disable-with so the browser
  #   disables it and shows a working label immediately on submit.
  test "shows section skeletons while async is pending and real content after",
       %{conn: conn} do
    seed_world()

    {:ok, view, html} = live(conn, "/portfolio")

    # Dead render (not connected): the Holdings tab's performance section shows
    # a skeleton placeholder rather than content, so the initial paint has
    # stable height.
    assert html =~ ~s(data-role="performance-skeleton")

    # After async completes the skeleton is gone and real content is present.
    full_html = render_async(view)

    refute full_html =~ ~s(data-role="performance-skeleton")
    assert full_html =~ "security-chart"

    # The Allocation & targets tab (ADR-0022) shows its own skeleton while
    # pending and the drift table after async.
    {:ok, alloc_view, alloc_html} = live(conn, "/portfolio?tab=allocation")

    assert alloc_html =~ ~s(data-role="allocation-skeleton")

    alloc_full_html = render_async(alloc_view)

    refute alloc_full_html =~ ~s(data-role="allocation-skeleton")
    assert alloc_full_html =~ ~s(class="drift-table")
  end

  # User story (ADR-0022 — one shared chart component):
  # As a maintainer who picked a non-default accent (Teal or Coral),
  # I want the portfolio performance line to follow my chosen accent,
  # so that the chart matches the rest of the UI instead of always being violet.
  #
  # Acceptance criteria:
  # - The portfolio chart renders through the shared security-chart component,
  #   whose .quote-line stroke uses the switched --color-accent variable.
  # - The old bespoke .perf-line/.perf-chart CSS is gone (single chart path).
  test "performance line stroke follows the chosen accent variable (#411)" do
    app_css = File.read!("priv/static/app.css")

    assert app_css =~
             ~r/\.security-chart \.quote-line\s*\{[^}]*stroke:\s*var\(--color-accent[,)]/s

    refute app_css =~ ~r/\.perf-line\s*\{/s
  end

  # User story (Steve UAT #411):
  # As a maintainer reading the portfolio performance chart,
  # I want labeled value/date axes and the underlying data as an accessible
  # table, so that I can read the figures at the ends of the line and a screen
  # reader can reach the whole series (UX-DR10) — matching the security detail
  # charts that already set the quality bar.
  #
  # Acceptance criteria:
  # - The chart figure shows value-axis labels (percent) and the first/last
  #   date as date-axis labels.
  # - The series is reachable as a <table> with a caption and one row per point.
  # - The chart keeps role="img" and an aria-label.
  test "the performance chart has labeled axes and an accessible data table (#411)",
       %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    figure = view |> element("#performance-figure") |> render()

    # Value axis carries signed percent tick labels (the run climbs to ~+8%).
    assert figure =~ ~r/\+\d+(\.\d+)? %/
    # Date axis labels the most recent point with its ISO date.
    assert figure =~ Date.to_iso8601(Date.utc_today())

    # The shared chart component renders the line with accessible semantics
    # (ADR-0022: one chart path), including the TTWROR zero line.
    assert has_element?(view, "svg.security-chart[role='img'][aria-label]")
    assert figure =~ "chart-zeroline"

    # The series is reachable as a table (UX-DR10).
    assert has_element?(view, "#performance-figure table caption")
    assert has_element?(view, "#performance-figure table tbody tr")
  end

  # User story (Steve UAT #336):
  # As a maintainer reading the performance chart,
  # I want to see the selected period's result (% and €) at a glance and toggle
  # the line between the TTWROR % and the absolute € value,
  # so that the chart answers "how much am I up, in % and in money?" without a
  # mouseover, and I can read the wealth trajectory when I want it.
  #
  # Acceptance criteria:
  # - A period-performance badge shows the TTWROR % and the € gain
  #   ((end − start) − net external flows), coloured by sign.
  # - A "% (TTWROR)" ↔ "Value (€)" toggle switches the rendered series.
  # - The toggle choice survives a period switch.
  test "the performance chart has a period badge and a %/€ series toggle (#336)",
       %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    # Badge: TTWROR is +8.0% and the € gain is end(1080) − start(0) − flows(1000)
    # = +80.00, both positive.
    badge = view |> element("[data-role='period-badge']") |> render()
    assert badge =~ "+8.0"
    assert badge =~ "80.00"
    assert badge =~ "EUR"
    assert has_element?(view, "[data-role='period-badge'].is-positive")

    # The toggle label reads "% (TTWROR)" — not a doubled, over-escaped "%%"
    # (Steve UAT, reconsolidation).
    assert has_element?(view, "button[phx-value-mode='ttwror']", "% (TTWROR)")
    refute render(view) =~ "%% (TTWROR)"

    # Default series is the TTWROR %.
    assert has_element?(view, "#performance-figure[data-chart-mode='ttwror']")

    # Toggling to Value switches the rendered series (money axis, no zero line).
    view |> element("button[phx-value-mode='value']") |> render_click()
    assert has_element?(view, "#performance-figure[data-chart-mode='value']")
    # ADR-0024: the value series describes the wealth number, not a portfolio.
    assert has_element?(view, "svg.security-chart[aria-label='Value over time']")
    refute view |> element("#performance-figure") |> render() =~ "chart-zeroline"

    # The choice survives a period switch.
    view |> element("button[phx-value-period='ytd']") |> render_click()
    assert has_element?(view, "#performance-figure[data-chart-mode='value']")
  end

  # User story (Steve UAT #336/#411 follow-up):
  # As a maintainer hovering the performance line,
  # I want a crosshair tooltip showing the date, TTWROR % and € value of the
  # day under the pointer,
  # so that I can read the figure at any point in time without leaving the
  # chart. The hover itself is JS (manual UAT); this asserts the server wiring
  # the hook reads.
  #
  # Acceptance criteria:
  # - The chart is hooked with the shared ChartCrosshair (ADR-0022: one chart
  #   path) and carries a JSON payload whose per-point display label shows
  #   both series (% and € value), independent of the displayed line.
  test "the performance chart exposes a crosshair payload (#336/#411)", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    figure = view |> element("#performance-figure") |> render()
    assert figure =~ ~s(phx-hook="ChartCrosshair")

    payload = view |> element("#performance-figure script[data-chart-payload]") |> render()
    # The payload carries date · % · € points, incl. today's point and the
    # base currency, so the tooltip shows both series at once.
    assert payload =~ Date.to_iso8601(Date.utc_today())
    assert payload =~ "EUR"
    assert payload =~ "%"
  end

  test "Set balance button carries phx-disable-with for immediate working state",
       %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    button_html = view |> element("#portfolio-cash button[type=submit]") |> render()
    assert button_html =~ "phx-disable-with"
  end

  test "figures stay visible during set_balance refresh and update in place after async",
       %{conn: conn} do
    %{cash: cash} = seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    # Submit the balance form — figures stay rendered in place (no skeleton).
    # The existing content is visible immediately; no layout shift occurs.
    html_after_submit =
      view
      |> form("#portfolio-cash form", %{
        "balance" => %{
          "cash_account_id" => to_string(cash.id),
          "date" => Date.to_iso8601(Date.utc_today()),
          "amount" => "500"
        }
      })
      |> render_submit()

    # The Holdings tab keeps its performance chart in place (the allocation
    # section lives on the Allocation & targets tab since ADR-0022).
    refute html_after_submit =~ ~s(data-role="performance-skeleton")
    assert html_after_submit =~ "security-chart"

    # After the async jobs finish the updated totals are swapped in place.
    full_html = render_async(view)

    refute full_html =~ ~s(data-role="performance-skeleton")
    assert full_html =~ "1,380.00"
  end

  # User story:
  # As a local portfolio maintainer setting a cash balance,
  # I do NOT want a status toast interrupting me on success — the submit
  # button's busy state plus the figures updating in place are confirmation
  # enough, so routine balance entry stays quiet and frictionless.
  #
  # Acceptance criteria:
  # - On success, no status toast renders (no ".status-toast" element).
  # - No legacy inline alert banners render either.
  # - The submit button carries phx-disable-with busy feedback.
  test "set_balance success shows no status toast (button feedback is enough)",
       %{conn: conn} do
    %{cash: cash} = seed_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    view
    |> form("#portfolio-cash form", %{
      "balance" => %{
        "cash_account_id" => to_string(cash.id),
        "date" => Date.to_iso8601(Date.utc_today()),
        "amount" => "500"
      }
    })
    |> render_submit()

    refute has_element?(view, ".status-toast")
    refute has_element?(view, "p.alert-success")
    refute has_element?(view, "p.alert-error")

    # The button's busy state is the in-context feedback that replaces the toast.
    assert has_element?(view, "#portfolio-cash button[type=submit][phx-disable-with]")
  end

  # User story:
  # As a local portfolio maintainer tracking currency exposure,
  # I want the Currency classification view to show EUR cash inside the EUR
  # bucket and USD cash inside the USD bucket (not as a separate currency-less
  # "Cash" lump),
  # so that the sunburst and drift table reflect my actual currency exposure.
  #
  # Acceptance criteria:
  # - Switching to the Currency classification shows EUR cash in the EUR row.
  # - USD cash (after FX conversion) appears in the USD row.
  # - No currency-less "Cash" row is shown in the Currency view.
  # - The asset-class view still shows a separate Cash row (issue #335).
  # - The total basis (total_value) is identical for both classification views.
  test "currency allocation view attributes cash to its currency bucket (issue #407)",
       %{conn: conn} do
    %{portfolio: portfolio} =
      world = WorldFixtures.base_world(name: "FX Portfolio", cash_name: "EUR Giro")

    # Seed EUR/USD rate so the USD account can be valued.
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          rate: "1.1",
          date: Date.utc_today(),
          source: "manual"
        }
      ])

    {:ok, usd_cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "USD Giro",
        currency_code: "USD"
      })

    # Deposit 200 EUR into EUR account and set 110 USD (= 100 EUR) in USD account.
    WorldFixtures.deposit!(world, "200", Date.utc_today())

    {:ok, _} =
      Ledger.set_cash_balance(Portfolixir.Actor.owner_ui(), usd_cash, %{
        date: Date.utc_today(),
        amount: "110"
      })

    Classifications.ensure_builtins()
    classifications = Classifications.list_classifications()
    currency_cl = Enum.find(classifications, &(&1.key == "currency"))
    asset_cl = Enum.find(classifications, &(&1.key == "asset_class"))

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)

    # Switch to the Currency classification.
    view
    |> form("#portfolio-allocation form", %{"classification_id" => to_string(currency_cl.id)})
    |> render_change()

    html = render_async(view)

    # EUR cash (200 EUR) attributed to the EUR category row in the drift table.
    assert html =~ "EUR"
    # No currency-less cash row with data-role="allocation-cash" in currency view.
    refute has_element?(view, ~s([data-role="allocation-cash"]))

    # Switch back to the asset-class classification.
    view
    |> form("#portfolio-allocation form", %{"classification_id" => to_string(asset_cl.id)})
    |> render_change()

    asset_html = render_async(view)

    # In the asset-class view the separate Cash row is still present (issue #335).
    assert asset_html =~ ~s(data-role="allocation-cash")
    assert asset_html =~ "Cash"
  end

  # -- Story 5 (#468): per-view SOLL/drift viewer on the portfolio page --------

  # A custom Strategy tree on the base world with one Core category holding the
  # only security, plus a named view, so the viewer can read a per-view plan.
  defp viewer_world do
    %{portfolio: portfolio} =
      world = WorldFixtures.base_world(name: "Plan Depot", cash_name: "Giro", depot_name: "Depot")

    security = WorldFixtures.create_security!(name: "World ETF", ticker: "WLD")

    today = Date.utc_today()
    start = Date.add(today, -10)

    WorldFixtures.deposit!(world, "1000", start)
    WorldFixtures.buy!(world, security, quantity: "8", price: "100", date: start)
    WorldFixtures.put_quotes!(security, [{start, "100"}, {today, "110"}])

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core",
        color: "#2563eb"
      })

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        security.id,
        classification.id,
        core.id
      )

    {:ok, scoped_view} = Buckets.create_view(Actor.owner_ui(), %{name: "Strategie"})

    Map.merge(world, %{
      classification: classification,
      core: core,
      security: security,
      scoped_view: scoped_view,
      portfolio: portfolio
    })
  end

  # User story:
  # As a local portfolio maintainer rebalancing against my plan (ADR-0023),
  # I want to expand a drift-table category into its member securities, each
  # with its share of the category drift and an indicative buy/sell quantity
  # at the valuation price,
  # so that I can read what a corrective trade would look like — while the app
  # never creates, stores, or transmits an order.
  #
  # Acceptance criteria:
  # - A category with positions carries a toggle; the positions are hidden
  #   until it is expanded.
  # - An expanded category lists each security with value, weight, its share
  #   of the drift, and a sell (positive drift) / buy (negative) hint with the
  #   indicative quantity, rounded only at display (ADR-0016).
  # - There is no order button, form, or persisted state behind the hint.
  test "expands a drift category into member securities with rebalancing hints",
       %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)

    # Collapsed by default: no position rows in the drift table.
    refute has_element?(view, ~s([data-role="allocation-position"]))

    view
    |> element(~s(.drift-table [data-role="toggle-positions"]))
    |> render_click()

    drift_table = view |> element(".drift-table") |> render()

    # The member security with its value and weight (880 of 1080 = 81.5%).
    assert drift_table =~ "World ETF"
    assert drift_table =~ "880.00"

    # Its share of Core's drift (the only position: the full +232.00) and the
    # sell hint at the implied unit price: 232 × 8 / 880 ≈ 2.11 units.
    position_row = view |> element(~s([data-role="allocation-position"])) |> render()
    assert position_row =~ "232.00"
    # The hint names the unit so the quantity cannot be misread as an amount
    # (Steve UAT, reconsolidation).
    assert position_row =~ "Sell"
    assert position_row =~ "2.11"
    assert position_row =~ "units"
    # The hint renders in aligned parts (verb / ≈ / quantity / unit) so the
    # quantities line up across rows (UAT fix round).
    assert position_row =~ ~s(class="rebalance-verb")
    assert position_row =~ ~s(class="rebalance-qty")

    # Collapse again: the position rows disappear.
    view
    |> element(~s(.drift-table [data-role="toggle-positions"]))
    |> render_click()

    refute has_element?(view, ~s([data-role="allocation-position"]))
  end

  # User story:
  # As a local portfolio maintainer steering a named view,
  # I want the SOLL/Target/Drift columns and the Σ check to reflect that
  # active view's plan for the active classification,
  # so that IST and SOLL move together with the view I am looking at.
  #
  # Acceptance criteria:
  # - With a plan for (active view, classification), the drift table shows the
  #   Target and Drift columns and the "Σ target top level" check.
  # - The shown target is the active view's plan target, not another view's.
  test "shows the active view's SOLL plan target and drift on the drift table",
       %{conn: conn} do
    world = viewer_world()

    # The Strategie view's plan steers Core to 50%.
    {:ok, _} =
      Targets.set_targets(
        world.portfolio.id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.5"}],
        view: world.scoped_view.id
      )

    conn = get(conn, "/portfolio?tab=allocation&view=#{world.scoped_view.id}")
    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation&view=#{world.scoped_view.id}")
    html = render_async(view)

    # The plan-present table carries the Target/Drift columns and the Σ check.
    assert html =~ ~s(data-role="target-sum-top-level")
    assert has_element?(view, ".drift-table")

    # Core's target is the Strategie view's 50%, not a dash and not Gesamt's.
    drift_table = view |> element(".drift-table") |> render()
    assert drift_table =~ "50.0"
    # Drift (actual - target, ADR-0023): 880 - 0.5 * 1080 = +340 (overweight).
    assert drift_table =~ "340.00"
    # No "no plan" hint when a plan exists.
    refute html =~ "No target plan for this view"
  end

  # User story:
  # As a local portfolio maintainer looking at a view that has no SOLL plan for
  # the active classification,
  # I want the allocation to stay IST-only with a clear hint and a deep-link
  # into the editor (pre-selecting the view + classification),
  # so that a missing plan is explained, not blank, and easy to create.
  #
  # Acceptance criteria:
  # - The drift table renders IST-only: no Target/Drift columns, no Σ check.
  # - A hint ("No target plan for this view") is shown.
  # - The hint deep-links to /classifications/<id>?soll_view=<view_id>.
  test "shows an IST-only table with a deep-link hint when the view has no plan",
       %{conn: conn} do
    world = viewer_world()

    # Gesamt carries a plan, but the Strategie view does NOT — the active view's
    # absence is what matters (no Gesamt leak).
    {:ok, _} =
      Targets.set_targets(
        world.portfolio.id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.6"}],
        view: nil
      )

    conn = get(conn, "/portfolio?tab=allocation&view=#{world.scoped_view.id}")
    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation&view=#{world.scoped_view.id}")
    html = render_async(view)

    # IST-only: the Target/Drift Σ check is absent, the actual share is still shown.
    refute has_element?(view, ~s([data-role="target-sum-top-level"]))
    assert html =~ "81.5"

    # The no-plan hint explains the empty SOLL side and links into the editor with
    # the view + classification pre-selected.
    hint = view |> element(~s([data-role="no-plan-hint"])) |> render()
    assert hint =~ "No target plan for this view"

    href = "/classifications/#{world.classification.id}?soll_view=#{world.scoped_view.id}"
    assert has_element?(view, ~s([data-role="no-plan-hint"] a[href="#{href}"]))
  end

  # User story:
  # As a local portfolio maintainer with several views,
  # I want switching the view switcher to swap IST and SOLL together,
  # so that I never see a 200% / ghost-row mix of two plans.
  #
  # Acceptance criteria:
  # - View A (plan) shows its target; navigating to view B (no plan) drops to
  #   IST-only, and back to A restores the target — IST and SOLL move together.
  test "switching the active view swaps IST and SOLL together (no ghost rows)",
       %{conn: conn} do
    world = viewer_world()

    {:ok, other} = Buckets.create_view(Actor.owner_ui(), %{name: "Crypto"})

    # Strategie view: Core 50%. Crypto view: no plan at all.
    {:ok, _} =
      Targets.set_targets(
        world.portfolio.id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.5"}],
        view: world.scoped_view.id
      )

    # Under Strategie the SOLL is shown.
    conn = get(conn, "/portfolio?tab=allocation&view=#{world.scoped_view.id}")
    {:ok, view_a, _html} = live(conn, "/portfolio?tab=allocation&view=#{world.scoped_view.id}")
    html_a = render_async(view_a)
    assert html_a =~ ~s(data-role="target-sum-top-level")
    assert view_a |> element(".drift-table") |> render() =~ "50.0"

    # Switching to Crypto (no plan) drops to IST-only — SOLL moves with IST.
    conn = get(conn, "/portfolio?tab=allocation&view=#{other.id}")
    {:ok, view_b, _html} = live(conn, "/portfolio?tab=allocation&view=#{other.id}")
    html_b = render_async(view_b)
    refute has_element?(view_b, ~s([data-role="target-sum-top-level"]))
    assert html_b =~ "No target plan for this view"
  end

  # User story:
  # As a local portfolio maintainer steering a cash quote inside a view,
  # I want the Cash row to read that view's plan cash target,
  # so that the cash drift follows the active view's plan, not a global value.
  #
  # Acceptance criteria:
  # - With the active view's plan carrying a cash target, the cash row shows it.
  test "the cash row reads the active view's plan cash target", %{conn: conn} do
    world = viewer_world()

    # The Strategie plan steers Core 50% and cash 10%.
    {:ok, _} =
      Targets.set_targets(
        world.portfolio.id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.5"}],
        view: world.scoped_view.id
      )

    :ok = Targets.set_cash_target(world.portfolio.id, "0.1", view: world.scoped_view.id)

    conn = get(conn, "/portfolio?tab=allocation&view=#{world.scoped_view.id}")
    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation&view=#{world.scoped_view.id}")
    html = render_async(view)

    cash_row = view |> element(~s([data-role="allocation-cash"])) |> render()
    # The Strategie view's 10% cash target renders (not a dash, not Gesamt's).
    assert cash_row =~ "10.0"
    assert cash_row =~ "EUR"
    refute html =~ "No target plan for this view"
  end

  # User story (#468, optional chip marker):
  # As a local portfolio maintainer scanning the view switcher,
  # I want a subtle marker on the chips of views that already have a SOLL plan
  # for the active classification,
  # so that I can tell at a glance which views are steered and which are IST-only.
  #
  # Acceptance criteria:
  # - A view with a plan for the active classification carries data-has-plan on
  #   its chip; a view without one does not.
  test "marks view-switcher chips that have a plan for the active classification",
       %{conn: conn} do
    world = viewer_world()

    {:ok, unplanned} = Buckets.create_view(Actor.owner_ui(), %{name: "Crypto"})

    # Only the Strategie view has a plan for this classification.
    {:ok, _} =
      Targets.set_targets(
        world.portfolio.id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.5"}],
        view: world.scoped_view.id
      )

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    # The planned view's chip is marked; the unplanned view's chip is not.
    assert has_element?(view, "#view-switch-#{world.scoped_view.id}[data-has-plan]")
    refute has_element?(view, "#view-switch-#{unplanned.id}[data-has-plan]")
  end

  # User story (#468, German copy):
  # As a German-speaking maintainer on a view with no plan,
  # I want the no-plan hint in German,
  # so the bridge into the editor reads in my language.
  #
  # Acceptance criteria:
  # - With locale=de the no-plan hint reads "Kein Soll-Plan für diese Sicht".
  test "renders the no-plan hint in German", %{conn: conn} do
    world = viewer_world()

    conn = get(conn, "/portfolio?tab=allocation&view=#{world.scoped_view.id}&locale=de")

    {:ok, view, _html} =
      live(conn, "/portfolio?tab=allocation&view=#{world.scoped_view.id}&locale=de")

    html = render_async(view)

    assert html =~ "Kein Soll-Plan für diese Sicht"
    assert html =~ "Plan für diese Sicht anlegen"
  end

  # User story:
  # As a user whose holdings are not assigned to a custom classification's
  # categories, I want the allocation to point me to where I assign them (#499),
  # so the large "Unassigned" share is actionable, not a dead end.
  test "allocation hints to assign unassigned holdings on a custom classification (#499)",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Depot", cash_name: "Giro", depot_name: "Depot")
    security = WorldFixtures.create_security!(name: "World ETF", ticker: "WLD")
    today = Date.utc_today()
    start = Date.add(today, -5)
    WorldFixtures.deposit!(world, "1000", start)
    WorldFixtures.buy!(world, security, quantity: "8", price: "100", date: start)
    WorldFixtures.put_quotes!(security, [{start, "100"}, {today, "110"}])

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, _core} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    # security intentionally NOT assigned -> unassigned in this classification

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)

    view
    |> element("form[phx-change='select_classification']")
    |> render_change(%{"classification_id" => to_string(classification.id)})

    render_async(view)

    assert has_element?(view, "[data-role='unassigned-hint']")

    assert has_element?(
             view,
             "[data-role='unassigned-hint'] a[href='/classifications/#{classification.id}']"
           )
  end

  # User story:
  # As a user reading the allocation, I want the not-in-a-category bucket to use
  # one name across the donut and the table (#500), so the same thing isn't
  # called both "Unsorted" and "Unassigned" on one screen.
  test "allocation labels the not-in-a-category bucket 'Unassigned' consistently (#500)",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Depot", cash_name: "Giro", depot_name: "Depot")
    security = WorldFixtures.create_security!(name: "World ETF", ticker: "WLD")
    today = Date.utc_today()
    start = Date.add(today, -5)
    WorldFixtures.deposit!(world, "1000", start)
    WorldFixtures.buy!(world, security, quantity: "8", price: "100", date: start)
    WorldFixtures.put_quotes!(security, [{start, "100"}, {today, "110"}])

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    # no category assignment -> the holding is the unassigned remainder

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)

    view
    |> element("form[phx-change='select_classification']")
    |> render_change(%{"classification_id" => to_string(classification.id)})

    render_async(view)
    allocation = view |> element("#portfolio-allocation") |> render()

    # Both the donut data and the table row use "Unassigned"; "Unsorted" is gone.
    assert allocation =~ "Unassigned"
    refute allocation =~ "Unsorted"
  end

  # User story (Steve UAT, reconsolidation):
  # As a maintainer whose categories have no chosen colours,
  # I want the sunburst, legend and drift table to assign distinct palette
  # colours automatically,
  # so that the allocation stays readable instead of rendering every
  # category in the same fallback grey.
  test "colourless categories get distinct palette colours", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Palette Depot")

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    sec_a = WorldFixtures.create_security!(name: "Aaa Co", ticker: "AAA")
    sec_b = WorldFixtures.create_security!(name: "Bbb Co", ticker: "BBB")

    for {name, security} <- [{"First", sec_a}, {"Second", sec_b}] do
      {:ok, category} =
        Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
          classification_id: classification.id,
          name: name
        })

      {:ok, _} =
        Classifications.assign_security(
          Portfolixir.Actor.owner_ui(),
          security.id,
          classification.id,
          category.id
        )
    end

    WorldFixtures.deposit!(world, "300", ~D[2026-01-01])
    WorldFixtures.buy!(world, sec_a, quantity: "1", price: "100", date: ~D[2026-01-02])
    WorldFixtures.buy!(world, sec_b, quantity: "1", price: "200", date: ~D[2026-01-02])
    WorldFixtures.put_quote!(sec_a, Date.utc_today(), "100")
    WorldFixtures.put_quote!(sec_b, Date.utc_today(), "200")

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    html = render_async(view)

    # No category renders in the fallback grey, and the two categories get
    # two different colours.
    refute html =~ "#6b7280"

    fills =
      ~r/fill="(#[0-9a-fA-F]{6})"/
      |> Regex.scan(html)
      |> Enum.map(fn [_, color] -> color end)
      |> Enum.uniq()

    assert length(fills) >= 2
  end

  # User story (owner request, reconsolidation follow-up + UAT fix round):
  # As a local portfolio maintainer reading the allocation tree,
  # I want every category row to expand/collapse its direct children —
  # subcategories and positions alike — plus ONE expand/collapse-all toggle
  # directly above the drift table,
  # so that the first look is the top-level bird's view and I can drill down
  # to any single position without scrolling through the whole tree.
  #
  # Acceptance criteria:
  # - By default only top-level categories are visible (collapsed).
  # - A row's chevron reveals its direct children (subcategory rows and/or
  #   its own positions); collapsing an ancestor hides the whole subtree.
  # - A single toggle button reads "Expand all" while anything is collapsed;
  #   clicking it reveals every level down to the positions and flips the
  #   label to "Collapse all"; clicking again returns to the top-level view.
  test "allocation tree collapses to top level and expands down to positions",
       %{conn: conn} do
    world = seed_world()

    # Give Core a subcategory with its own security.
    {:ok, sub} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: world.classification.id,
        name: "Subcore",
        parent_id: world.core.id
      })

    sub_security = WorldFixtures.create_security!(name: "Sub ETF", ticker: "SUB")

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        sub_security.id,
        world.classification.id,
        sub.id
      )

    WorldFixtures.buy!(world, sub_security, quantity: "2", price: "50", date: ~D[2026-01-02])
    WorldFixtures.put_quote!(sub_security, Date.utc_today(), "50")

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)

    drift_table = fn -> view |> element(".drift-table") |> render() end

    # Default: the top-level category is visible, its subcategory and
    # positions are not.
    assert drift_table.() =~ "Core"
    refute drift_table.() =~ "Subcore"
    refute has_element?(view, ~s([data-role="allocation-position"]))

    # Expanding Core reveals its direct children: the subcategory row and
    # Core's own positions.
    view
    |> element(
      ~s(.drift-table [data-role="toggle-positions"][phx-value-category-id="#{world.core.id}"])
    )
    |> render_click()

    assert drift_table.() =~ "Subcore"
    assert drift_table.() =~ "World ETF"

    # The subcategory's own position stays hidden until Subcore expands too.
    refute drift_table.() =~ "Sub ETF"

    # One toggle above the table: it reads "Expand all" while collapsed,
    # expands every level down to the positions, then flips its label.
    toggle = fn -> view |> element(~s([data-role="toggle-all-categories"])) end
    assert toggle.() |> render() =~ "Expand all"

    toggle.() |> render_click()
    assert drift_table.() =~ "Sub ETF"
    assert toggle.() |> render() =~ "Collapse all"

    # Clicking again: back to the top-level bird's view, label flips back.
    toggle.() |> render_click()
    refute drift_table.() =~ "Subcore"
    refute has_element?(view, ~s([data-role="allocation-position"]))
    assert toggle.() |> render() =~ "Expand all"

    # The two separate header buttons are gone.
    refute has_element?(view, ~s([data-role="expand-all-categories"]))
    refute has_element?(view, ~s([data-role="collapse-all-categories"]))
  end

  # User story (UAT fix round):
  # As a local portfolio maintainer with unassigned holdings,
  # I want the "Unassigned" tree row to expand like a category row,
  # so that I can see WHICH securities are unassigned without leaving the
  # allocation view.
  #
  # Acceptance criteria:
  # - The Unassigned row carries a chevron toggle; expanding it lists the
  #   unassigned positions with name, market value and actual weight
  #   (target/drift stay em-dashes).
  # - The assign-hint link stays in place.
  test "the Unassigned tree row expands into its positions", %{conn: conn} do
    world = seed_world()

    # A holding that is NOT assigned in the active classification.
    loose_security = WorldFixtures.create_security!(name: "Loose ETF", ticker: "LSE")
    WorldFixtures.buy!(world, loose_security, quantity: "2", price: "50", date: ~D[2026-01-02])
    WorldFixtures.put_quote!(loose_security, Date.utc_today(), "50")

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)

    # Collapsed: the unassigned security's name is not listed.
    refute view |> element(".drift-table") |> render() =~ "Loose ETF"

    view
    |> element(
      ~s(.drift-table [data-role="toggle-positions"][phx-value-category-id="unassigned"])
    )
    |> render_click()

    drift_table = view |> element(".drift-table") |> render()
    assert drift_table =~ "Loose ETF"
    assert drift_table =~ "100.00"

    # The assign-hint link stays.
    assert has_element?(view, ~s([data-role="unassigned-hint"] a))
  end

  # User story (UAT fix round):
  # As a local portfolio maintainer drilling into the allocation tree,
  # I want the whole category-name cell to toggle the row (not only the tiny
  # chevron),
  # so that expanding a category doesn't demand pixel-precise clicking.
  #
  # Acceptance criteria:
  # - Clicking the category name cell of a row with a subtree expands it;
  #   clicking again collapses it.
  test "clicking the category name cell toggles the row's positions", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)

    refute has_element?(view, ~s([data-role="allocation-position"]))

    view
    |> element(~s(.drift-table td[phx-click="toggle_category_positions"]))
    |> render_click()

    assert has_element?(view, ~s([data-role="allocation-position"]))

    view
    |> element(~s(.drift-table td[phx-click="toggle_category_positions"]))
    |> render_click()

    refute has_element?(view, ~s([data-role="allocation-position"]))
  end

  # User story (owner request, reconsolidation follow-up + UAT fix round):
  # As a local portfolio maintainer rebalancing,
  # I want a flat positions view of the allocation, sorted by SIGNED drift,
  # so that the most-overweight positions sit on top, the most-underweight at
  # the bottom, and the list never interleaves buys and sells.
  #
  # Acceptance criteria:
  # - A "Tree | Positions" switch on the Allocation & targets tab.
  # - The positions mode lists one row per security with its category as
  #   context, plus the cash row, sorted by signed drift descending
  #   (overweight first, underweight last; no sign interleaving).
  # - Column headers re-sort (e.g. by value, and by category label
  #   case-insensitively with unassigned rows last).
  test "the flat positions view ranks by signed drift and re-sorts on demand",
       %{conn: conn} do
    world = seed_world()

    # A second, small position in a second category with a small NEGATIVE
    # drift, and a third (lowercase-named) category with an even smaller
    # POSITIVE drift — signed ordering must group the positive above the
    # negative, where absolute ordering would interleave them.
    {:ok, minor} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: world.classification.id,
        name: "Minor"
      })

    minor_security = WorldFixtures.create_security!(name: "Minor ETF", ticker: "MIN")

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        minor_security.id,
        world.classification.id,
        minor.id
      )

    WorldFixtures.buy!(world, minor_security, quantity: "1", price: "100", date: ~D[2026-01-02])
    WorldFixtures.put_quote!(minor_security, Date.utc_today(), "100")

    {:ok, aggressive} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: world.classification.id,
        name: "aggressive"
      })

    small_security = WorldFixtures.create_security!(name: "Small ETF", ticker: "SML")

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        small_security.id,
        world.classification.id,
        aggressive.id
      )

    WorldFixtures.buy!(world, small_security, quantity: "1", price: "50", date: ~D[2026-01-02])
    WorldFixtures.put_quote!(small_security, Date.utc_today(), "50")

    # Basis 1080 (880 World + 100 Minor + 50 Small + 50 cash):
    # Core   drift = 880 − 0.60 × 1080 = +232.00 (overweight)
    # Minor  drift = 100 − 0.10 × 1080 =   −8.00 (underweight)
    # Small  drift =  50 − 0.04 × 1080 =   +6.80 (overweight, |drift| < 8)
    {:ok, _} =
      Targets.set_targets(world.portfolio.id, world.classification.id, [
        %{"category_id" => world.core.id, "target_weight" => "0.6"},
        %{"category_id" => minor.id, "target_weight" => "0.1"},
        %{"category_id" => aggressive.id, "target_weight" => "0.04"}
      ])

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)

    # Switch to the flat positions view.
    view |> element(~s([data-role="allocation-mode-flat"])) |> render_click()

    flat = view |> element(~s([data-role="flat-positions"])) |> render()

    # One row per security with its category as context, plus cash.
    assert flat =~ "World ETF"
    assert flat =~ "Minor ETF"
    assert flat =~ "Small ETF"
    assert flat =~ "Core"
    assert flat =~ "Minor"
    assert flat =~ ~s(data-role="flat-cash")

    # Default order: signed drift descending — every overweight position
    # (+232, +6.8) above every underweight one (−8). Absolute ordering
    # would wrongly slot −8 above +6.8.
    world_at = :binary.match(flat, "World ETF") |> elem(0)
    small_at = :binary.match(flat, "Small ETF") |> elem(0)
    minor_at = :binary.match(flat, "Minor ETF") |> elem(0)
    assert world_at < small_at
    assert small_at < minor_at

    # Re-sorting by value ascending puts the small position first.
    view |> element(~s([data-role="flat-sort-value"])) |> render_click()
    view |> element(~s([data-role="flat-sort-value"])) |> render_click()

    resorted = view |> element(~s([data-role="flat-positions"])) |> render()
    world_at = :binary.match(resorted, "World ETF") |> elem(0)
    minor_at = :binary.match(resorted, "Minor ETF") |> elem(0)
    assert minor_at < world_at

    # Sorting by category orders the labels case-insensitively ascending
    # ("aggressive" < "Core" < "Minor" — a case-sensitive sort would put the
    # lowercase name last); the category-less cash row sinks to the end.
    view |> element(~s([data-role="flat-sort-category"])) |> render_click()

    by_category = view |> element(~s([data-role="flat-positions"])) |> render()
    small_at = :binary.match(by_category, "Small ETF") |> elem(0)
    world_at = :binary.match(by_category, "World ETF") |> elem(0)
    minor_at = :binary.match(by_category, "Minor ETF") |> elem(0)
    cash_at = :binary.match(by_category, ~s(data-role="flat-cash")) |> elem(0)
    assert small_at < world_at
    assert world_at < minor_at
    assert minor_at < cash_at

    # Back to the tree.
    view |> element(~s([data-role="allocation-mode-tree"])) |> render_click()
    assert has_element?(view, ".drift-table")
  end
end
