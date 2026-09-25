defmodule Portfolixir.Portfolios.PolicyFindings do
  @moduledoc """
  The findings read (ADR-0049 §5): the operator's policy rules in force today
  for one evaluation context, evaluated over the figures the product already
  serves.

  The **shell** half of the engine/shell split (AR-2). It loads the rule
  versions in force (`PolicyRules.in_force/3`), reads each measure **off an
  existing payload** — it computes no figure of its own — and hands both to
  the pure `Portfolixir.Engines.PolicyEvaluation`:

  | Measure | Subject | Read off |
  |---|---|---|
  | `weight` | security | `Risk` — the lens's merged single-name weight over the steerable basis |
  | `hhi` | basis | `Risk` — the lens's HHI |
  | `weight` | category, cash | `Allocation` — the actual weight (a fraction, × 100); cash through `Allocation.cash_weight/2`, the same share under any tree |
  | `drift` | category, security | `Allocation` — the drift of the active plan (a fraction, × 100 = percentage points) |
  | `weight` | view | `Valuation` — the subject view's steerable basis over the context's |
  | `volatility`, `max_drawdown` | basis | `RiskMetrics` — ADR-0047's figure at the rule's window (a ratio, × 100) |

  Every measure is read in the rule's **context**: the portfolio, scoped by
  the context view when the rule has one.

  ## Undetermined never passes (§3)

  A measure that cannot be read becomes an `undetermined` reading with its
  reason, never a zero and never a pass: a refused metric
  (`insufficient_data`, with ADR-0047's `required` and `observations`), an
  undefined one (`undefined`), a drift with no active plan
  (`no_active_plan`) or no target for its subject (`no_target`), a subject
  that no longer exists (`subject_not_found`), a subject held but not
  valued (`unvalued` — outside the steerable basis, so it has no weight to
  read), and a context whose basis is empty (`empty_basis` — a weight of
  nothing is not 0 %, it is undefined).
  A security that is simply not held has a weight of `0`: that *is* a
  reading, and a floor on it can breach.

  ## Registry

  `policy_findings` registers with ADR-0039 at computation version 1 and
  lifetime `:request`, keyed under `Derived.portfolio_basis/1` — every write
  that moves a measure bumps it — **and** the portfolio's rules counter
  (`Derived.rules_basis/1`), carried in the entry key, which every rule write
  bumps. Evaluation is **today only** (§5): a historical finding would need
  the valuation walk at that date and is FR-48's input, deferred.
  """

  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Clock
  alias Portfolixir.Derived
  alias Portfolixir.Engines.PolicyEvaluation
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.PricingContext
  alias Portfolixir.Portfolios.Risk
  alias Portfolixir.Portfolios.RiskMetrics
  alias Portfolixir.Portfolios.Valuation

  @zero Decimal.new(0)
  @hundred Decimal.new(100)
  @states [:breached, :undetermined, :ok]

  @doc "The finding states, in the order a reader meets them."
  @spec states() :: [atom()]
  def states, do: @states

  @doc """
  The findings of the rules in force today for `portfolio_id` in one context.

  Options:

    * `:view` — the context view id (`nil`: the portfolio-wide context);
    * `:status` — a list of states to keep (default: all three). The
      `summary` always counts every finding;
    * `:today` — the evaluation date (default the host's today).

  Returns `%{portfolio_id, view_id, as_of, findings, summary}` or
  `{:error, :view_not_found}`.
  """
  @spec for_portfolio(integer(), keyword()) :: map() | {:error, :view_not_found}
  def for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    view_id = Keyword.get(opts, :view)
    today = Keyword.get(opts, :today) || Clock.today()

    with :ok <- view_exists(view_id) do
      {:fresh, findings} =
        Derived.fetch(
          :policy_findings,
          Derived.portfolio_basis(portfolio_id),
          entry_key(portfolio_id, view_id, today),
          fn -> evaluate(portfolio_id, view_id, today) end
        )

      %{
        portfolio_id: portfolio_id,
        view_id: view_id,
        as_of: today,
        summary: summary(findings),
        findings: keep(findings, Keyword.get(opts, :status))
      }
    end
  end

  defp view_exists(nil), do: :ok

  defp view_exists(view_id) when is_integer(view_id) do
    if Buckets.get_view(view_id), do: :ok, else: {:error, :view_not_found}
  end

  defp entry_key(portfolio_id, view_id, today) do
    rules_version = Derived.current_version(Derived.rules_basis(portfolio_id))
    "view=#{view_id || "unscoped"}|as_of=#{today}|rules=#{rules_version}"
  end

  defp summary(findings) do
    counts = Enum.frequencies_by(findings, & &1.state)
    Map.new(@states, &{&1, Map.get(counts, &1, 0)})
  end

  defp keep(findings, nil), do: findings

  defp keep(findings, states) when is_list(states),
    do: Enum.filter(findings, &(&1.state in states))

  defp evaluate(portfolio_id, view_id, today) do
    pairs = PolicyRules.in_force(portfolio_id, view_id, today)

    keys =
      pairs
      |> Enum.map(fn {_rule, version} -> PolicyEvaluation.measure_key(version) end)
      |> Enum.uniq()

    sources = %{portfolio_id: portfolio_id, view_id: view_id, today: today, keys: keys}
    loaded = load(sources)

    measures = Map.new(keys, &{&1, read(&1, loaded, sources)})
    PolicyEvaluation.evaluate(pairs, measures)
  end

  # -- loading: each source once, only when a rule needs it ------------------

  defp load(%{keys: []}), do: %{}

  # The context is valued ONCE (E25 S4, F74): the lens, the breakdowns, the
  # cash share, the context total, the unvalued set and a view subject's
  # membership are all read off that one valuation, and its pricing pass
  # (ADR-0035) is shared with the subject views, which cost one valuation
  # each. A vanished context view leaves `context` nil, which every read
  # answers as before: an empty basis or a subject not found.
  defp load(%{portfolio_id: pid, view_id: view_id, today: today, keys: keys}) do
    context = lazy_if(Enum.any?(keys, &(not metric_key?(&1))), fn -> context(pid, view_id) end)
    valuation = context && context.valuation

    %{
      context: context,
      risk: lazy_if(Enum.any?(keys, &risk_key?/1), fn -> risk(pid, view_id, valuation) end),
      allocations: allocations(pid, view_id, keys, valuation),
      cash:
        lazy_if({:weight, :cash} in keys, fn ->
          valuation && Allocation.cash_weight(pid, view: view_id, valuation: valuation)
        end),
      metrics:
        lazy_if(Enum.any?(keys, &metric_key?/1), fn ->
          RiskMetrics.for_portfolio(pid, [], view: view_id, as_of: today)
        end),
      context_total: valuation && valuation.total_value,
      unvalued:
        lazy_if(Enum.any?(keys, &unvalued_key?/1), fn -> unvalued_security_ids(valuation) end)
    }
  end

  defp context(pid, view_id) do
    pricing = PricingContext.for_portfolio(pid, base_currency(pid))

    case Valuation.for_portfolio(pid, view: view_id, pricing_context: pricing) do
      %{} = valuation -> %{valuation: valuation, pricing: pricing}
      _vanished -> nil
    end
  end

  defp base_currency(pid) do
    case Portfolios.get_portfolio(pid) do
      %{base_currency_code: code} -> code
      _gone -> nil
    end
  end

  defp lazy_if(true, fun), do: fun.()
  defp lazy_if(false, _fun), do: nil

  defp unvalued_key?({:weight, :security, _}), do: true
  defp unvalued_key?({:weight, :category, _, _}), do: true
  defp unvalued_key?(_key), do: false

  # The positions held but not valued (a quote with no rate, no price at all):
  # they are outside the steerable basis, so a subject made only of them has
  # no weight to read — which is not 0 % (ADR-0049 §4, never a pass).
  defp unvalued_security_ids(%{positions: positions}),
    do: for(%{valued: false, security_id: id} <- positions, into: MapSet.new(), do: id)

  defp unvalued_security_ids(_vanished), do: MapSet.new()

  defp risk_key?({:weight, :security, _}), do: true
  defp risk_key?({:hhi}), do: true
  defp risk_key?(_key), do: false

  defp metric_key?({metric, _window}) when metric in [:volatility, :max_drawdown], do: true
  defp metric_key?(_key), do: false

  defp risk(_pid, _view_id, nil), do: nil

  defp risk(pid, view_id, valuation) do
    Risk.for_portfolio(pid, view: view_id, top_n: :all, metrics: false, valuation: valuation)
  end

  # One breakdown per classification a rule reads. Cash needs none: its share
  # is the same under every tree (`Allocation.cash_weight/2`).
  defp allocations(_pid, _view_id, _keys, nil), do: %{}

  defp allocations(pid, view_id, keys, valuation) do
    classification_ids =
      keys
      |> Enum.flat_map(fn
        {_measure, :category, classification_id, _category_id} -> [classification_id]
        {:drift, :security, classification_id, _security_id} -> [classification_id]
        _other -> []
      end)
      |> Enum.uniq()

    Map.new(classification_ids, fn classification_id ->
      {classification_id,
       Allocation.for_portfolio(pid, classification_id, view: view_id, valuation: valuation)}
    end)
  end

  # The subject view's valued positions that lie inside the context (§2: the
  # weight is a share of the context's basis, 0–100). Portfolio-wide, that is
  # the subject's whole basis; inside a view, only the positions both views
  # hold count — the membership read off the context's one valuation.
  defp subject_total(_pid, _subject_view_id, _context_view_id, nil), do: nil

  defp subject_total(pid, subject_view_id, context_view_id, context) do
    case Valuation.for_portfolio(pid, view: subject_view_id, pricing_context: context.pricing) do
      %{total_value: total} when is_nil(context_view_id) ->
        total

      %{positions: subject} ->
        inside =
          MapSet.new(context.valuation.positions, &{&1.securities_account_id, &1.security_id})

        subject
        |> Enum.filter(
          &(&1.valued and MapSet.member?(inside, {&1.securities_account_id, &1.security_id}))
        )
        |> Enum.reduce(@zero, &Decimal.add(&1.market_value, &2))

      _vanished ->
        nil
    end
  end

  # -- reading: one measure off its loaded source ------------------------------

  defp read({:weight, :security, security_id}, %{risk: risk} = loaded, sources) do
    with_basis(risk_basis(sources), fn ->
      with {:ok, risk} <- present(risk),
           :ok <- non_empty(risk.steerable_basis) do
        case Enum.find(risk.top_holdings, &(&1.security_id == security_id)) do
          nil -> unheld_or_unvalued(loaded, [security_id])
          exposure -> {:ok, exposure.weight}
        end
      end
    end)
  end

  defp read({:hhi}, %{risk: risk}, sources) do
    with_basis(risk_basis(sources), fn ->
      with {:ok, risk} <- present(risk),
           :ok <- non_empty(risk.steerable_basis) do
        {:ok, risk.hhi.value}
      end
    end)
  end

  defp read({:weight, :category, classification_id, category_id}, loaded, sources) do
    with_basis(allocation_basis(sources, "actual_weight × 100"), fn ->
      with {:ok, allocation} <- allocation(loaded, classification_id),
           :ok <- non_empty(allocation.total_value) do
        case find_row(allocation, category_id) do
          %{actual_weight: weight} -> {:ok, percent(weight)}
          nil -> absent_category(loaded, classification_id, category_id)
        end
      end
    end)
  end

  defp read({:weight, :cash}, %{cash: cash}, sources) do
    with_basis(allocation_basis(sources, "cash.actual_weight × 100"), fn ->
      with {:ok, cash} <- present(cash),
           :ok <- non_empty(cash.total_value) do
        {:ok, percent(cash.actual_weight)}
      end
    end)
  end

  defp read(
         {:weight, :view, subject_view_id},
         %{context_total: context_total, context: context},
         sources
       ) do
    basis = %{
      source:
        "valuation: the subject view's steerable basis (its valued positions) within the " <>
          "context — inside a view context, only the positions both views hold — over the " <>
          "context's steerable basis, × 100",
      scale: "percent of the context's steerable basis",
      as_of: sources.today,
      view_id: sources.view_id
    }

    with_basis(basis, fn ->
      with :ok <- non_empty(context_total),
           subject when not is_nil(subject) <-
             subject_total(sources.portfolio_id, subject_view_id, sources.view_id, context) do
        {:ok, subject |> Decimal.div(context_total) |> Decimal.mult(@hundred)}
      else
        nil -> {:undetermined, :subject_not_found}
        other -> other
      end
    end)
  end

  defp read({:drift, :category, classification_id, category_id}, loaded, sources) do
    with_basis(
      drift_basis(
        loaded,
        classification_id,
        sources,
        "drift_weight × 100 (actual − target of the active plan)"
      ),
      fn ->
        with {:ok, allocation} <- allocation(loaded, classification_id),
             :ok <- non_empty(allocation.total_value),
             :ok <- has_plan(allocation) do
          case find_row(allocation, category_id) do
            %{has_target: true, drift_weight: drift} -> {:ok, percent(drift)}
            _untargeted -> {:undetermined, :no_target}
          end
        end
      end
    )
  end

  defp read({:drift, :security, classification_id, security_id}, loaded, sources) do
    basis =
      drift_basis(
        loaded,
        classification_id,
        sources,
        "the position's drift_weight × 100 (ADR-0030)"
      )

    with_basis(basis, fn ->
      with {:ok, allocation} <- allocation(loaded, classification_id),
           :ok <- non_empty(allocation.total_value),
           :ok <- has_plan(allocation) do
        case find_position(allocation, security_id) do
          %{target_weight: %Decimal{}, drift_weight: %Decimal{} = drift} -> {:ok, percent(drift)}
          _untargeted -> {:undetermined, :no_target}
        end
      end
    end)
  end

  defp read({metric, window}, %{metrics: metrics}, sources) do
    label = Atom.to_string(window)

    basis = %{
      source:
        "portfolio metrics (ADR-0047): #{metric} over the #{label} window of the TTWROR " <>
          "chain's flow-adjusted daily return factors, a ratio × 100",
      scale: "percent",
      window: label,
      as_of: sources.today,
      view_id: sources.view_id
    }

    case metrics do
      %{^metric => %{^label => %{insufficient_data: true} = figure}} ->
        %{
          undetermined: :insufficient_data,
          required: figure.required,
          observations: figure.observations,
          basis: basis
        }

      %{^metric => %{^label => %{value: %Decimal{} = value}}} ->
        %{value: percent(value), basis: basis}

      %{^metric => %{^label => %{value: nil}}} ->
        %{undetermined: :undefined, basis: basis}

      _unreadable ->
        %{undetermined: :subject_not_found, basis: basis}
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp with_basis(basis, fun) do
    case fun.() do
      {:ok, %Decimal{} = value} -> %{value: value, basis: basis}
      {:undetermined, reason} -> %{undetermined: reason, basis: basis}
    end
  end

  defp present(%{} = source), do: {:ok, source}
  defp present(_missing), do: {:undetermined, :subject_not_found}

  defp non_empty(%Decimal{} = total) do
    if Decimal.compare(total, @zero) == :gt, do: :ok, else: {:undetermined, :empty_basis}
  end

  defp non_empty(_missing), do: {:undetermined, :empty_basis}

  defp has_plan(%{has_plan: true}), do: :ok
  defp has_plan(_allocation), do: {:undetermined, :no_active_plan}

  defp allocation(%{allocations: allocations}, classification_id) do
    case Map.get(allocations, classification_id) do
      {:ok, allocation} -> {:ok, allocation}
      _missing -> {:undetermined, :subject_not_found}
    end
  end

  defp find_row(allocation, category_id),
    do: Enum.find(allocation.categories, &(&1.category_id == category_id))

  defp find_position(allocation, security_id) do
    unassigned = if allocation.unassigned, do: allocation.unassigned.positions, else: []

    allocation.categories
    |> Enum.flat_map(& &1.positions)
    |> Enum.concat(unassigned)
    |> Enum.find(&(&1.security_id == security_id and not is_nil(&1.target_weight)))
  end

  # A category the breakdown leaves out has neither value nor target: its
  # weight is 0, a reading — unless it no longer belongs to the classification,
  # or its members are held but unvalued (then there is nothing to read).
  defp absent_category(loaded, classification_id, category_id) do
    case Classifications.get_category(category_id) do
      %Category{classification_id: ^classification_id} ->
        unheld_or_unvalued(loaded, members_under(classification_id, category_id))

      _gone ->
        {:undetermined, :subject_not_found}
    end
  end

  # Not in the steerable basis: 0 % when nothing of it is held, undetermined
  # when something of it is held and could not be valued.
  defp unheld_or_unvalued(loaded, security_ids) do
    unvalued = Map.get(loaded, :unvalued) || MapSet.new()

    if Enum.any?(security_ids, &MapSet.member?(unvalued, &1)),
      do: {:undetermined, :unvalued},
      else: {:ok, @zero}
  end

  # The securities assigned to the category or to any category below it.
  defp members_under(classification_id, category_id) do
    categories = Classifications.list_categories(classification_id)
    subtree = subtree_ids(categories, MapSet.new([category_id]))

    case Classifications.security_category_map(classification_id) do
      {:ok, map} -> for {security_id, cid} <- map, MapSet.member?(subtree, cid), do: security_id
      {:error, _} -> []
    end
  end

  defp subtree_ids(categories, ids) do
    grown =
      categories
      |> Enum.filter(&(&1.parent_id in ids))
      |> Enum.map(& &1.id)
      |> MapSet.new()
      |> MapSet.union(ids)

    if MapSet.size(grown) == MapSet.size(ids), do: ids, else: subtree_ids(categories, grown)
  end

  defp percent(%Decimal{} = fraction), do: Decimal.mult(fraction, @hundred)

  defp risk_basis(sources) do
    %{
      source:
        "risk lens: the merged single-name weight and the HHI over the steerable basis " <>
          "(the valued positions, scoped by the context view)",
      scale: "percent of the steerable basis; HHI 0-10000",
      as_of: sources.today,
      view_id: sources.view_id
    }
  end

  # A drift names the base it moves against: the allocation renormalises a plan
  # that covers less than 100 % over its allocated portion (target / Σ
  # targets), and a reader who assumed plain actual − target would misread the
  # figure (AGENTS.md: the computation basis travels in the payload).
  defp drift_basis(loaded, classification_id, sources, figure) do
    base = allocation_basis(sources, figure)

    case allocation(loaded, classification_id) do
      {:ok, %{drift_basis: "allocated_portion"}} ->
        %{
          base
          | source:
              base.source <>
                "; the plan's targets sum to less than 100 %, so each target is renormalised " <>
                "over the allocated portion (target / Σ targets) and the drift is actual − that " <>
                "renormalised target"
        }
        |> Map.put(:drift_basis, "allocated_portion")

      {:ok, %{drift_basis: drift_basis}} ->
        Map.put(base, :drift_basis, drift_basis)

      _no_allocation ->
        base
    end
  end

  defp allocation_basis(sources, figure) do
    %{
      source:
        "allocation breakdown: #{figure}, over the steering basis (valued positions plus " <>
          "deployable cash, scoped by the context view)",
      scale: "percent of the steering basis; drift in percentage points",
      as_of: sources.today,
      view_id: sources.view_id
    }
  end
end
