defmodule Portfolixir.Portfolios.PolicyFindingsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.PolicyFindings
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.Risk
  alias Portfolixir.Portfolios.Targets

  defp today, do: Portfolixir.Clock.today()
  defp d(value), do: Decimal.new(value)

  # A young portfolio (five days of history, so every portfolio metric
  # refuses): 10 000 deposited, 1 000 in Alpha and 4 000 in Beta, 5 000 cash.
  # Risk basis (valued positions) 5 000 → Alpha 20 %, Beta 80 %, HHI 6 800.
  # Allocation basis (positions + deployable cash) 10 000 → cash 50 %.
  setup do
    world = base_world(name: "Findings")
    alpha = create_security!(name: "Alpha Timber AB", ticker: "ALP")
    beta = create_security!(name: "Beta Solar SE", ticker: "BET")
    start = Date.add(today(), -5)

    deposit!(world, "10000", start)
    buy!(world, alpha, quantity: "10", price: "100", date: start)
    buy!(world, beta, quantity: "40", price: "100", date: start)
    put_quote!(alpha, start, "100")
    put_quote!(beta, start, "100")

    {:ok, tree} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, growth} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Growth"
      })

    {:ok, _} = Classifications.assign_security(Actor.owner_ui(), alpha.id, tree.id, growth.id)

    %{world: world, alpha: alpha, beta: beta, tree: tree, growth: growth}
  end

  defp rule!(world, name, version, opts \\ []) do
    {:ok, rule} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          view_id: Keyword.get(opts, :view_id),
          name: name,
          version: version
        },
        today: Keyword.get(opts, :today, today())
      )

    rule
  end

  defp finding(result, rule), do: Enum.find(result.findings, &(&1.rule_id == rule.id))

  # User story (FR-43, ADR-0049 §2, §5):
  # As the operator's agent on a scheduled run,
  # I want one read that tells me which of the operator's rules hold,
  # so that "am I inside my limits?" is answered from the figures the
  # instance already serves and not from my own arithmetic.
  #
  # Acceptance criteria:
  # - Each measure is the figure an existing read already produces, on the
  #   rule's scale: the risk lens's merged single-name weight and HHI, the
  #   allocation's category and cash weight (fractions × 100).
  # - A cap strictly above, a floor strictly below, is breached; on the line
  #   is ok.
  # - Each finding carries its computation basis naming the source read.
  test "evaluates weight, cash and HHI rules over the figures the reads serve",
       %{world: world, alpha: alpha, tree: tree, growth: growth} do
    single =
      rule!(world, "Single name at most 10 %", %{
        subject_type: "security",
        security_id: alpha.id,
        measure: "weight",
        kind: "cap",
        threshold: "10",
        severity: "hard"
      })

    cash =
      rule!(world, "Cash floor", %{
        subject_type: "cash",
        measure: "weight",
        kind: "floor",
        threshold: "60",
        severity: "warn"
      })

    hhi =
      rule!(world, "HHI", %{
        subject_type: "basis",
        measure: "hhi",
        kind: "cap",
        threshold: "7000",
        severity: "warn"
      })

    growth_weight =
      rule!(world, "Growth at most 10 %", %{
        subject_type: "category",
        classification_id: tree.id,
        category_id: growth.id,
        measure: "weight",
        kind: "cap",
        threshold: "10",
        severity: "warn"
      })

    result = PolicyFindings.for_portfolio(world.portfolio.id)

    risk = Risk.for_portfolio(world.portfolio.id, top_n: 10)
    alpha_weight = Enum.find(risk.top_holdings, &(&1.security_id == alpha.id)).weight

    assert %{state: :breached, value: value, distance: distance} = finding(result, single)
    assert Decimal.equal?(value, alpha_weight)
    assert Decimal.equal?(value, d("20"))
    assert Decimal.equal?(distance, d("10"))
    assert finding(result, single).computation_basis.source =~ "risk"

    assert %{state: :breached, value: cash_value} = finding(result, cash)
    assert Decimal.equal?(cash_value, d("50"))

    assert %{state: :ok, value: hhi_value} = finding(result, hhi)
    assert Decimal.equal?(hhi_value, risk.hhi.value)

    {:ok, allocation} = Allocation.for_portfolio(world.portfolio.id, tree.id)
    row = Enum.find(allocation.categories, &(&1.category_id == growth.id))

    assert %{state: :ok, value: growth_value} = finding(result, growth_weight)
    assert Decimal.equal?(growth_value, Decimal.mult(row.actual_weight, 100))

    assert result.summary == %{breached: 2, undetermined: 0, ok: 2}
  end

  # User story (ADR-0049 §3 — the invariant the record exists for):
  # As the operator,
  # I want a rule whose figure cannot be read to say so,
  # so that a rule set never reads green because its inputs were missing.
  #
  # Acceptance criteria:
  # - A rule over a refused portfolio metric is `undetermined` with reason
  #   `insufficient_data`, and carries ADR-0047's `required` and the
  #   observations it had.
  # - A drift rule whose context has no active plan is `undetermined`
  #   (`no_active_plan`); one whose plan has no target for the subject is
  #   `undetermined` (`no_target`).
  # - Undetermined findings are in the default read, never filtered out and
  #   never counted as ok.
  test "a refused metric, a missing plan and a missing target are undetermined, never ok",
       %{world: world, alpha: alpha, beta: beta, tree: tree, growth: growth} do
    vol =
      rule!(world, "Volatility under 15 %", %{
        subject_type: "basis",
        measure: "volatility",
        window: "90d",
        kind: "cap",
        threshold: "15",
        severity: "warn"
      })

    drift =
      rule!(world, "Growth in band", %{
        subject_type: "category",
        classification_id: tree.id,
        category_id: growth.id,
        measure: "drift",
        kind: "band",
        lower: "-3",
        upper: "3",
        severity: "warn"
      })

    beta_drift =
      rule!(world, "Beta near target", %{
        subject_type: "security",
        security_id: beta.id,
        classification_id: tree.id,
        measure: "drift",
        kind: "band",
        lower: "-3",
        upper: "3",
        severity: "warn"
      })

    result = PolicyFindings.for_portfolio(world.portfolio.id)

    assert %{state: :undetermined, reason: :insufficient_data, required: 20, observations: n} =
             finding(result, vol)

    assert n < 20
    assert %{state: :undetermined, reason: :no_active_plan} = finding(result, drift)
    assert %{state: :undetermined, reason: :no_active_plan} = finding(result, beta_drift)
    assert result.summary.undetermined == 3
    assert result.summary.ok == 0

    # A plan now exists — but it carries a target for Alpha's position only.
    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, tree.id, [
        %{"category_id" => growth.id, "security_id" => alpha.id, "target_weight" => "0.1"}
      ])

    result = PolicyFindings.for_portfolio(world.portfolio.id)

    # The category's effective target rolls up from its position (ADR-0030).
    assert %{state: state} = finding(result, drift)
    assert state in [:ok, :breached]
    assert %{state: :undetermined, reason: :no_target} = finding(result, beta_drift)
  end

  # Acceptance criteria (ADR-0049 §2):
  # - A drift rule reads the allocation's drift of the context's active
  #   plan, in percentage points (drift_weight × 100), for a category and for
  #   a security carrying a position target.
  test "reads drift off the active plan, in percentage points",
       %{world: world, alpha: alpha, tree: tree, growth: growth} do
    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, tree.id, [
        %{"category_id" => growth.id, "target_weight" => "0.3"}
      ])

    drift =
      rule!(world, "Growth in band", %{
        subject_type: "category",
        classification_id: tree.id,
        category_id: growth.id,
        measure: "drift",
        kind: "band",
        lower: "-3",
        upper: "3",
        severity: "warn"
      })

    {:ok, allocation} = Allocation.for_portfolio(world.portfolio.id, tree.id)
    row = Enum.find(allocation.categories, &(&1.category_id == growth.id))

    assert %{state: :breached, value: value} =
             world.portfolio.id |> PolicyFindings.for_portfolio() |> finding(drift)

    assert Decimal.equal?(value, Decimal.mult(row.drift_weight, 100))

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, tree.id, [
        %{"category_id" => growth.id, "security_id" => alpha.id, "target_weight" => "0.1"}
      ])

    position =
      rule!(world, "Alpha near its target", %{
        subject_type: "security",
        security_id: alpha.id,
        classification_id: tree.id,
        measure: "drift",
        kind: "cap",
        threshold: "50",
        severity: "warn"
      })

    {:ok, allocation} = Allocation.for_portfolio(world.portfolio.id, tree.id)

    entry =
      allocation.categories
      |> Enum.flat_map(& &1.positions)
      |> Enum.find(&(&1.security_id == alpha.id))

    assert %{state: :ok, value: position_value} =
             world.portfolio.id |> PolicyFindings.for_portfolio() |> finding(position)

    assert Decimal.equal?(position_value, Decimal.mult(entry.drift_weight, 100))
  end

  # Acceptance criteria (ADR-0049 §1, §2 — the bucket scope):
  # - A view subject's weight is its steerable basis over the context's.
  # - A rule in a view context is evaluated only in that context.
  test "a view subject is weighed against the context; a view context only in itself",
       %{world: world} do
    {:ok, everything} = Buckets.create_view(Actor.owner_ui(), %{name: "Alles hier"})

    whole =
      rule!(world, "Nothing is more than half", %{
        subject_type: "view",
        subject_view_id: everything.id,
        measure: "weight",
        kind: "cap",
        threshold: "50",
        severity: "hard"
      })

    scoped =
      rule!(
        world,
        "Only in the view",
        %{
          subject_type: "basis",
          measure: "hhi",
          kind: "cap",
          threshold: "10000",
          severity: "warn"
        },
        view_id: everything.id
      )

    result = PolicyFindings.for_portfolio(world.portfolio.id)
    assert %{state: :breached, value: value} = finding(result, whole)
    assert Decimal.equal?(value, d("100"))
    refute finding(result, scoped)

    in_view = PolicyFindings.for_portfolio(world.portfolio.id, view: everything.id)
    assert %{state: :ok} = finding(in_view, scoped)
    refute finding(in_view, whole)
  end

  # Acceptance criteria (ADR-0049 §5):
  # - The read is memoised under the portfolio basis AND the rules counter,
  #   so an edited cap is evaluated on the very next read.
  # - status= narrows the findings; the summary still counts them all.
  test "an edited rule is evaluated on the next read; status narrows",
       %{world: world, alpha: alpha} do
    rule =
      rule!(
        world,
        "Single name at most 10 %",
        %{
          subject_type: "security",
          security_id: alpha.id,
          measure: "weight",
          kind: "cap",
          threshold: "10",
          severity: "hard",
          valid_from: Date.add(today(), -3)
        },
        today: Date.add(today(), -3)
      )

    assert %{state: :breached} =
             world.portfolio.id |> PolicyFindings.for_portfolio() |> finding(rule)

    {:ok, _} =
      PolicyRules.add_version(Actor.owner_ui(), rule, %{
        subject_type: "security",
        security_id: alpha.id,
        measure: "weight",
        kind: "cap",
        threshold: "25",
        severity: "hard"
      })

    result = PolicyFindings.for_portfolio(world.portfolio.id)
    assert %{state: :ok, threshold: threshold} = finding(result, rule)
    assert Decimal.equal?(threshold, d("25"))

    narrowed = PolicyFindings.for_portfolio(world.portfolio.id, status: [:breached])
    assert narrowed.findings == []
    assert narrowed.summary == %{breached: 0, undetermined: 0, ok: 1}
  end
end
