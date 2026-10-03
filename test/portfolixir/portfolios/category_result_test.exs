defmodule Portfolixir.Portfolios.CategoryResultTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [
      add_depot: 2,
      base_world: 0,
      base_world: 1,
      create_security!: 1,
      buy!: 3,
      deposit!: 3,
      deposit!: 4
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
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

  # A bucket, the depot it tags and a view that includes only it (#901).
  defp tagged_bucket! do
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Retirement"})
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Retired", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])
    {bucket, view}
  end

  defp tag!(%{depot: depot}, bucket),
    do: :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [bucket.id])

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

    # ADR-0041 §2, last paragraph: "Parent categories roll up from their members
    # the same way, so a level's result reconstructs from the level below it."
    # That is a stated property with money behind it, so it gets its own test
    # rather than riding on the flat case.
    test "a parent reconstructs from the level below it" do
      world = base_world()

      {:ok, classification} =
        Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

      {:ok, equities} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Equities"
        })

      {:ok, europe} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Europe",
          parent_id: equities.id
        })

      {:ok, usa} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "USA",
          parent_id: equities.id
        })

      eu = create_security!(name: "Euro AG", ticker: "EUA")
      us = create_security!(name: "States AG", ticker: "USA")

      assign!(eu, classification, europe)
      assign!(us, classification, usa)

      deposit!(%{world | portfolio: world.portfolio}, "10000", ~D[2026-01-01])
      buy!(%{world | portfolio: world.portfolio}, eu, quantity: "10", price: "100")
      buy!(%{world | portfolio: world.portfolio}, us, quantity: "10", price: "50")

      prices = %{eu.id => Decimal.new("120"), us.id => Decimal.new("40")}

      {:ok, result} =
        CategoryResult.for_portfolio(world.portfolio.id, classification.id, prices: prices)

      europe_row = fetch(result, europe.id)
      usa_row = fetch(result, usa.id)
      parent = fetch(result, equities.id)

      assert Decimal.equal?(europe_row.result_abs, Decimal.new("200"))
      assert Decimal.equal?(usa_row.result_abs, Decimal.new("-100"))

      # The parent is the sum of the level below it, on BOTH sides of the ratio.
      assert Decimal.equal?(parent.invested, Decimal.new("1500"))
      assert Decimal.equal?(parent.result_abs, Decimal.new("100"))

      assert Decimal.equal?(
               parent.invested,
               Decimal.add(europe_row.invested, usa_row.invested)
             )

      assert Decimal.equal?(
               parent.result_abs,
               Decimal.add(europe_row.result_abs, usa_row.result_abs)
             )

      # ...and the parent percentage is money-weighted over the whole subtree
      # (100 / 1500), NOT the mean of its children's +20% and -20%, which would
      # read as 0% and hide a real gain.
      assert Decimal.equal?(Decimal.round(parent.result_pct, 6), Decimal.new("0.066667"))
      assert parent.member_count == 2
    end

    test "a security filed in no category is left out of every row" do
      world = world_with_tree()

      filed = create_security!(name: "Filed AG", ticker: "FIL")
      loose = create_security!(name: "Loose AG", ticker: "LOO")

      assign!(filed, world.classification, world.core)

      deposit!(world, "10000", ~D[2026-01-01])
      buy!(world, filed, quantity: "10", price: "100")
      buy!(world, loose, quantity: "10", price: "100")

      prices = %{filed.id => Decimal.new("150"), loose.id => Decimal.new("150")}

      {:ok, result} =
        CategoryResult.for_portfolio(world.portfolio.id, world.classification.id, prices: prices)

      core = fetch(result, world.core.id)

      # Only the filed position; the unassigned one is not silently folded in.
      assert core.member_count == 1
      assert Decimal.equal?(core.invested, Decimal.new("1000"))
      assert [%{security_name: "Filed AG"}] = core.positions
    end

    # ADR-0033: a position whose base-currency decomposition is unavailable is
    # the OTHER exclusion path (§4), distinct from having no price at all.
    test "a member without a base-currency decomposition is excluded and named" do
      world = world_with_tree()

      foreign = create_security!(name: "Foreign AG", ticker: "FGN", currency: "USD")
      assign!(foreign, world.classification, world.core)

      deposit!(world, "10000", ~D[2026-01-01])
      buy!(world, foreign, quantity: "10", price: "100")

      # Priced, but with no rate to the base currency, so the base-currency
      # return is not derivable -- honestly unavailable rather than guessed.
      {:ok, result} =
        CategoryResult.for_portfolio(world.portfolio.id, world.classification.id,
          prices: %{foreign.id => Decimal.new("150")},
          fx_rates: %{}
        )

      core = fetch(result, world.core.id)

      assert core.covered_count == 0
      assert core.member_count == 1
      assert [excluded] = core.excluded
      assert excluded.security_name == "Foreign AG"
      assert excluded.reason != nil
      # Excluded from the sums, not counted as zero.
      assert Decimal.equal?(core.invested, Decimal.new("0"))
      assert is_nil(core.result_pct)
    end

    # The human surface this feeds (the classification tree) is global, not
    # portfolio-scoped: ADR-0024 demoted portfolios as a user-facing grouping,
    # so the view a person reads spans them. Per-portfolio cost lots are built
    # from that portfolio's own transactions, so the sums add up across
    # portfolios without double-counting.
    test "rolls up across every portfolio for the global view" do
      first = world_with_tree()

      second = base_world(name: "Second", cash_name: "Second Cash", depot_name: "Second Depot")

      alpha = create_security!(name: "Alpha AG", ticker: "ALP")
      assign!(alpha, first.classification, first.core)

      deposit!(first, "10000", ~D[2026-01-01])
      buy!(first, alpha, quantity: "10", price: "100")

      deposit!(second, "10000", ~D[2026-01-01])
      buy!(second, alpha, quantity: "5", price: "200")

      prices = %{alpha.id => Decimal.new("150")}

      {:ok, result} =
        CategoryResult.for_all_portfolios(first.classification.id, prices: prices)

      core = fetch(result, first.core.id)

      # 1000 in the first portfolio + 1000 in the second.
      assert Decimal.equal?(core.invested, Decimal.new("2000"))
      # 15 units at 150 = 2250.
      assert Decimal.equal?(core.current_value, Decimal.new("2250"))
      assert Decimal.equal?(core.result_abs, Decimal.new("250"))

      # One security, so one member row even though it is held twice.
      assert core.member_count == 1
      assert [row] = core.positions
      assert Decimal.equal?(row.quantity, Decimal.new("15"))
    end

    test "an unknown classification is a not-found rather than a crash" do
      world = base_world()
      assert {:error, :not_found} = CategoryResult.for_portfolio(world.portfolio.id, 9_999_999)
    end

    test "states the scope it was computed over" do
      world = world_with_tree()

      {:ok, result} = CategoryResult.for_portfolio(world.portfolio.id, world.classification.id)

      assert result.scope == :portfolio
      assert result.view_id == nil
      assert result.base_currency == "EUR"
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

  # User story (#901; ADR-0041 §1, ADR-0051 §6):
  # As the operator's agent reading the category result,
  # I want it at the scopes the performance family reads — one portfolio,
  # narrowed by a view, or a view across every portfolio —
  # so that "how is Core doing in my retirement view?" is one read, not a
  # join of holdings to buckets I would do myself.
  #
  # Acceptance criteria:
  # - for_portfolio/3 with `view:` rolls up only that portfolio's positions
  #   matching the view; without it the result is unchanged.
  # - for_view/3 rolls up the positions matching the view across every
  #   portfolio, each account once, in EUR: a member whose cost was not paid
  #   in EUR is excluded and named (missing_base_cost), never summed across
  #   currencies.
  # - The result states its scope, its view and its base currency; an
  #   unknown view is {:error, :view_not_found}.
  describe "the view scope (#901)" do
    test "narrows one portfolio to the positions matching a view" do
      world = world_with_tree()

      %{depot: other_depot, cash: other_cash} =
        add_depot(world.portfolio, depot_name: "Other", cash_name: "Other Cash")

      other = %{world | depot: other_depot, cash: other_cash}
      {bucket, view} = tagged_bucket!()
      tag!(world, bucket)

      alpha = create_security!(name: "Alpha AG", ticker: "ALP")
      beta = create_security!(name: "Beta AG", ticker: "BET")
      assign!(alpha, world.classification, world.core)
      assign!(beta, world.classification, world.core)

      deposit!(world, "10000", ~D[2026-01-01])
      deposit!(other, "10000", ~D[2026-01-01])
      buy!(world, alpha, quantity: "10", price: "100")
      buy!(other, beta, quantity: "10", price: "50")

      prices = %{alpha.id => Decimal.new("150"), beta.id => Decimal.new("40")}

      {:ok, scoped} =
        CategoryResult.for_portfolio(world.portfolio.id, world.classification.id,
          view: view.id,
          prices: prices
        )

      core = fetch(scoped, world.core.id)

      # Only the tagged depot's Alpha: 10 at 100, now 10 at 150.
      assert Decimal.equal?(core.invested, Decimal.new("1000"))
      assert Decimal.equal?(core.current_value, Decimal.new("1500"))
      assert Decimal.equal?(core.result_abs, Decimal.new("500"))
      assert core.member_count == 1
      assert [%{security_name: "Alpha AG"}] = core.positions

      assert scoped.scope == :portfolio
      assert scoped.portfolio_id == world.portfolio.id
      assert scoped.view_id == view.id
      assert scoped.base_currency == "EUR"

      # Without the view nothing is narrowed: 1000 + 500 invested.
      {:ok, unscoped} =
        CategoryResult.for_portfolio(world.portfolio.id, world.classification.id, prices: prices)

      assert Decimal.equal?(fetch(unscoped, world.core.id).invested, Decimal.new("1500"))
      assert unscoped.view_id == nil
    end

    test "rolls a view up across every portfolio, each account once, in EUR" do
      first = world_with_tree()
      second = base_world(name: "Second", cash_name: "Second Cash", depot_name: "Second Depot")

      outside =
        base_world(name: "Outside", cash_name: "Outside Cash", depot_name: "Outside Depot")

      dollar =
        base_world(
          name: "Dollar",
          currency: "USD",
          cash_name: "Dollar Cash",
          depot_name: "Dollar Depot"
        )

      {bucket, view} = tagged_bucket!()
      for world <- [first, second, dollar], do: tag!(world, bucket)

      alpha = create_security!(name: "Alpha AG", ticker: "ALP")
      yankee = create_security!(name: "Yankee Inc", ticker: "YNK", currency: "USD")
      assign!(alpha, first.classification, first.core)
      assign!(yankee, first.classification, first.core)

      for world <- [first, second, outside], do: deposit!(world, "10000", ~D[2026-01-01])
      deposit!(dollar, "10000", ~D[2026-01-01], currency: "USD")

      buy!(first, alpha, quantity: "10", price: "100")
      buy!(second, alpha, quantity: "5", price: "200")
      # Outside the view: never counted.
      buy!(outside, alpha, quantity: "100", price: "1")
      # Paid in USD: the view's figures are in EUR, so this cost has no EUR
      # amount to add.
      buy!(dollar, yankee, quantity: "3", price: "10", currency: "USD")

      prices = %{alpha.id => Decimal.new("150"), yankee.id => Decimal.new("12")}

      {:ok, result} = CategoryResult.for_view(view.id, first.classification.id, prices: prices)

      core = fetch(result, first.core.id)

      # 1000 in the first portfolio + 1000 in the second; 15 units at 150.
      assert Decimal.equal?(core.invested, Decimal.new("2000"))
      assert Decimal.equal?(core.current_value, Decimal.new("2250"))
      assert Decimal.equal?(core.result_abs, Decimal.new("250"))
      assert Decimal.equal?(core.result_pct, Decimal.new("0.125"))

      assert core.covered_count == 1
      assert core.member_count == 2
      assert [%{security_name: "Alpha AG", quantity: quantity}] = core.positions
      assert Decimal.equal?(quantity, Decimal.new("15"))

      assert [%{security_name: "Yankee Inc", reason: :missing_base_cost}] = core.excluded

      assert result.scope == :view
      assert result.portfolio_id == nil
      assert result.view_id == view.id
      assert result.base_currency == "EUR"
      assert result.basis == "current_composition"
    end

    test "an unknown view is a not-found rather than a crash" do
      world = world_with_tree()

      assert {:error, :view_not_found} =
               CategoryResult.for_portfolio(world.portfolio.id, world.classification.id,
                 view: 9_999_999
               )

      assert {:error, :view_not_found} =
               CategoryResult.for_view(9_999_999, world.classification.id)

      {_bucket, view} = tagged_bucket!()
      assert {:error, :not_found} = CategoryResult.for_view(view.id, 9_999_999)
    end
  end
end
