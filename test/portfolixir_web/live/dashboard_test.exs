defmodule PortfolixirWeb.DashboardTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets
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

  # User story (Steve UAT #337, reshaped by ADR-0022 and ADR-0024):
  # As a user who already has transactions,
  # I want the dashboard to answer "did anything change, does anything need
  # me?" — one view-scoped value plus change, not per-portfolio cards,
  # so that the morning glance shows the slice of wealth I steer and forensic
  # detail stays in the audit journal.
  #
  # Acceptance criteria:
  # - Once any transaction exists, the workflow-path wizard is gone.
  # - The dashboard shows ONE value card scoped to the default view —
  #   "Everything" when none is set — with the YTD TTWROR as the change signal.
  # - The recent-activity feed and the count cards are gone from the populated
  #   overview (the wizard keeps its counts).
  # User story (fix round, UAT locale):
  # As a German-speaking maintainer,
  # I want the wealth card's default-scope label to read "Alles",
  # so that the localized dashboard never shows an uppercase English
  # "EVERYTHING". (The label is translated at render time — the card data is
  # computed in an async task whose process has no user locale.)
  test "the wealth card's Everything label is localized", %{conn: conn} do
    seed_holding()

    {:ok, view, _html} = live(conn, "/?locale=de")
    html = render_async(view)

    assert has_element?(view, "#dashboard-wealth-card span", "Alles")
    refute html =~ "Everything"
  end

  test "a populated dashboard shows value and change, not an activity feed", %{conn: conn} do
    seed_holding()

    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "#workflow-path")
    assert has_element?(view, "#dashboard-overview")

    html = render_async(view)

    # One wealth card, scoped to Everything (no default view set): 10 shares
    # @ 120 = 1200 securities, less the 1000 the buy took from cash = 200
    # total incl. cash.
    expected = Format.money(Valuation.for_view(nil, base_currency: "EUR").total_with_cash)
    assert html =~ "Everything"
    assert has_element?(view, "a#dashboard-wealth-card[href='/portfolio']")
    assert html =~ "#{expected} EUR"

    # The change signal: the card carries the YTD TTWROR.
    assert has_element?(view, "[data-role='card-ttwror']")
    assert html =~ "YTD"

    # No per-portfolio cards (ADR-0024: portfolios are no longer the
    # user-facing grouping), no activity feed, no count cards.
    refute has_element?(view, "[id^='dashboard-portfolio-']")
    refute has_element?(view, "#dashboard-recent")
    refute has_element?(view, "#dashboard-securities-count")
  end

  # User story (ADR-0024):
  # As a local portfolio maintainer with a default view,
  # I want the dashboard value card scoped to that view,
  # so that my daily check-in opens on the slice of wealth I steer.
  #
  # Acceptance criteria:
  # - With a default view set, the card carries the view's name and the
  #   view-scoped total (here: the depot's securities only — the untagged cash
  #   account is out of the view's scope).
  test "the dashboard value card scopes to the default view", %{conn: conn} do
    seed_holding()

    depot = Portfolios.list_securities_accounts() |> hd()
    {:ok, bucket} = Portfolixir.Buckets.create_bucket(Actor.owner_ui(), %{name: "mine"})
    :ok = Portfolixir.Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [bucket.id])

    {:ok, mine} =
      Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "Mine", include_all: false})

    :ok = Portfolixir.Buckets.set_view_buckets(Actor.owner_ui(), mine, [bucket.id], [])
    :ok = Portfolixir.Settings.set_default_view(mine.id)

    {:ok, view, _html} = live(conn, "/")
    html = render_async(view)

    expected = Format.money(Valuation.for_view(mine.id, base_currency: "EUR").total_with_cash)
    assert has_element?(view, "#dashboard-wealth-card", "Mine")
    assert html =~ "#{expected} EUR"

    # The scope actually narrows: 1200 securities in scope, while Everything
    # also counts the untagged cash account's -1000 balance.
    everything = Format.money(Valuation.for_view(nil, base_currency: "EUR").total_with_cash)
    refute expected == everything
  end

  # User story (ADR-0022 / ADR-0023):
  # As a local portfolio maintainer steering against a target plan,
  # I want the dashboard to flag categories whose drift exceeds a threshold,
  # so that "does anything need rebalancing?" is answered on the morning
  # glance, with a link straight into the Allocation & targets tab.
  #
  # Acceptance criteria:
  # - With a plan and a category beyond ±5 pp drift, an attention item names
  #   the category and links to /portfolio?tab=allocation.
  # - Only categories that carry a target are considered (an untargeted parent
  #   is not an alert).
  # - Without any drift beyond the threshold (or without a plan), the section
  #   shows the all-clear note instead.
  test "the dashboard flags categories drifting beyond the threshold", %{conn: conn} do
    %{portfolio: portfolio, security: security} = seed_holding()

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, _} =
      Classifications.assign_security(
        Actor.owner_ui(),
        security.id,
        classification.id,
        core.id
      )

    # The buy spent undeposited cash, so counting cash is 0 and the basis is
    # the 1200 securities value: actual 100% vs target 60% -> +40 pp / 480 EUR.
    {:ok, _} =
      Targets.set_targets(portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"}
      ])

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(view, "#dashboard-attention [data-role='drift-alert']", "Core")

    # The card says WHY these items need attention (UAT fix round): an
    # explanatory line under the heading naming the ±5 pp threshold …
    explainer = view |> element(~s([data-role="attention-explainer"])) |> render()
    assert explainer =~ "±5 pp"
    assert explainer =~ "target weight"

    # … and each item reads as text: "40.0 pp above target", not a bare "+40.0 pp".
    alert = view |> element(~s(#dashboard-attention [data-role="drift-alert"])) |> render()
    assert alert =~ ~s(href="/portfolio?tab=allocation")
    assert alert =~ "40.0"
    assert alert =~ "above target"
    assert alert =~ "480.00"

    # ADR-0024: the internal portfolio iterated as the drift mechanism is not
    # surfaced as a grouping label on the alert.
    refute alert =~ "Main"
  end

  test "the dashboard shows the all-clear note when nothing drifts", %{conn: conn} do
    seed_holding()

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(view, "#dashboard-attention [data-role='all-clear']")
    refute has_element?(view, "#dashboard-attention [data-role='drift-alert']")
  end

  # The dashboard must alert against the same default tree the Wealth page
  # steers by (first CUSTOM classification, else the built-in asset-class
  # tree) — with built-ins seeded first at boot, alerting against "the first
  # classification" would silently miss a plan on the custom strategy tree.
  test "drift alerts use the custom tree even when built-ins are seeded first", %{conn: conn} do
    %{portfolio: portfolio, security: security} = seed_holding()

    # Built-ins get the lowest ids/positions, like the boot seeding does.
    Classifications.ensure_builtins()

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), security.id, classification.id, core.id)

    {:ok, _} =
      Targets.set_targets(portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"}
      ])

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(view, "#dashboard-attention [data-role='drift-alert']", "Core")
  end

  # User story (Steve UAT #337 follow-up):
  # As a maintainer keeping the local records auditable,
  # I want the dashboard to flag securities that need attention — no recent
  # quote, no asset class, no logo — with links to fix them,
  # so that data gaps surface on the morning overview instead of silently
  # skewing valuations (this is exactly how we found the missing-quotes issue).
  #
  # Acceptance criteria:
  # - The populated dashboard renders a data-quality card with counts for
  #   securities without a recent quote, without an asset class, and without a
  #   logo, each linking to the securities surface.
  test "a populated dashboard surfaces a data-quality card", %{conn: conn} do
    seed_holding()

    {:ok, _} =
      Catalog.create_security(Actor.owner_ui(), %{name: "NoQuote Co", currency_code: "EUR"})

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(view, "#dashboard-data-quality")

    # NoQuote Co has no quote at all, so the "no recent quote" count is > 0.
    assert has_element?(view, "#dashboard-data-quality [data-role='dq-quotes'] strong")
    refute has_element?(view, "#dashboard-data-quality [data-role='dq-quotes'] strong", "0")

    # Neither synthetic security has a logo.
    assert has_element?(view, "#dashboard-data-quality [data-role='dq-logo'] strong", "2")

    # Each tile links to where the gap is fixed.
    assert has_element?(view, "#dashboard-data-quality a[href='/securities']")
  end
end
