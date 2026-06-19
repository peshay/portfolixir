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
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Main", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
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
  # - "Total" (no view) is the default, marked active on first load.
  # - Selecting a view (a full navigation through the ViewScope plug) makes that
  #   view the active one.
  # - The choice persists onto the next surface (here: dashboard -> portfolio).
  test "the active view defaults to Total and persists across pages", %{conn: conn} do
    world()
    {:ok, retirement} = Buckets.create_view(Actor.owner_ui(), %{name: "Retirement"})

    # Total is the default.
    {:ok, _dash, html} = live(conn, "/")
    assert html =~ "Total"
    assert html =~ ~r/id="view-switch-total"[^>]*is-active/

    # A full navigation with ?view=ID runs the plug and stores the choice.
    conn = get(conn, "/?view=#{retirement.id}")
    {:ok, dash, html} = live(conn, "/?view=#{retirement.id}")
    assert html =~ ~r/id="view-switch-#{retirement.id}"[^>]*is-active/
    assert has_element?(dash, "[data-role='active-view']", "Retirement")

    # The preference rides along to the portfolio surface without re-specifying it.
    {:ok, portfolio_view, _html} = live(conn, "/portfolio")
    assert has_element?(portfolio_view, "[data-role='active-view']", "Retirement")
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
      Ledger.create_transaction(%{
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

    test "?view=total clears the preference back to Total and deletes the cookie" do
      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/?view=total")
        |> Map.put(:query_string, "view=total")
        |> run_plug()

      assert get_session(conn, ViewScope.session_key()) == nil
      # delete_resp_cookie schedules the cookie for removal (max_age: 0).
      assert %{max_age: 0} = conn.resp_cookies[ViewScope.cookie_name()]
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

    test "with no ?view= and a junk cookie the session falls back to Total" do
      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/")
        |> Map.put(:query_string, "")
        |> Map.put(:cookies, %{ViewScope.cookie_name() => "garbage"})
        |> run_plug()

      assert get_session(conn, ViewScope.session_key()) == nil
    end
  end
end
