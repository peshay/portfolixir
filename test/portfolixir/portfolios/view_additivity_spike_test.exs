defmodule Portfolixir.Portfolios.ViewAdditivitySpikeTest do
  @moduledoc """
  Validation spike for ADR-0024 (issue #574): view totals must stay additive
  under overlapping buckets before the buckets/views restructure may start.

  ADR-0024 §3 requires an overlap fixture — a shared depot in two buckets with
  a Decimal-exact assertion that the "everything" total equals the deduplicated
  union of the view's accounts. The kill criterion fires if account-level
  deduplication cannot be shown to work cleanly and cheaply in the existing
  code, so every assertion here is exact `Decimal` — never float tolerance.

  How deduplication happens today (evidence for the spike report): a view is
  never valued as a sum over buckets. `Valuation.for_portfolio/2` iterates the
  single-count position universe (`Ledger.positions_for_portfolio/1`, keyed by
  `{securities_account_id, security_id}`) and keeps each entry via the
  membership predicate `Buckets.position_in_scope?/3`, which resolves the
  position's effective bucket set once and asks
  `Engines.BucketResolution.in_view?/2`. Cash accounts pass through
  `Buckets.cash_in_scope?/2` the same way. A holding tagged with two included
  buckets therefore matches once — deduplication is by construction.
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
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

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

  # Spike-level stand-in for the not-yet-built cross-portfolio view valuation:
  # portfolios partition the accounts, so summing the portfolio-scoped view
  # valuations over every portfolio values the view's deduplicated account set
  # across the whole instance without counting any account twice. The minimal
  # production shape is a `Valuation.for_view/2` doing exactly this union.
  defp view_total_across_portfolios(portfolio_ids, view_id, prices) do
    portfolio_ids
    |> Enum.map(&Valuation.for_portfolio(&1, prices: prices, view: view_id))
    |> Enum.reduce(Decimal.new("0"), &Decimal.add(&2, &1.total_with_cash))
  end

  # User story (spike, ADR-0024 §3 / #574):
  # As the maintainer deciding whether buckets/views may replace portfolios,
  # I want proof that a depot tagged into two buckets is counted exactly once
  # in any view spanning both buckets,
  # so that the total wealth number can never be inflated by overlapping tags.
  #
  # Acceptance criteria:
  # - The "everything" total over all accounts equals the total of a view that
  #   includes BOTH buckets of a shared depot — the depot counts once, not twice.
  # - Two overlapping views may each contain the shared depot, but each view
  #   internally deduplicates; their totals must not be summed.
  # - All assertions are exact Decimal comparisons.
  test "a shared depot in two buckets counts once in a view spanning both (overlap gate)" do
    world = base_world(name: "Household", cash_name: "Shared Cash", depot_name: "Shared Depot")

    partner =
      add_depot(world.portfolio, cash_name: "Partner Cash", depot_name: "Partner Depot")

    partner_world = %{portfolio: world.portfolio, depot: partner.depot, cash: partner.cash}

    shared_sec = create_security!(name: "Shared Co.", ticker: "SHRD", asset_class: "equity")
    partner_sec = create_security!(name: "Partner Co.", ticker: "PRTN", asset_class: "equity")

    deposit!(world, "300", ~D[2026-01-01], [])
    buy!(world, shared_sec, quantity: "10", price: "10")
    deposit!(partner_world, "500", ~D[2026-01-01], [])
    buy!(partner_world, partner_sec, quantity: "5", price: "20")

    prices = %{shared_sec.id => Decimal.new("10"), partner_sec.id => Decimal.new("20")}

    mine = bucket!("mine")
    household = bucket!("household")

    # The overlap: the shared depot and its cash carry BOTH buckets.
    tag_accounts!([mine.id, household.id], [world.depot], [world.cash])
    tag_accounts!([household.id], [partner.depot], [partner.cash])

    both_view = view_including!("Mine+Household", [mine, household])
    mine_view = view_including!("Mine", [mine])
    household_view = view_including!("Household", [household])

    everything = Valuation.for_portfolio(world.portfolio.id, prices: prices)

    # Everything: positions 100 + 100, cash 200 + 400.
    assert Decimal.equal?(everything.total_value, Decimal.new("200"))
    assert Decimal.equal?(everything.total_cash, Decimal.new("600"))
    assert Decimal.equal?(everything.total_with_cash, Decimal.new("800"))

    # (a) The decisive case: the view spanning both buckets equals the
    # deduplicated union of its accounts — byte-identical to "everything".
    # A bucket-summing resolution would report 1100 (the shared depot's
    # 100 position + 200 cash counted twice); membership-based resolution
    # reports 800.
    both = Valuation.for_portfolio(world.portfolio.id, prices: prices, view: both_view.id)
    assert both == everything
    assert Decimal.equal?(both.total_with_cash, Decimal.new("800"))
    refute Decimal.equal?(both.total_with_cash, Decimal.new("1100"))

    # No position row is duplicated for carrying two included buckets.
    position_keys = Enum.map(both.positions, &{&1.securities_account_id, &1.security_id})
    assert position_keys == Enum.uniq(position_keys)

    # (b) Two overlapping views both include the shared depot, each counting
    # it once internally.
    mine_val = Valuation.for_portfolio(world.portfolio.id, prices: prices, view: mine_view.id)
    assert Decimal.equal?(mine_val.total_with_cash, Decimal.new("300"))

    household_val =
      Valuation.for_portfolio(world.portfolio.id, prices: prices, view: household_view.id)

    assert Decimal.equal?(household_val.total_with_cash, Decimal.new("800"))

    # Overlapping view totals exceed the single-count universe when summed —
    # per ADR-0018 they are overlapping facets and must never be added.
    summed = Decimal.add(mine_val.total_with_cash, household_val.total_with_cash)
    assert Decimal.equal?(summed, Decimal.new("1100"))
    refute Decimal.equal?(summed, everything.total_with_cash)
  end

  # User story (spike, ADR-0024 §6 / #574):
  # As the maintainer migrating existing portfolios to buckets and views,
  # I want the mirrored setup (one exclusive-dimension bucket per portfolio,
  # one view per bucket) to reproduce today's portfolio totals exactly,
  # so that the migration changes presentation, never a single number.
  #
  # Acceptance criteria:
  # - The view-scoped valuation of each mirrored portfolio is identical to the
  #   portfolio-scoped valuation the Wealth page computes today — same quote
  #   pricing, same latest-trade-price fallback, same EUR-hub FX conversion.
  # - Under the exclusive dimension, the per-view totals add up to the
  #   instance-wide total (additivity is preserved, not dropped).
  test "one exclusive bucket + view per portfolio reproduces portfolio totals exactly" do
    alpha = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")

    alpha_usd =
      add_depot(alpha.portfolio,
        currency: "USD",
        cash_name: "Alpha USD Cash",
        depot_name: "Alpha USD Depot"
      )

    alpha_usd_world = %{portfolio: alpha.portfolio, depot: alpha_usd.depot, cash: alpha_usd.cash}

    beta = base_world(name: "Beta", cash_name: "Beta Cash", depot_name: "Beta Depot")

    eur_sec = create_security!(name: "Euro Co.", ticker: "EURC", asset_class: "equity")

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

    deposit!(alpha, "1000", ~D[2026-01-01], [])
    buy!(alpha, eur_sec, quantity: "3", price: "111.11")
    deposit!(alpha_usd_world, "1500", ~D[2026-01-01], currency: "USD")
    buy!(alpha_usd_world, usd_sec, quantity: "10", price: "100", currency: "USD")

    deposit!(beta, "300", ~D[2026-01-01], [])
    buy!(beta, trade_sec, quantity: "4", price: "25")

    prices = %{eur_sec.id => Decimal.new("111.11"), usd_sec.id => Decimal.new("100")}

    # The ADR-0024 migration shape: one exclusive-dimension bucket per
    # portfolio, one view per bucket.
    b_alpha = bucket!("portfolio-alpha")
    b_beta = bucket!("portfolio-beta")
    tag_accounts!([b_alpha.id], [alpha.depot, alpha_usd.depot], [alpha.cash, alpha_usd.cash])
    tag_accounts!([b_beta.id], [beta.depot], [beta.cash])
    v_alpha = view_including!("Alpha view", [b_alpha])
    v_beta = view_including!("Beta view", [b_beta])

    # Portfolio-scoped totals, computed the way the Wealth page does today.
    alpha_today = Valuation.for_portfolio(alpha.portfolio.id, prices: prices)
    beta_today = Valuation.for_portfolio(beta.portfolio.id, prices: prices)

    # Alpha: 333.33 EUR + (1000 USD -> 800 EUR) positions;
    # 666.67 EUR + (500 USD -> 400 EUR) cash.
    assert Decimal.equal?(alpha_today.total_value, Decimal.new("1133.33"))
    assert Decimal.equal?(alpha_today.total_cash, Decimal.new("1066.67"))
    assert Decimal.equal?(alpha_today.total_with_cash, Decimal.new("2200"))

    # Beta: 4 x 25 via the trade-price fallback; 300 - 100 cash.
    assert Decimal.equal?(beta_today.total_with_cash, Decimal.new("300"))
    assert [%{price_source: :trade}] = beta_today.positions

    # Migration equivalence: the mirrored view reproduces the portfolio total
    # byte-for-byte — same pricing fallbacks, same FX path, same weights.
    alpha_scoped =
      Valuation.for_portfolio(alpha.portfolio.id, prices: prices, view: v_alpha.id)

    beta_scoped = Valuation.for_portfolio(beta.portfolio.id, prices: prices, view: v_beta.id)
    assert alpha_scoped == alpha_today
    assert beta_scoped == beta_today
    assert [%{price_source: :trade}] = beta_scoped.positions

    # Exclusivity holds: the alpha view sees nothing of beta's accounts.
    cross = Valuation.for_portfolio(beta.portfolio.id, prices: prices, view: v_alpha.id)
    assert cross.positions == []
    assert Decimal.equal?(cross.total_with_cash, Decimal.new("0"))

    # Additivity across the instance: under the exclusive dimension the
    # per-view totals sum to the instance-wide total.
    portfolio_ids = [alpha.portfolio.id, beta.portfolio.id]
    alpha_view_total = view_total_across_portfolios(portfolio_ids, v_alpha.id, prices)
    beta_view_total = view_total_across_portfolios(portfolio_ids, v_beta.id, prices)

    assert Decimal.equal?(alpha_view_total, Decimal.new("2200"))
    assert Decimal.equal?(beta_view_total, Decimal.new("300"))

    everything_total =
      Decimal.add(alpha_today.total_with_cash, beta_today.total_with_cash)

    assert Decimal.equal?(Decimal.add(alpha_view_total, beta_view_total), everything_total)
    assert Decimal.equal?(everything_total, Decimal.new("2500"))
  end

  # User story (spike, ADR-0024 context / #574):
  # As the maintainer demoting the portfolio entity,
  # I want evidence that the Portfolio Performance import only needs depots and
  # cash accounts from the source file and fabricates the container internally,
  # so that removing portfolios from the UI cannot break the import round-trip.
  #
  # Acceptance criteria:
  # - The parsed preview references only PP depot ("portfolio" in PP-speak) and
  #   PP cash-account names; no Portfolixir portfolio concept comes from the file.
  # - The container is supplied by the application at apply time; its name is
  #   the app's choice, not a value from the file.
  test "the PP import takes depots and cash accounts from the file, the portfolio from the app" do
    body = File.read!(Path.join(@fixtures, "sample.json"))
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "sample.json")

    # The file's "portfolio"/"otherPortfolio" fields are PP depot names; the
    # mapping layer resolves them as depots, never as a Portfolixir portfolio.
    assert Mapping.unique_depot_pp_names(preview) == ["Test-Depot", "Test-Depot-2"]
    assert Mapping.unique_cash_pp_names(preview) == ["Test-Cash", "Test-Cash-2"]

    params = %{
      portfolio: {:create, %{name: "Spike Container", base_currency_code: "EUR"}},
      cash_accounts: %{
        "Test-Cash" => {:create, "Test-Cash"},
        "Test-Cash-2" => {:create, "Test-Cash-2"}
      },
      depots: %{
        "Test-Depot" => %{target: {:create, "Test-Depot"}, cash: "Test-Cash"},
        "Test-Depot-2" => %{target: {:create, "Test-Depot-2"}, cash: "Test-Cash-2"}
      }
    }

    assert {:ok, _result} = Imports.apply(preview, params)

    # The container carries the app-supplied name — fabricated internally,
    # exactly what ADR-0024 replaces with an editable bucket tag.
    portfolio = Enum.find(Portfolios.list_portfolios(), &(&1.name == "Spike Container"))
    assert portfolio

    depot_names =
      portfolio.id
      |> Portfolios.list_securities_accounts_for_portfolio()
      |> Enum.map(& &1.name)
      |> Enum.sort()

    assert depot_names == ["Test-Depot", "Test-Depot-2"]
  end
end
