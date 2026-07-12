defmodule Portfolixir.Portfolios.ViewValuationTest do
  @moduledoc """
  Cross-portfolio view valuation (ADR-0024, epic story 1): `Valuation.for_view/2`
  values the deduplicated union of all accounts matching a view across every
  portfolio, with the same pricing fallbacks and EUR-hub FX as
  `Valuation.for_portfolio/2`. All money assertions are exact `Decimal` —
  never float tolerance.
  """
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [
      base_world: 1,
      add_depot: 2,
      create_security!: 1,
      buy!: 3,
      deposit!: 4
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Valuation

  defp bucket!(name) do
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: name})
    bucket
  end

  defp view_including!(name, buckets) do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: name, include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, Enum.map(buckets, & &1.id), [])
    view
  end

  defp tag_accounts!(bucket_ids, depots, cash_accounts) do
    Enum.each(depots, &Buckets.set_depot_default_buckets(Actor.owner_ui(), &1, bucket_ids))
    Enum.each(cash_accounts, &Buckets.set_cash_account_buckets(Actor.owner_ui(), &1, bucket_ids))
  end

  # The spike's stand-in construction (view_additivity_spike_test.exs): summing
  # the portfolio-scoped view valuations over every portfolio values the view's
  # deduplicated account set instance-wide. `for_view/2` must be Decimal-exact
  # equal to it.
  defp sum_over_portfolios(portfolio_ids, view_id, prices) do
    portfolio_ids
    |> Enum.map(&Valuation.for_portfolio(&1, prices: prices, view: view_id))
    |> Enum.reduce(Decimal.new("0"), &Decimal.add(&2, &1.total_with_cash))
  end

  # User story (ADR-0024 story 1):
  # As a local portfolio maintainer,
  # I want a view's total wealth computed across all portfolios with each
  # account counted once,
  # so that views become the trustworthy aggregation scope of the app.
  #
  # Acceptance criteria:
  # - `Valuation.for_view/2` values the deduplicated union of all accounts
  #   matching the view across portfolios — Decimal-exact equal to the spike's
  #   sum of portfolio-scoped view valuations.
  # - The same pricing fallbacks apply: quote/override price, then the latest
  #   own trade price (`price_source: :trade`).
  # - Multi-currency positions and cash convert through the EUR hub exactly as
  #   in `for_portfolio/2`.
  # - A depot tagged into two included buckets counts once, never twice.
  # - Overlap is reported as data: which depots/cash accounts carry more than
  #   one of the view's included buckets.
  test "values a view across all portfolios with each account counted once" do
    alpha = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")

    alpha_usd =
      add_depot(alpha.portfolio,
        currency: "USD",
        cash_name: "Alpha USD Cash",
        depot_name: "Alpha USD Depot"
      )

    alpha_usd_world = %{portfolio: alpha.portfolio, depot: alpha_usd.depot, cash: alpha_usd.cash}

    beta = base_world(name: "Beta", cash_name: "Beta Cash", depot_name: "Beta Depot")

    shared_sec = create_security!(name: "Shared Co.", ticker: "SHRD", asset_class: "equity")

    usd_sec =
      create_security!(name: "US Co.", ticker: "USCO", currency: "USD", asset_class: "equity")

    # No quote and no price override: valued via the latest-trade-price fallback.
    trade_sec = create_security!(name: "Trade-Priced Co.", ticker: "TRDP", asset_class: "equity")

    # 1 EUR = 1.25 USD (ECB semantics), the EUR-hub rate used by valuation.
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-06-01],
          rate: "1.25",
          source: "manual"
        }
      ])

    deposit!(alpha, "300", ~D[2026-01-01], [])
    buy!(alpha, shared_sec, quantity: "10", price: "10")
    deposit!(alpha_usd_world, "1500", ~D[2026-01-01], currency: "USD")
    buy!(alpha_usd_world, usd_sec, quantity: "10", price: "100", currency: "USD")
    deposit!(beta, "300", ~D[2026-01-01], [])
    buy!(beta, trade_sec, quantity: "4", price: "25")

    prices = %{shared_sec.id => Decimal.new("10"), usd_sec.id => Decimal.new("100")}

    mine = bucket!("mine")
    household = bucket!("household")

    # The overlap: the Alpha EUR depot and its cash carry BOTH buckets.
    tag_accounts!([mine.id, household.id], [alpha.depot], [alpha.cash])
    tag_accounts!([household.id], [alpha_usd.depot, beta.depot], [alpha_usd.cash, beta.cash])

    both_view = view_including!("Mine+Household", [mine, household])
    mine_view = view_including!("Mine", [mine])
    household_view = view_including!("Household", [household])

    portfolio_ids = [alpha.portfolio.id, beta.portfolio.id]

    # The household view spans every account: positions 100 EUR + (1000 USD ->
    # 800 EUR) + 100 EUR trade-priced; cash 200 EUR + (500 USD -> 400 EUR) +
    # 200 EUR.
    household_val = Valuation.for_view(household_view.id, prices: prices)
    assert household_val.view_id == household_view.id
    assert household_val.base_currency == "EUR"
    assert Decimal.equal?(household_val.total_value, Decimal.new("1000"))
    assert Decimal.equal?(household_val.total_cash, Decimal.new("800"))
    assert Decimal.equal?(household_val.total_with_cash, Decimal.new("1800"))

    # Trade-price fallback survives the cross-portfolio path.
    assert household_val.trade_priced_count == 1
    trade_position = Enum.find(household_val.positions, &(&1.security_id == trade_sec.id))
    assert trade_position.price_source == :trade
    assert Decimal.equal?(trade_position.market_value, Decimal.new("100"))

    # Weights are shares of the cross-portfolio securities total.
    usd_position = Enum.find(household_val.positions, &(&1.security_id == usd_sec.id))
    assert Decimal.equal?(usd_position.weight, Decimal.new("0.8"))

    # The decisive dedup case: the view spanning both buckets equals the
    # deduplicated union of its accounts. Bucket-summing resolution would
    # count the doubly-tagged Alpha EUR depot (100) and cash (200) twice
    # and report 2100; membership-based resolution reports 1800.
    both_val = Valuation.for_view(both_view.id, prices: prices)
    assert Decimal.equal?(both_val.total_with_cash, Decimal.new("1800"))
    refute Decimal.equal?(both_val.total_with_cash, Decimal.new("2100"))

    # No position row is duplicated for carrying two included buckets.
    position_keys = Enum.map(both_val.positions, &{&1.securities_account_id, &1.security_id})
    assert position_keys == Enum.uniq(position_keys)

    # The narrow view sees only the doubly-tagged depot and cash.
    mine_val = Valuation.for_view(mine_view.id, prices: prices)
    assert Decimal.equal?(mine_val.total_with_cash, Decimal.new("300"))

    # Decimal-exact parity with the spike's sum-over-portfolios construction.
    for view <- [both_view, mine_view, household_view] do
      total = Valuation.for_view(view.id, prices: prices).total_with_cash
      assert Decimal.equal?(total, sum_over_portfolios(portfolio_ids, view.id, prices))
    end

    # Overlap as data: the Alpha EUR depot and cash carry two of the spanning
    # view's included buckets; single-bucket views report no overlap even for
    # the doubly-tagged accounts (only *included* buckets count).
    assert both_val.overlap == %{
             overlapping?: true,
             securities_account_ids: [alpha.depot.id],
             cash_account_ids: [alpha.cash.id]
           }

    assert household_val.overlap.overlapping? == false

    assert mine_val.overlap == %{
             overlapping?: false,
             securities_account_ids: [],
             cash_account_ids: []
           }
  end

  # User story (ADR-0024 story 1):
  # As a local portfolio maintainer,
  # I want a special "everything" scope equal to the unscoped sum over all
  # portfolios,
  # so that the instance-wide total needs no artificial catch-all view.
  #
  # Acceptance criteria:
  # - `Valuation.for_view(nil, opts)` equals the Decimal-exact sum of the
  #   unscoped `for_portfolio/2` totals over all portfolios.
  # - The everything scope reports no overlap (there is no include set).
  test "the everything scope (view_id nil) equals the unscoped sum over all portfolios" do
    alpha = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")
    beta = base_world(name: "Beta", cash_name: "Beta Cash", depot_name: "Beta Depot")

    security = create_security!(name: "World Co.", ticker: "WRLD", asset_class: "equity")

    deposit!(alpha, "300", ~D[2026-01-01], [])
    buy!(alpha, security, quantity: "10", price: "10")
    deposit!(beta, "500", ~D[2026-01-01], [])
    buy!(beta, security, quantity: "5", price: "20")

    prices = %{security.id => Decimal.new("10")}

    everything = Valuation.for_view(nil, prices: prices)

    unscoped_sum =
      [alpha.portfolio.id, beta.portfolio.id]
      |> Enum.map(&Valuation.for_portfolio(&1, prices: prices))
      |> Enum.reduce(Decimal.new("0"), &Decimal.add(&2, &1.total_with_cash))

    assert everything.view_id == nil
    assert Decimal.equal?(everything.total_with_cash, unscoped_sum)
    # Positions 100 + 50; cash 200 + 400.
    assert Decimal.equal?(everything.total_with_cash, Decimal.new("750"))

    assert everything.overlap == %{
             overlapping?: false,
             securities_account_ids: [],
             cash_account_ids: []
           }
  end

  # User story (fix round, per-portfolio trade-price fallback):
  # As a local portfolio maintainer,
  # I want the cross-portfolio view valuation to price each portfolio's
  # quote-less positions with THAT portfolio's own latest trade price,
  # so that the everything scope stays Decimal-identical to the sum of the
  # unscoped portfolio totals — a position with no price observation in its
  # own portfolio must stay unvalued, not borrow another portfolio's price.
  #
  # Acceptance criteria:
  # - A quote-less security delivered into portfolio A but traded only in
  #   portfolio B is unvalued in A and trade-priced in B under `for_view/2`.
  # - `for_view(nil)` equals the Decimal-exact sum of the unscoped
  #   `for_portfolio/2` totals.
  test "quote-less positions use each portfolio's own trade price, never a global one" do
    alpha = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")
    beta = base_world(name: "Beta", cash_name: "Beta Cash", depot_name: "Beta Depot")

    ghost = create_security!(name: "Ghost Co.", ticker: "GHST", asset_class: "equity")

    # Delivered into Alpha: held there without any own price observation.
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: alpha.portfolio.id,
        securities_account_id: alpha.depot.id,
        security_id: ghost.id,
        type: "inbound_delivery",
        date: ~D[2026-01-02],
        quantity: "7",
        currency_code: "EUR"
      })

    # Traded only in Beta: the trade price belongs to Beta's universe.
    deposit!(beta, "500", ~D[2026-01-01], [])
    buy!(beta, ghost, quantity: "2", price: "30")

    everything = Valuation.for_view(nil, [])

    alpha_row = Enum.find(everything.positions, &(&1.securities_account_id == alpha.depot.id))
    beta_row = Enum.find(everything.positions, &(&1.securities_account_id == beta.depot.id))

    # Alpha's delivered position stays unvalued (no price in Alpha's own
    # portfolio); Beta's is valued at its own trade price.
    refute alpha_row.valued
    assert beta_row.valued
    assert beta_row.price_source == :trade
    assert everything.unvalued_count == 1
    assert everything.trade_priced_count == 1

    # Decimal-exact parity with the sum of the unscoped portfolio totals:
    # Beta 60 position + 440 cash = 500; Alpha contributes nothing valued.
    unscoped_sum =
      [alpha.portfolio.id, beta.portfolio.id]
      |> Enum.map(&Valuation.for_portfolio(&1, []))
      |> Enum.reduce(Decimal.new("0"), &Decimal.add(&2, &1.total_with_cash))

    assert Decimal.equal?(everything.total_with_cash, unscoped_sum)
    assert Decimal.equal?(everything.total_with_cash, Decimal.new("500"))
  end

  # User story (fix round, deleted-view degradation):
  # As a local portfolio maintainer,
  # I want `for_view/2` on a vanished view id to return a not-found error,
  # so that a stale id from another tab degrades instead of crashing.
  test "for_view returns a not-found error for a deleted view id" do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Gone", include_all: true})
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), view)

    assert Valuation.for_view(view.id, []) == {:error, :view_not_found}
  end

  # User story (ADR-0024 story 1):
  # As a local portfolio maintainer,
  # I want per-position bucket overrides honored in the cross-portfolio scope,
  # so that a position deliberately re-tagged out of a view never leaks back in.
  #
  # Acceptance criteria:
  # - A position override wins over the depot default in `for_view/2`, exactly
  #   as it does in the portfolio-scoped path.
  test "honors per-position bucket overrides in the cross-portfolio scope" do
    world = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")

    kept = create_security!(name: "Kept Co.", ticker: "KEPT", asset_class: "equity")
    moved = create_security!(name: "Moved Co.", ticker: "MOVD", asset_class: "equity")

    deposit!(world, "500", ~D[2026-01-01], [])
    buy!(world, kept, quantity: "1", price: "100")
    buy!(world, moved, quantity: "1", price: "100")

    prices = %{kept.id => Decimal.new("100"), moved.id => Decimal.new("100")}

    household = bucket!("household")
    side = bucket!("side")
    tag_accounts!([household.id], [world.depot], [world.cash])
    :ok = Buckets.set_position_override(Actor.owner_ui(), world.depot, moved, [side.id])

    household_view = view_including!("Household", [household])
    side_view = view_including!("Side", [side])

    household_val = Valuation.for_view(household_view.id, prices: prices)
    assert Enum.map(household_val.positions, & &1.security_id) == [kept.id]
    # Position 100 + cash 300; the moved position is out despite the depot tag.
    assert Decimal.equal?(household_val.total_with_cash, Decimal.new("400"))

    side_val = Valuation.for_view(side_view.id, prices: prices)
    assert Enum.map(side_val.positions, & &1.security_id) == [moved.id]
    assert Decimal.equal?(side_val.total_with_cash, Decimal.new("100"))
  end
end
