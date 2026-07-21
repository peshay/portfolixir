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
  (actual share, target from the active view's plan cash target, drift) in the
  same drift logic, and every category percentage shrinks accordingly once cash
  joins the 100% (issue #335). Drift is
  `actual_weight - target_weight` per category (positive = overweight,
  negative = underweight; ADR-0023); `drift_value` restates that drift as an
  amount in the base currency, i.e. how much to sell (positive) or buy
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

  ## View-bound SOLL plans (ADR-0020)

  The SOLL side is driven by the **active view's plan** for the classification.
  Targets are keyed by `(view, classification)`; `view: nil` is the portfolio-wide
  **Gesamt** plan that reproduces today's behaviour. `for_portfolio/3` loads
  **only** the addressed plan (its category targets and its cash target), so no
  foreign target from another view ever leaks into the breakdown — the ghost-row /
  ~200% Σ incoherence is gone by construction. When the active view carries **no
  plan** for the classification, the result is **IST-only**: no targets, no cash
  target, a zero `top_level_target_sum`, and `has_plan: false` so callers can hide
  the SOLL/drift columns. Loading happens in this impure shell; the pure builder
  receives the plan as injected data (AR-2).

  ## Position-level SOLL (ADR-0030 slice 2a, #481)

  When the active plan carries **position rows** (SOLL on individual securities),
  the breakdown reflects them:

  - A category's `target_weight` is the **effective** target (ADR-0030): the sum
    of its position rows when any exist (positions are the source of truth),
    else the explicit category-row weight. `conflict` flags a category whose
    explicit weight and position sum disagree, `has_stale` one whose position
    rows include a stale row (its security no longer sits under the filed
    category); both are display-only, nothing is resolved or dropped. The
    Σ figures (`child_target_sum`, `top_level_target_sum`) consume the same
    effective values, so no surface disagrees with another.
  - A category's `positions` are the **union** of its in-scope held positions
    and the plan's position-target rows, matched by security. Each entry carries
    `target_weight` (its position SOLL, `nil` when none), `held`, and — when it
    has its own SOLL — its own `drift_weight` (actual weight − target weight,
    ADR-0023) with `drift_value` and the indicative `rebalance_quantity`.
    Entries without their own SOLL keep the category-share hints unchanged.
  - The owner's display rule (binding, #481): a position row is **shown** when
    it has holdings in scope OR a position SOLL target > 0 in the active plan;
    a SOLL-only row shows with IST 0 (quantity, value, weight all zero) and the
    full underweight drift — "this needs buying". A row is **hidden** only when
    its SOLL is 0/absent AND its holdings are zero.
  - A SOLL-only (unheld) entry's indicative quantity is priced at the security's
    **latest stored quote** converted to the base currency; without a price no
    quantity is invented (`nil`). A held entry keeps the valuation's implied
    unit price. A target row whose security is held under a *different* category
    (an ancestor filing, or a stale row) attaches its SOLL to the security's
    held entry — IST is never faked to zero for a security that is held —
    while the target keeps counting toward the category it was filed under.
  """

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Classifications
  alias Portfolixir.Fx
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation

  @zero Decimal.new("0")

  @doc """
  Builds the allocation breakdown for `portfolio_id` against `classification_id`.

  Options are passed through to `Valuation.for_portfolio/2` (e.g. `:prices`,
  `:base_currency`). `:view` (a `%View{}`, a view id, or `nil` = Gesamt) scopes
  **both** the IST valuation (#444) and the SOLL plan (ADR-0020): only the
  addressed view's `(view, classification)` plan is loaded. Returns
  `{:ok, breakdown}` or `{:error, :not_found}` when the classification does not
  exist.
  """
  def for_portfolio(portfolio_id, classification_id, opts \\ [])
      when is_integer(portfolio_id) and is_integer(classification_id) do
    case Classifications.security_category_map(classification_id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, security_categories} ->
        classification = Classifications.get_classification(classification_id)
        categories = Classifications.list_categories(classification_id)
        view = Keyword.get(opts, :view)

        # A vanished view degrades to `{:error, :view_not_found}` (fix round)
        # instead of raising out of an async render or API request.
        with %{} = valuation <- Valuation.for_portfolio(portfolio_id, opts) do
          soll = plan_soll(portfolio_id, classification_id, view)
          soll = put_unheld_prices(soll, valuation, opts)

          {:ok, build(valuation, classification, categories, security_categories, soll)}
        end
    end
  end

  # The SOLL side is the active view's plan only (ADR-0020). A view "has a plan"
  # for this surface when it carries a `(view, classification)` category plan OR
  # a portfolio-wide cash target (the legacy cash-target home, which may be
  # steered without any category targets — the prior Gesamt behaviour). With no
  # plan at all, the breakdown is IST-only: no targets, no cash target,
  # `has_plan: false`, so callers can hide the SOLL/drift columns. The plan —
  # explicit category rows AND position rows (ADR-0030 slice 2a) — is read here,
  # in the impure shell, and injected into the pure `build/5` as data (AR-2).
  defp plan_soll(portfolio_id, classification_id, view) do
    cash_target = Targets.get_cash_target(portfolio_id, view: view)
    category_plan? = Targets.plan_exists?(portfolio_id, classification_id, view: view)

    cond do
      category_plan? ->
        explicit =
          portfolio_id
          |> Targets.list_targets(classification_id: classification_id, view: view)
          |> Map.new(&{&1.category_id, &1.target_weight})

        position_targets =
          Targets.list_position_targets(portfolio_id,
            classification_id: classification_id,
            view: view
          )

        %{
          explicit: explicit,
          position_targets: position_targets,
          unheld_prices: %{},
          cash_target: cash_target,
          has_plan: true
        }

      not is_nil(cash_target) ->
        %{
          explicit: %{},
          position_targets: [],
          unheld_prices: %{},
          cash_target: cash_target,
          has_plan: true
        }

      true ->
        %{
          explicit: %{},
          position_targets: [],
          unheld_prices: %{},
          cash_target: nil,
          has_plan: false
        }
    end
  end

  # Base-currency unit prices for the plan's SOLL-only securities (position
  # targets whose security carries no valued holding in scope): the indicative
  # ADR-0023 quantity for "this needs buying" is priced at the latest stored
  # quote (or the test `:prices` override), converted via the EUR hub. A missing
  # quote, currency or FX path yields `nil` — no price is ever invented. Impure
  # (quote + FX reads), so it lives in the shell next to the other loads (AR-2).
  defp put_unheld_prices(%{position_targets: []} = soll, _valuation, _opts), do: soll

  defp put_unheld_prices(soll, valuation, opts) do
    held =
      for position <- valuation.positions, position.valued, into: MapSet.new() do
        position.security_id
      end

    price_overrides = Keyword.get(opts, :prices, %{})

    unheld_prices =
      soll.position_targets
      |> Enum.reject(&MapSet.member?(held, &1.security_id))
      |> Map.new(fn target ->
        {target.security_id, unheld_base_price(target, price_overrides, valuation.base_currency)}
      end)

    %{soll | unheld_prices: unheld_prices}
  end

  defp unheld_base_price(target, price_overrides, base_currency) do
    native =
      case Map.get(price_overrides, target.security_id) do
        %Decimal{} = price -> price
        _no_override -> latest_quote_close(target.security_id)
      end

    currency = target.security && target.security.currency_code

    with %Decimal{} <- native,
         true <- is_binary(currency) and is_binary(base_currency),
         {:ok, converted} <- Fx.convert(native, currency, base_currency) do
      converted
    else
      _missing -> nil
    end
  end

  defp latest_quote_close(security_id) do
    case Quotes.latest(security_id) do
      %{close: %Decimal{} = close} -> close
      _none -> nil
    end
  end

  defp build(valuation, classification, categories, security_categories, soll) do
    %{cash_target: cash_target, has_plan: has_plan} = soll
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

    # ADR-0030 slice 2a: the SOLL side resolves to the EFFECTIVE targets —
    # a category with position rows is steered by their sum (positions are the
    # source of truth), everything else by its explicit weight. `kept`,
    # `child_target_sums` and `top_level_target_sum` all consume the same
    # effective map, so the Σ family never disagrees with the rows.
    position_rows_by_category = Enum.group_by(soll.position_targets, & &1.category_id)
    position_sums = position_sums(position_rows_by_category)
    targets = Map.merge(soll.explicit, position_sums)
    category_flags = category_flags(position_rows_by_category, position_sums, soll.explicit)
    position_soll = position_soll(soll, steering_positions)

    children_by_parent = Enum.group_by(categories, & &1.parent_id)
    rolled = rolled_values(categories, children_by_parent, own_value_by_category)
    kept = kept_categories(categories, rolled, targets)
    child_target_sums = child_target_sums(children_by_parent, targets)

    rows =
      children_by_parent
      |> preorder()
      |> Enum.filter(fn {category, _depth} -> MapSet.member?(kept, category.id) end)
      |> Enum.map(fn {category, depth} ->
        category
        |> row(
          depth,
          Map.get(own_value_by_category, category.id, @zero),
          Map.get(rolled, category.id, @zero),
          Map.get(targets, category.id),
          Map.get(child_target_sums, category.id),
          Map.get(category_flags, category.id),
          category_position_entries(
            Map.get(positions_by_category, category.id, []),
            category.id,
            position_soll,
            total
          ),
          total
        )
        |> with_rebalance_hints(has_plan)
      end)

    distribute_cash? = classification.key == "currency"

    %{
      portfolio_id: valuation.portfolio_id,
      classification_id: classification.id,
      classification_name: classification.name,
      base_currency: valuation.base_currency,
      total_value: total,
      unvalued_count: valuation.unvalued_count,
      has_plan: has_plan,
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
  # the categories' shares once cash joins the 100%), its target is the active
  # view's plan cash target, and the drift is `actual - target` (ADR-0023),
  # restated in the base currency like every category drift. Always present so the UI/API
  # can render the row even when there is no cash yet or no cash target set.
  #
  # For the built-in currency classification (issue #407), `distributed: true`
  # is added to signal to the UI that cash has been attributed to currency
  # buckets and no separate Cash row should be rendered.
  defp cash_row(counting_cash, cash_target, total, distributed?) do
    actual = weight(counting_cash, total)
    target_weight = cash_target || @zero
    drift_weight = Decimal.sub(actual, target_weight)

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
  # e.g. the outermost sunburst ring. `drift_value` and `rebalance_quantity`
  # stay nil here; category rows overwrite them when the view has a plan
  # (ADR-0023), so every entry has a uniform shape for the UI/API.
  # `target_weight`/`drift_weight` (ADR-0030 slice 2a) stay nil until a
  # position SOLL row attaches; `held` is true by construction here.
  defp position_entries(positions, total) do
    positions
    |> Enum.group_by(&{&1.security_id, &1.security_name})
    |> Enum.map(fn {{security_id, security_name}, grouped} ->
      value = sum_values(grouped)

      %{
        security_id: security_id,
        security_name: security_name,
        quantity: sum_quantities(grouped),
        market_value: value,
        weight: weight(value, total),
        target_weight: nil,
        drift_weight: nil,
        drift_value: nil,
        rebalance_quantity: nil,
        held: true
      }
    end)
    |> Enum.sort_by(& &1.market_value, {:desc, Decimal})
  end

  # The sum of each category's position rows — the effective steering number
  # once positions exist (ADR-0030: positions are the source of truth).
  defp position_sums(position_rows_by_category) do
    Map.new(position_rows_by_category, fn {category_id, rows} ->
      {category_id, Enum.reduce(rows, @zero, &Decimal.add(&2, &1.target_weight))}
    end)
  end

  # Per-category advisory flags (ADR-0030): `conflict` when an explicit
  # category weight coexists with a differing position sum (the sum steers,
  # the mismatch is surfaced, nothing is dropped), `has_stale` when any of the
  # category's position rows is stale. Categories without position rows are
  # absent — their rows default both flags to false.
  defp category_flags(position_rows_by_category, position_sums, explicit) do
    Map.new(position_rows_by_category, fn {category_id, rows} ->
      explicit_weight = Map.get(explicit, category_id)
      sum = Map.fetch!(position_sums, category_id)

      {category_id,
       %{
         conflict: not is_nil(explicit_weight) and not Decimal.equal?(explicit_weight, sum),
         has_stale: Enum.any?(rows, & &1.stale)
       }}
    end)
  end

  # The position-SOLL lookup the row builder joins against: every position
  # target by security (a held entry attaches its SOLL wherever it renders),
  # plus the SOLL-only rows — securities without a valued holding in scope —
  # grouped under the category they were filed under, with their injected
  # latest-quote base prices.
  defp position_soll(soll, steering_positions) do
    held_ids = MapSet.new(steering_positions, & &1.security_id)

    %{
      by_security: Map.new(soll.position_targets, &{&1.security_id, &1}),
      unheld_by_category:
        soll.position_targets
        |> Enum.reject(&MapSet.member?(held_ids, &1.security_id))
        |> Enum.group_by(& &1.category_id),
      unheld_prices: soll.unheld_prices
    }
  end

  # The union of a category's in-scope held positions and the plan's position
  # SOLL rows (ADR-0030 slice 2a), with the owner's display rule applied:
  # shown when held in scope OR SOLL > 0; hidden only when SOLL is 0/absent
  # AND holdings are zero. Held entries come largest first as before; the
  # SOLL-only rows follow, largest target first.
  defp category_position_entries(held_positions, category_id, position_soll, total) do
    held_entries =
      held_positions
      |> position_entries(total)
      |> Enum.map(&attach_position_soll(&1, position_soll.by_security, total))

    unheld_entries =
      position_soll.unheld_by_category
      |> Map.get(category_id, [])
      |> Enum.map(&unheld_entry(&1, position_soll.unheld_prices, total))
      |> Enum.sort_by(& &1.target_weight, {:desc, Decimal})

    Enum.reject(held_entries ++ unheld_entries, &hidden_position?/1)
  end

  # The owner's hide rule (#481, binding): a row disappears only when it has
  # neither holdings nor a positive SOLL — everything else stays visible.
  defp hidden_position?(entry) do
    zero_soll? = is_nil(entry.target_weight) or Decimal.equal?(entry.target_weight, @zero)
    zero_soll? and Decimal.equal?(entry.quantity, @zero)
  end

  # A held entry with its own position SOLL gets its own drift (ADR-0023 sign:
  # actual weight − target weight, positive = overweight), restated in the
  # base currency, and the indicative quantity at the valuation's implied unit
  # price. Entries without a SOLL row pass through untouched and later receive
  # the category-share hints exactly as before.
  defp attach_position_soll(entry, by_security, total) do
    case Map.get(by_security, entry.security_id) do
      nil ->
        entry

      target ->
        drift_weight = Decimal.sub(entry.weight, target.target_weight)
        drift_value = Decimal.mult(drift_weight, total)

        %{
          entry
          | target_weight: target.target_weight,
            drift_weight: drift_weight,
            drift_value: drift_value,
            rebalance_quantity: implied_price_quantity(entry, drift_value)
        }
    end
  end

  # drift_value / (market_value / quantity) = drift_value × quantity /
  # market_value — multiplications before the division so exact fixtures stay
  # exact (ADR-0016). No hint without a defined implied unit price.
  defp implied_price_quantity(entry, drift_value) do
    if Decimal.equal?(entry.quantity, @zero) or Decimal.equal?(entry.market_value, @zero) do
      nil
    else
      drift_value |> Decimal.mult(entry.quantity) |> Decimal.div(entry.market_value)
    end
  end

  # A SOLL-only row (#481: "this needs buying"): IST 0 across the board, the
  # full underweight drift, and — where a latest-quote base price exists — the
  # indicative buy quantity. Without a price the quantity stays nil; a price
  # is never invented.
  defp unheld_entry(target, unheld_prices, total) do
    drift_weight = Decimal.sub(@zero, target.target_weight)
    drift_value = Decimal.mult(drift_weight, total)
    price = Map.get(unheld_prices, target.security_id)

    rebalance_quantity =
      if is_nil(price) or Decimal.equal?(price, @zero) do
        nil
      else
        Decimal.div(drift_value, price)
      end

    %{
      security_id: target.security_id,
      security_name: target.security && target.security.name,
      quantity: @zero,
      market_value: @zero,
      weight: @zero,
      target_weight: target.target_weight,
      drift_weight: drift_weight,
      drift_value: drift_value,
      rebalance_quantity: rebalance_quantity,
      held: false
    }
  end

  defp sum_quantities(positions) do
    Enum.reduce(positions, @zero, &Decimal.add(&2, &1.quantity))
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

  defp row(
         category,
         depth,
         own_value,
         rolled_value,
         target,
         child_target_sum,
         flags,
         positions,
         total
       ) do
    actual = weight(rolled_value, total)
    target_weight = target || @zero
    drift_weight = Decimal.sub(actual, target_weight)

    %{
      category_id: category.id,
      parent_id: category.parent_id,
      depth: depth,
      name: category.name,
      color: category.color,
      own_market_value: own_value,
      market_value: rolled_value,
      actual_weight: actual,
      # The EFFECTIVE target (ADR-0030): the position sum when position rows
      # exist, else the explicit category weight; `conflict`/`has_stale`
      # surface a divergent explicit weight or a stale position row.
      target_weight: target_weight,
      drift_weight: drift_weight,
      drift_value: Decimal.mult(drift_weight, total),
      child_target_sum: child_target_sum,
      conflict: (flags && flags.conflict) || false,
      has_stale: (flags && flags.has_stale) || false,
      positions: positions
    }
  end

  # Display-only rebalancing hints (ADR-0023): each position's proportional
  # share of the category drift (weighted by market value within the rolled-up
  # subtree value) and that share as an indicative quantity at the position's
  # implied base-currency unit price (market_value / quantity — the same price
  # basis the valuation used). Positive = sell, negative = buy. Derived data
  # only; nothing here is persisted, and there is no fee/tax modelling. Both
  # multiplications happen before the division so exact fixtures stay exact
  # (ADR-0016: full precision in compute, round at display).
  defp with_rebalance_hints(row, false), do: row

  defp with_rebalance_hints(row, true) do
    if Decimal.equal?(row.market_value, @zero) do
      row
    else
      # An entry with its own position SOLL (ADR-0030 slice 2a) already
      # carries its own drift/hint from `attach_position_soll` — only the
      # SOLL-less entries receive the category-share figures, unchanged.
      positions =
        Enum.map(row.positions, fn
          %{target_weight: %Decimal{}} = position ->
            position

          position ->
            %{
              position
              | drift_value:
                  row.drift_value
                  |> Decimal.mult(position.market_value)
                  |> Decimal.div(row.market_value),
                rebalance_quantity: rebalance_quantity(position, row)
            }
        end)

      %{row | positions: positions}
    end
  end

  # No hint without a defined implied unit price: a zero quantity or a
  # zero-valued position (e.g. a stored 0 close) makes market_value/quantity
  # meaningless, and the qty-cancellation below would suggest trading a
  # worthless position.
  defp rebalance_quantity(position, row) do
    if Decimal.equal?(position.quantity, @zero) or
         Decimal.equal?(position.market_value, @zero) do
      nil
    else
      # share / unit_price = (drift × mv / rolled) / (mv / qty) = drift × qty / rolled.
      row.drift_value |> Decimal.mult(position.quantity) |> Decimal.div(row.market_value)
    end
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
