defmodule Portfolixir.Portfolios.CategoryResult do
  @moduledoc """
  Per-category result: what a category cost, what it is worth now, and what it
  has made — rolled up from the positions currently filed under it
  ([ADR-0041](../../../docs/decisions/0041-per-category-performance.md) slice
  one, issue #712).

  **The computation basis is one line, and it travels with the payload:** this
  is a statement about the **current composition**. There is no period, no
  membership variant and no as-of qualifier to choose, because the question
  being answered is "what do the things filed here today add up to?" — see
  ADR-0041 §1. A time-weighted series over changing membership is explicitly a
  different decision (§6) and is not what this returns.

  Two properties carry the money, and both are pinned by exact `Decimal`
  expectations in `test/portfolixir/portfolios/category_result_test.exs` rather
  than left to review:

  1. **Money-weighted, never a mean of percentages** (§2). The category
     percentage is `Σ result ÷ Σ invested`. Averaging the members' own
     percentages lets a 10 EUR position at +300 % dominate a category that is
     flat across 10 000 EUR, and it is the single most likely way to ship a
     plausible wrong number here.
  2. **Underivable rows are excluded and named** (§4). A member with no usable
     price, or whose base-currency decomposition is unavailable
     (`decomposed: false`, ADR-0033), is left out of **both** sides of the sum
     and listed with its reason. It is never folded in at a result of zero,
     which would quietly understate the category, and the row states how many
     members it covers out of how many it has.

  Nothing here is computed for the first time. `Ledger.holdings_for_portfolio/2`
  already carries each position's base-currency cost (`base_cost`) and its
  base-currency total return (`total_return_base_abs`); the work is grouping
  them by the tree. Current value is derived as `invested + result` rather than
  re-converting the market value, so the three figures cannot disagree with each
  other by a rounding step (ADR-0016: no rounding between steps).
  """

  alias Portfolixir.Classifications
  alias Portfolixir.Ledger

  @zero Decimal.new("0")

  @basis "current_composition"

  @doc """
  Rolls the current holdings of `portfolio_id` up the tree of
  `classification_id`.

  Returns `{:ok, result}` where `result.categories` carries one entry per
  category in the tree — including categories with no members, which report
  zeroes and a `nil` percentage rather than claiming to be flat — plus
  `result.basis`, the one-line computation basis of ADR-0041 §1.

  Options are passed through to `Ledger.holdings_for_portfolio/2`: `:prices`
  and `:fx_rates` for deterministic fixtures.
  """
  def for_portfolio(portfolio_id, classification_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(classification_id) do
    case Classifications.security_category_map(classification_id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, security_categories} ->
        categories = Classifications.list_categories(classification_id)
        holdings = Ledger.holdings_for_portfolio(portfolio_id, opts)

        {:ok,
         %{
           portfolio_id: portfolio_id,
           classification_id: classification_id,
           basis: @basis,
           categories: roll_up(categories, security_categories, holdings)
         }}
    end
  end

  defp roll_up(categories, security_categories, holdings) do
    # A position counts toward the category it is filed under AND every
    # ancestor, so a parent's result reconstructs from the level below it
    # (ADR-0041 §2, last paragraph).
    ancestors = ancestor_index(categories)

    entries =
      holdings
      |> Enum.reject(&Decimal.equal?(&1.quantity, @zero))
      |> Enum.map(&member_entry/1)

    by_category =
      Enum.reduce(entries, %{}, fn entry, acc ->
        case Map.get(security_categories, entry.security_id) do
          nil ->
            acc

          category_id ->
            category_id
            |> then(&[&1 | Map.get(ancestors, &1, [])])
            |> Enum.reduce(acc, fn id, inner ->
              Map.update(inner, id, [entry], &[entry | &1])
            end)
        end
      end)

    Enum.map(categories, fn category ->
      by_category
      |> Map.get(category.id, [])
      |> category_row(category)
    end)
  end

  # Each category's ancestors, so a member rolls into every level above it.
  defp ancestor_index(categories) do
    parents = Map.new(categories, &{&1.id, &1.parent_id})

    Map.new(categories, fn category ->
      {category.id, ancestors_of(category.parent_id, parents, [])}
    end)
  end

  defp ancestors_of(nil, _parents, acc), do: Enum.reverse(acc)

  defp ancestors_of(id, parents, acc),
    do: ancestors_of(Map.get(parents, id), parents, [id | acc])

  # A member is covered when its base-currency cost AND its base-currency total
  # return are both derivable. Anything else is excluded and named (§4).
  defp member_entry(holding) do
    base = %{
      security_id: holding.security_id,
      security_name: holding.security_name,
      quantity: holding.quantity
    }

    cond do
      is_nil(holding.market_value) ->
        Map.merge(base, %{covered: false, reason: :no_usable_price})

      holding.decomposed != true ->
        Map.merge(base, %{
          covered: false,
          reason: holding.undecomposed_reason || :not_decomposed
        })

      is_nil(holding.base_cost) ->
        Map.merge(base, %{covered: false, reason: :missing_base_cost})

      true ->
        invested = holding.base_cost
        result_abs = holding.total_return_base_abs

        Map.merge(base, %{
          covered: true,
          reason: nil,
          invested: invested,
          result_abs: result_abs,
          current_value: Decimal.add(invested, result_abs),
          result_pct: percentage(result_abs, invested)
        })
    end
  end

  defp category_row(entries, category) do
    {covered, excluded} = Enum.split_with(entries, & &1.covered)

    invested = sum(covered, :invested)
    result_abs = sum(covered, :result_abs)

    %{
      category_id: category.id,
      parent_id: category.parent_id,
      name: category.name,
      invested: invested,
      # Derived from the two sums rather than re-converted, so the three
      # figures cannot drift apart by a rounding step.
      current_value: Decimal.add(invested, result_abs),
      result_abs: result_abs,
      # Money-weighted (§2). Nil when nothing is invested: there is no
      # percentage to state, and a zero would claim the category is flat.
      result_pct: percentage(result_abs, invested),
      covered_count: length(covered),
      member_count: length(entries),
      excluded:
        Enum.map(
          excluded,
          &%{security_id: &1.security_id, security_name: &1.security_name, reason: &1.reason}
        ),
      positions:
        Enum.map(covered, fn entry ->
          %{
            security_id: entry.security_id,
            security_name: entry.security_name,
            quantity: entry.quantity,
            invested: entry.invested,
            current_value: entry.current_value,
            result_abs: entry.result_abs,
            result_pct: entry.result_pct
          }
        end)
    }
  end

  defp sum(entries, key),
    do: Enum.reduce(entries, @zero, &Decimal.add(&2, Map.fetch!(&1, key)))

  # Money-weighted (ADR-0041 §2): the ratio of the SUMS, never a mean of the
  # members' own ratios. Nil rather than zero when nothing is invested -- a zero
  # would state that the category is flat, which is a different claim from
  # having nothing to measure.
  defp percentage(result_abs, invested) do
    unless Decimal.equal?(invested, @zero) do
      Decimal.div(result_abs, invested)
    end
  end
end
