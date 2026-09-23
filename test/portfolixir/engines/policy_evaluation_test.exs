defmodule Portfolixir.Engines.PolicyEvaluationTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Portfolixir.Engines.PolicyEvaluation
  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRuleVersion

  @basis %{source: "test", as_of: ~D[2026-09-23]}

  defp d(value), do: Decimal.new(value)

  defp pair(id, attrs) do
    rule = %PolicyRule{id: id, name: "Rule #{id}", portfolio_id: 1}

    version =
      struct(
        PolicyRuleVersion,
        Map.merge(
          %{
            id: id * 10,
            policy_rule_id: id,
            subject_type: :cash,
            measure: :weight,
            kind: :cap,
            threshold: d("10"),
            severity: :warn,
            valid_from: ~D[2026-01-01]
          },
          attrs
        )
      )

    {rule, version}
  end

  defp reading(value), do: %{value: d(value), basis: @basis}

  defp evaluate_one(attrs, reading) do
    {_rule, version} = rule_pair = pair(1, attrs)

    [finding] =
      PolicyEvaluation.evaluate([rule_pair], %{PolicyEvaluation.measure_key(version) => reading})

    finding
  end

  # User story (ADR-0049 §1, §5):
  # As the operator,
  # I want my own line read exactly the way the risk lens reads one,
  # so that a rule and the lens never disagree about where a line is.
  #
  # Acceptance criteria:
  # - A cap is breached strictly above its threshold, a floor strictly below,
  #   a band strictly outside [lower, upper]; on the line is ok (CM3).
  # - The finding carries the measured value and the signed distance to the
  #   nearest line on the measure's scale (value − line).
  test "reads a cap, a floor and a band strictly, with the signed distance" do
    assert %{state: :ok, distance: distance} = evaluate_one(%{}, reading("10"))
    assert Decimal.equal?(distance, d("0"))

    assert %{state: :breached, value: value, distance: over} =
             evaluate_one(%{}, reading("12.4"))

    assert Decimal.equal?(value, d("12.4"))
    assert Decimal.equal?(over, d("2.4"))

    floor = %{kind: :floor, threshold: d("5")}
    assert %{state: :ok} = evaluate_one(floor, reading("5"))
    assert %{state: :breached, distance: under} = evaluate_one(floor, reading("4.5"))
    assert Decimal.equal?(under, d("-0.5"))

    band = %{
      subject_type: :category,
      classification_id: 3,
      category_id: 4,
      measure: :drift,
      kind: :band,
      threshold: nil,
      lower: d("-3"),
      upper: d("3")
    }

    assert %{state: :ok, distance: inside} = evaluate_one(band, reading("-1.2"))
    # Inside a band the nearest line is the lower one here: -1.2 − (−3).
    assert Decimal.equal?(inside, d("1.8"))
    assert %{state: :breached, distance: past} = evaluate_one(band, reading("3.5"))
    assert Decimal.equal?(past, d("0.5"))
    assert %{state: :breached} = evaluate_one(band, reading("-3.01"))
    assert %{state: :ok} = evaluate_one(band, reading("3"))
  end

  # Acceptance criteria (ADR-0049 §3 — the invariant this record exists for):
  # - A measure that could not be read makes the finding `undetermined`,
  #   never `ok`, with its reason; a refused metric carries `required` and
  #   `observations`.
  # - A measure the shell did not supply at all is `undetermined` too
  #   (`not_measured`) — absence is never a pass.
  test "an unreadable measure is undetermined with its reason, never ok" do
    refused = %{
      undetermined: :insufficient_data,
      required: 20,
      observations: 14,
      basis: @basis
    }

    vol = %{
      subject_type: :basis,
      measure: :volatility,
      window: :"90d",
      threshold: d("15")
    }

    assert %{state: :undetermined, reason: :insufficient_data, required: 20, observations: 14} =
             finding = evaluate_one(vol, refused)

    assert finding.value == nil
    assert finding.distance == nil

    {_rule, version} = rule_pair = pair(2, %{})

    assert [%{state: :undetermined, reason: :not_measured}] =
             PolicyEvaluation.evaluate([rule_pair], %{})

    assert PolicyEvaluation.measure_key(version) == {:weight, :cash}
  end

  property "no undetermined reading ever evaluates to ok or breached" do
    check all(
            reason <-
              member_of([
                :insufficient_data,
                :no_active_plan,
                :no_target,
                :subject_not_found,
                :empty_basis
              ]),
            kind <- member_of([:cap, :floor, :band]),
            threshold <- integer(-100..100)
          ) do
      attrs =
        case kind do
          :band -> %{kind: :band, threshold: nil, lower: d(threshold), upper: d(threshold + 1)}
          other -> %{kind: other, threshold: d(threshold)}
        end

      finding = evaluate_one(attrs, %{undetermined: reason, basis: @basis})
      assert finding.state == :undetermined
      assert finding.reason == reason
    end
  end

  # Acceptance criteria (ADR-0049 §9):
  # - Findings sort breached first, then undetermined, then ok; within a
  #   state hard before warn, then by rule.
  test "sorts breached, undetermined, ok — hard before warn" do
    pairs = [
      pair(1, %{severity: :warn}),
      pair(2, %{measure: :hhi, subject_type: :basis, threshold: d("2500")}),
      pair(3, %{severity: :hard, subject_type: :security, security_id: 9}),
      pair(4, %{severity: :hard})
    ]

    measures = %{
      {:weight, :cash} => reading("12"),
      {:weight, :security, 9} => reading("1")
    }

    assert [4, 1, 2, 3] = pairs |> PolicyEvaluation.evaluate(measures) |> Enum.map(& &1.rule_id)
  end

  # Acceptance criteria (ADR-0049 §5, AGENTS.md metric-basis rule):
  # - Every finding carries the computation basis of the reading it used.
  test "every finding carries its computation basis" do
    assert %{computation_basis: @basis} = evaluate_one(%{}, reading("3"))
  end
end
