defmodule PortfolixirWeb.SecuritiesPnlDecompositionTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger

  # Synthetic ADR-0033 fixture figures only.

  defp usd_world do
    world = base_world(name: "LV Decomp", cash_name: "LV Cash", depot_name: "LV Depot")
    security = create_security!(name: "LV US Equity", ticker: "LUS", currency: "USD")
    Map.put(world, :security, security)
  end

  defp settled_buy!(w) do
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: ~D[2026-01-15],
        quantity: "10",
        price: "100.00",
        currency_code: "USD",
        security_amount: "1000.00",
        settlement_amount: "800.00",
        settlement_fx_rate: "0.80"
      })
  end

  defp legacy_buy!(w) do
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: ~D[2026-01-15],
        quantity: "10",
        price: "80.00",
        currency_code: "EUR"
      })
  end

  defp seed_current_rate!(rate) do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-07-31],
          rate: rate,
          source: "manual"
        }
      ])
  end

  # User story (ADR-0033, issue #569):
  # As a maintainer on the security detail holdings tab,
  # I want each depot row to show the price return and the currency return
  # next to the total, with the committed explanation behind the info
  # tooltip,
  # so that price moves and FX effects are visibly separated where I read
  # the position.
  #
  # Acceptance criteria:
  # - With current rate 1 EUR = 1.00 USD: price return +100.00, currency
  #   return +200.00 (1,000 x 1 - 800), total +300.00.
  # - The tooltip carries the committed ADR-0033 copy.
  test "the holdings tab shows the price/currency decomposition with the tooltip", %{conn: conn} do
    w = usd_world()
    settled_buy!(w)
    put_quote!(w.security, ~D[2026-07-31], "110.00")
    seed_current_rate!("1.00")

    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=holdings")
    html = view |> element("#detail-tab-panel-holdings") |> render()

    assert html =~ "Price return"
    assert html =~ "Currency return"
    assert html =~ "+100.00"
    assert html =~ "+200.00"
    assert html =~ "+300.00"

    assert html =~ "the change of the security&#39;s own price, converted at today&#39;s rate"
    assert html =~ "the effect of the exchange rate on the amount originally invested"
  end

  # User story (honesty in the UI):
  # As a maintainer whose imported cross-currency row has no derivable
  # native leg,
  # I want dashes instead of numbers on the holdings tab,
  # so that the surface never shows the old blind cross-currency figure.
  test "an underivable row renders dashes, not a blind figure", %{conn: conn} do
    w = usd_world()
    legacy_buy!(w)
    put_quote!(w.security, ~D[2026-07-31], "110.00")

    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=holdings")
    html = view |> element("#detail-tab-panel-holdings") |> render()

    # The blind unrealized figure (1100 USD - 800 EUR = "300") must not
    # appear anywhere on the panel.
    refute html =~ "+300.00"
    refute html =~ "+37.50"
    assert html =~ "—"
  end

  # User story (ADR-0033 — open lots surface):
  # As a maintainer on the trades tab,
  # I want each open FIFO lot to show its security-currency basis and the
  # price/currency decomposition,
  # so that the lot view agrees with the holdings view by construction.
  test "the open lots table shows the native basis and decomposition", %{conn: conn} do
    w = usd_world()

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: ~D[2026-01-15],
        quantity: "10",
        price: "80.00",
        currency_code: "EUR",
        security_amount: "1000.00",
        settlement_amount: "800.00",
        settlement_fx_rate: "0.80"
      })

    put_quote!(w.security, ~D[2026-07-31], "110.00")
    seed_current_rate!("1.00")

    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=trades")
    html = view |> element("#detail-tab-panel-trades") |> render()

    # The native per-unit basis (100.00 USD), not the recorded 80.00 EUR,
    # prices the lot against the USD quote.
    assert html =~ "100.00"
    assert html =~ "Price return"
    assert html =~ "Currency return"
    assert html =~ "+200.00"
  end

  # User story (ADR-0033 — the chart overlay stops folding blind):
  # As a maintainer whose imported cross-currency buys carry no native leg,
  # I want the cost-basis chart overlay to stay away rather than draw a
  # EUR figure onto a USD price chart,
  # so that the chart never resurrects the blind comparison.
  test "the cost-basis overlay is honestly unavailable without a native leg", %{conn: conn} do
    w = usd_world()
    legacy_buy!(w)
    today = Date.utc_today()
    put_quote!(w.security, Date.add(today, -30), "100.00")
    put_quote!(w.security, Date.add(today, -5), "110.00")

    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=chart")

    html =
      view
      |> element("button[phx-click='toggle_detail_cost_basis']")
      |> render_click()

    refute html =~ "chart-cost-basis"
  end

  # Counter-metric: a backfilled cross-currency buy folds its NATIVE price
  # into the overlay, so the line sits on the security-currency price scale.
  test "the cost-basis overlay uses the native leg when derivable", %{conn: conn} do
    w = usd_world()

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: Date.add(Date.utc_today(), -20),
        quantity: "10",
        price: "80.00",
        currency_code: "EUR",
        security_amount: "1000.00",
        settlement_amount: "800.00",
        settlement_fx_rate: "0.80"
      })

    today = Date.utc_today()
    put_quote!(w.security, Date.add(today, -30), "100.00")
    put_quote!(w.security, Date.add(today, -5), "110.00")

    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=chart")

    html =
      view
      |> element("button[phx-click='toggle_detail_cost_basis']")
      |> render_click()

    assert html =~ "chart-cost-basis"
  end
end
