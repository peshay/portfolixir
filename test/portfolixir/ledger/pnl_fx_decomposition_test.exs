defmodule Portfolixir.Ledger.PnlFxDecompositionTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger

  # All figures below are the synthetic ADR-0033 fixture (EUR base, a USD
  # security, purchase rate 0.80 EUR/USD, current rate 0.90 EUR/USD) or exact
  # variations of it. Nothing here resembles any real portfolio.

  defp usd_world do
    world = base_world(name: "FX Decomp", cash_name: "EUR Cash", depot_name: "FX Depot")
    security = create_security!(name: "Synthetic US Equity", ticker: "SUS", currency: "USD")
    Map.put(world, :security, security)
  end

  # A manual ADR-0015 booking: trade in the security's own currency, cash leg
  # in EUR carried by the settlement fields.
  defp manual_cross_buy!(w, opts \\ []) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: Keyword.get(opts, :date, ~D[2026-01-15]),
        quantity: Keyword.get(opts, :quantity, "10"),
        price: Keyword.get(opts, :price, "100.00"),
        currency_code: "USD",
        security_amount: Keyword.get(opts, :security_amount, "1000.00"),
        settlement_amount: Keyword.get(opts, :settlement_amount, "800.00"),
        settlement_fx_rate: Keyword.get(opts, :settlement_fx_rate, "0.80")
      })

    tx
  end

  # A backfilled imported booking: booked in the account currency (EUR price),
  # with the ADR-0015 settlement fields carrying the derived native leg.
  defp backfilled_import_buy!(w, opts \\ []) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: Keyword.get(opts, :date, ~D[2026-01-15]),
        quantity: Keyword.get(opts, :quantity, "10"),
        price: Keyword.get(opts, :price, "80.00"),
        currency_code: "EUR",
        security_amount: Keyword.get(opts, :security_amount, "1000.00"),
        settlement_amount: Keyword.get(opts, :settlement_amount, "800.00"),
        settlement_fx_rate: Keyword.get(opts, :settlement_fx_rate, "0.80")
      })

    tx
  end

  # An imported cross-currency booking whose native leg was never derivable:
  # EUR-priced buy of the USD security, no settlement fields.
  defp unbackfilled_import_buy!(w, opts \\ []) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: Keyword.get(opts, :date, ~D[2026-01-15]),
        quantity: Keyword.get(opts, :quantity, "10"),
        price: Keyword.get(opts, :price, "80.00"),
        currency_code: "EUR"
      })

    tx
  end

  defp holding(w, opts) do
    [row] = Ledger.holdings_for_portfolio(w.portfolio.id, opts)
    row
  end

  # User story (ADR-0033, issue #569):
  # As a local portfolio maintainer holding a USD security bought through a
  # EUR account,
  # I want the position's P&L decomposed into a price return and a currency
  # return that sum exactly to the EUR total,
  # so that a price move and an FX move are never mixed into one misleading
  # number.
  #
  # Acceptance criteria (the ADR-0033 fixture, pinned exactly):
  # - cost basis is the security-currency cost (USD 1,000.00), avg cost 100.
  # - base_cost is the EUR amount actually paid (800.00).
  # - price return = (1,100 - 1,000) x 0.90 = EUR 90.00 (+11.25 %).
  # - currency return = 1,000 x 0.90 - 800 = EUR 100.00 (+12.50 %).
  # - total = EUR 190.00 (+23.75 %), and total = price + currency exactly.
  test "decomposes the ADR-0033 fixture into price and currency returns" do
    w = usd_world()
    manual_cross_buy!(w)
    put_quote!(w.security, ~D[2026-07-31], "110.00")

    row = holding(w, fx_rates: %{"USD" => Decimal.new("0.90")})

    assert Decimal.equal?(row.cost_basis, Decimal.new("1000.00"))
    assert Decimal.equal?(row.avg_cost, Decimal.new("100"))
    assert Decimal.equal?(row.market_value, Decimal.new("1100.00"))
    assert Decimal.equal?(row.unrealized_pnl_abs, Decimal.new("100.00"))

    assert row.decomposed
    assert row.undecomposed_reason == nil
    assert row.base_currency == "EUR"
    assert Decimal.equal?(row.base_cost, Decimal.new("800.00"))
    assert Decimal.equal?(row.price_return_abs, Decimal.new("90.00"))
    assert Decimal.equal?(row.currency_return_abs, Decimal.new("100.00"))
    assert Decimal.equal?(row.total_return_base_abs, Decimal.new("190.00"))
    assert Decimal.equal?(row.price_return_pct, Decimal.new("0.1125"))
    assert Decimal.equal?(row.currency_return_pct, Decimal.new("0.125"))
    assert Decimal.equal?(row.total_return_base_pct, Decimal.new("0.2375"))

    # The identity is exact by construction, not approximately true.
    assert Decimal.equal?(
             Decimal.add(row.price_return_abs, row.currency_return_abs),
             row.total_return_base_abs
           )
  end

  # User story (ADR-0033 day-one phantom):
  # As a maintainer who imported a EUR-booked buy of a USD security,
  # I want zero real movement to read as zero price return and zero currency
  # return through the real stored-rate path,
  # so that the phantom day-one P&L of the blind fold can never come back.
  #
  # Acceptance criteria:
  # - Uses a stored EUR-hub rate (1 EUR = 1.25 USD, i.e. 0.80 EUR/USD).
  # - cost basis is USD 1,000 (not the 800 EUR figure), avg cost USD 100.
  # - Both components and the total are exactly zero.
  test "day-one zero movement decomposes to exactly zero through stored rates" do
    w = usd_world()

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-01-15],
          rate: "1.25",
          source: "manual"
        }
      ])

    backfilled_import_buy!(w)
    put_quote!(w.security, ~D[2026-01-15], "100.00")

    row = holding(w, [])

    assert Decimal.equal?(row.cost_basis, Decimal.new("1000.00"))
    assert Decimal.equal?(row.avg_cost, Decimal.new("100"))
    assert row.decomposed
    assert Decimal.equal?(row.price_return_abs, Decimal.new("0"))
    assert Decimal.equal?(row.currency_return_abs, Decimal.new("0"))
    assert Decimal.equal?(row.total_return_base_abs, Decimal.new("0"))
    assert Decimal.equal?(row.unrealized_pnl_abs, Decimal.new("0"))
    assert Decimal.equal?(row.unrealized_pnl_pct, Decimal.new("0"))
  end

  # User story (ADR-0033 FX-loss case):
  # As a maintainer whose USD security is up in USD while the dollar fell,
  # I want the surface to show a positive price return, a negative currency
  # return and the negative EUR total,
  # so that a position that lost me money in EUR is never shown green without
  # the explanation.
  #
  # Acceptance criteria (rate 0.70 variant of the fixture):
  # - price return = (1,100 - 1,000) x 0.70 = EUR 70.00.
  # - currency return = 1,000 x 0.70 - 800 = EUR -100.00.
  # - total = EUR -30.00 while the native P&L stays +100 USD.
  test "an FX loss shows price up, currency down and a negative base total" do
    w = usd_world()
    manual_cross_buy!(w)
    put_quote!(w.security, ~D[2026-07-31], "110.00")

    row = holding(w, fx_rates: %{"USD" => Decimal.new("0.70")})

    assert Decimal.equal?(row.unrealized_pnl_abs, Decimal.new("100.00"))
    assert row.decomposed
    assert Decimal.equal?(row.price_return_abs, Decimal.new("70.00"))
    assert Decimal.equal?(row.currency_return_abs, Decimal.new("-100.00"))
    assert Decimal.equal?(row.total_return_base_abs, Decimal.new("-30.00"))
  end

  # User story (ADR-0033 degenerate case):
  # As a maintainer holding an ordinary EUR security in a EUR portfolio,
  # I want the currency return to be exactly zero and the price return to
  # equal the familiar P&L,
  # so that the decomposition adds no noise to the common case.
  #
  # Acceptance criteria:
  # - currency return is exactly 0 (no rate lookup is even needed).
  # - price return equals the total and the native unrealized P&L.
  test "a same-currency position has an exactly zero currency return" do
    world = base_world(name: "Same CCY Decomp", cash_name: "SC Cash", depot_name: "SC Depot")
    security = create_security!(name: "Synthetic EU Equity", ticker: "SEU", currency: "EUR")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "10",
        price: "100",
        currency_code: "EUR"
      })

    put_quote!(security, ~D[2026-06-01], "120")

    [row] = Ledger.holdings_for_portfolio(world.portfolio.id)

    assert row.decomposed
    assert row.base_currency == "EUR"
    assert Decimal.equal?(row.base_cost, Decimal.new("1000"))
    assert Decimal.equal?(row.currency_return_abs, Decimal.new("0"))
    assert Decimal.equal?(row.price_return_abs, Decimal.new("200"))
    assert Decimal.equal?(row.total_return_base_abs, Decimal.new("200"))
    assert Decimal.equal?(row.price_return_abs, row.unrealized_pnl_abs)
  end

  # User story (ADR-0033 hard requirement 1):
  # As a maintainer comparing the holdings rows with the portfolio total,
  # I want the per-position base-currency totals to sum exactly to the
  # base-currency P&L over the same positions,
  # so that the rows and the total can never disagree.
  #
  # Acceptance criteria:
  # - EUR position: total 200; USD position: total 190 (fixture rate 0.90).
  # - The row sums equal (sum of base market values) - (sum of base costs),
  #   Decimal-exactly.
  test "row totals reconcile with the base-currency P&L over the same positions" do
    w = usd_world()
    manual_cross_buy!(w)
    put_quote!(w.security, ~D[2026-07-31], "110.00")

    eur = create_security!(name: "Synthetic EU Core", ticker: "SEC", currency: "EUR")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: eur.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "10",
        price: "100",
        currency_code: "EUR"
      })

    put_quote!(eur, ~D[2026-07-31], "120")

    rows =
      Ledger.holdings_for_portfolio(w.portfolio.id, fx_rates: %{"USD" => Decimal.new("0.90")})

    assert length(rows) == 2
    assert Enum.all?(rows, & &1.decomposed)

    row_sum =
      Enum.reduce(rows, Decimal.new(0), fn row, acc ->
        Decimal.add(acc, row.total_return_base_abs)
      end)

    base_market_value =
      Enum.reduce(rows, Decimal.new(0), fn row, acc ->
        rate = if row.currency_code == "USD", do: Decimal.new("0.90"), else: Decimal.new("1")
        Decimal.add(acc, Decimal.mult(row.market_value, rate))
      end)

    base_cost_sum =
      Enum.reduce(rows, Decimal.new(0), fn row, acc -> Decimal.add(acc, row.base_cost) end)

    assert Decimal.equal?(row_sum, Decimal.sub(base_market_value, base_cost_sum))
    assert Decimal.equal?(row_sum, Decimal.new("390.00"))
  end

  # User story (ADR-0033 hard requirement 4 — honesty over availability):
  # As a maintainer with an imported cross-currency buy whose native leg was
  # never derivable,
  # I want the security-currency cost basis and the decomposition reported
  # unavailable instead of a silently wrong number,
  # so that the old phantom P&L cannot hide behind a confident figure.
  #
  # Acceptance criteria:
  # - cost_basis / avg_cost / unrealized P&L are nil.
  # - decomposed is false with reason :missing_native_cost.
  # - The EUR amount actually paid stays visible as base_cost.
  test "a cross-currency row with no derivable native leg is honestly unavailable" do
    w = usd_world()
    unbackfilled_import_buy!(w)
    put_quote!(w.security, ~D[2026-07-31], "110.00")

    row = holding(w, fx_rates: %{"USD" => Decimal.new("0.90")})

    assert row.cost_basis == nil
    assert row.avg_cost == nil
    assert row.unrealized_pnl_abs == nil
    assert row.unrealized_pnl_pct == nil
    refute row.decomposed
    assert row.undecomposed_reason == :missing_native_cost
    assert Decimal.equal?(row.base_cost, Decimal.new("800.00"))
    assert row.base_currency == "EUR"
    # The market value is price-derived and stays visible.
    assert Decimal.equal?(row.market_value, Decimal.new("1100.00"))
  end

  # User story (ADR-0033 hard requirement 4):
  # As a maintainer without a stored rate for the security's currency,
  # I want the decomposition marked unavailable with reason missing_fx while
  # the native figures stay intact,
  # so that a missing rate never invents a base-currency number.
  test "a missing current rate reports missing_fx and keeps native figures" do
    w = usd_world()
    manual_cross_buy!(w)
    put_quote!(w.security, ~D[2026-07-31], "110.00")

    row = holding(w, [])

    assert Decimal.equal?(row.cost_basis, Decimal.new("1000.00"))
    assert Decimal.equal?(row.unrealized_pnl_abs, Decimal.new("100.00"))
    refute row.decomposed
    assert row.undecomposed_reason == :missing_fx
    assert row.price_return_abs == nil
    assert row.currency_return_abs == nil
    assert row.total_return_base_abs == nil
  end

  # User story (ADR-0033 requirement 5 — no mixed-currency figure):
  # As a maintainer who paid for a USD security from a USD cash account of a
  # EUR-base portfolio,
  # I want the decomposition reported unavailable (the settlement leg is not
  # in the base currency) instead of pretending USD were EUR,
  # so that the base_cost is always denominated in a named currency.
  test "a settlement leg outside the base currency reports missing_base_cost" do
    world =
      base_world(
        name: "USD Cash World",
        cash_name: "USD Cash",
        cash_currency: "USD",
        depot_name: "USD Depot"
      )

    security = create_security!(name: "Synthetic US Tech", ticker: "SUT", currency: "USD")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "10",
        price: "100",
        currency_code: "USD"
      })

    put_quote!(security, ~D[2026-06-01], "110")

    [row] =
      Ledger.holdings_for_portfolio(world.portfolio.id, fx_rates: %{"USD" => Decimal.new("0.90")})

    # Native figures are exact — the security-currency side is unaffected.
    assert Decimal.equal?(row.cost_basis, Decimal.new("1000"))
    assert Decimal.equal?(row.unrealized_pnl_abs, Decimal.new("100"))
    refute row.decomposed
    assert row.undecomposed_reason == :missing_base_cost
    assert Decimal.equal?(row.base_cost, Decimal.new("1000"))
    assert row.base_currency == "USD"
  end

  # User story (ADR-0033 consequence — the fold carries a cost pair):
  # As a maintainer selling part of a cross-currency position,
  # I want the sell to slice the native and the base cost proportionally,
  # so that the remaining position's decomposition still reconciles.
  #
  # Acceptance criteria:
  # - After selling 5 of 10: native cost 500.00 USD, base cost 400.00 EUR.
  test "a sell slices native and base cost proportionally" do
    w = usd_world()
    manual_cross_buy!(w)

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "sell",
        date: ~D[2026-03-01],
        quantity: "5",
        price: "120.00",
        currency_code: "USD",
        security_amount: "600.00",
        settlement_amount: "540.00",
        settlement_fx_rate: "0.90"
      })

    put_quote!(w.security, ~D[2026-07-31], "110.00")

    row = holding(w, fx_rates: %{"USD" => Decimal.new("0.90")})

    assert Decimal.equal?(row.quantity, Decimal.new("5"))
    assert Decimal.equal?(row.cost_basis, Decimal.new("500.00"))
    assert Decimal.equal?(row.base_cost, Decimal.new("400.00"))
    assert row.decomposed
    # price = (550 - 500) x 0.90 = 45; currency = 500 x 0.90 - 400 = 50.
    assert Decimal.equal?(row.price_return_abs, Decimal.new("45.00"))
    assert Decimal.equal?(row.currency_return_abs, Decimal.new("50.00"))
    assert Decimal.equal?(row.total_return_base_abs, Decimal.new("95.00"))
  end

  # User story (ADR-0033 surfaces change together):
  # As a maintainer on the security detail page,
  # I want the per-depot holdings rows to carry the same decomposition,
  # so that the security detail and the portfolio holdings cannot disagree.
  test "holdings_for_security carries the same decomposition fields" do
    w = usd_world()
    manual_cross_buy!(w)

    [row] =
      Ledger.holdings_for_security(w.security.id,
        latest_price: Decimal.new("110.00"),
        fx_rates: %{"USD" => Decimal.new("0.90")}
      )

    assert Decimal.equal?(row.cost_basis, Decimal.new("1000.00"))
    assert row.decomposed
    assert Decimal.equal?(row.price_return_abs, Decimal.new("90.00"))
    assert Decimal.equal?(row.currency_return_abs, Decimal.new("100.00"))
    assert Decimal.equal?(row.total_return_base_abs, Decimal.new("190.00"))
    assert row.base_currency == "EUR"
  end

  # User story (ADR-0033 — FIFO open lots adopt the same basis):
  # As a maintainer reading the FIFO open lots of an imported cross-currency
  # position,
  # I want each lot's basis in the security's own currency plus the same
  # price/currency decomposition,
  # so that the lots and the holdings surface cannot disagree from birth.
  test "open lots carry the native basis and the decomposition" do
    w = usd_world()
    backfilled_import_buy!(w)

    %{open_lots: [lot]} =
      Ledger.list_trades_for_security(w.security.id,
        latest_price: Decimal.new("110.00"),
        fx_rates: %{"USD" => Decimal.new("0.90")}
      )

    # The recorded (transaction-currency) price stays visible, the native
    # per-unit basis is derived from the settlement legs.
    assert Decimal.equal?(lot.buy_price, Decimal.new("80.00"))
    assert Decimal.equal?(lot.buy_price_native, Decimal.new("100.00"))
    assert Decimal.equal?(lot.unrealized_pnl_abs, Decimal.new("100.00"))
    assert Decimal.equal?(lot.unrealized_pnl_pct, Decimal.new("0.1"))
    assert lot.decomposed
    assert lot.base_currency == "EUR"
    assert Decimal.equal?(lot.base_cost, Decimal.new("800.00"))
    assert Decimal.equal?(lot.price_return_abs, Decimal.new("90.00"))
    assert Decimal.equal?(lot.currency_return_abs, Decimal.new("100.00"))
    assert Decimal.equal?(lot.total_return_base_abs, Decimal.new("190.00"))
  end

  # User story (honesty on lots):
  # As a maintainer with an unbackfillable imported cross-currency lot,
  # I want the lot's unrealized P&L reported unavailable instead of comparing
  # a EUR price against a USD quote,
  # so that the lot surface never resurrects the blind comparison.
  test "an open lot with no derivable native leg is honestly unavailable" do
    w = usd_world()
    unbackfilled_import_buy!(w)

    %{open_lots: [lot]} =
      Ledger.list_trades_for_security(w.security.id, latest_price: Decimal.new("110.00"))

    assert Decimal.equal?(lot.buy_price, Decimal.new("80.00"))
    assert lot.buy_price_native == nil
    assert lot.unrealized_pnl_abs == nil
    assert lot.unrealized_pnl_pct == nil
    refute lot.decomposed
    assert lot.undecomposed_reason == :missing_native_cost
  end
end
