defmodule PortfolixirWeb.DashboardTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

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
    # The KPI strip is absent in the empty state (UX-DR2 as amended 2026-09-14).
    refute has_element?(view, "#dashboard-kpi-strip")
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

    # The change signal: the card carries the TTWROR since the start of the
    # year, said in words (#1090, board 08 ③).
    assert has_element?(view, "[data-role='card-ttwror']", "year to date")

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

    # #798 (UX-DR2 as amended 2026-09-14): each row also carries a decorative
    # drift bar around zero — sign, colour and the direction word stay the
    # accessible channels, so the bar is aria-hidden.
    assert alert =~ ~s(class="drift-bar" aria-hidden="true")
    assert alert =~ ~s(drift-bar__fill is-over)

    under =
      view |> element(~s(#dashboard-attention [data-role="drift-alert"]), "Cash") |> render()

    assert under =~ ~s(drift-bar__fill is-under)

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
    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{asset_class: "equity"})

    {:ok, _} = Catalog.put_logo_attributes(security, %{"logo_path" => "logos/acme.png"})

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    refute has_element?(view, "#dashboard-data-quality")
    refute has_element?(view, "[data-role='data-quality-line']")
  end

  # User story (PR #1102):
  # As a maintainer who retires a security that was sold out or delisted,
  # I want the Overview's quote, asset-class and logo counts to drop with it,
  # so that the line counts what still needs work, not what I have closed.
  #
  # Acceptance criteria:
  # - A never-priced security without an asset class or a logo counts once
  #   under each of the three findings, and the asset-class link opens a list
  #   holding it.
  # - Retired, it counts under none, the asset-class link's list no longer
  #   holds it, and with nothing else open the line is gone.
  test "a retired security leaves the data-quality line's quote, class and logo counts",
       %{conn: conn} do
    %{security: security} = seed_holding()

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{asset_class: "equity"})

    {:ok, _} = Catalog.put_logo_attributes(security, %{"logo_path" => "logos/acme.png"})

    {:ok, closed} =
      Catalog.create_security(Actor.owner_ui(), %{name: "Closed Co", currency_code: "EUR"})

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(
             view,
             "[data-role='dq-quotes']",
             "one security in the catalog without a quote in 7 days"
           )

    assert has_element?(view, "[data-role='dq-class']", "one without an asset class")
    assert has_element?(view, "[data-role='dq-logo']", "one without a logo")

    [class_href] =
      view
      |> element("[data-role='dq-class']")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")

    {:ok, list, _html} = live(conn, class_href)
    assert has_element?(list, "td", "Closed Co")

    {:ok, _} = Catalog.update_security(Actor.owner_ui(), closed, %{is_retired: true})

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    refute has_element?(view, "[data-role='dq-quotes']")
    refute has_element?(view, "[data-role='dq-class']")
    refute has_element?(view, "[data-role='dq-logo']")
    refute has_element?(view, "#dashboard-data-quality")

    {:ok, list, _html} = live(conn, class_href)
    refute has_element?(list, "td", "Closed Co")
  end

  # User story (#933, review pass 1):
  # As an operator whose logo files were lost with the volume,
  # I want the Overview's logo count to include every stored logo whose file
  # is gone, a manual one included, but never my deliberate "no logo" choice,
  # so that the count raises the alarm and tells me what to fetch or upload
  # again.
  #
  # Acceptance criteria:
  # - Before the reconciliation the two rows with a stored path count as
  #   having a logo; after it marks them, the line reads "2 without a logo"
  #   and links to dq=missing_logo, whose list holds both.
  # - A security locked to "no logo" is not counted.
  test "the logo count includes logos whose file is gone once marked", %{conn: conn} do
    %{security: security} = seed_holding()

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{asset_class: "equity"})

    {:ok, manual} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Manual Co",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, chosen} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Chosen Co",
        currency_code: "EUR",
        asset_class: "equity"
      })

    for {row, attrs} <- [
          {security, %{"logo_source" => "wikipedia"}},
          {manual, %{"logo_source" => "manual", "logo_locked" => true}}
        ] do
      path = "/security_logos/#{row.id}.png"
      {:ok, _} = Catalog.put_logo_attributes(row, Map.put(attrs, "logo_path", path))
    end

    {:ok, _} = Catalog.put_logo_attributes(chosen, %{"logo_locked" => true})

    {:ok, view, _html} = live(conn, "/")
    render_async(view)
    refute has_element?(view, "[data-role='dq-logo']")

    tmp =
      Path.join(System.tmp_dir!(), "portfolixir-dq-gone-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf(tmp) end)
    assert {:ok, %{marked: 2}} = Catalog.LogoStore.reconcile_missing_files(storage_dir: tmp)

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(
             view,
             ~s([data-role='dq-logo'][href="/securities?dq=missing_logo"]),
             "2 without a logo"
           )

    {:ok, list, _html} = live(conn, "/securities?dq=missing_logo")
    assert has_element?(list, "td", "ACME")
    assert has_element?(list, "td", "Manual Co")
    refute has_element?(list, "td", "Chosen Co")
  end

  # User story (#1068, D-15; board 01, pin 5):
  # As the operator whose Overview total a bond on two scales inflates or
  # deflates a hundredfold,
  # I want the data-quality line to count the bonds priced on two scales,
  # in either direction, at problem severity,
  # so that the alarm stands where the total it concerns is read, and its
  # count opens a list of the same size (#705).
  #
  # Acceptance criteria:
  # - One forward finding (quotes near 100, a buy near 1) and one reverse
  #   finding (quotes near 1, a buy near 100) read "2 Anleihen auf zwei
  #   Skalen bepreist" on the German line, linking to
  #   /securities?dq=two_scales, and the note takes the problem severity,
  #   the highest present.
  # - The linked list holds those two bonds and nothing else, under a
  #   removable "Auf zwei Skalen bepreist" filter chip.
  # - A bond on one scale and an unclassed security with no master data
  #   quoted 25 times its buy price are not counted.
  test "the data-quality line counts the bonds priced on two scales, at problem severity",
       %{conn: conn} do
    world = base_world()

    for {name, attrs, price, close} <- [
          {"Kestrel Anleihe 2030 2,75%", %{asset_class: "bond"}, "0.985", "97.25"},
          {"Birkenhain Wasser Anleihe 2029 1,50%", %{asset_class: "bond"}, "98.40", "0.981"},
          {"Musterland Anleihe 2029", %{asset_class: "bond"}, "99.10", "98.40"},
          {"Ostsee Holz", %{}, "4", "100"}
        ] do
      {:ok, security} =
        Catalog.create_security(
          Actor.owner_ui(),
          Map.merge(%{name: name, currency_code: "EUR"}, attrs)
        )

      buy!(world, security, quantity: "100", price: price, date: ~D[2026-03-12])
      put_quote!(security, ~D[2026-09-30], close)
    end

    conn = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(
             view,
             ~s(#dashboard-dq-line a[data-role="dq-two-scales"][href="/securities?dq=two_scales"]),
             "2 Anleihen auf zwei Skalen bepreist"
           )

    assert has_element?(view, "#dashboard-data-quality .data-note--problem .data-note__word")
    refute has_element?(view, "#dashboard-data-quality .data-note--attention")

    {:ok, list, _html} = live(conn, "/securities?dq=two_scales")
    assert has_element?(list, "#filter-chips .chip", "Auf zwei Skalen bepreist")
    assert has_element?(list, "td", "Kestrel Anleihe 2030 2,75%")
    assert has_element?(list, "td", "Birkenhain Wasser Anleihe 2029 1,50%")
    refute has_element?(list, "td", "Musterland Anleihe 2029")
    refute has_element?(list, "td", "Ostsee Holz")
  end

  # User story (#1068, review): the singular follows the line's convention
  # ("eine Anleihe", "one bond"), and the problem outranks a stale quote.
  #
  # Acceptance criteria:
  # - One reverse bond reads "eine Anleihe auf zwei Skalen bepreist" in
  #   German and "one bond priced on two scales" in English.
  # - Beside a stale quote, the line keeps both findings and takes the
  #   problem severity, never attention.
  test "one bond on two scales reads in the singular, and outranks a stale quote",
       %{conn: conn} do
    world = base_world()

    {:ok, bond} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Birkenhain Wasser Anleihe 2029 1,50%",
        currency_code: "EUR",
        asset_class: "bond"
      })

    buy!(world, bond, quantity: "100", price: "98.40", date: ~D[2026-03-12])
    put_quote!(bond, Date.add(Date.utc_today(), -1), "0.981")

    {:ok, stale} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Nordwind Industrie AG",
        currency_code: "EUR",
        asset_class: "equity"
      })

    put_quote!(stale, Date.add(Date.utc_today(), -30), "12.50")

    german = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(german, "/")
    render_async(view)

    assert has_element?(
             view,
             ~s(#dashboard-dq-line a[data-role="dq-two-scales"]),
             "eine Anleihe auf zwei Skalen bepreist"
           )

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(
             view,
             ~s(#dashboard-dq-line a[data-role="dq-two-scales"][href="/securities?dq=two_scales"]),
             "one bond priced on two scales"
           )

    assert has_element?(view, ~s(#dashboard-dq-line a[data-role="dq-quotes"]))
    assert has_element?(view, "#dashboard-data-quality .data-note--problem", "Problem")
    refute has_element?(view, "#dashboard-data-quality .data-note--attention")

    {:ok, list, _html} = live(conn, "/securities?dq=two_scales")
    assert has_element?(list, "#filter-chips .chip", "Priced on two scales")
    assert has_element?(list, "td", "Birkenhain Wasser Anleihe 2029 1,50%")
    refute has_element?(list, "td", "Nordwind Industrie AG")
  end

  test "the data-quality line has no two-scales count while no bond is on two scales",
       %{conn: conn} do
    world = base_world()

    {:ok, bond} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Musterland Anleihe 2029",
        currency_code: "EUR",
        asset_class: "bond"
      })

    buy!(world, bond, quantity: "100", price: "99.10", date: ~D[2026-03-12])
    put_quote!(bond, ~D[2026-09-30], "98.40")

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    refute has_element?(view, ~s([data-role="dq-two-scales"]))
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
