defmodule PortfolixirWeb.Api.V1.PolicyJSON do
  @moduledoc """
  The JSON shapes of the policy-rules family (ADR-0049): a rule, one of its
  versions, and a finding.

  Every threshold and every measured value crosses the boundary as a Decimal
  string (ADR-0016); the closed sets travel as strings. A finding carries the
  rule's words, the measured value and the line, and **no action** — no
  quantity, no trade verb, no recommendation (§6), which
  `test/invariants/findings_carry_no_action_test.exs` walks the payload for.
  """

  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRuleVersion
  alias PortfolixirWeb.Api.V1.JSON

  @doc "One rule, annotated relative to the read's `as_of` (list read)."
  def rule(%PolicyRule{} = rule) do
    %{
      id: rule.id,
      portfolio_id: rule.portfolio_id,
      view_id: rule.view_id,
      name: rule.name,
      status: rule.status && to_string(rule.status),
      version_in_force: version(rule.version_in_force),
      next_version: version(rule.next_version),
      inserted_at: JSON.timestamp(rule.inserted_at),
      updated_at: JSON.timestamp(rule.updated_at)
    }
  end

  @doc "One rule with its whole version history, oldest first (show read)."
  def rule_with_versions(%PolicyRule{} = rule) do
    rule
    |> rule()
    |> Map.put(:versions, Enum.map(rule.versions, &version/1))
  end

  @doc "One version: the predicate and the period it is the standard."
  def version(nil), do: nil

  def version(%PolicyRuleVersion{} = version) do
    %{
      id: version.id,
      policy_rule_id: version.policy_rule_id,
      subject_type: to_string(version.subject_type),
      security_id: version.security_id,
      classification_id: version.classification_id,
      category_id: version.category_id,
      subject_view_id: version.subject_view_id,
      measure: to_string(version.measure),
      kind: to_string(version.kind),
      threshold: JSON.decimal(version.threshold),
      lower: JSON.decimal(version.lower),
      upper: JSON.decimal(version.upper),
      window: version.window && to_string(version.window),
      severity: to_string(version.severity),
      note: version.note,
      valid_from: JSON.date(version.valid_from),
      valid_until: JSON.date(version.valid_until)
    }
  end
end
