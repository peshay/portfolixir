defmodule Portfolixir.Portfolios.PricingContextTest do
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
  alias Portfolixir.Classifications
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.PricingContext
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation

  # User story:
  # As a local portfolio maintainer,
  # I want the market data a page needs (securities, quotes, own trade prices
  # and exchange rates) loaded once per read and reused by every valuation and
  # allocation in that read,
  # so that opening the dashboard stops asking the database the same handful of
  # questions hundreds of times — without any number on the page changing.
  #
  # Acceptance criteria (ADR-0035 hard requirements 1 and 4):
  # - Every affected read returns exactly what it returns today, with and
  #   without a supplied pricing context: positions, weights, totals, cash
  #   balances and the ADR-0033 decomposition fields are Decimal-identical.
  # - The honesty paths are untouched: `valued`, `unvalued_reason`
  #   (`:no_price` vs `:missing_fx`) and `price_source` behave identically, so
  #   an absent key in a preloaded map is never mistaken for "no price".
  # - The context is plain data with the lifetime of one read: nothing is
  #   stored, cached or invalidated.

  # ---------------------------------------------------------------------------
  # A multi-portfolio, multi-currency, quote/trade-price-mixed fixture.
  #
  #   * 3 portfolios: two EUR-based, one USD-based.
  #   * cash accounts in EUR, USD and NOK (NOK has no stored rate on purpose).
  #   * securities quoted in EUR, USD and GBX (the pence pseudo-currency that
  #     triangulates through GBP), one priced only by an own trade, one with no
  #     price at all, and one whose currency has no rate path.
  # ---------------------------------------------------------------------------
  defp world do
    put_rates()

    eur_a = base_world(name: "Synthetic Portfolio A", currency: "EUR")
    usd_b = base_world(name: "Synthetic Portfolio B", currency: "USD", cash_currency: "USD")
    eur_c = base_world(name: "Synthetic Portfolio C", currency: "EUR")

    nok_pair =
      add_depot(eur_c.portfolio,
        currency: "NOK",
        cash_currency: "NOK",
        cash_name: "Synthetic NOK Cash",
        depot_name: "Synthetic NOK Depot"
      )

    securities = securities()

    seed_eur_a(eur_a, securities)
    seed_usd_b(usd_b, securities)
    seed_eur_c(eur_c, nok_pair, securities)

    put_quotes(securities)

    %{eur_a: eur_a, usd_b: usd_b, eur_c: eur_c, nok_pair: nok_pair, securities: securities}
  end

  defp put_rates do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-01-05],
          rate: "1.05",
          source: "manual"
        },
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
        }
      ])
  end

  defp securities do
    %{
      eur: create_security!(name: "Synthetic EUR ETF", ticker: "SYNEUR", currency: "EUR"),
      usd:
        create_security!(
          name: "Synthetic USD Equity",
          ticker: "SYNUSD",
          currency: "USD",
          asset_class: "equity"
        ),
      gbx:
        create_security!(
          name: "Synthetic GBX Equity",
          ticker: "SYNGBX",
          currency: "GBX",
          asset_class: "equity"
        ),
      traded:
        create_security!(
          name: "Synthetic Trade-Priced Equity",
          ticker: "SYNTRD",
          currency: "USD",
          asset_class: "equity"
        ),
      unpriced:
        create_security!(
          name: "Synthetic Unpriced Equity",
          ticker: "SYNNIL",
          currency: "EUR",
          asset_class: "equity"
        ),
      norate:
        create_security!(
          name: "Synthetic NOK Equity",
          ticker: "SYNNOK",
          currency: "NOK",
          asset_class: "equity"
        )
    }
  end

  # Portfolio A: EUR base, a EUR holding, a cross-currency USD holding booked
  # per ADR-0015 (native price + settlement leg) and a GBX holding.
  defp seed_eur_a(world, securities) do
    deposit!(world, "50000", ~D[2026-01-02])
    buy!(world, securities.eur, quantity: "40", price: "125.50", date: ~D[2026-01-06])
    cross_currency_buy!(world, securities.usd, "30", "88.25", "0.80", ~D[2026-01-07])
    cross_currency_buy!(world, securities.gbx, "12", "1234.5", "0.0125", ~D[2026-02-10])
  end

  # Portfolio B: USD base, one USD holding plus a security that has no quote at
  # all, so its price falls back to this own trade (price_source :trade).
  defp seed_usd_b(world, securities) do
    deposit!(world, "20000", ~D[2026-01-02], currency: "USD")

    buy!(world, securities.usd,
      quantity: "10",
      price: "90",
      date: ~D[2026-01-08],
      currency: "USD"
    )

    buy!(world, securities.traded,
      quantity: "25",
      price: "40",
      date: ~D[2026-03-03],
      currency: "USD"
    )
  end

  # Portfolio C: EUR base, a delivered holding with no price at all
  # (unvalued_reason :no_price), a NOK-quoted holding with no rate path
  # (unvalued_reason :missing_fx), and a NOK cash account with no rate path.
  defp seed_eur_c(world, nok_pair, securities) do
    deposit!(world, "10000", ~D[2026-01-02])
    buy!(world, securities.eur, quantity: "10", price: "120", date: ~D[2026-01-09])
    inbound_delivery!(world, securities.unpriced, "7", ~D[2026-01-10])

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: nok_pair.cash.id,
        type: "deposit",
        date: ~D[2026-01-02],
        gross_amount: "5000",
        currency_code: "NOK"
      })

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: nok_pair.depot.id,
        cash_account_id: nok_pair.cash.id,
        security_id: securities.norate.id,
        type: "buy",
        date: ~D[2026-01-11],
        quantity: "15",
        price: "210",
        currency_code: "NOK"
      })
  end

  defp put_quotes(securities) do
    put_quote!(securities.eur, ~D[2026-06-30], "131.25")
    put_quote!(securities.usd, ~D[2026-06-30], "94.60")
    put_quote!(securities.gbx, ~D[2026-06-30], "1310.5")
    put_quote!(securities.norate, ~D[2026-06-30], "225.75")
    # `securities.traded` and `securities.unpriced` deliberately have no quote.
  end

  defp cross_currency_buy!(world, security, quantity, price, rate, date) do
    security_amount = Decimal.mult(Decimal.new(quantity), Decimal.new(price))

    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
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

  defp inbound_delivery!(world, security, quantity, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: security.id,
        type: "inbound_delivery",
        date: date,
        quantity: quantity,
        currency_code: security.currency_code
      })

    tx
  end

  # A recursive Decimal-aware comparison: every Decimal is compared with
  # `Decimal.equal?/2` and every other term with `==`, reporting the exact path
  # of the first difference. Structural equality is asserted on top, so a
  # numerically-equal-but-differently-scaled Decimal is caught too.
  defp assert_identical(left, right), do: assert_identical(left, right, [])

  defp assert_identical(%Decimal{} = left, %Decimal{} = right, path) do
    assert Decimal.equal?(left, right),
           "#{render_path(path)}: #{Decimal.to_string(left)} != #{Decimal.to_string(right)}"
  end

  defp assert_identical(left, right, path)
       when is_map(left) and is_map(right) and not is_struct(left) and not is_struct(right) do
    assert Map.keys(left) |> Enum.sort() == Map.keys(right) |> Enum.sort(),
           "#{render_path(path)}: different keys"

    Enum.each(left, fn {key, value} ->
      assert_identical(value, Map.fetch!(right, key), path ++ [key])
    end)
  end

  defp assert_identical(left, right, path) when is_list(left) and is_list(right) do
    assert length(left) == length(right), "#{render_path(path)}: different length"

    left
    |> Enum.zip(right)
    |> Enum.with_index()
    |> Enum.each(fn {{l, r}, index} -> assert_identical(l, r, path ++ [index]) end)
  end

  defp assert_identical(left, right, path) do
    assert left == right, "#{render_path(path)}: #{inspect(left)} != #{inspect(right)}"
  end

  defp render_path([]), do: "root"
  defp render_path(path), do: path |> Enum.map_join(".", &to_string/1)

  defp position(valuation, security_id) do
    Enum.find(valuation.positions, &(&1.security_id == security_id))
  end

  # ---------------------------------------------------------------------------

  test "for_portfolio/2 returns Decimal-identical results with and without a context" do
    w = world()
    context = PricingContext.for_all_portfolios("EUR")

    for portfolio <- [w.eur_a.portfolio, w.usd_b.portfolio, w.eur_c.portfolio] do
      without = Valuation.for_portfolio(portfolio.id)
      with_context = Valuation.for_portfolio(portfolio.id, pricing_context: context)

      assert_identical(without, with_context)
      assert without == with_context
    end
  end

  test "for_view/2 returns Decimal-identical results with and without a context" do
    _w = world()
    context = PricingContext.for_all_portfolios("EUR")

    without = Valuation.for_view(nil, base_currency: "EUR")
    with_context = Valuation.for_view(nil, base_currency: "EUR", pricing_context: context)

    assert_identical(without, with_context)
    assert without == with_context

    # The totals stay the sum of the per-portfolio valuations, both ways.
    assert Decimal.equal?(without.total_value, with_context.total_value)
    refute Decimal.equal?(without.total_value, Decimal.new(0))
  end

  test "holdings_by_security/1 returns Decimal-identical results with and without a context" do
    _w = world()
    context = PricingContext.for_all_portfolios("EUR")

    without = Valuation.holdings_by_security()
    with_context = Valuation.holdings_by_security(pricing_context: context)

    assert_identical(without, with_context)
    assert without == with_context
  end

  test "security_status/2 returns Decimal-identical results with and without a context" do
    w = world()
    context = PricingContext.for_all_portfolios("EUR")

    for {_key, security} <- w.securities, bases <- [["EUR"], ["EUR", "USD"], ["NOK"]] do
      without = Valuation.security_status(security.id, bases)
      with_context = Valuation.security_status(security.id, bases, pricing_context: context)

      assert_identical(without, with_context)
      assert without == with_context
    end
  end

  test "Allocation.for_portfolio/3 returns Decimal-identical results with and without a context" do
    w = world()
    classification = steering_tree(w)
    context = PricingContext.for_all_portfolios("EUR")

    for portfolio <- [w.eur_a.portfolio, w.usd_b.portfolio, w.eur_c.portfolio] do
      {:ok, without} = Allocation.for_portfolio(portfolio.id, classification.id)

      {:ok, with_context} =
        Allocation.for_portfolio(portfolio.id, classification.id, pricing_context: context)

      assert_identical(without, with_context)
      assert without == with_context
    end
  end

  defp steering_tree(w) do
    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Synthetic Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Synthetic Core"
      })

    {:ok, satellite} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Synthetic Satellite"
      })

    for {key, security} <- w.securities do
      category = if key in [:eur, :usd], do: core, else: satellite

      {:ok, _} =
        Classifications.assign_security(
          Actor.owner_ui(),
          security.id,
          classification.id,
          category.id
        )
    end

    for portfolio <- [w.eur_a.portfolio, w.usd_b.portfolio, w.eur_c.portfolio] do
      {:ok, _} =
        Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
          %{"category_id" => core.id, "target_weight" => "0.7"},
          %{"category_id" => satellite.id, "target_weight" => "0.3"}
        ])
    end

    classification
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a position whose price or exchange rate is missing to say so exactly
  # as before when the page preloads its market data,
  # so that a preloaded map's absent key can never be silently read as
  # "no price" (or hide one that exists).
  #
  # Acceptance criteria:
  # - A quote-less but traded security keeps `price_source: :trade`.
  # - A security with neither quote nor trade reports `unvalued_reason:
  #   :no_price`.
  # - A priced security with no rate path reports `unvalued_reason:
  #   :missing_fx` and keeps its native `latest_price` / `price_currency`.
  test "the honesty paths behave identically through a preloaded context" do
    w = world()
    context = PricingContext.for_all_portfolios("EUR")

    trade_priced =
      Valuation.for_portfolio(w.usd_b.portfolio.id, pricing_context: context)
      |> position(w.securities.traded.id)

    assert trade_priced.price_source == :trade
    assert trade_priced.valued
    assert Decimal.equal?(trade_priced.latest_price, Decimal.new("40"))

    eur_c = Valuation.for_portfolio(w.eur_c.portfolio.id, pricing_context: context)

    unpriced = position(eur_c, w.securities.unpriced.id)
    refute unpriced.valued
    assert unpriced.unvalued_reason == :no_price
    assert is_nil(unpriced.latest_price)
    assert is_nil(unpriced.price_source)

    norate = position(eur_c, w.securities.norate.id)
    refute norate.valued
    assert norate.unvalued_reason == :missing_fx
    assert norate.price_source == :quote
    assert norate.price_currency == "NOK"
    assert Decimal.equal?(norate.latest_price, Decimal.new("225.75"))

    # The NOK cash account has no rate path either and stays out of the total.
    nok_cash = Enum.find(eur_c.cash_balances, &(&1.currency == "NOK"))
    refute nok_cash.valued
    assert is_nil(nok_cash.base_value)
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a read handed market data that does not cover everything it needs to
  # fall back to the lookup it replaced instead of guessing,
  # so that a narrower context can never turn a priced position into an
  # unvalued one or a rate path into a missing one.
  test "a context that does not cover a read falls back and stays identical" do
    w = world()

    # Built for portfolio A only: it carries neither B's positions and cash nor
    # the securities B holds but A does not.
    narrow = PricingContext.for_portfolio(w.eur_a.portfolio.id, "EUR")

    assert :miss = PricingContext.positions(narrow, w.usd_b.portfolio.id)
    assert :miss = PricingContext.security(narrow, w.securities.traded.id)

    without = Valuation.for_portfolio(w.usd_b.portfolio.id)
    with_narrow = Valuation.for_portfolio(w.usd_b.portfolio.id, pricing_context: narrow)

    assert_identical(without, with_narrow)
    assert without == with_narrow

    # The quote-less, trade-priced holding outside the narrow context's coverage
    # is still priced from its own trade, not reported as unpriced.
    fallback = position(with_narrow, w.securities.traded.id)
    assert fallback.price_source == :trade
    assert fallback.valued

    # A securities-only context carries no positions, cash accounts or balances
    # at all: every one of those falls back too.
    securities_only = PricingContext.for_securities([w.securities.eur.id])

    assert :miss = PricingContext.positions(securities_only, w.eur_c.portfolio.id)
    assert :miss = PricingContext.cash_accounts(securities_only, w.eur_c.portfolio.id)
    assert :miss = PricingContext.cash_balances(securities_only, :all)

    view_without = Valuation.for_view(nil, base_currency: "EUR")

    view_with =
      Valuation.for_view(nil, base_currency: "EUR", pricing_context: securities_only)

    assert_identical(view_without, view_with)
    assert view_without == view_with
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the batched market-data loaders to resolve prices and rates exactly
  # like the per-row lookups they replace,
  # so that the ADR-0033 price/currency decomposition on the holdings surfaces
  # keeps reporting the same figures and the same honest unavailability.
  test "batched quotes and hub rates feed the ADR-0033 decomposition identically" do
    w = world()

    for portfolio <- [w.eur_a.portfolio, w.usd_b.portfolio, w.eur_c.portfolio] do
      context = PricingContext.for_portfolio(portfolio.id, portfolio.base_currency_code)

      without = Ledger.holdings_for_portfolio(portfolio.id)

      with_batched =
        Ledger.holdings_for_portfolio(portfolio.id,
          prices: PricingContext.quote_prices(context),
          fx_rates: PricingContext.base_rates(context, portfolio.base_currency_code)
        )

      assert_identical(without, with_batched)
      assert without == with_batched

      for row <- with_batched do
        assert Map.has_key?(row, :price_return_abs)
        assert Map.has_key?(row, :currency_return_abs)
        assert Map.has_key?(row, :decomposed)
      end
    end
  end

  test "the context is plain read-scoped data, not stored state" do
    _w = world()

    first = PricingContext.for_all_portfolios("EUR")
    second = PricingContext.for_all_portfolios("EUR")

    assert %PricingContext{} = first
    assert first == second
    refute is_pid(first)
  end

  # Without this, the identical-output tests above would still pass if every
  # lookup silently fell back to the per-row query the context is meant to
  # replace: the win would be zero and nothing would say so.
  test "the instance-wide context actually covers every held security and currency" do
    w = world()
    context = PricingContext.for_all_portfolios("EUR")

    for {key, security} <- w.securities do
      assert {:ok, %{id: id}} = PricingContext.security(context, security.id)
      assert id == security.id

      case key do
        key when key in [:traded, :unpriced] ->
          assert {:ok, nil} = PricingContext.quote_row(context, security.id)

        _quoted ->
          assert {:ok, %{close: %Decimal{}}} = PricingContext.quote_row(context, security.id)
      end
    end

    assert {:ok, _} = PricingContext.positions(context, w.eur_a.portfolio.id)
    assert {:ok, _} = PricingContext.cash_accounts(context, w.usd_b.portfolio.id)
    assert {:ok, _} = PricingContext.cash_balances(context, w.eur_c.portfolio.id)

    # NOK is covered and has no rate: absent from the map is the answer, not a
    # coverage miss.
    assert {:error, :no_rate} = PricingContext.rate(context, "NOK", "EUR")
    assert {:ok, usd} = PricingContext.rate(context, "USD", "EUR")
    assert Decimal.equal?(usd, Decimal.div(Decimal.new(1), Decimal.new("1.25")))
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the bulk hub-rate loader to answer exactly what the per-row rate
  # lookup answers, including the GBX/GBP pence case and the EUR-hub
  # triangulation, so that converting from a preloaded map cannot change a
  # single converted figure.
  test "Fx.hub_rates/1 matches the per-row rate lookups, GBX and hub included" do
    put_rates()

    rates = Fx.hub_rates(["EUR", "USD", "GBP", "GBX", "NOK"])

    assert Decimal.equal?(rates["EUR"], Decimal.new(1))
    assert Decimal.equal?(rates["USD"], Decimal.new("1.25"))
    assert Decimal.equal?(rates["GBP"], Decimal.new("0.80"))
    assert Decimal.equal?(rates["GBX"], Decimal.new("80.00"))
    refute Map.has_key?(rates, "NOK")

    for from <- ["EUR", "USD", "GBP", "GBX", "NOK"], to <- ["EUR", "USD", "GBP", "GBX", "NOK"] do
      amount = Decimal.new("1234.5678")

      assert Fx.rate_from_hub_rates(from, to, rates) == Fx.rate(from, to),
             "rate #{from}->#{to} differs"

      assert Fx.convert_with_hub_rates(amount, from, to, rates) == Fx.convert(amount, from, to),
             "convert #{from}->#{to} differs"
    end
  end
end
