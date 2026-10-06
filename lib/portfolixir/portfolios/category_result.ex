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

  **One currency per result** (#1048). A sum adds one currency: a portfolio's
  own read is in its base currency, and the reads that span portfolios -- a
  view (`for_view/3`) and every portfolio (`for_all_portfolios/2`) -- are in
  EUR. A member held in a portfolio whose base currency is not EUR has no EUR
  cost to add, so in those two it is excluded and named with
  `missing_base_cost`; its cost is never converted through the hub, which
  would state a cost nobody paid.

  Every result carries `excluded_members`: each excluded member **once**,
  across the tree, sorted by name, with the category it is filed under, its
  reason and, when it is out only because its cost was not paid in EUR, that
  cost in the currency it was paid in (`native_costs`, one amount per
  currency). It is an internal key: `/api/v1` picks its fields explicitly and
  does not serve it (#1091 decides how).

  Nothing here is computed for the first time. `Ledger.holdings_for_portfolio/2`
  already carries each position's base-currency cost (`base_cost`) and its
  base-currency total return (`total_return_base_abs`); the work is grouping
  them by the tree. Current value is derived as `invested + result` rather than
  re-converting the market value, so the three figures cannot disagree with each
  other by a rounding step (ADR-0016: no rounding between steps).
  """

  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Portfolio

  @zero Decimal.new("0")

  @basis "current_composition"

  # The currency of the reads that span portfolios -- a view (#901) and every
  # portfolio (#1048): their figures are in the EUR hub, as the view
  # valuation's and the view performance's are.
  @hub "EUR"

  @doc """
  Rolls the current holdings of `portfolio_id` up the tree of
  `classification_id`.

  Returns `{:ok, result}` where `result.categories` carries one entry per
  category in the tree — including categories with no members, which report
  zeroes and a `nil` percentage rather than claiming to be flat — plus
  `result.basis`, the one-line computation basis of ADR-0041 §1, the
  scope it was computed over (`scope: :portfolio`, `view_id`,
  `base_currency`: the portfolio's), and `result.excluded_members`, each
  excluded member once (see the moduledoc). Nothing here is converted, so no
  member of a portfolio's own read is out for its cost's currency.

  Options: `:view` (a view id, #901) narrows the roll-up to the portfolio's
  positions matching that view, the way it narrows the valuation and the
  performance walk (ADR-0018); an unknown view is
  `{:error, :view_not_found}`. `:prices` and `:fx_rates` are passed through
  to `Ledger.holdings_for_portfolio/2` for deterministic fixtures.
  """
  def for_portfolio(portfolio_id, classification_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(classification_id) do
    view_id = Keyword.get(opts, :view)

    with {:ok, security_categories} <- Classifications.security_category_map(classification_id),
         scope when not is_tuple(scope) <- Buckets.load_scope(portfolio_id, view_id) do
      holdings =
        portfolio_id
        |> Ledger.holdings_for_portfolio(opts)
        |> in_scope(scope)

      currency = base_currency(portfolio_id)

      {categories, excluded_members} =
        roll_up(
          Classifications.list_categories(classification_id),
          security_categories,
          holdings,
          currency
        )

      {:ok,
       %{
         portfolio_id: portfolio_id,
         view_id: view_id,
         scope: :portfolio,
         base_currency: currency,
         classification_id: classification_id,
         basis: @basis,
         categories: categories,
         excluded_members: excluded_members
       }}
    end
  end

  @doc """
  The roll-up of a bucket **view across every portfolio** (#901; ADR-0051
  §6): the positions matching `view_id` in every portfolio, each account
  counted once — an account belongs to exactly one portfolio — the scope the
  view valuation and the view performance cover (ADR-0024).

  The figures are in EUR (`base_currency: "EUR"`). A member's invested amount
  is the settlement leg actually paid (ADR-0033), so a member held in a
  portfolio whose base currency is not EUR has no EUR cost to add: it is
  excluded and named with `missing_base_cost`, never summed across
  currencies.

  An unknown view is `{:error, :view_not_found}`, an unknown classification
  `{:error, :not_found}`. Options as `for_portfolio/3`.
  """
  def for_view(view_id, classification_id, opts \\ [])
      when is_integer(view_id) and is_integer(classification_id) do
    with {:ok, security_categories} <- Classifications.security_category_map(classification_id),
         scope when not is_tuple(scope) <- Buckets.load_global_scope(view_id) do
      holdings = hub_holdings(opts, &in_scope(&1, scope))

      {categories, excluded_members} =
        roll_up(
          Classifications.list_categories(classification_id),
          security_categories,
          holdings,
          @hub
        )

      {:ok,
       %{
         portfolio_id: nil,
         view_id: view_id,
         scope: :view,
         base_currency: @hub,
         classification_id: classification_id,
         basis: @basis,
         categories: categories,
         excluded_members: excluded_members
       }}
    end
  end

  # Every portfolio's holdings, narrowed by `narrow`, in the EUR hub: the one
  # currency rule the two cross-portfolio reads share (#901, #1048).
  defp hub_holdings(opts, narrow) do
    Enum.flat_map(Portfolios.list_portfolios(), fn portfolio ->
      portfolio.id
      |> Ledger.holdings_for_portfolio(opts)
      |> narrow.()
      |> Enum.map(&in_hub_currency(&1, portfolio.base_currency_code))
    end)
  end

  defp in_scope(holdings, scope) do
    Enum.filter(
      holdings,
      &Buckets.position_in_scope?(scope, &1.securities_account_id, &1.security_id)
    )
  end

  # A holding's base-currency figures are its portfolio's currency. Outside
  # EUR they cannot enter a EUR sum, so the row is reported the way any
  # holding without a cost in the base currency is: not decomposed, for
  # missing_base_cost (ADR-0033), which excludes and names it (§4). The cost
  # it does have travels with it as its native cost -- the settlement leg
  # actually paid, in the portfolio's currency, never converted (#1048). A
  # row already undecomposed keeps the reason it has, and has no cost to
  # state for this one.
  defp in_hub_currency(holding, @hub), do: holding

  defp in_hub_currency(%{decomposed: true, base_cost: base_cost} = holding, other_currency) do
    holding
    |> Map.merge(%{decomposed: false, undecomposed_reason: :missing_base_cost})
    |> Map.put(:native_cost, base_cost && %{amount: base_cost, currency: other_currency})
  end

  defp in_hub_currency(holding, _other_currency), do: holding

  defp base_currency(portfolio_id) do
    case Portfolios.get_portfolio(portfolio_id) do
      %Portfolio{base_currency_code: code} -> code
      nil -> nil
    end
  end

  @doc """
  The same roll-up across **every** portfolio (`scope: :all`).

  This is what the human surface reads: the classification tree is global, since
  [ADR-0024](../../../docs/decisions/0024-buckets-and-views-replace-portfolios-in-the-ui.md)
  demoted portfolios as a user-facing grouping. Per-portfolio cost lots are
  built from that portfolio's own transactions, so the EUR sums add across
  portfolios without double-counting; a security held in two of them appears as
  one member row carrying the combined quantity.

  The figures are in EUR (`base_currency: "EUR"`), under `for_view/3`'s rule
  (#1048): a member held in a portfolio whose base currency is not EUR has no
  EUR cost, so it is excluded and named with `missing_base_cost` and its
  native cost in `excluded_members`, never summed across currencies. A
  security held in both kinds of portfolio is excluded whole (§4: no partial
  sum of a security). On an instance whose portfolios are all EUR, nothing
  is excluded for its currency and every figure is what the plain sum gives.
  """
  def for_all_portfolios(classification_id, opts \\ []) when is_integer(classification_id) do
    case Classifications.security_category_map(classification_id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, security_categories} ->
        {categories, excluded_members} =
          roll_up(
            Classifications.list_categories(classification_id),
            security_categories,
            hub_holdings(opts, & &1),
            @hub
          )

        {:ok,
         %{
           portfolio_id: nil,
           scope: :all,
           base_currency: @hub,
           classification_id: classification_id,
           basis: @basis,
           categories: categories,
           excluded_members: excluded_members
         }}
    end
  end

  # The categories' rows, and the excluded members once each across the tree
  # (#1048). `currency` is the result's: what a covered slice's cost is in,
  # when a security excluded whole lists every slice's cost.
  defp roll_up(categories, security_categories, holdings, currency) do
    # A position counts toward the category it is filed under AND every
    # ancestor, so a parent's result reconstructs from the level below it
    # (ADR-0041 §2, last paragraph).
    ancestors = ancestor_index(categories)

    # Each member with the category it is filed under; an unfiled one is in
    # no row and in no list.
    filed =
      holdings
      |> Enum.reject(&Decimal.equal?(&1.quantity, @zero))
      |> Enum.map(&member_entry/1)
      |> merge_by_security(currency)
      |> Enum.flat_map(fn entry ->
        case Map.get(security_categories, entry.security_id) do
          nil -> []
          category_id -> [{entry, category_id}]
        end
      end)

    by_category =
      Enum.reduce(filed, %{}, fn {entry, category_id}, acc ->
        category_id
        |> then(&[&1 | Map.get(ancestors, &1, [])])
        |> Enum.reduce(acc, fn id, inner ->
          Map.update(inner, id, [entry], &[entry | &1])
        end)
      end)

    rows =
      Enum.map(categories, fn category ->
        by_category
        |> Map.get(category.id, [])
        |> category_row(category)
      end)

    {rows, excluded_members(filed)}
  end

  # Each excluded member once, though it rolls into every ancestor's row: the
  # list a reader can be shown in one place (#1048), sorted by name.
  defp excluded_members(filed) do
    filed
    |> Enum.reject(fn {entry, _category_id} -> entry.covered end)
    |> Enum.map(fn {entry, category_id} ->
      %{
        security_id: entry.security_id,
        security_name: entry.security_name,
        category_id: category_id,
        reason: entry.reason,
        native_costs: entry.native_costs
      }
    end)
    |> Enum.sort_by(&{&1.security_name || "", &1.security_id})
  end

  # Each category's ancestors, so a member rolls into every level above it.
  # The walk carries the ids it has met: a parent loop stored before the write
  # guard (F11) ends it where the loop closes, and a member then counts once
  # per category on the loop, never forever.
  defp ancestor_index(categories) do
    parents = Map.new(categories, &{&1.id, &1.parent_id})

    Map.new(categories, fn category ->
      {category.id, ancestors_of(category.parent_id, parents, [], MapSet.new([category.id]))}
    end)
  end

  defp ancestors_of(nil, _parents, acc, _seen), do: Enum.reverse(acc)

  defp ancestors_of(id, parents, acc, seen) do
    if MapSet.member?(seen, id),
      do: Enum.reverse(acc),
      else: ancestors_of(Map.get(parents, id), parents, [id | acc], MapSet.put(seen, id))
  end

  # A member is covered when its base-currency cost AND its base-currency total
  # return are both derivable. Anything else is excluded and named (§4).
  defp member_entry(holding) do
    base = %{
      security_id: holding.security_id,
      security_name: holding.security_name,
      quantity: holding.quantity,
      # Set only where the hub rule excluded a cost it does know (#1048).
      native_cost: Map.get(holding, :native_cost)
    }

    cond do
      is_nil(holding.market_value) ->
        Map.merge(base, %{covered: false, reason: :no_usable_price})

      # One branch, not two: `decomposed: true` already implies a settlement leg,
      # so a nil base_cost beside it is unreachable in practice. Keeping the
      # guard costs nothing and keeping it SEPARATE cost an untestable line.
      holding.decomposed != true or is_nil(holding.base_cost) ->
        Map.merge(base, %{
          covered: false,
          reason: holding.undecomposed_reason || :missing_base_cost
        })

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

  # A security held in several depots or portfolios is ONE member row: that is
  # what a reader recognises, and it keeps member_count a count of securities
  # rather than of depot slots. An uncovered slice makes the whole row
  # uncovered -- partially summing a security would understate it in exactly
  # the way §4 forbids.
  defp merge_by_security(entries, currency) do
    entries
    |> Enum.group_by(& &1.security_id)
    |> Enum.map(fn {_security_id, [first | _] = slices} ->
      if Enum.all?(slices, & &1.covered) do
        invested = sum(slices, :invested)
        result_abs = sum(slices, :result_abs)

        %{
          first
          | quantity: sum(slices, :quantity),
            invested: invested,
            result_abs: result_abs,
            current_value: Decimal.add(invested, result_abs),
            result_pct: percentage(result_abs, invested)
        }
      else
        uncovered = Enum.find(slices, &(not &1.covered))

        uncovered
        |> Map.put(:quantity, sum(slices, :quantity))
        |> Map.put(:native_costs, native_costs(slices, currency))
      end
    end)
  end

  # What an uncovered row cost, per currency, when it is out ONLY because its
  # cost was not paid in EUR (#1048): every uncovered slice carries the cost
  # it was paid, and a covered slice adds its own in the result's currency
  # ("1.000,00 EUR + 1.500,00 USD"). The result's currency first, then the
  # others by code. A slice out for any other reason has no cost to state,
  # and neither has the row: the list is empty and the reason speaks.
  defp native_costs(slices, currency) do
    {covered, uncovered} = Enum.split_with(slices, & &1.covered)

    if Enum.all?(uncovered, &match?(%{native_cost: %{}}, &1)) do
      (Enum.map(covered, &%{amount: &1.invested, currency: currency}) ++
         Enum.map(uncovered, & &1.native_cost))
      |> Enum.group_by(& &1.currency, & &1.amount)
      |> Enum.map(fn {code, amounts} ->
        %{amount: Enum.reduce(amounts, @zero, &Decimal.add(&2, &1)), currency: code}
      end)
      |> Enum.sort_by(&{&1.currency != currency, &1.currency})
    else
      []
    end
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
