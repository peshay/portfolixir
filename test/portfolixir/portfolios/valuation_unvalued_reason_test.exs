defmodule Portfolixir.Portfolios.ValuationUnvaluedReasonTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [
      base_world: 0,
      create_security!: 1,
      buy!: 3,
      put_quote!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation

  # User story (#406):
  # As a local portfolio maintainer,
  # I want the valuation to distinguish "no price at all" from "price known,
  # but no exchange rate to the base currency stored",
  # so that the data-quality warning tells the truth instead of claiming a
  # priced position has no price.
  #
  # Acceptance criteria:
  # - A position with a resolvable native price but no FX path to the base
  #   currency counts as NOT valued in base-currency totals (owner decision
  #   2026-07-31), carries `unvalued_reason: :missing_fx`, and keeps its
  #   native `latest_price` and `price_currency` so the UI can show them.
  # - A position with neither quote nor trade price carries
  #   `unvalued_reason: :no_price` and a nil price.
  # - A valued position carries `unvalued_reason: nil`.

  test "distinguishes missing-FX from no-price positions" do
    world = base_world()

    usd = create_security!(name: "US Co.", ticker: "USCO", currency: "USD", asset_class: "equity")
    dark = create_security!(name: "Dark Co.", ticker: "DARK", asset_class: "equity")

    # The USD position is priced by a quote, but no USD->EUR rate is stored.
    {:ok, usd_cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "USD Cash",
        currency_code: "USD"
      })

    {:ok, usd_depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: usd_cash.id,
        name: "USD Depot"
      })

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: usd_depot.id,
        cash_account_id: usd_cash.id,
        security_id: usd.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "10",
        price: "100",
        fees: "0",
        taxes: "0",
        currency_code: "USD"
      })

    put_quote!(usd, ~D[2026-06-01], "120")

    # The dark position is held via delivery only: no quote, no trade price.
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: dark.id,
        type: "inbound_delivery",
        date: ~D[2026-01-02],
        quantity: "7",
        currency_code: "EUR"
      })

    valuation = Valuation.for_portfolio(world.portfolio.id)
    by_security = Map.new(valuation.positions, &{&1.security_id, &1})

    usd_row = by_security[usd.id]
    refute usd_row.valued
    assert usd_row.unvalued_reason == :missing_fx
    assert Decimal.equal?(usd_row.latest_price, Decimal.new("120"))
    assert usd_row.price_currency == "USD"
    assert is_nil(usd_row.market_value)

    dark_row = by_security[dark.id]
    refute dark_row.valued
    assert dark_row.unvalued_reason == :no_price
    assert is_nil(dark_row.latest_price)
    assert is_nil(dark_row.market_value)

    assert valuation.unvalued_count == 2
  end

  test "a valued position carries no unvalued reason" do
    world = base_world()
    equity = create_security!(name: "Apple Inc.", ticker: "AAPL", asset_class: "equity")
    buy!(world, equity, quantity: "10", price: "80")
    put_quote!(equity, ~D[2026-06-01], "100")

    valuation = Valuation.for_portfolio(world.portfolio.id)
    [row] = valuation.positions

    assert row.valued
    assert is_nil(row.unvalued_reason)
    assert row.price_currency == "EUR"
  end

  # User story (#406):
  # As a local portfolio maintainer,
  # I want portfolio totals and the security detail to resolve prices with the
  # SAME semantics (the global trade-price fallback wins on both surfaces),
  # so that the two screens can never disagree about whether a price exists.
  #
  # Acceptance criteria:
  # - A quote-less security held in portfolio B but traded (priced) only in
  #   portfolio A is valued in B's totals from the global latest trade price
  #   (price_source :trade), exactly as the global holdings view prices it.
  # - The view valuation (all portfolios) agrees with the sum of the
  #   per-portfolio totals.

  test "prices a position from a trade booked in another portfolio (global fallback)" do
    world_a = base_world()

    {:ok, portfolio_b} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Second Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, cash_b} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio_b.id,
        name: "B Cash",
        currency_code: "EUR"
      })

    {:ok, depot_b} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio_b.id,
        cash_account_id: cash_b.id,
        name: "B Depot"
      })

    quiet = create_security!(name: "Quiet Co.", ticker: "QUIET", asset_class: "equity")

    # The only price observation lives in portfolio A.
    buy!(world_a, quiet, quantity: "10", price: "50")

    # Portfolio B holds the security via delivery only.
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio_b.id,
        securities_account_id: depot_b.id,
        security_id: quiet.id,
        type: "inbound_delivery",
        date: ~D[2026-02-02],
        quantity: "4",
        currency_code: "EUR"
      })

    valuation_b = Valuation.for_portfolio(portfolio_b.id)
    [row] = valuation_b.positions

    assert row.valued
    assert row.price_source == :trade
    assert Decimal.equal?(row.latest_price, Decimal.new("50"))
    assert Decimal.equal?(row.market_value, Decimal.new("200"))
    assert valuation_b.unvalued_count == 0

    # The global holdings view prices it identically.
    global = Valuation.holdings_by_security()
    assert global[quiet.id].valued
    assert Decimal.equal?(global[quiet.id].market_value, Decimal.new("700"))

    # And the everything-view total equals the sum of the portfolio totals.
    valuation_a = Valuation.for_portfolio(world_a.portfolio.id)
    view = Valuation.for_view(nil)

    assert Decimal.equal?(
             view.total_value,
             Decimal.add(valuation_a.total_value, valuation_b.total_value)
           )
  end

  # User story (#406, review fix):
  # As a local portfolio maintainer with a non-EUR-base portfolio,
  # I want the security detail's "counted in totals?" status resolved against
  # the base currencies of the portfolios that actually hold the security,
  # so that the detail line never claims a position is missing from totals
  # that do count it (or vice versa).
  #
  # Acceptance criteria:
  # - For a USD-base portfolio holding a USD-priced security with no stored
  #   rates at all, the status is valued (USD->USD needs no rate), matching
  #   for_portfolio/2.
  # - With a mixed set of bases, the failing bases are reported in
  #   missing_rate_currencies and the status is unvalued (:missing_fx).
  test "security_status resolves against the holding portfolios' base currencies" do
    world = base_world()

    usd = create_security!(name: "US Co.", ticker: "USCO", currency: "USD", asset_class: "equity")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: usd.id,
        type: "inbound_delivery",
        date: ~D[2026-01-02],
        quantity: "3",
        currency_code: "USD"
      })

    put_quote!(usd, ~D[2026-06-01], "120")

    # A USD-base portfolio counts the USD position without any stored rate.
    status = Valuation.security_status(usd.id, ["USD"])
    assert status.valued
    assert is_nil(status.unvalued_reason)
    assert status.missing_rate_currencies == []

    # Against EUR (the default hub) the rate is genuinely missing.
    status = Valuation.security_status(usd.id)
    refute status.valued
    assert status.unvalued_reason == :missing_fx
    assert status.missing_rate_currencies == ["EUR"]

    # Mixed bases: only the failing base is reported.
    status = Valuation.security_status(usd.id, ["EUR", "USD"])
    refute status.valued
    assert status.unvalued_reason == :missing_fx
    assert status.missing_rate_currencies == ["EUR"]
  end

  # User story (#406):
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want the global holdings-by-security valuation to carry the same honest
  # unvalued reason per security,
  # so that the classification tree, the API and the security detail explain
  # a missing value the same way the portfolio totals do.
  #
  # Acceptance criteria:
  # - Each holdings_by_security row carries `unvalued_reason`
  #   (:no_price | :missing_fx | nil) plus the native `latest_price`,
  #   `price_currency` and `price_source`.
  # - The API report rows carry the same fields.

  test "holdings_by_security carries unvalued reasons and native prices" do
    world = base_world()

    usd = create_security!(name: "US Co.", ticker: "USCO", currency: "USD", asset_class: "equity")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: usd.id,
        type: "inbound_delivery",
        date: ~D[2026-01-02],
        quantity: "3",
        currency_code: "USD"
      })

    put_quote!(usd, ~D[2026-06-01], "120")

    dark = create_security!(name: "Dark Co.", ticker: "DARK", asset_class: "equity")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: dark.id,
        type: "inbound_delivery",
        date: ~D[2026-01-02],
        quantity: "7",
        currency_code: "EUR"
      })

    valued = create_security!(name: "EU Co.", ticker: "EUCO", asset_class: "equity")
    buy!(world, valued, quantity: "2", price: "10")
    put_quote!(valued, ~D[2026-06-01], "11")

    holdings = Valuation.holdings_by_security()

    assert holdings[usd.id].unvalued_reason == :missing_fx
    assert Decimal.equal?(holdings[usd.id].latest_price, Decimal.new("120"))
    assert holdings[usd.id].price_currency == "USD"
    assert holdings[usd.id].price_source == :quote

    assert holdings[dark.id].unvalued_reason == :no_price
    assert is_nil(holdings[dark.id].latest_price)

    assert is_nil(holdings[valued.id].unvalued_reason)
    assert holdings[valued.id].price_source == :quote

    report = Valuation.holdings_by_security_report()
    usd_row = Enum.find(report.holdings, &(&1.security_id == usd.id))
    assert usd_row.unvalued_reason == :missing_fx
    assert Decimal.equal?(usd_row.latest_price, Decimal.new("120"))
    assert usd_row.price_currency == "USD"

    # A missing-FX position becomes valued once the rate arrives.
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-06-04],
          rate: "1.20",
          source: "manual"
        }
      ])

    holdings = Valuation.holdings_by_security()
    assert holdings[usd.id].valued
    assert is_nil(holdings[usd.id].unvalued_reason)
    assert Decimal.equal?(holdings[usd.id].market_value, Decimal.new("300"))
  end
end
