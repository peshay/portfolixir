defmodule Portfolixir.Portfolios.CategoryResultTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.CategoryResult

  defp world_with_tree do
    world = base_world()

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, satellite} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Satellite"
      })

    Map.merge(world, %{classification: classification, core: core, satellite: satellite})
  end

  defp assign!(security, classification, category) do
    {:ok, _} =
      Classifications.assign_security(
        Actor.owner_ui(),
        security.id,
        classification.id,
        category.id
      )
  end

  defp fetch(result, category_id),
    do: Enum.find(result.categories, &(&1.category_id == category_id))

  # User story (#712, ADR-0041 §§1-4):
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want each category in my tree to state what it cost me, what it is worth
  # now and what it has made,
  # so that "how is my Core doing?" is answered where the positions already sit
  # side by side, instead of by me adding up rows.
  #
  # Acceptance criteria:
  # - Per category: invested (Σ base-currency cost), current value, result in
  #   base currency, and result as a percentage of invested.
  # - The figure is a statement about the CURRENT COMPOSITION -- no period, no
  #   membership basis, no as-of. That one line is the whole computation basis
  #   (ADR-0041 §1), and it travels with the payload.
  # - The category expands to the member positions that produced it, each with
  #   its own contribution (§3): the aggregate and the expansion ship together.
  describe "money-weighted category roll-up (#712)" do
    test "rolls invested, value and result up from the members" do
      world = world_with_tree()

      alpha = create_security!(name: "Alpha AG", ticker: "ALP")
      beta = create_security!(name: "Beta AG", ticker: "BET")

      assign!(alpha, world.classification, world.core)
      assign!(beta, world.classification, world.core)

      deposit!(world, "10000", ~D[2026-01-01])
      # Invested 1000 and 500; now worth 1500 and 400.
      buy!(world, alpha, quantity: "10", price: "100")
      buy!(world, beta, quantity: "10", price: "50")

      prices = %{alpha.id => Decimal.new("150"), beta.id => Decimal.new("40")}

      {:ok, result} =
        CategoryResult.for_portfolio(world.portfolio.id, world.classification.id, prices: prices)

      core = fetch(result, world.core.id)

      assert Decimal.equal?(core.invested, Decimal.new("1500"))
      assert Decimal.equal?(core.current_value, Decimal.new("1900"))
      assert Decimal.equal?(core.result_abs, Decimal.new("400"))

      # 400 / 1500 = 0.2666... carried at full precision (ADR-0016: round only
      # at the human display, which this is not).
      assert Decimal.equal?(Decimal.round(core.result_pct, 6), Decimal.new("0.266667"))

      assert core.covered_count == 2
      assert core.member_count == 2
      assert core.excluded == []

      # §3: the aggregate resolves into the rows behind it.
      assert [alpha_row, beta_row] =
               Enum.sort_by(core.positions, & &1.security_name)

      assert alpha_row.security_name == "Alpha AG"
      assert Decimal.equal?(alpha_row.invested, Decimal.new("1000"))
      assert Decimal.equal?(alpha_row.result_abs, Decimal.new("500"))
      assert Decimal.equal?(alpha_row.result_pct, Decimal.new("0.5"))

      assert beta_row.security_name == "Beta AG"
      assert Decimal.equal?(beta_row.invested, Decimal.new("500"))
      assert Decimal.equal?(beta_row.result_abs, Decimal.new("-100"))
      assert Decimal.equal?(beta_row.result_pct, Decimal.new("-0.2"))

      # The contributions reconstruct the aggregate exactly.
      assert Decimal.equal?(
               Decimal.add(alpha_row.result_abs, beta_row.result_abs),
               core.result_abs
             )

      # §1: the basis is one line and it is on the payload.
      assert result.basis == "current_composition"
    end

    # THE risk-tier property (ADR-0041 §2, and the single most likely way to
    # ship a plausible wrong number here): the percentage is Σ result ÷ Σ
    # invested, NEVER the mean of the members' percentages.
    test "the percentage is money-weighted, not a mean of the members'" do
      world = world_with_tree()

      whale = create_security!(name: "Whale AG", ticker: "WHL")
      minnow = create_security!(name: "Minnow AG", ticker: "MIN")

      assign!(whale, world.classification, world.core)
      assign!(minnow, world.classification, world.core)

      deposit!(world, "20000", ~D[2026-01-01])
      # A big flat position and a tiny one at +300%.
      buy!(world, whale, quantity: "100", price: "100")
      buy!(world, minnow, quantity: "1", price: "10")

      prices = %{whale.id => Decimal.new("100"), minnow.id => Decimal.new("40")}

      {:ok, result} =
        CategoryResult.for_portfolio(world.portfolio.id, world.classification.id, prices: prices)

      core = fetch(result, world.core.id)

      # Invested 10_000 + 10 = 10_010; result 0 + 30 = 30.
      assert Decimal.equal?(core.invested, Decimal.new("10010"))
      assert Decimal.equal?(core.result_abs, Decimal.new("30"))

      # Money-weighted: 30 / 10010 = 0.0029970... -- the category is essentially
      # flat, which is the truth about the money.
      assert Decimal.equal?(Decimal.round(core.result_pct, 6), Decimal.new("0.002997"))

      # The mean of the members' percentages would be (0 + 3) / 2 = 1.5, i.e.
      # +150%, letting a 10 EUR position dominate a 10_000 EUR one. Assert the
      # defect is absent rather than merely assert the right number.
      refute Decimal.equal?(Decimal.round(core.result_pct, 6), Decimal.new("1.500000"))
      assert Decimal.compare(core.result_pct, Decimal.new("0.01")) == :lt
    end

    # ADR-0041 §4: a member whose result is not derivable is excluded from the
    # sums AND listed -- never counted as zero, which would quietly understate
    # the category.
    test "a member with no usable price is excluded from the sums and named" do
      world = world_with_tree()

      priced = create_security!(name: "Priced AG", ticker: "PRC")
      dark = create_security!(name: "Dark AG", ticker: "DRK")

      assign!(priced, world.classification, world.core)
      assign!(dark, world.classification, world.core)

      deposit!(world, "10000", ~D[2026-01-01])
      buy!(world, priced, quantity: "10", price: "100")
      buy!(world, dark, quantity: "10", price: "50")

      # Only the first security has a price; the second is unpriceable.
      prices = %{priced.id => Decimal.new("150")}

      {:ok, result} =
        CategoryResult.for_portfolio(world.portfolio.id, world.classification.id, prices: prices)

      core = fetch(result, world.core.id)

      # The dark position's 500 of cost is NOT in invested: an excluded row is
      # excluded from both sides, not folded in at a result of zero.
      assert Decimal.equal?(core.invested, Decimal.new("1000"))
      assert Decimal.equal?(core.result_abs, Decimal.new("500"))
      assert Decimal.equal?(core.result_pct, Decimal.new("0.5"))

      # ...and it is named, with the reason, so the gap has an address.
      assert core.covered_count == 1
      assert core.member_count == 2
      assert [excluded] = core.excluded
      assert excluded.security_name == "Dark AG"
      assert excluded.reason == :no_usable_price
    end

    test "a category with no members reports zeroes rather than nil" do
      world = world_with_tree()

      alpha = create_security!(name: "Alpha AG", ticker: "ALP")
      assign!(alpha, world.classification, world.core)

      deposit!(world, "10000", ~D[2026-01-01])
      buy!(world, alpha, quantity: "10", price: "100")

      {:ok, result} =
        CategoryResult.for_portfolio(world.portfolio.id, world.classification.id,
          prices: %{alpha.id => Decimal.new("100")}
        )

      satellite = fetch(result, world.satellite.id)

      assert Decimal.equal?(satellite.invested, Decimal.new("0"))
      assert Decimal.equal?(satellite.current_value, Decimal.new("0"))
      assert Decimal.equal?(satellite.result_abs, Decimal.new("0"))
      # No invested capital means no percentage to state -- not a zero
      # percentage, which would claim the category is flat.
      assert is_nil(satellite.result_pct)
      assert satellite.member_count == 0
      assert satellite.positions == []
    end
  end
end
