defmodule PortfolixirWeb.PerformanceStaleServeTest do
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Cache

  # User story (2026-07-29, ADR-0032 §6, issue #562):
  # As a local portfolio maintainer,
  # I want the last known series shown immediately while a fresh one computes,
  # so that a recomputation never puts a skeleton where a number could be.
  #
  # Acceptance criteria:
  # - The superseded series renders IMMEDIATELY, labelled with the data it
  #   contains (booking count, newest booking, as-of) and a recomputing
  #   marker — never as a bare number (owner requirement).
  # - When the fresh series lands, the banner disappears in the same update.
  # - The dashboard tile serves the last known YTD figure the same way.
  # - Without a superseded generation, the skeleton renders as before.

  setup do
    Cache.reset()
    Application.put_env(:portfolixir, Cache, enabled?: true)
    on_exit(fn -> Application.put_env(:portfolixir, Cache, enabled?: false) end)
    :ok
  end

  defp seeded_world! do
    Classifications.ensure_builtins()

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Stale", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Stale Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Stale Depot"
      })

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Stale AG",
        currency_code: "EUR",
        isin: "DE000STALE01"
      })

    %{portfolio: portfolio, cash: cash, depot: depot, security: security}
  end

  defp buy!(world, date, price) do
    {:ok, _tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: world.security.id,
        type: "buy",
        date: date,
        quantity: Decimal.new("10"),
        price: Decimal.new(price),
        gross_amount: Decimal.mult(Decimal.new("10"), Decimal.new(price)),
        currency_code: "EUR"
      })
  end

  # Compute once, then supersede the memo with a booking: the previous
  # generation is now what §6 serves. The surfaces read the cross-portfolio
  # view walk (#577), so that is the scope superseded here; the per-portfolio
  # memo keeps its own §6 coverage in the memo integration test.
  defp supersede!(world) do
    base_currency = world.portfolio.base_currency_code
    Performance.view_analysis(nil, base_currency: base_currency)
    buy!(world, ~D[2024-04-02], "110")

    assert %{daily: [_ | _]} =
             Performance.previous_view_analysis(nil, base_currency: base_currency)
  end

  test "the Wealth chart serves the superseded series labelled, then swaps", %{conn: conn} do
    world = seeded_world!()
    buy!(world, ~D[2024-01-02], "100")
    supersede!(world)

    {:ok, view, html} = live(conn, "/portfolio")

    # Immediately: the superseded series, with its provenance, marked.
    assert html =~ "data-role=\"performance-stale\""
    assert html =~ "Superseded series"
    # Singular with one seeded booking (ngettext, issue 636).
    assert html =~ "booking through"
    assert html =~ "Recomputing"
    # The series itself renders — a number, not a skeleton.
    assert html =~ "data-role=\"period-badge\""

    # When the fresh walk lands, the banner leaves in the same update.
    html = render_async(view)
    refute html =~ "data-role=\"performance-stale\""
    assert html =~ "data-role=\"period-badge\""
  end

  test "without a superseded generation the chart loads as before", %{conn: conn} do
    world = seeded_world!()
    buy!(world, ~D[2024-01-02], "100")

    {:ok, view, html} = live(conn, "/portfolio")

    refute html =~ "data-role=\"performance-stale\""
    html = render_async(view)
    assert html =~ "data-role=\"period-badge\""
    refute html =~ "Superseded series"
  end

  test "the dashboard tile serves the last known YTD figure labelled, then swaps", %{conn: conn} do
    world = seeded_world!()
    # A booking this year so the YTD summary carries a TTWROR.
    buy!(world, Date.add(Date.utc_today(), -30), "100")
    supersede!(world)

    {:ok, view, html} = live(conn, "/")

    assert html =~ "data-role=\"overview-stale\""
    assert html =~ "Last known:"
    # Singular with one seeded booking (ngettext, issue 636).
    assert html =~ "booking through"
    assert html =~ "Recomputing"

    html = render_async(view)
    refute html =~ "data-role=\"overview-stale\""
    assert html =~ "dashboard-wealth-card"
  end

  test "without a superseded generation the dashboard shows the plain skeleton", %{conn: conn} do
    world = seeded_world!()
    buy!(world, Date.add(Date.utc_today(), -30), "100")

    {:ok, view, html} = live(conn, "/")

    refute html =~ "data-role=\"overview-stale\""
    render_async(view)
    assert render(view) =~ "dashboard-wealth-card"
  end
end
