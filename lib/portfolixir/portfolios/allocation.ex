defmodule Portfolixir.Portfolios.Allocation do
  @moduledoc """
  Read-time SOLL/IST allocation breakdown for one portfolio and classification.

  Groups the live valuation's valued positions into the chosen classification's
  categories (the IST side), joins each category's stored target weight (the SOLL
  side, see `Portfolixir.Portfolios.Targets`), and reports the drift between
  them — all in one call, so the weekly check does not need to join holdings,
  classifications, and targets by hand.

  Weights are shares of the valued positions' total market value, matching
  `Portfolixir.Portfolios.Valuation` (cash is reported there, not here). Drift is
  `target_weight - actual_weight` per category; `drift_value` restates that drift
  as an amount in the base currency, i.e. how much to buy (positive) or sell
  (negative) to reach the target.
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
    {market_value_by_category, unassigned_value} = group_positions(valuation, security_categories)

    rows =
      categories
      |> Enum.map(fn category ->
        {category, Map.get(market_value_by_category, category.id, @zero),
         Map.get(targets, category.id)}
      end)
      |> Enum.filter(fn {_category, market_value, target} ->
        positive?(market_value) or not is_nil(target)
      end)
      |> Enum.map(fn {category, market_value, target} ->
        row(category, market_value, target, total)
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

  # Sums each valued position's market value into its category, collecting
  # positions with no assignment in this classification into the unassigned pot.
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

  defp row(category, market_value, target, total) do
    actual = weight(market_value, total)
    target_weight = target || @zero
    drift_weight = Decimal.sub(target_weight, actual)

    %{
      category_id: category.id,
      name: category.name,
      color: category.color,
      market_value: market_value,
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
