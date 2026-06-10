defmodule Portfolixir.Portfolios.AllocationTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
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
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Local Portfolio", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Local Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Main Depot"
      })

    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    {:ok, satellite} =
      Classifications.create_category(%{classification_id: classification.id, name: "Satellite"})

    {:ok, defensive} =
      Classifications.create_category(%{classification_id: classification.id, name: "Defensive"})

    %{
      portfolio: portfolio,
      cash: cash,
      depot: depot,
      classification: classification,
      core: core,
      satellite: satellite,
      defensive: defensive
    }
  end

  defp create_security!(name, ticker) do
    {:ok, security} =
      Catalog.create_security(%{
        name: name,
        ticker_symbol: ticker,
        currency_code: "EUR",
        asset_class: "equity"
      })

    security
  end

  defp buy!(%{portfolio: p, depot: d, cash: c}, security, qty, price) do
    {:ok, _tx} =
      Ledger.create_transaction(%{
        portfolio_id: p.id,
        securities_account_id: d.id,
        cash_account_id: c.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: qty,
        price: price,
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })
  end

  defp fetch_category(allocation, category_id) do
    Enum.find(allocation.categories, &(&1.category_id == category_id))
  end

  test "breaks the valuation down by category and reports drift against targets" do
    world = setup_world()

    %{classification: classification, core: core, satellite: satellite, defensive: defensive} =
      world

    core_security = create_security!("Core Equity", "CORE")
    satellite_security = create_security!("Satellite Equity", "SAT")
    unassigned_security = create_security!("Loose Equity", "LOOSE")

    {:ok, _} = Classifications.assign_security(core_security.id, classification.id, core.id)

    {:ok, _} =
      Classifications.assign_security(satellite_security.id, classification.id, satellite.id)

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

    # The loose security is summed into the unassigned bucket.
    assert Decimal.equal?(allocation.unassigned.market_value, Decimal.new("300"))

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

    tech_security = create_security!("Tech Co.", "TECH")
    emerging_security = create_security!("Emerging Co.", "EMRG")

    {:ok, _} = Classifications.assign_security(tech_security.id, classification.id, tech.id)

    {:ok, _} =
      Classifications.assign_security(emerging_security.id, classification.id, emerging.id)

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

    # Tree order: the parent comes before its children.
    ids = Enum.map(allocation.categories, & &1.category_id)

    assert Enum.find_index(ids, &(&1 == growth.id)) <
             Enum.find_index(ids, &(&1 == tech.id))
  end

  test "returns not_found for an unknown classification" do
    world = setup_world()
    assert {:error, :not_found} = Allocation.for_portfolio(world.portfolio.id, 999_999)
  end
end
