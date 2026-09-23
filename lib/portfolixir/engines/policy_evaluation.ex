defmodule Portfolixir.Engines.PolicyEvaluation do
  @moduledoc """
  Evaluates the operator's policy rules (ADR-0049 §3, §5) over measures an
  existing read already produced.

  This is an **engine** (architecture D2/P3): pure functions over injected
  data — no `Repo`, no clock, no config. `Portfolixir.Portfolios.PolicyFindings`
  loads the rule versions in force and reads each measure off the payload that
  already serves it (the risk lens, the allocation breakdown, the portfolio
  metrics, the valuation); nothing here computes a figure of its own.

  ## A reading

  The measure map is keyed by `measure_key/1` and holds, per key, either

    * `%{value: Decimal.t(), basis: map()}` — the measure was read, on the
      rule's own scale; or
    * `%{undetermined: reason, basis: map()}` (plus `required` and
      `observations` for a refused metric) — it could not be.

  ## Three states, and undetermined never passes

    * `:ok` — read, and on the right side of the line;
    * `:breached` — read, and **strictly** beyond it: a cap strictly above its
      threshold, a floor strictly below, a band strictly outside
      `[lower, upper]` — the risk lens's own reading of a line (CM3), so the
      two never disagree about where one is;
    * `:undetermined` — not read, with its `reason`. A key the shell did not
      supply at all is `:not_measured`: absence is never a pass.

  A rule set that reads green because half its inputs were missing is the
  prose drift again with a check mark on it; that is why this is the
  invariant the property test pins.

  ## What a finding carries — and what it never does

  The rule's identity and words, the version, the thresholds, the measured
  `value`, the `state`, the signed `distance` (value − the nearest line, on
  the measure's scale — arithmetic, not a recommendation) and the reading's
  `computation_basis`. **No action**: no quantity, no trade verb, no
  suggestion (§6); `findings_carry_no_action_test.exs` walks the rendered
  payload for any such key.
  """

  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRuleVersion

  @type state :: :ok | :breached | :undetermined
  @type reading ::
          %{value: Decimal.t(), basis: map()}
          | %{required(:undetermined) => atom(), optional(atom()) => term()}
  @type finding :: %{atom() => term()}

  @state_order %{breached: 0, undetermined: 1, ok: 2}
  @severity_order %{hard: 0, warn: 1}

  @doc """
  The key a version's measure is read under — the one question the shell has
  to answer for it. Two versions asking the same question share one reading.
  """
  @spec measure_key(PolicyRuleVersion.t()) :: tuple()
  def measure_key(%PolicyRuleVersion{measure: :weight, subject_type: :security} = v),
    do: {:weight, :security, v.security_id}

  def measure_key(%PolicyRuleVersion{measure: :weight, subject_type: :category} = v),
    do: {:weight, :category, v.classification_id, v.category_id}

  def measure_key(%PolicyRuleVersion{measure: :weight, subject_type: :cash}),
    do: {:weight, :cash}

  def measure_key(%PolicyRuleVersion{measure: :weight, subject_type: :view} = v),
    do: {:weight, :view, v.subject_view_id}

  def measure_key(%PolicyRuleVersion{measure: :drift, subject_type: :category} = v),
    do: {:drift, :category, v.classification_id, v.category_id}

  def measure_key(%PolicyRuleVersion{measure: :drift, subject_type: :security} = v),
    do: {:drift, :security, v.classification_id, v.security_id}

  def measure_key(%PolicyRuleVersion{measure: :hhi}), do: {:hhi}

  def measure_key(%PolicyRuleVersion{measure: metric, window: window})
      when metric in [:volatility, :max_drawdown],
      do: {metric, window}

  @doc """
  One finding per `{rule, version}` pair, sorted breached, undetermined, ok —
  hard before warn within a state, then by rule id.
  """
  @spec evaluate([{PolicyRule.t(), PolicyRuleVersion.t()}], %{tuple() => reading()}) ::
          [finding()]
  def evaluate(pairs, measures) when is_list(pairs) and is_map(measures) do
    pairs
    |> Enum.map(fn {rule, version} ->
      finding(rule, version, Map.get(measures, measure_key(version)))
    end)
    |> Enum.sort_by(fn finding ->
      {Map.fetch!(@state_order, finding.state), Map.fetch!(@severity_order, finding.severity),
       finding.rule_id}
    end)
  end

  defp finding(rule, version, reading) do
    rule
    |> base(version)
    |> Map.merge(outcome(version, reading))
  end

  defp base(%PolicyRule{} = rule, %PolicyRuleVersion{} = version) do
    %{
      rule_id: rule.id,
      rule_name: rule.name,
      view_id: rule.view_id,
      version_id: version.id,
      valid_from: version.valid_from,
      valid_until: version.valid_until,
      subject_type: version.subject_type,
      security_id: version.security_id,
      classification_id: version.classification_id,
      category_id: version.category_id,
      subject_view_id: version.subject_view_id,
      measure: version.measure,
      window: version.window,
      kind: version.kind,
      severity: version.severity,
      threshold: version.threshold,
      lower: version.lower,
      upper: version.upper,
      note: version.note
    }
  end

  defp outcome(version, %{value: %Decimal{} = value} = reading) do
    %{
      state: if(breached?(version, value), do: :breached, else: :ok),
      value: value,
      distance: distance(version, value),
      reason: nil,
      required: nil,
      observations: nil,
      computation_basis: Map.get(reading, :basis)
    }
  end

  defp outcome(_version, %{undetermined: reason} = reading) when is_atom(reason) do
    undetermined(reason, reading)
  end

  defp outcome(_version, nil), do: undetermined(:not_measured, %{})

  defp undetermined(reason, reading) do
    %{
      state: :undetermined,
      value: nil,
      distance: nil,
      reason: reason,
      required: Map.get(reading, :required),
      observations: Map.get(reading, :observations),
      computation_basis: Map.get(reading, :basis)
    }
  end

  # Strictly beyond the line (CM3): on it is ok.
  defp breached?(%{kind: :cap, threshold: threshold}, value), do: gt?(value, threshold)
  defp breached?(%{kind: :floor, threshold: threshold}, value), do: gt?(threshold, value)

  defp breached?(%{kind: :band, lower: lower, upper: upper}, value),
    do: gt?(lower, value) or gt?(value, upper)

  # value − the nearest line. A cap or floor has one line; inside a band the
  # nearer of the two, outside it the one crossed.
  defp distance(%{kind: kind, threshold: threshold}, value) when kind in [:cap, :floor],
    do: Decimal.sub(value, threshold)

  defp distance(%{kind: :band, lower: lower, upper: upper}, value) do
    to_lower = Decimal.sub(value, lower)
    to_upper = Decimal.sub(value, upper)

    if Decimal.compare(Decimal.abs(to_lower), Decimal.abs(to_upper)) == :gt,
      do: to_upper,
      else: to_lower
  end

  defp gt?(a, b), do: Decimal.compare(a, b) == :gt
end
