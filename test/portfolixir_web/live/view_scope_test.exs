defmodule PortfolixirWeb.ViewScopeTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation

  defp world do
    # Built-in trees are seeded at startup in prod (#529); seed them within the
    # test sandbox so the view switcher / scoping surfaces resolve them.
    Portfolixir.Classifications.ensure_builtins()

    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Main",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    %{portfolio: portfolio, cash: cash, depot: depot}
  end

  # User story:
  # As a local portfolio maintainer,
  # I want to pick an active view that persists across pages,
  # so that every analytics surface stays scoped to the same slice of wealth.
  #
  # Acceptance criteria:
  # - "Everything" (no view) is the built-in default, marked active on first load
  #   (ADR-0024: views replace portfolios as the user-facing grouping).
  # - Selecting a view (a full navigation through the ViewScope plug) makes that
  #   view the active one.
  # - The choice persists onto the next navigation without re-specifying ?view=.
  # The switcher lives on the analytics surfaces that the scope actually filters
  # (the portfolio surface), not on the dashboard whose raw counts it cannot
  # narrow — so this exercises it there.
  test "the active view defaults to Everything and persists across pages", %{conn: conn} do
    world()
    {:ok, retirement} = Buckets.create_view(Actor.owner_ui(), %{name: "Retirement"})

    # Everything is the built-in default.
    {:ok, _portfolio, html} = live(conn, "/portfolio")
    assert html =~ "Everything"
    assert html =~ ~r/id="view-switch-total"[^>]*is-active/

    # A full navigation with ?view=ID runs the plug and stores the choice.
    conn = get(conn, "/portfolio?view=#{retirement.id}")
    {:ok, scoped, html} = live(conn, "/portfolio?view=#{retirement.id}")
    assert html =~ ~r/id="view-switch-#{retirement.id}"[^>]*is-active/
    assert has_element?(scoped, "[data-role='active-view']", "Retirement")

    # The preference rides along to the next navigation without re-specifying it.
    {:ok, again, _html} = live(conn, "/portfolio")
    assert has_element?(again, "[data-role='active-view']", "Retirement")
  end

  # User story:
  # As a local portfolio maintainer who has not created any views yet,
  # I want the view switcher to tell me where to make one,
  # so that I understand the control needs a view before it can filter anything.
  #
  # Acceptance criteria:
  # - With no views, the switcher shows a "no views yet" prompt.
  # - The prompt links to the Buckets & views page (/buckets).
  test "the switcher prompts to create a view when none exist", %{conn: conn} do
    world()

    {:ok, view, html} = live(conn, "/portfolio")

    assert html =~ "View:"
    assert has_element?(view, "[data-role='no-views'] a[href='/buckets']")
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a non-Total view to scope the analytics on the surface,
  # so that the figures reflect only the holdings the view matches.
  #
  # Acceptance criteria:
  # - With a view that excludes the only holding's bucket, the portfolio
  #   securities total drops to zero (the position is out of scope).
  test "a non-Total view scopes the portfolio valuation", %{conn: conn} do
    %{portfolio: portfolio, cash: cash, depot: depot} = world()

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
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
        %{date: Date.utc_today(), close: "100.00", source: "manual"}
      ])

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Stocks"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [bucket.id])

    # A view that excludes the holding's only bucket leaves it out of scope.
    {:ok, excluding} = Buckets.create_view(Actor.owner_ui(), %{name: "Without stocks"})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), excluding, [], [bucket.id])

    unscoped = Valuation.for_portfolio(portfolio.id)
    scoped = Valuation.for_portfolio(portfolio.id, view: excluding.id)

    assert Decimal.compare(unscoped.total_value, 0) == :gt
    assert Decimal.equal?(scoped.total_value, 0)

    # And the LiveView renders under that scope without crashing.
    conn = get(conn, "/portfolio?view=#{excluding.id}")
    {:ok, view, _html} = live(conn, "/portfolio?view=#{excluding.id}")
    assert has_element?(view, "[data-role='active-view']", "Without stocks")
  end

  describe "ViewScope plug" do
    alias PortfolixirWeb.ViewScope

    # The plug is driven directly so the rarely-exercised shape branches —
    # clearing back to Total, rejecting a non-integer id, and carrying the
    # cookie when no ?view= is present — get explicit, meaningful coverage.

    defp run_plug(conn) do
      conn
      |> Plug.Test.init_test_session(%{})
      |> ViewScope.call(ViewScope.init([]))
    end

    test "exposes the cookie and session key names" do
      assert ViewScope.cookie_name() == "portfolixir_view"
      assert ViewScope.session_key() == "active_view_id"
    end

    test "a positive integer id is stored in the session and the cookie" do
      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/?view=7")
        |> Map.put(:query_string, "view=7")
        |> run_plug()

      assert get_session(conn, ViewScope.session_key()) == 7
      assert %{value: "7"} = conn.resp_cookies[ViewScope.cookie_name()]
    end

    # An explicit Everything choice is stored (not cleared): with a
    # user-settable default view (ADR-0024) "never chose" falls back to the
    # default, so "chose Everything" must stay distinguishable from it.
    test "?view=total stores the explicit Everything choice in session and cookie" do
      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/?view=total")
        |> Map.put(:query_string, "view=total")
        |> run_plug()

      assert get_session(conn, ViewScope.session_key()) == "total"
      assert %{value: "total"} = conn.resp_cookies[ViewScope.cookie_name()]
    end

    test "a non-integer ?view= value is rejected and clears the preference" do
      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/?view=not-a-number")
        |> Map.put(:query_string, "view=not-a-number")
        |> run_plug()

      assert get_session(conn, ViewScope.session_key()) == nil
      assert %{max_age: 0} = conn.resp_cookies[ViewScope.cookie_name()]
    end

    test "with no ?view= the session is rebuilt from a valid cookie" do
      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/")
        |> Map.put(:query_string, "")
        |> Map.put(:cookies, %{ViewScope.cookie_name() => "42"})
        |> run_plug()

      assert get_session(conn, ViewScope.session_key()) == 42
      # No explicit choice means the cookie is left untouched.
      refute Map.has_key?(conn.resp_cookies, ViewScope.cookie_name())
    end

    test "with no ?view= and a junk cookie the session falls back to unset" do
      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/")
        |> Map.put(:query_string, "")
        |> Map.put(:cookies, %{ViewScope.cookie_name() => "garbage"})
        |> run_plug()

      assert get_session(conn, ViewScope.session_key()) == nil
    end

    test "with no ?view= an explicit Everything cookie is carried into the session" do
      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/")
        |> Map.put(:query_string, "")
        |> Map.put(:cookies, %{ViewScope.cookie_name() => "total"})
        |> run_plug()

      assert get_session(conn, ViewScope.session_key()) == "total"
    end
  end

  describe "default view preference (ADR-0024)" do
    alias Portfolixir.Settings

    # User story:
    # As a local portfolio maintainer,
    # I want my own default view applied when I open the Wealth page,
    # so that my daily check-in starts on the slice of wealth I steer.
    #
    # Acceptance criteria:
    # - With a default view set and no explicit view chosen, the page mounts
    #   scoped to the default view.
    # - An explicit ?view=total (Everything) overrides the default and persists.
    # - An explicit other view still wins over the default.
    test "the default view is applied on mount when no explicit view is chosen",
         %{conn: conn} do
      world()
      {:ok, mine} = Buckets.create_view(Actor.owner_ui(), %{name: "Mine"})
      :ok = Settings.set_default_view(mine.id)

      # No explicit choice anywhere: the default view scopes the page.
      {:ok, scoped, html} = live(conn, "/portfolio")
      assert html =~ ~r/id="view-switch-#{mine.id}"[^>]*is-active/
      assert has_element?(scoped, "[data-role='active-view']", "Mine")

      # Explicitly picking Everything overrides the default…
      conn = get(conn, "/portfolio?view=total")
      {:ok, _lv, html} = live(conn, "/portfolio")
      assert html =~ ~r/id="view-switch-total"[^>]*is-active/

      # …and an explicit other view wins over the default too.
      {:ok, other} = Buckets.create_view(Actor.owner_ui(), %{name: "Other"})
      conn = get(conn, "/portfolio?view=#{other.id}")
      {:ok, lv, _html} = live(conn, "/portfolio")
      assert has_element?(lv, "[data-role='active-view']", "Other")
    end

    # User story:
    # As a local portfolio maintainer,
    # I want a "set as default" affordance on the view picker,
    # so that I can pin my daily scope without editing configuration.
    #
    # Acceptance criteria:
    # - The active non-default selection offers "Set as default".
    # - Clicking it persists the preference server-side; the switcher then
    #   marks the selection as the default.
    test "set as default persists the active view as the default", %{conn: conn} do
      world()
      {:ok, mine} = Buckets.create_view(Actor.owner_ui(), %{name: "Mine"})

      conn = get(conn, "/portfolio?view=#{mine.id}")
      {:ok, lv, _html} = live(conn, "/portfolio")

      lv |> element("[data-role='set-default-view']") |> render_click()

      assert Settings.default_view_id() == mine.id
      assert has_element?(lv, "[data-role='default-view-marker']")
    end
  end

  describe "view-scoped Wealth page (ADR-0024)" do
    import Portfolixir.WorldFixtures,
      only: [base_world: 1, create_security!: 1, buy!: 3, put_quote!: 3]

    alias Portfolixir.Settings

    # User story:
    # As a local portfolio maintainer with more than one (legacy) portfolio,
    # I want the Wealth header totals to follow the active view across all
    # portfolios, so that the page shows my wealth, not one container's slice.
    #
    # Acceptance criteria:
    # - With Everything active, the securities total spans both portfolios'
    #   holdings (via the deduplicated view valuation, Valuation.for_view/2).
    test "the Wealth header totals span portfolios under Everything", %{conn: conn} do
      Portfolixir.Classifications.ensure_builtins()
      alpha = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")
      beta = base_world(name: "Beta", cash_name: "Beta Cash", depot_name: "Beta Depot")

      security = create_security!(name: "World Co.", ticker: "WRLD", asset_class: "equity")
      put_quote!(security, Date.utc_today(), "10")
      buy!(alpha, security, quantity: "10", price: "10")
      buy!(beta, security, quantity: "5", price: "10")

      {:ok, lv, _html} = live(conn, "/portfolio")
      html = render_async(lv)

      # 10×10 (Alpha) + 5×10 (Beta) = 150 securities value across portfolios.
      assert html =~ ~r/id="kpi-securities".*150\.00/s
    end

    # User story:
    # As a local portfolio maintainer whose view includes overlapping buckets,
    # I want a badge near the total saying accounts are counted once,
    # so that I never misread per-bucket figures as an additive breakdown.
    #
    # Acceptance criteria:
    # - A view whose included buckets share an account shows the overlap badge.
    # - Everything (no view) shows no badge.
    test "shows the overlap badge when the view's buckets share an account", %{conn: conn} do
      Portfolixir.Classifications.ensure_builtins()
      alpha = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")

      security = create_security!(name: "ACME", ticker: "ACME", asset_class: "equity")
      put_quote!(security, Date.utc_today(), "10")
      buy!(alpha, security, quantity: "10", price: "10")

      {:ok, mine} = Buckets.create_bucket(Actor.owner_ui(), %{name: "mine"})
      {:ok, household} = Buckets.create_bucket(Actor.owner_ui(), %{name: "household"})

      :ok =
        Buckets.set_depot_default_buckets(Actor.owner_ui(), alpha.depot, [
          mine.id,
          household.id
        ])

      {:ok, both} = Buckets.create_view(Actor.owner_ui(), %{name: "Both", include_all: false})
      :ok = Buckets.set_view_buckets(Actor.owner_ui(), both, [mine.id, household.id], [])

      # Everything: deduplication is trivial, no badge.
      {:ok, lv, _html} = live(conn, "/portfolio")
      render_async(lv)
      refute has_element?(lv, "[data-role='overlap-badge']")

      # The overlapping view: badge next to the total.
      conn = get(conn, "/portfolio?view=#{both.id}")
      {:ok, lv, _html} = live(conn, "/portfolio")
      render_async(lv)
      assert has_element?(lv, "[data-role='overlap-badge']")
    end

    # User story:
    # As a local portfolio maintainer,
    # I want view-scoped series labelled "Composition as of today",
    # so that I know current bucket membership is applied retroactively
    # (ADR-0024 modification 4).
    #
    # Acceptance criteria:
    # - With an active view the performance section carries the label.
    # - Under Everything the label is absent.
    test "labels the view-scoped performance series", %{conn: conn} do
      Portfolixir.Classifications.ensure_builtins()
      alpha = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")

      security = create_security!(name: "ACME", ticker: "ACME", asset_class: "equity")
      put_quote!(security, Date.utc_today(), "10")
      buy!(alpha, security, quantity: "10", price: "10")

      {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Mine"})

      {:ok, lv, _html} = live(conn, "/portfolio")
      html = render_async(lv)
      refute html =~ "Composition as of today"

      conn = get(conn, "/portfolio?view=#{view.id}")
      {:ok, lv, _html} = live(conn, "/portfolio")
      html = render_async(lv)
      assert html =~ "Composition as of today"
    end

    # User story:
    # As a local portfolio maintainer whose portfolios were just migrated,
    # I want a one-time "your portfolios are now views" notice on the Wealth
    # page, so that I understand where my groupings went — once.
    #
    # Acceptance criteria:
    # - After the ADR-0024 seed the notice lists the seeded views.
    # - Dismissing persists; a fresh mount no longer shows the notice.
    test "shows the migration notice until dismissed", %{conn: conn} do
      world()
      {:ok, _summary} = Buckets.seed_portfolio_scope_buckets(Actor.owner_ui())

      {:ok, lv, html} = live(conn, "/portfolio")
      assert html =~ "Your portfolios are now views"
      assert has_element?(lv, "[data-role='migration-views'] li", "Main")

      lv |> element("[data-role='dismiss-migration-notice']") |> render_click()
      refute has_element?(lv, "[data-role='migration-notice']")

      assert Settings.migration_notice_dismissed?()

      {:ok, _lv, html} = live(conn, "/portfolio")
      refute html =~ "Your portfolios are now views"
    end
  end
end
