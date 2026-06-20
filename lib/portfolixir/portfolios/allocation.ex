defmodule Portfolixir.Portfolios.Allocation do
  @moduledoc """
  Read-time SOLL/IST allocation breakdown for one portfolio and classification.

  Groups the live valuation's valued positions into the chosen classification's
  categories (the IST side), joins each category's stored target weight (the SOLL
  side, see `Portfolixir.Portfolios.Targets`), and reports the drift between
  them — all in one call, so the weekly check does not need to join holdings,
  classifications, and targets by hand.

  Categories form a **tree** (`parent_id`). A position assigned to a child
  counts toward that child **and every ancestor**: a parent's IST is the
  rolled-up value of its whole subtree, so a strategy node like *Growth* with a
  50% target is compared against the sum of its sub-categories rather than
  showing 0%. Each row therefore carries both `own_market_value` (positions
  assigned directly to it) and `market_value` (the rolled-up subtree total);
  `actual_weight` uses the rolled-up value. Rows come back in tree order
  (parent before its children) with a `depth`, so the table can indent.

  Weights are shares of the **steering basis**: the (possibly view-scoped) valued
  positions' total market value *plus* the deployable cash (`free_cash` accounts
  with a non-negative balance, FR6; ADR-0009). To keep a holding out of the
  steering basis while it still counts toward total wealth, tag it with a bucket
  and exclude that bucket from the active view (ADR-0018): the position then falls
  outside the view's scope and never enters this 100%. (This replaces the retired
  per-security `excluded_from_allocation_targets` flag / ADR-0013.) Cash is
  **part** of the basis: a
  maintainer who steers a cash quote (e.g. ~5%) gets a dedicated `cash` row
  (actual share, target from the portfolio's `cash_target_weight`, drift) in the
  same drift logic, and every category percentage shrinks accordingly once cash
  joins the 100% (issue #335). Drift is
  `target_weight - actual_weight` per category; `drift_value` restates that drift
  as an amount in the base currency, i.e. how much to buy (positive) or sell
  (negative) to reach the target. Because parents aggregate their children,
  the displayed IST percentages intentionally do not sum to 100% across levels
  — only the leaves (plus unassigned) do.

  ## Currency classification: cash by currency (issue #407)

  When the active classification is the built-in **currency** tree, each cash
  account's deployable balance is attributed to its own `currency_code` bucket
  instead of appearing as a separate currency-less "Cash" row. EUR cash flows
  into the EUR category, USD cash into USD, and so on; foreign-currency balances
  are converted to the base currency via the EUR hub before being added (same
  `base_value` the valuation already computes). This gives a complete picture of
  currency exposure — securities and cash together — without changing the steering
  basis or totals. The `cash` field in the result carries `distributed: true` so
  the UI knows not to render a separate Cash row for this view. All other
  classifications (asset-class, custom) are unaffected: they keep the separate
  Cash row as before.

  ## Target consistency (advisory)

  Targets can be set freely at any level, so the SOLL side is not forced to be
  internally consistent. To make divergence visible without enforcing it, the
  breakdown carries two derived, display-only figures:

  - Each row exposes `child_target_sum`: the sum of the **direct** children's
    target weights, or `nil` when no direct child carries a target. The UI
    compares it against the row's own `target_weight`.
  - The breakdown exposes `top_level_target_sum`: the sum of the **root**
    categories' target weights **plus the cash target**, compared by the UI
    against `100%` (`1`) — so the Σ check reflects categories + cash vs 100%.

  Both are pure read-time hints; nothing here blocks saving targets, and the
  comparison the UI draws uses exact `Decimal.equal?/2`.
  """

  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation

  @zero Decimal.new("0")

  @doc """
  Builds the allocation breakdown for `portfolio_id` against `classification_id`.

  Options are passed through to `Valuation.for_portfolio/2` (e.g. `:prices`,
  `:base_currency`) for testing. Returns `{:ok, breakdown}` or
  `{:error, :not_found}` when the classification does not exist.
  """
  def for_portfolio(portfolio_id, classification_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(classification_id) do
    case Classifications.security_category_map(classification_id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, security_categories} ->
        classification = Classifications.get_classification(classification_id)
        categories = Classifications.list_categories(classification_id)
        valuation = Valuation.for_portfolio(portfolio_id, opts)
        cash_target = cash_target_for(portfolio_id)

        targets =
          portfolio_id
          |> Targets.list_targets(classification_id: classification_id)
          |> Map.new(&{&1.category_id, &1.target_weight})

        {:ok,
         build(
           valuation,
           classification,
           categories,
           security_categories,
           targets,
           cash_target
         )}
    end
  end

  # The portfolio's stored cash target weight (the SOLL cash share), or nil when
  # the maintainer does not steer a cash quote (issue #335).
  defp cash_target_for(portfolio_id) do
    case Portfolios.get_portfolio(portfolio_id) do
      %{cash_target_weight: weight} -> weight
      _ -> nil
    end
  end

  defp build(
         valuation,
         classification,
         categories,
         security_categories,
         targets,
         cash_target
       ) do
    steering_positions = Enum.filter(valuation.positions, & &1.valued)

    # The steering basis (the 100%) is the (possibly view-scoped) valued
    # securities PLUS the deployable cash (`free_cash` accounts with a
    # non-negative balance, FR6; ADR-0009). Cash is part of the target mix: a
    # maintainer who steers ~5% cash wants it tracked in the same drift logic, so
    # its weight enters the same 100% as the categories (issue #335). Category
    # percentages, target/actual/drift, the Σ header and the sunburst are all
    # shares of this basis. To keep a holding out of the basis while it still
    # counts toward total wealth, exclude its bucket from the active view
    # (ADR-0018), which removes it from the valuation's scoped positions.
    securities_value = valuation.total_value
    counting_cash = valuation.counting_cash
    total = Decimal.add(securities_value, counting_cash)

    {positions_by_category, unassigned_positions} =
      group_positions(steering_positions, security_categories)

    own_value_by_category =
      positions_by_category
      |> Map.new(fn {category_id, positions} ->
        {category_id, sum_values(positions)}
      end)
      |> merge_currency_cash(classification, categories, valuation.cash_balances)

    children_by_parent = Enum.group_by(categories, & &1.parent_id)
    rolled = rolled_values(categories, children_by_parent, own_value_by_category)
    kept = kept_categories(categories, rolled, targets)
    child_target_sums = child_target_sums(children_by_parent, targets)

    rows =
      children_by_parent
      |> preorder()
      |> Enum.filter(fn {category, _depth} -> MapSet.member?(kept, category.id) end)
      |> Enum.map(fn {category, depth} ->
        row(
          category,
          depth,
          Map.get(own_value_by_category, category.id, @zero),
          Map.get(rolled, category.id, @zero),
          Map.get(targets, category.id),
          Map.get(child_target_sums, category.id),
          position_entries(Map.get(positions_by_category, category.id, []), total),
          total
        )
      end)

    distribute_cash? = classification.key == "currency"

    %{
      portfolio_id: valuation.portfolio_id,
      classification_id: classification.id,
      classification_name: classification.name,
      base_currency: valuation.base_currency,
      total_value: total,
      unvalued_count: valuation.unvalued_count,
      categories: rows,
      cash: cash_row(counting_cash, cash_target, total, distribute_cash?),
      top_level_target_sum:
        top_level_target_sum_for(children_by_parent, targets, cash_target, distribute_cash?),
      unassigned: unassigned(unassigned_positions, total)
    }
  end

  # When cash is distributed into currency buckets (issue #407), the cash target
  # is not added to the top-level sum — cash is already inside the categories.
  # For all other classifications, the cash target is added as before (#335).
  defp top_level_target_sum_for(children_by_parent, targets, _cash_target, true) do
    top_level_target_sum(children_by_parent, targets)
  end

  defp top_level_target_sum_for(children_by_parent, targets, cash_target, false) do
    Decimal.add(top_level_target_sum(children_by_parent, targets), cash_target || @zero)
  end

  # For the built-in currency classification, cash accounts' deployable balances
  # are attributed to their currency's category (EUR cash → EUR bucket, USD → USD,
  # etc.) rather than appearing as a separate row. The base_value (already
  # converted to the portfolio base currency by Valuation.cash_for/2 via the EUR
  # hub) is added directly, so multi-currency cash is correctly represented in the
  # base-currency basis without a second FX call here. Issue #407; only the
  # currency classification is affected — all other classifications are unchanged.
  defp merge_currency_cash(own_value_by_category, %{key: "currency"}, categories, balances) do
    category_by_key = Map.new(categories, &{&1.key, &1.id})

    Enum.reduce(balances, own_value_by_category, fn entry, acc ->
      with true <- entry.deployable,
           true <- entry.valued,
           %Decimal{} = base_value <- entry.base_value,
           {:ok, category_id} <- Map.fetch(category_by_key, entry.currency) do
        Map.update(acc, category_id, base_value, &Decimal.add(&1, base_value))
      else
        _ -> acc
      end
    end)
  end

  defp merge_currency_cash(own_value_by_category, _classification, _categories, _balances) do
    own_value_by_category
  end

  # The cash row sits in the same drift logic as the categories: its actual
  # weight is the counting cash as a share of the steering basis (so it shrinks
  # the categories' shares once cash joins the 100%), its target is the
  # portfolio's stored cash target, and the drift is `target - actual`, restated
  # in the base currency like every category drift. Always present so the UI/API
  # can render the row even when there is no cash yet or no cash target set.
  #
  # For the built-in currency classification (issue #407), `distributed: true`
  # is added to signal to the UI that cash has been attributed to currency
  # buckets and no separate Cash row should be rendered.
  defp cash_row(counting_cash, cash_target, total, distributed?) do
    actual = weight(counting_cash, total)
    target_weight = cash_target || @zero
    drift_weight = Decimal.sub(target_weight, actual)

    %{
      market_value: counting_cash,
      actual_weight: actual,
      target_weight: target_weight,
      drift_weight: drift_weight,
      drift_value: Decimal.mult(drift_weight, total),
      distributed: distributed?
    }
  end

  # Sum of the direct children's target weights per parent, or absent when no
  # direct child carries a target — so the UI only hints where a comparison is
  # meaningful. Advisory only; never used to validate or block saving targets.
  defp child_target_sums(children_by_parent, targets) do
    children_by_parent
    |> Map.delete(nil)
    |> Enum.reduce(%{}, fn {parent_id, children}, acc ->
      case sum_targets(children, targets) do
        nil -> acc
        sum -> Map.put(acc, parent_id, sum)
      end
    end)
  end

  # Sum of the root categories' target weights, used for the "Σ top level"
  # header hint compared against 100% (the caller adds the cash target on top).
  # Returns zero when no root has a target.
  defp top_level_target_sum(children_by_parent, targets) do
    roots = Map.get(children_by_parent, nil, [])
    sum_targets(roots, targets) || @zero
  end

  # Adds the target weights of the categories that actually carry one. Returns
  # nil when none of them do, so callers can tell "no targets" from "sum is 0".
  defp sum_targets(categories, targets) do
    Enum.reduce(categories, nil, fn category, acc ->
      case Map.get(targets, category.id) do
        nil -> acc
        weight -> Decimal.add(acc || @zero, weight)
      end
    end)
  end

  # Groups each valued position under the category it is directly assigned to,
  # collecting positions with no assignment into the unassigned pot.
  defp group_positions(positions, security_categories) do
    positions
    |> Enum.reduce({%{}, []}, fn position, {by_category, unassigned} ->
      case Map.get(security_categories, position.security_id) do
        nil ->
          {by_category, [position | unassigned]}

        category_id ->
          {Map.update(by_category, category_id, [position], &[position | &1]), unassigned}
      end
    end)
  end

  defp sum_values(positions) do
    Enum.reduce(positions, @zero, &Decimal.add(&2, &1.market_value))
  end

  # One entry per security (a security held in several depots is merged),
  # largest first — the per-position breakdown behind a category's own value,
  # e.g. the outermost sunburst ring.
  defp position_entries(positions, total) do
    positions
    |> Enum.group_by(&{&1.security_id, &1.security_name})
    |> Enum.map(fn {{security_id, security_name}, grouped} ->
      value = sum_values(grouped)

      %{
        security_id: security_id,
        security_name: security_name,
        market_value: value,
        weight: weight(value, total)
      }
    end)
    |> Enum.sort_by(& &1.market_value, {:desc, Decimal})
  end

  # Rolled-up value per category = own value + every descendant's own value.
  # Computed once by memoised post-order walk from the roots.
  defp rolled_values(categories, children_by_parent, own_value_by_category) do
    roots = Map.get(children_by_parent, nil, [])

    {rolled, _} =
      Enum.reduce(roots, {%{}, MapSet.new()}, fn category, acc ->
        accumulate(category, children_by_parent, own_value_by_category, acc)
      end)

    # Categories whose parent is missing/cyclic never reached from a root still
    # get at least their own value, so nothing silently drops out of the total.
    Enum.reduce(categories, rolled, fn category, acc ->
      Map.put_new(acc, category.id, Map.get(own_value_by_category, category.id, @zero))
    end)
  end

  defp accumulate(category, children_by_parent, own_value_by_category, {rolled, seen}) do
    if MapSet.member?(seen, category.id) do
      {rolled, seen}
    else
      seen = MapSet.put(seen, category.id)
      children = Map.get(children_by_parent, category.id, [])

      {rolled, seen} =
        Enum.reduce(children, {rolled, seen}, fn child, acc ->
          accumulate(child, children_by_parent, own_value_by_category, acc)
        end)

      own = Map.get(own_value_by_category, category.id, @zero)

      subtotal =
        Enum.reduce(children, own, fn child, acc ->
          Decimal.add(acc, Map.get(rolled, child.id, @zero))
        end)

      {Map.put(rolled, category.id, subtotal), seen}
    end
  end

  # A row survives when its subtree holds value or it carries a target; ancestors
  # of any survivor are kept too, so the tree never shows an orphaned child.
  defp kept_categories(categories, rolled, targets) do
    parent_by_id = Map.new(categories, &{&1.id, &1.parent_id})

    directly_kept =
      for category <- categories,
          positive?(Map.get(rolled, category.id, @zero)) or Map.has_key?(targets, category.id),
          into: MapSet.new(),
          do: category.id

    Enum.reduce(directly_kept, directly_kept, fn id, kept ->
      add_ancestors(id, parent_by_id, kept)
    end)
  end

  defp add_ancestors(id, parent_by_id, kept) do
    case Map.get(parent_by_id, id) do
      nil ->
        kept

      parent_id ->
        if MapSet.member?(kept, parent_id) do
          kept
        else
          add_ancestors(parent_id, parent_by_id, MapSet.put(kept, parent_id))
        end
    end
  end

  # Depth-first preorder (parent before children), each level kept in the
  # categories' own position order, tagging every node with its depth.
  defp preorder(children_by_parent), do: preorder(children_by_parent, nil, 0)

  defp preorder(children_by_parent, parent_id, depth) do
    children_by_parent
    |> Map.get(parent_id, [])
    |> Enum.flat_map(fn category ->
      [{category, depth} | preorder(children_by_parent, category.id, depth + 1)]
    end)
  end

  defp row(category, depth, own_value, rolled_value, target, child_target_sum, positions, total) do
    actual = weight(rolled_value, total)
    target_weight = target || @zero
    drift_weight = Decimal.sub(target_weight, actual)

    %{
      category_id: category.id,
      parent_id: category.parent_id,
      depth: depth,
      name: category.name,
      color: category.color,
      own_market_value: own_value,
      market_value: rolled_value,
      actual_weight: actual,
      target_weight: target_weight,
      drift_weight: drift_weight,
      drift_value: Decimal.mult(drift_weight, total),
      child_target_sum: child_target_sum,
      positions: positions
    }
  end

  defp unassigned(positions, total) do
    value = sum_values(positions)

    if positive?(value) do
      %{
        market_value: value,
        actual_weight: weight(value, total),
        positions: position_entries(positions, total)
      }
    else
      nil
    end
  end

  defp weight(market_value, total) do
    if Decimal.equal?(total, @zero) do
      @zero
    else
      Decimal.div(market_value, total)
    end
  end

  defp positive?(decimal), do: Decimal.compare(decimal, @zero) == :gt
end
