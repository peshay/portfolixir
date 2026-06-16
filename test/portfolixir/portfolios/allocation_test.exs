defmodule Portfolixir.Portfolios.AllocationTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, base_world: 1, create_security!: 1, buy!: 3, deposit!: 3]

  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Targets

  # User story:
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want one call that breaks my live valuation down by strategy category and
  # compares it to my stored target weights,
  # so that my weekly SOLL/IST check and the drift per category come from a
  # single response instead of joining holdings, classifications and targets.
  #
  # Acceptance criteria:
  # - Each category reports its market value and actual weight (share of total).
  # - Each category reports its stored target weight and the drift
  #   (target - actual), both as a weight and restated in the base currency.
  # - A category with a target but no holdings still appears (drift = target).
  # - Securities held but unassigned in the tree are summed into `unassigned`.
  # - A parent category rolls up the value of its whole subtree: a position
  #   assigned to a child counts toward the child AND every ancestor, so a
  #   parent with a target is compared against its children's sum (not 0%).
  # - Rows come back in tree order (parent before children) tagged with depth,
  #   and each carries its own (direct) value next to the rolled-up value.

  defp setup_world do
    world = base_world()

    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    {:ok, satellite} =
      Classifications.create_category(%{classification_id: classification.id, name: "Satellite"})

    {:ok, defensive} =
      Classifications.create_category(%{classification_id: classification.id, name: "Defensive"})

    Map.merge(world, %{
      classification: classification,
      core: core,
      satellite: satellite,
      defensive: defensive
    })
  end

  defp equity!(name, ticker),
    do: create_security!(name: name, ticker: ticker, asset_class: "equity")

  defp buy!(world, security, qty, price), do: buy!(world, security, quantity: qty, price: price)

  defp fetch_category(allocation, category_id) do
    Enum.find(allocation.categories, &(&1.category_id == category_id))
  end

  test "breaks the valuation down by category and reports drift against targets" do
    world = setup_world()

    %{classification: classification, core: core, satellite: satellite, defensive: defensive} =
      world

    core_security = equity!("Core Equity", "CORE")
    satellite_security = equity!("Satellite Equity", "SAT")
    unassigned_security = equity!("Loose Equity", "LOOSE")

    {:ok, _} = Classifications.assign_security(core_security.id, classification.id, core.id)

    {:ok, _} =
      Classifications.assign_security(satellite_security.id, classification.id, satellite.id)

    # Fund the cash account so the buys leave it at zero: counting cash is 0, so
    # the basis here is securities only (the cash-in-basis case is covered by the
    # dedicated test below). See issue #335.
    deposit!(world, "1500", ~D[2026-01-01])

    buy!(world, core_security, "10", "80")
    buy!(world, satellite_security, "10", "40")
    buy!(world, unassigned_security, "5", "60")

    {:ok, _} =
      Targets.set_targets(world.portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"},
        %{"category_id" => satellite.id, "target_weight" => "0.3"},
        %{"category_id" => defensive.id, "target_weight" => "0.1"}
      ])

    prices = %{
      core_security.id => Decimal.new("80"),
      satellite_security.id => Decimal.new("40"),
      unassigned_security.id => Decimal.new("60")
    }

    {:ok, allocation} =
      Allocation.for_portfolio(world.portfolio.id, classification.id, prices: prices)

    # Total of the valued positions: 800 + 400 + 300.
    assert Decimal.equal?(allocation.total_value, Decimal.new("1500"))
    assert allocation.classification_name == "Strategy"

    core_row = fetch_category(allocation, core.id)
    assert Decimal.equal?(core_row.market_value, Decimal.new("800"))
    assert Decimal.equal?(Decimal.round(core_row.actual_weight, 4), Decimal.new("0.5333"))
    assert Decimal.equal?(core_row.target_weight, Decimal.new("0.6"))
    # target - actual = 0.6 - 0.5333... ; restated: +100 EUR to reach target.
    assert Decimal.equal?(Decimal.round(core_row.drift_value, 2), Decimal.new("100"))

    satellite_row = fetch_category(allocation, satellite.id)
    assert Decimal.equal?(satellite_row.market_value, Decimal.new("400"))
    assert Decimal.equal?(Decimal.round(satellite_row.drift_value, 2), Decimal.new("50"))

    # Defensive has a target but no holdings: it still appears, fully under target.
    defensive_row = fetch_category(allocation, defensive.id)
    assert Decimal.equal?(defensive_row.market_value, Decimal.new("0"))
    assert Decimal.equal?(defensive_row.target_weight, Decimal.new("0.1"))
    assert Decimal.equal?(Decimal.round(defensive_row.drift_value, 2), Decimal.new("150"))

    # The loose security is summed into the unassigned bucket, with its
    # per-position breakdown attached.
    assert Decimal.equal?(allocation.unassigned.market_value, Decimal.new("300"))
    assert [%{security_name: "Loose Equity"}] = allocation.unassigned.positions

    assert Decimal.equal?(
             Decimal.round(allocation.unassigned.actual_weight, 4),
             Decimal.new("0.2")
           )
  end

  test "rolls subcategory values up into their parent and tags depth" do
    world = setup_world()
    %{classification: classification, core: growth} = world

    # Growth (target 50%) is a parent with two children; nothing is assigned to
    # Growth directly, only to its children — its IST must be their sum, not 0%.
    {:ok, tech} =
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Tech",
        parent_id: growth.id
      })

    {:ok, emerging} =
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Emerging",
        parent_id: growth.id
      })

    tech_security = equity!("Tech Co.", "TECH")
    emerging_security = equity!("Emerging Co.", "EMRG")

    {:ok, _} = Classifications.assign_security(tech_security.id, classification.id, tech.id)

    {:ok, _} =
      Classifications.assign_security(emerging_security.id, classification.id, emerging.id)

    # Fund the cash account so the buys leave it at zero (basis = securities).
    deposit!(world, "1000", ~D[2026-01-01])

    buy!(world, tech_security, "10", "60")
    buy!(world, emerging_security, "10", "40")

    {:ok, _} =
      Targets.set_targets(world.portfolio.id, classification.id, [
        %{"category_id" => growth.id, "target_weight" => "0.5"}
      ])

    prices = %{
      tech_security.id => Decimal.new("60"),
      emerging_security.id => Decimal.new("40")
    }

    {:ok, allocation} =
      Allocation.for_portfolio(world.portfolio.id, classification.id, prices: prices)

    # Total: 600 + 400 = 1000.
    assert Decimal.equal?(allocation.total_value, Decimal.new("1000"))

    growth_row = fetch_category(allocation, growth.id)
    # Rolled-up: 600 + 400 = 1000 -> 100% IST, even though nothing is assigned
    # to Growth directly (own value 0).
    assert growth_row.depth == 0
    assert Decimal.equal?(growth_row.own_market_value, Decimal.new("0"))
    assert Decimal.equal?(growth_row.market_value, Decimal.new("1000"))
    assert Decimal.equal?(growth_row.actual_weight, Decimal.new("1"))
    assert Decimal.equal?(growth_row.target_weight, Decimal.new("0.5"))
    # Over target by 0.5 -> sell 500 EUR to reach it.
    assert Decimal.equal?(Decimal.round(growth_row.drift_value, 2), Decimal.new("-500"))

    tech_row = fetch_category(allocation, tech.id)
    assert tech_row.depth == 1
    assert tech_row.parent_id == growth.id
    assert Decimal.equal?(tech_row.own_market_value, Decimal.new("600"))
    assert Decimal.equal?(tech_row.market_value, Decimal.new("600"))
    assert Decimal.equal?(tech_row.actual_weight, Decimal.new("0.6"))

    # The per-position breakdown behind a category's own value (sunburst ring).
    assert [tech_position] = tech_row.positions
    assert tech_position.security_name == "Tech Co."
    assert Decimal.equal?(tech_position.market_value, Decimal.new("600"))
    assert Decimal.equal?(tech_position.weight, Decimal.new("0.6"))
    assert fetch_category(allocation, growth.id).positions == []

    # Tree order: the parent comes before its children.
    ids = Enum.map(allocation.categories, & &1.category_id)

    assert Enum.find_index(ids, &(&1 == growth.id)) <
             Enum.find_index(ids, &(&1 == tech.id))
  end

  # User story:
  # As a local portfolio maintainer setting targets at several levels,
  # I want the breakdown to carry advisory consistency figures (sum of a
  # parent's child targets, and the sum of the top-level targets),
  # so that the UI can hint at divergence without enforcing it.
  #
  # Acceptance criteria:
  # - Each row exposes `child_target_sum`: the sum of its direct children's
  #   targets, or nil when no direct child carries a target.
  # - The breakdown exposes `top_level_target_sum`: the sum of the root
  #   categories' targets (zero when none have a target).
  test "exposes advisory child and top-level target sums" do
    world = setup_world()
    %{classification: classification, core: core, satellite: satellite} = world

    {:ok, tech} =
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Tech",
        parent_id: core.id
      })

    {:ok, emerging} =
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Emerging",
        parent_id: core.id
      })

    {:ok, _} =
      Targets.set_targets(world.portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"},
        %{"category_id" => satellite.id, "target_weight" => "0.3"},
        %{"category_id" => tech.id, "target_weight" => "0.3"},
        %{"category_id" => emerging.id, "target_weight" => "0.2"}
      ])

    {:ok, allocation} =
      Allocation.for_portfolio(world.portfolio.id, classification.id, prices: %{})

    core_row = fetch_category(allocation, core.id)
    # Children 0.3 + 0.2 = 0.5 (≠ Core's own 0.6 → the UI flags this).
    assert Decimal.equal?(core_row.child_target_sum, Decimal.new("0.5"))

    # Satellite has no children with targets, so no comparison is offered.
    assert fetch_category(allocation, satellite.id).child_target_sum == nil

    # Top-level sum is Core 0.6 + Satellite 0.3 = 0.9 (≠ 1 → header flags it).
    assert Decimal.equal?(allocation.top_level_target_sum, Decimal.new("0.9"))
  end

  test "returns a zero top-level target sum when no root carries a target" do
    world = setup_world()

    {:ok, allocation} =
      Allocation.for_portfolio(world.portfolio.id, world.classification.id, prices: %{})

    assert Decimal.equal?(allocation.top_level_target_sum, Decimal.new("0"))
  end

  # User story:
  # As a local portfolio maintainer who steers a cash quote (e.g. ~5%),
  # I want cash tracked inside the same SOLL/IST drift logic as my categories,
  # so that the allocation's 100% basis is securities + counting cash, a "Cash"
  # row reports its actual/target/drift, and the category percentages shrink once
  # cash joins the basis.
  #
  # Acceptance criteria:
  # - The 100% basis = securities (minus excluded) + counting cash.
  # - A `cash` row reports actual (counting cash share), target (the portfolio's
  #   cash_target_weight) and drift (target - actual), restated in base currency.
  # - Category percentages are shares of the larger basis (they shrink vs. a
  #   securities-only basis).
  # - The Σ header (top_level_target_sum) includes the cash target.
  test "treats counting cash as part of the allocation basis with its own row" do
    world = setup_world()
    %{classification: classification, core: core, satellite: satellite} = world

    core_security = equity!("Core Equity", "CORE")
    satellite_security = equity!("Satellite Equity", "SAT")

    {:ok, _} = Classifications.assign_security(core_security.id, classification.id, core.id)

    {:ok, _} =
      Classifications.assign_security(satellite_security.id, classification.id, satellite.id)

    # Securities worth 600 + 320 = 920; deposit 1000 then spend 920 on the buys
    # leaves 80 cash -> 100% basis = securities 920 + cash 80 = 1000.
    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, core_security, "10", "60")
    buy!(world, satellite_security, "8", "40")

    {:ok, _} =
      Targets.set_targets(world.portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"},
        %{"category_id" => satellite.id, "target_weight" => "0.35"}
      ])

    {:ok, _} = Portfolios.set_cash_target(world.portfolio, Decimal.new("0.05"))

    prices = %{
      core_security.id => Decimal.new("60"),
      satellite_security.id => Decimal.new("40")
    }

    {:ok, allocation} =
      Allocation.for_portfolio(world.portfolio.id, classification.id, prices: prices)

    # The 100% basis is securities (920) + counting cash (80) = 1000.
    assert Decimal.equal?(allocation.total_value, Decimal.new("1000"))

    # The cash row: actual 80/1000 = 0.08 (8%), target 0.05 (5%); drift
    # target - actual = -0.03 (cash is 3 pp over target), restated as -30 EUR
    # (i.e. reduce cash by 30 to hit the 5% target).
    assert Decimal.equal?(allocation.cash.market_value, Decimal.new("80"))
    assert Decimal.equal?(allocation.cash.actual_weight, Decimal.new("0.08"))
    assert Decimal.equal?(allocation.cash.target_weight, Decimal.new("0.05"))
    assert Decimal.equal?(allocation.cash.drift_weight, Decimal.new("-0.03"))
    assert Decimal.equal?(Decimal.round(allocation.cash.drift_value, 2), Decimal.new("-30"))

    # Category percentages shrink once cash joins the basis: Core is 600/1000 =
    # 0.60, NOT 600/920 = 0.6522 (the securities-only basis).
    core_row = fetch_category(allocation, core.id)
    assert Decimal.equal?(core_row.market_value, Decimal.new("600"))
    assert Decimal.equal?(core_row.actual_weight, Decimal.new("0.6"))
    refute Decimal.equal?(Decimal.round(core_row.actual_weight, 4), Decimal.new("0.6522"))

    satellite_row = fetch_category(allocation, satellite.id)
    assert Decimal.equal?(satellite_row.market_value, Decimal.new("320"))
    assert Decimal.equal?(satellite_row.actual_weight, Decimal.new("0.32"))

    # The Σ header includes the cash target: 0.6 + 0.35 + 0.05 = 1.0.
    assert Decimal.equal?(allocation.top_level_target_sum, Decimal.new("1.0"))
  end

  test "cash row uses a zero target when no cash target is set" do
    world = setup_world()

    deposit!(world, "100", ~D[2026-01-01])

    {:ok, allocation} =
      Allocation.for_portfolio(world.portfolio.id, world.classification.id, prices: %{})

    # 100% basis is just the cash (no securities): cash actual is the whole basis.
    assert Decimal.equal?(allocation.cash.market_value, Decimal.new("100"))
    assert Decimal.equal?(allocation.cash.actual_weight, Decimal.new("1"))
    assert Decimal.equal?(allocation.cash.target_weight, Decimal.new("0"))
  end

  test "returns not_found for an unknown classification" do
    world = setup_world()
    assert {:error, :not_found} = Allocation.for_portfolio(world.portfolio.id, 999_999)
  end

  # An unknown portfolio still resolves the (existing) classification, so the
  # cash target lookup falls back to nil rather than raising: there is no stored
  # cash_target_weight to steer when the portfolio does not exist (issue #335).
  test "falls back to a nil cash target for an unknown portfolio id" do
    world = setup_world()

    {:ok, allocation} =
      Allocation.for_portfolio(999_999, world.classification.id, prices: %{})

    # No portfolio, no positions, no cash: the basis is zero and the cash row's
    # target defaults to zero (the nil cash target maps to a 0 weight).
    assert Decimal.equal?(allocation.total_value, Decimal.new("0"))
    assert Decimal.equal?(allocation.cash.target_weight, Decimal.new("0"))
  end

  # User story:
  # As a local portfolio maintainer who steers currency exposure,
  # I want cash attributed to its account's currency bucket in the Currency
  # classification view (EUR cash → EUR, USD cash → USD),
  # so that the drift table and sunburst reflect my true currency exposure
  # including cash — not a separate, currency-less "Cash" lump (issue #407).
  #
  # Acceptance criteria:
  # - In the Currency classification, each cash account's balance is attributed
  #   to its own currency_code bucket (grouped with securities of that currency).
  # - No separate currency-less cash row appears in the Currency view.
  # - The total_value/basis is unchanged: counting cash still enters the 100%.
  # - The asset-class classification keeps cash as its own separate row (#335).
  # - Multi-currency: foreign cash converted to EUR via the hub for the basis.
  describe "currency classification cash attribution (issue #407)" do
    defp setup_currency_world do
      # EUR portfolio with one EUR and one USD cash account plus a EUR depot.
      world = base_world(name: "Currency Portfolio", currency: "EUR")

      {:ok, usd_cash} =
        Portfolios.create_cash_account(%{
          portfolio_id: world.portfolio.id,
          name: "USD Cash",
          currency_code: "USD"
        })

      # Seed the EUR/USD rate so USD cash can be converted (ADR-0007).
      {:ok, _} =
        Portfolixir.Fx.upsert_many([
          %{
            base_currency: "EUR",
            quote_currency: "USD",
            rate: "1.1",
            date: Date.utc_today(),
            source: "manual"
          }
        ])

      Map.put(world, :usd_cash, usd_cash)
    end

    test "EUR cash is attributed to the EUR currency bucket" do
      world = setup_currency_world()
      Classifications.ensure_builtins()
      currency_cl = Classifications.get_classification_by_key("currency")

      # Deposit 100 EUR into the EUR cash account.
      deposit!(world, "100", ~D[2026-01-01])

      {:ok, allocation} =
        Allocation.for_portfolio(world.portfolio.id, currency_cl.id, prices: %{})

      # Basis: no securities, 100 EUR counting cash.
      assert Decimal.equal?(allocation.total_value, Decimal.new("100"))

      # Cash is attributed to currency category, not a separate row.
      assert allocation.cash.distributed == true

      eur_row = Enum.find(allocation.categories, &(&1.name =~ "EUR"))
      assert eur_row != nil
      # EUR cash value (100) attributed to the EUR currency bucket.
      assert Decimal.equal?(eur_row.market_value, Decimal.new("100"))
      assert Decimal.equal?(eur_row.actual_weight, Decimal.new("1"))
    end

    test "USD cash is attributed to the USD currency bucket using base_value" do
      world = setup_currency_world()
      Classifications.ensure_builtins()
      currency_cl = Classifications.get_classification_by_key("currency")

      # Set USD cash balance to 110 USD = 100 EUR at 1 EUR = 1.1 USD.
      {:ok, _} =
        Portfolixir.Ledger.set_cash_balance(
          world.usd_cash,
          %{date: ~D[2026-01-01], amount: "110"}
        )

      {:ok, allocation} =
        Allocation.for_portfolio(world.portfolio.id, currency_cl.id, prices: %{})

      # Basis: 110 USD counting cash = 100 EUR base value.
      assert Decimal.equal?(allocation.total_value, Decimal.new("100"))

      usd_row = Enum.find(allocation.categories, &(&1.name =~ "USD"))
      assert usd_row != nil
      # USD cash at 100 EUR base value attributed to USD bucket.
      assert Decimal.equal?(usd_row.market_value, Decimal.new("100"))
    end

    test "EUR security + EUR cash: both appear in EUR bucket; total unchanged" do
      world = setup_currency_world()
      Classifications.ensure_builtins()
      currency_cl = Classifications.get_classification_by_key("currency")

      eur_security = create_security!(name: "EUR Bond", ticker: "EURBND", currency: "EUR")

      # Deposit 200, buy security for 100, leaving 100 EUR cash.
      deposit!(world, "200", ~D[2026-01-01])
      buy!(world, eur_security, quantity: "2", price: "50")

      prices = %{eur_security.id => Decimal.new("50")}

      {:ok, allocation} =
        Allocation.for_portfolio(world.portfolio.id, currency_cl.id, prices: prices)

      # Basis: securities 100 + counting cash 100 = 200.
      assert Decimal.equal?(allocation.total_value, Decimal.new("200"))

      eur_row = Enum.find(allocation.categories, &(&1.name =~ "EUR"))
      # EUR security 100 + EUR cash 100 = 200 in the EUR bucket.
      assert Decimal.equal?(eur_row.market_value, Decimal.new("200"))
      assert Decimal.equal?(eur_row.actual_weight, Decimal.new("1"))
    end

    test "EUR security + USD cash: separate buckets; total unchanged" do
      world = setup_currency_world()
      Classifications.ensure_builtins()
      currency_cl = Classifications.get_classification_by_key("currency")

      eur_security = create_security!(name: "EUR Stock", ticker: "EURST", currency: "EUR")

      # Buy EUR security for 100.
      deposit!(world, "100", ~D[2026-01-01])
      buy!(world, eur_security, quantity: "2", price: "50")

      # USD cash: 110 USD = 100 EUR at 1.1.
      {:ok, _} =
        Portfolixir.Ledger.set_cash_balance(
          world.usd_cash,
          %{date: ~D[2026-01-01], amount: "110"}
        )

      prices = %{eur_security.id => Decimal.new("50")}

      {:ok, allocation} =
        Allocation.for_portfolio(world.portfolio.id, currency_cl.id, prices: prices)

      # Basis: EUR security 100 + USD counting cash 100 EUR = 200.
      assert Decimal.equal?(allocation.total_value, Decimal.new("200"))

      eur_row = Enum.find(allocation.categories, &(&1.name =~ "EUR"))
      usd_row = Enum.find(allocation.categories, &(&1.name =~ "USD"))

      # EUR bucket: security only (100).
      assert Decimal.equal?(eur_row.market_value, Decimal.new("100"))
      # USD bucket: USD cash only (100 EUR base value).
      assert Decimal.equal?(usd_row.market_value, Decimal.new("100"))

      # No separate cash row.
      assert allocation.cash.distributed == true
    end

    test "asset-class classification keeps cash as its own separate row" do
      world = setup_currency_world()
      Classifications.ensure_builtins()
      asset_cl = Classifications.get_classification_by_key("asset_class")

      deposit!(world, "100", ~D[2026-01-01])

      {:ok, allocation} =
        Allocation.for_portfolio(world.portfolio.id, asset_cl.id, prices: %{})

      # Asset-class view: the separate cash row is present and not distributed.
      refute Map.get(allocation.cash, :distributed, false)
      assert Decimal.equal?(allocation.cash.market_value, Decimal.new("100"))
    end

    test "total_value basis is the same regardless of currency classification" do
      # This pins the invariant: switching from a custom classification to the
      # built-in currency classification must not change the total_value (basis).
      world = setup_currency_world()
      Classifications.ensure_builtins()
      currency_cl = Classifications.get_classification_by_key("currency")

      {:ok, custom_cl} = Classifications.create_classification(%{name: "Custom"})

      eur_security = create_security!(name: "EUR Fund", ticker: "EURFD", currency: "EUR")

      deposit!(world, "200", ~D[2026-01-01])
      buy!(world, eur_security, quantity: "2", price: "50")

      prices = %{eur_security.id => Decimal.new("50")}

      {:ok, custom_alloc} =
        Allocation.for_portfolio(world.portfolio.id, custom_cl.id, prices: prices)

      {:ok, currency_alloc} =
        Allocation.for_portfolio(world.portfolio.id, currency_cl.id, prices: prices)

      # Both views report the same total basis: security 100 + cash 100 = 200.
      assert Decimal.equal?(custom_alloc.total_value, currency_alloc.total_value)
      assert Decimal.equal?(currency_alloc.total_value, Decimal.new("200"))
    end
  end
end
