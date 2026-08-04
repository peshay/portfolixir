defmodule Portfolixir.Portfolios.PricingProbeTest do
  @moduledoc false
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [
      base_world: 1,
      add_depot: 2,
      create_security!: 1,
      buy!: 3,
      deposit!: 3,
      deposit!: 4,
      put_quote!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.PricingContext
  alias Portfolixir.Portfolios.Valuation

  defp rates do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-06-05],
          rate: "1.25",
          source: "manual"
        },
        %{
          base_currency: "EUR",
          quote_currency: "GBP",
          date: ~D[2026-06-05],
          rate: "0.80",
          source: "manual"
        },
        %{
          base_currency: "EUR",
          quote_currency: "CHF",
          date: ~D[2026-06-05],
          rate: "0.95",
          source: "manual"
        }
      ])
  end


  defp xbuy!(w, security, quantity, price, rate, date) do
    security_amount = Decimal.mult(Decimal.new(quantity), Decimal.new(price))

    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: security.id,
        type: "buy",
        date: date,
        quantity: quantity,
        price: price,
        currency_code: security.currency_code,
        security_amount: Decimal.to_string(security_amount),
        settlement_amount: security_amount |> Decimal.mult(Decimal.new(rate)) |> to_string(),
        settlement_fx_rate: rate
      })

    tx
  end

  test "GBX-based portfolio: base currency itself needs GBX triangulation" do
    rates()
    w = base_world(name: "P GBX", currency: "GBX", cash_currency: "GBX")
    eur_sec = create_security!(name: "S EUR", ticker: "SEUR", currency: "EUR")
    usd_sec = create_security!(name: "S USD", ticker: "SUSD", currency: "USD")
    deposit!(w, "100000", ~D[2026-01-02], currency: "GBX")
    xbuy!(w, eur_sec, "5", "100", "80", ~D[2026-01-06])
    xbuy!(w, usd_sec, "3", "50", "64", ~D[2026-01-07])
    put_quote!(eur_sec, ~D[2026-06-30], "111.11")
    put_quote!(usd_sec, ~D[2026-06-30], "77.77")

    without = Valuation.for_portfolio(w.portfolio.id)
    ctx = PricingContext.for_all_portfolios("GBX")
    with_ctx = Valuation.for_portfolio(w.portfolio.id, pricing_context: ctx)
    assert without == with_ctx

    ctx2 = PricingContext.for_portfolio(w.portfolio.id, "GBX")
    assert without == Valuation.for_portfolio(w.portfolio.id, pricing_context: ctx2)
    refute Decimal.equal?(without.total_value, Decimal.new(0))
  end

  test "split-adjusted quotes: batched loader equals per-row for split and non-split securities" do
    rates()
    w = base_world(name: "P split", currency: "EUR")
    split_sec = create_security!(name: "S split", ticker: "SSPL", currency: "EUR")
    plain_sec = create_security!(name: "S plain", ticker: "SPLN", currency: "EUR")
    two_splits = create_security!(name: "S two", ticker: "STWO", currency: "USD")
    deposit!(w, "100000", ~D[2026-01-02])
    buy!(w, split_sec, quantity: "10", price: "100", date: ~D[2026-01-06])
    buy!(w, plain_sec, quantity: "10", price: "100", date: ~D[2026-01-06])
    xbuy!(w, two_splits, "10", "100", "0.8", ~D[2026-01-06])

    for {sec, date, p, q} <- [
          {split_sec, ~D[2026-03-01], 2, 1},
          {two_splits, ~D[2026-02-01], 3, 1},
          {two_splits, ~D[2026-04-01], 5, 2}
        ] do
      {:ok, _} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: w.portfolio.id,
          security_id: sec.id,
          type: "split",
          date: date,
          currency_code: sec.currency_code,
          split_ratio_numerator: p,
          split_ratio_denominator: q
        })
    end

    # A stale close from BEFORE the split effective dates, so adjustment bites.
    put_quote!(split_sec, ~D[2026-02-15], "200")
    put_quote!(plain_sec, ~D[2026-06-30], "200")
    put_quote!(two_splits, ~D[2026-01-15], "300")

    ids = [split_sec.id, plain_sec.id, two_splits.id]
    batched = Quotes.adjusted_latest_by_security_ids(ids)

    for id <- ids do
      assert Quotes.adjusted_latest(id) == Map.get(batched, id), "adjusted quote differs for #{id}"
    end

    without = Valuation.for_portfolio(w.portfolio.id)
    ctx = PricingContext.for_all_portfolios("EUR")
    assert without == Valuation.for_portfolio(w.portfolio.id, pricing_context: ctx)
  end

  test "base_currency override outside a supplied context's coverage still matches" do
    rates()
    w = base_world(name: "P ovr", currency: "EUR")
    sec = create_security!(name: "S", ticker: "SX", currency: "USD")
    deposit!(w, "100000", ~D[2026-01-02])
    xbuy!(w, sec, "4", "50", "0.8", ~D[2026-01-06])
    put_quote!(sec, ~D[2026-06-30], "61.75")

    ctx = PricingContext.for_all_portfolios("EUR")

    for base <- ["CHF", "GBX", "GBP", "USD", "EUR", "NOK"] do
      without = Valuation.for_portfolio(w.portfolio.id, base_currency: base)
      with_ctx = Valuation.for_portfolio(w.portfolio.id, base_currency: base, pricing_context: ctx)
      assert without == with_ctx, "base #{base} differs"

      vwithout = Valuation.for_view(nil, base_currency: base)
      vwith = Valuation.for_view(nil, base_currency: base, pricing_context: ctx)
      assert vwithout == vwith, "view base #{base} differs"
    end
  end

  test "security_status with bases outside a supplied context's coverage" do
    rates()
    w = base_world(name: "P st", currency: "EUR")
    sec = create_security!(name: "S", ticker: "SY", currency: "USD")
    nosec = create_security!(name: "S none", ticker: "SZ", currency: "NOK")
    deposit!(w, "100000", ~D[2026-01-02])
    xbuy!(w, sec, "4", "50", "0.8", ~D[2026-01-06])
    put_quote!(sec, ~D[2026-06-30], "61.75")

    ctx = PricingContext.for_all_portfolios("EUR")

    for s <- [sec, nosec],
        bases <- [["EUR"], ["CHF"], ["GBX"], ["NOK", "CHF"], ["EUR", "USD", "GBP"], []] do
      assert Valuation.security_status(s.id, bases) ==
               Valuation.security_status(s.id, bases, pricing_context: ctx),
             "status #{s.id} bases #{inspect(bases)} differs"
    end

    # A security that is not held at all is outside an instance-wide context's
    # security coverage -> must fall back, not read as "no such security".
    assert Valuation.security_status(nosec.id, ["EUR"]).price_currency == "NOK"
  end

  test "cross-portfolio narrow context reuse: every pair of contexts stays identical" do
    rates()
    a = base_world(name: "PA", currency: "EUR")
    b = base_world(name: "PB", currency: "CHF", cash_currency: "CHF")
    c = base_world(name: "PC", currency: "USD", cash_currency: "USD")
    extra = add_depot(c.portfolio, currency: "GBP", cash_currency: "GBP", cash_name: "GBP Cash", depot_name: "GBP Depot")

    s_eur = create_security!(name: "SE", ticker: "SE", currency: "EUR")
    s_gbx = create_security!(name: "SG", ticker: "SG", currency: "GBX")
    s_nok = create_security!(name: "SN", ticker: "SN", currency: "NOK")

    deposit!(a, "50000", ~D[2026-01-02])
    deposit!(b, "50000", ~D[2026-01-02], currency: "CHF")
    deposit!(c, "50000", ~D[2026-01-02], currency: "USD")

    buy!(a, s_eur, quantity: "10", price: "100", date: ~D[2026-01-06])
    xbuy!(b, s_gbx, "10", "1000", "0.012", ~D[2026-01-06])
    xbuy!(c, s_nok, "10", "100", "0.09", ~D[2026-01-06])

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: c.portfolio.id,
        cash_account_id: extra.cash.id,
        type: "deposit",
        date: ~D[2026-01-02],
        gross_amount: "1234",
        currency_code: "GBP"
      })

    put_quote!(s_eur, ~D[2026-06-30], "123.45")
    put_quote!(s_gbx, ~D[2026-06-30], "1111.5")
    put_quote!(s_nok, ~D[2026-06-30], "99.99")

    contexts = [
      PricingContext.for_all_portfolios("EUR"),
      PricingContext.for_all_portfolios("CHF"),
      PricingContext.for_portfolio(a.portfolio.id, "EUR"),
      PricingContext.for_portfolio(b.portfolio.id, "CHF"),
      PricingContext.for_portfolio(c.portfolio.id, "USD"),
      PricingContext.for_securities([s_eur.id]),
      PricingContext.for_securities([])
    ]

    for p <- [a.portfolio, b.portfolio, c.portfolio] do
      without = Valuation.for_portfolio(p.id)

      for {ctx, i} <- Enum.with_index(contexts) do
        assert without == Valuation.for_portfolio(p.id, pricing_context: ctx),
               "portfolio #{p.id} with context #{i} differs"
      end
    end

    view_without = Valuation.for_view(nil, base_currency: "EUR")
    hbs_without = Valuation.holdings_by_security()

    for {ctx, i} <- Enum.with_index(contexts) do
      assert view_without == Valuation.for_view(nil, base_currency: "EUR", pricing_context: ctx),
             "view with context #{i} differs"

      assert hbs_without == Valuation.holdings_by_security(pricing_context: ctx),
             "holdings_by_security with context #{i} differs"
    end
  end

  test "portfolio with no cash accounts and no positions" do
    rates()
    {:ok, empty} =
      Portfolixir.Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Empty",
        base_currency_code: "EUR"
      })

    ctx = PricingContext.for_all_portfolios("EUR")
    assert Valuation.for_portfolio(empty.id) == Valuation.for_portfolio(empty.id, pricing_context: ctx)
    assert Valuation.for_view(nil, base_currency: "EUR") ==
             Valuation.for_view(nil, base_currency: "EUR", pricing_context: ctx)
  end
end
