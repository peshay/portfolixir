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

  Weights are shares of the valued positions' total market value, matching
  `Portfolixir.Portfolios.Valuation` (cash is reported there, not here). Drift is
  `target_weight - actual_weight` per category; `drift_value` restates that drift
  as an amount in the base currency, i.e. how much to buy (positive) or sell
  (negative) to reach the target. Because parents aggregate their children,
  the displayed IST percentages intentionally do not sum to 100% across levels
  — only the leaves (plus unassigned) do.
  """

  alias Portfolixir.Classifications
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

        targets =
          portfolio_id
          |> Targets.list_targets(classification_id: classification_id)
          |> Map.new(&{&1.category_id, &1.target_weight})

        {:ok, build(valuation, classification, categories, security_categories, targets)}
    end
  end

  defp build(valuation, classification, categories, security_categories, targets) do
    total = valuation.total_value
    {own_value_by_category, unassigned_value} = group_positions(valuation, security_categories)

    children_by_parent = Enum.group_by(categories, & &1.parent_id)
    rolled = rolled_values(categories, children_by_parent, own_value_by_category)
    kept = kept_categories(categories, rolled, targets)

    rows =
      categories
      |> preorder(children_by_parent)
      |> Enum.filter(fn {category, _depth} -> MapSet.member?(kept, category.id) end)
      |> Enum.map(fn {category, depth} ->
        row(
          category,
          depth,
          Map.get(own_value_by_category, category.id, @zero),
          Map.get(rolled, category.id, @zero),
          Map.get(targets, category.id),
          total
        )
      end)

    %{
      portfolio_id: valuation.portfolio_id,
      classification_id: classification.id,
      classification_name: classification.name,
      base_currency: valuation.base_currency,
      total_value: total,
      unvalued_count: valuation.unvalued_count,
      categories: rows,
      unassigned: unassigned(unassigned_value, total)
    }
  end

  # Sums each valued position's market value into the category it is directly
  # assigned to, collecting positions with no assignment into the unassigned pot.
  defp group_positions(valuation, security_categories) do
    valuation.positions
    |> Enum.filter(& &1.valued)
    |> Enum.reduce({%{}, @zero}, fn position, {by_category, unassigned} ->
      case Map.get(security_categories, position.security_id) do
        nil ->
          {by_category, Decimal.add(unassigned, position.market_value)}

        category_id ->
          {Map.update(
             by_category,
             category_id,
             position.market_value,
             &Decimal.add(&1, position.market_value)
           ), unassigned}
      end
    end)
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

  defp row(category, depth, own_value, rolled_value, target, total) do
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
      drift_value: Decimal.mult(drift_weight, total)
    }
  end

  defp unassigned(value, total) do
    if positive?(value) do
      %{market_value: value, actual_weight: weight(value, total)}
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
