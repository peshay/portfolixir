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
    # The value sits in its own count-up digits span beside the currency.
    assert html =~ ">#{expected}</span>"
    assert html =~ "EUR"

    # The change signal: the card carries the YTD TTWROR.
    assert has_element?(view, "[data-role='card-ttwror']")
    assert html =~ "YTD"

    # No per-portfolio cards (ADR-0024: portfolios are no longer the
    # user-facing grouping), no activity feed, no count cards.
    refute has_element?(view, "[id^='dashboard-portfolio-']")
    refute has_element?(view, "#dashboard-recent")
    refute has_element?(view, "#dashboard-securities-count")
  end

  # User story:
  # As a user opening the Overview while the wealth card computes,
  # I want pending sections to show a value-sized placeholder with the
  # "computing" cue instead of a "Loading…" verb,
  # so that loading indication is consistent and survives reduced motion as
  # a static cue (UX-DR20; the stale-TTWROR line keeps its "Recomputing."
  # sentence and loses only the loading heading).
  #
  # Acceptance criteria:
  # - No "Loading…" string renders on the Overview.
  # - Pending sections carry the value skeleton, aria-busy and the cue word.
  test "overview pending sections use the computing cue, not a loading verb", %{conn: conn} do
    seed_holding()

    {:ok, _view, html} = live(conn, "/")

    refute html =~ "Loading…"
    assert html =~ "value-skeleton"
    assert html =~ ~s(aria-busy="true")
    assert html =~ "computing"
  end

  # User story:
  # As a user glancing at the Overview wealth card,
  # I want the YTD change signal coloured by its sign,
  # so that a losing year is recognisable without reading the digits
  # (UX-DR7, issue 637 — semantic colour at every level, not only totals).
  #
  # Acceptance criteria:
  # - The card's TTWROR fragment carries is-positive/is-negative by sign.
  test "the wealth card's YTD change carries its sign class (#637)", %{conn: conn} do
    %{security: security, portfolio: portfolio} = seed_holding()

    # Give the YTD window a real opening value: the position already exists
    # at the year boundary (a second buy dated last year) and is quoted 100
    # then, 120 today — a positive YTD change.
    last_year = %{Date.utc_today() | month: 1, day: 2} |> Date.add(-10)
    [depot] = Portfolios.list_securities_accounts_for_portfolio(portfolio.id)

    # The deposit funds both buys, so the year opens with a real value
    # instead of cash and securities netting to zero.
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: depot.cash_account_id,
        type: "deposit",
        date: Date.add(last_year, -1),
        gross_amount: "2000",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: depot.cash_account_id,
        security_id: security.id,
        type: "buy",
        date: last_year,
        quantity: Decimal.new("5"),
        price: Decimal.new("100.00"),
        fees: Decimal.new("0"),
        taxes: Decimal.new("0"),
        currency_code: "EUR"
      })

    {:ok, _} =
      Quotes.upsert_many(security.id, [
        %{date: last_year, close: "100.00", source: "manual"},
        %{date: %{Date.utc_today() | month: 1, day: 2}, close: "100.00", source: "manual"}
      ])

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    # 10 @ 100 bought, quoted 120 today: a positive YTD change.
    assert view |> element("[data-role='card-ttwror']") |> render() =~ "is-positive"
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
    # The value sits in its own count-up digits span beside the currency.
    assert html =~ ">#{expected}</span>"
    assert html =~ "EUR"

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
    #
    # The plan is completed to 1.0 so it stays a FULL-ALLOCATION fixture:
    # ADR-0040 (#709) measures drift against the allocated portion only where a
    # plan is deliberately short, and the subject of this test is the drift
    # THRESHOLD, not the remainder. With Sigma = 1.0 the +40 pp above is
    # unchanged. The remaining 0.4 goes to the CASH target rather than to a
    # second category: cash enters the top-level sum but is not a category, so
    # it completes the plan without adding a second drift alert.
    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"}
      ])

    {:ok, _} = Portfolios.set_cash_target(Actor.owner_ui(), portfolio, Decimal.new("0.4"))

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(view, "#dashboard-attention [data-role='drift-alert']", "Core")

    # The card says WHY these items need attention (UAT fix round): an
    # explanatory line under the heading naming the ±5 pp threshold …
    explainer = view |> element(~s([data-role="attention-explainer"])) |> render()
    assert explainer =~ "±5 pp"
    assert explainer =~ "target weight"

    # … and WHAT the count is computed against (#673, UX-DR2): the view, the
    # plan and the tree — with several views and plans per allocation the
    # warning must name its basis.
    basis = view |> element(~s([data-role="attention-basis"])) |> render()
    assert basis =~ "Everything"
    assert basis =~ "Plan"
    assert basis =~ "Strategy"

    # … and each item reads as text: "40.0 pp above target", not a bare "+40.0 pp".
    #
    # Scoped to the Core alert by text. Under a FULL plan (ADR-0040, #709) the
    # drifts sum to zero, so whenever one bucket is over target another is under
    # it -- here Core at +40 pp and the 0.4 cash target at -40 pp. Two alerts is
    # the correct behaviour of a complete plan, and the previous single-element
    # selector only worked because the short plan produced one-sided phantom
    # drift.
    alert =
      view |> element(~s(#dashboard-attention [data-role="drift-alert"]), "Core") |> render()

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

    # Completed to 1.0 via the cash target, per ADR-0040 (#709): this test is
    # about which TREE the alerts come from, not about a short plan, and cash
    # completes the sum without adding a second alert.
    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"}
      ])

    {:ok, _} = Portfolios.set_cash_target(Actor.owner_ui(), portfolio, Decimal.new("0.4"))

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(view, "#dashboard-attention [data-role='drift-alert']", "Core")
  end

  # User story (#561, UX-DR2 — the 2026-07-12 decision, adopted 2026-08-05):
  # As a maintainer keeping the local records auditable,
  # I want data quality on the Overview to be ONE line whose counts link to
  # the securities list pre-filtered to the offending set,
  # so that every count carries a path to fix it instead of landing on the
  # unfiltered index.
  #
  # Acceptance criteria:
  # - Data quality renders as a single data-note line, not a card grid.
  # - Each count links to /securities with the matching filter applied
  #   (dq=stale_quote, filter[]=asset_class:is_nil, dq=missing_logo).
  # - The line renders only when at least one count is non-zero; there is no
  #   green all-clear badge.
  # - The note carries a severity word and glyph, never colour alone.
  test "data quality is one line linking to pre-filtered securities lists", %{conn: conn} do
    seed_holding()

    {:ok, _} =
      Catalog.create_security(Actor.owner_ui(), %{name: "NoQuote Co", currency_code: "EUR"})

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(view, "#dashboard-data-quality [data-role='data-quality-line']")
    refute has_element?(view, "#dashboard-data-quality .grid .stat")

    # Counts link to the pre-filtered securities list (#651).
    assert has_element?(
             view,
             ~s(#dashboard-data-quality a[href="/securities?dq=stale_quote"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-quality a[href="/securities?dq=missing_logo"])
           )

    # The note is a data-note with a severity word (UX-DR17/UX-DR7): a stale
    # quote is an attention-level finding.
    assert has_element?(
             view,
             "#dashboard-data-quality .data-note--attention .data-note__word",
             "Attention"
           )
  end

  test "the data-quality line is absent when nothing is wrong", %{conn: conn} do
    %{security: security} = seed_holding()

    # Close every gap: quote is fresh (seed), add class and logo.
    {:ok, _} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        asset_class: "equity",
        attributes: %{"logo_path" => "logos/acme.png"}
      })

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    refute has_element?(view, "#dashboard-data-quality")
    refute has_element?(view, "[data-role='data-quality-line']")
  end

  # User story (issue #718, D1 / UX-DR21):
  # As a local portfolio maintainer,
  # I want the drift card named for what it contains,
  # so that a heading states a content, not an urgency or an intended
  # reaction — the card holds exactly one thing: categories off their
  # target weight.
  #
  # Acceptance criteria:
  # - The card heading is "Off target" (DE "Ziel-Abweichungen"), and the
  #   anthropomorphic "Needs attention" is gone from the surface.
  # - The basis line #673 added stays.
  test "the drift card is named for what it contains (UX-DR21)", %{conn: conn} do
    seed_holding()

    {:ok, view, html} = live(conn, "/")
    render_async(view)

    assert has_element?(view, "#dashboard-attention h2", "Off target")
    refute html =~ "Needs attention"
    assert has_element?(view, "[data-role='attention-explainer']")

    de_conn = Phoenix.ConnTest.build_conn() |> put_req_header("accept-language", "de")
    {:ok, _view, de_html} = live(de_conn, "/")
    assert de_html =~ "Ziel-Abweichungen"
    refute de_html =~ "Braucht Aufmerksamkeit"
  end
end
