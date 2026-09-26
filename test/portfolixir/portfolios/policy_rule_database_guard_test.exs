defmodule Portfolixir.Portfolios.PolicyRuleDatabaseGuardTest do
  # E25 S6 (#891), F51, decision T-3: the database's own guard on the policy
  # tables was narrower than ADR-0049 §4 states. It refused a change to a
  # version in force, but not a change to a scheduled version's start, rule
  # or predicate, not a change to a rule's context, and not a TRUNCATE of
  # either table. A new migration extends the update guard to every
  # version's identity, predicate and start date, guards the rule's identity
  # and context, and refuses TRUNCATE on both tables. No insert trigger
  # (T-3): the bounded date and the context's refusal are the two layers on
  # the insert side.
  #
  # async: false — a TRUNCATE takes a lock on the table that every
  # concurrent policy-rule test would wait on until this test ends.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios.PolicyRules

  defp today, do: Portfolixir.Clock.today()

  defp weight_cap(security, attrs) do
    Map.merge(
      %{
        subject_type: "security",
        security_id: security.id,
        measure: "weight",
        kind: "cap",
        threshold: "10",
        severity: "hard"
      },
      attrs
    )
  end

  defp rule!(portfolio, security, attrs \\ %{}) do
    {:ok, rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Single name at most 10 %",
        version: weight_cap(security, attrs)
      })

    rule
  end

  # A raw statement with the journal actor set, so the journal guard is not
  # what refuses it; the rolled-back savepoint keeps the sandbox usable.
  defp raw(sql, params) do
    Repo.transaction(fn ->
      Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")
      Repo.query!(sql, params)
    end)
  end

  defp assert_restricted(sql, params \\ []) do
    error = assert_raise Postgrex.Error, fn -> raw(sql, params) end
    assert error.postgres.code == :restrict_violation, "#{sql} failed with #{inspect(error)}"
  end

  setup do
    world = base_world(name: "Guard Portfolio")
    other = base_world(name: "Other Guard Portfolio")
    security = create_security!(name: "Fjord Guard Energy ASA", ticker: "FGE")
    %{world: world, other: other, security: security}
  end

  # User story:
  # As the operator relying on "what was the standard on date D" being a
  # read,
  # I want the database itself to refuse a raw write that moves a scheduled
  # version into the past, onto another rule, or to another predicate,
  # so that no path around the context can backdate or re-parent a standard.
  #
  # Acceptance criteria:
  # - A raw UPDATE of a scheduled version's valid_from, policy_rule_id, id or
  #   predicate raises restrict_violation.
  # - Its valid_until and updated_at stay writable: that is how the context
  #   closes a version.
  test "a raw update of a scheduled version's identity, predicate or start is refused",
       %{world: world, security: security} do
    rule = rule!(world.portfolio, security, %{valid_from: Date.add(today(), 30)})
    other_rule = rule!(world.portfolio, security, %{valid_from: Date.add(today(), 60)})
    [version] = PolicyRules.get_rule(rule.id).versions

    assert_restricted("UPDATE policy_rule_versions SET valid_from = $1 WHERE id = $2", [
      Date.add(today(), -400),
      version.id
    ])

    assert_restricted("UPDATE policy_rule_versions SET policy_rule_id = $1 WHERE id = $2", [
      other_rule.id,
      version.id
    ])

    assert_restricted("UPDATE policy_rule_versions SET id = id + 1000000 WHERE id = $1", [
      version.id
    ])

    assert_restricted("UPDATE policy_rule_versions SET threshold = 12 WHERE id = $1", [
      version.id
    ])

    assert {:ok, _} =
             raw("UPDATE policy_rule_versions SET valid_until = $1 WHERE id = $2", [
               Date.add(today(), 90),
               version.id
             ])

    assert {:ok, _} =
             raw("UPDATE policy_rule_versions SET updated_at = now() WHERE id = $1", [version.id])
  end

  # User story:
  # As the operator reading which context a rule was evaluated in,
  # I want a rule's id, portfolio and view fixed at the database,
  # so that a raw write cannot move a rule, with its whole history, into
  # another portfolio or view.
  #
  # Acceptance criteria:
  # - A raw UPDATE of a rule's portfolio_id, view_id or id raises
  #   restrict_violation; its name stays writable (the rename).
  test "a raw update of a rule's identity or context is refused, its name is not",
       %{world: world, other: other, security: security} do
    rule = rule!(world.portfolio, security)

    assert_restricted("UPDATE policy_rules SET portfolio_id = $1 WHERE id = $2", [
      other.portfolio.id,
      rule.id
    ])

    {:ok, view} = Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "Guard view"})

    assert_restricted("UPDATE policy_rules SET view_id = $1 WHERE id = $2", [view.id, rule.id])
    assert_restricted("UPDATE policy_rules SET id = id + 1000000 WHERE id = $1", [rule.id])

    assert {:ok, _} = raw("UPDATE policy_rules SET name = 'Renamed' WHERE id = $1", [rule.id])
  end

  # User story:
  # As the operator whose standards the database keeps,
  # I want TRUNCATE refused on both policy tables,
  # so that a statement-level wipe cannot remove versions in force that no
  # row-level DELETE may touch.
  #
  # Acceptance criteria:
  # - TRUNCATE policy_rule_versions and TRUNCATE policy_rules CASCADE each
  #   raise restrict_violation, and the rule and its version remain.
  test "TRUNCATE of either policy table is refused", %{world: world, security: security} do
    rule = rule!(world.portfolio, security)

    assert_restricted("TRUNCATE policy_rule_versions")
    assert_restricted("TRUNCATE policy_rules CASCADE")

    assert %{versions: [_version]} = PolicyRules.get_rule(rule.id)
  end
end
