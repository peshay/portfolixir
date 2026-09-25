defmodule Portfolixir.Portfolios.PolicyRuleLockTest do
  # E25 S6 (#891), F48: add_version, retire_rule and delete_rule read a
  # rule's versions FOR UPDATE, which holds the rows that exist but not the
  # rule, so a version added concurrently could land after a retirement had
  # read the versions and survive it. Each of the three writes now locks the
  # parent rule row FOR UPDATE, in a statement of its own, before it reads
  # the versions; a version insert waits on that lock through its foreign
  # key.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.PolicyRules

  defp today, do: Portfolixir.Clock.today()

  defp weight_cap(security, attrs \\ %{}) do
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

  defp rule!(portfolio, version_attrs) do
    {:ok, rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Single name at most 10 %",
        version: version_attrs
      })

    rule
  end

  setup do
    world = base_world(name: "Rule Lock Portfolio")
    security = create_security!(name: "Harbour Lock Shipping ASA", ticker: "HLS")
    %{world: world, security: security}
  end

  # User story:
  # As the operator retiring a rule while the agent adds a version to it,
  # I want the two writes to take turns on the rule,
  # so that no version starting after the retirement survives it.
  #
  # Acceptance criteria:
  # - add_version, retire_rule and delete_rule each lock the rule row FOR
  #   UPDATE, in a statement that reads no version, before they read the
  #   rule's versions.
  test "each version-reading write locks the rule before it reads the versions",
       %{world: world, security: security} do
    in_force = rule!(world.portfolio, weight_cap(security))

    scheduled =
      rule!(world.portfolio, weight_cap(security, %{valid_from: Date.add(today(), 30)}))

    writes = [
      {"add_version",
       fn ->
         PolicyRules.add_version(
           Actor.owner_ui(),
           in_force,
           weight_cap(security, %{threshold: "12", valid_from: Date.add(today(), 5)})
         )
       end},
      {"retire_rule", fn -> PolicyRules.retire_rule(Actor.owner_ui(), in_force, %{}) end},
      {"delete_rule", fn -> PolicyRules.delete_rule(Actor.owner_ui(), scheduled) end}
    ]

    for {name, write} <- writes do
      queries = capture_queries(fn -> assert {:ok, _} = write.() end)

      rule_lock =
        Enum.find_index(queries, &(&1 =~ ~r/FROM "policy_rules" AS \w+ WHERE .*FOR UPDATE/s))

      versions_read =
        Enum.find_index(queries, &(&1 =~ ~r/FROM "policy_rule_versions" .*FOR UPDATE/s))

      assert rule_lock, "#{name} takes no lock on the rule"
      assert versions_read, "#{name} reads no versions"
      assert rule_lock < versions_read, "#{name} reads the versions before it locks the rule"
      refute Enum.at(queries, rule_lock) =~ "policy_rule_versions"
    end
  end

  # User story:
  # As the agent writing to a rule the operator deleted a moment earlier,
  # I want the write to answer that the rule is gone,
  # so that it neither crashes nor writes a version for a rule that no
  # longer exists.
  #
  # Acceptance criteria:
  # - add_version, retire_rule and delete_rule on a deleted rule answer
  #   :not_found and journal nothing.
  test "a write to a rule deleted in the meantime answers not found",
       %{world: world, security: security} do
    rule = rule!(world.portfolio, weight_cap(security, %{valid_from: Date.add(today(), 30)}))
    assert {:ok, _} = PolicyRules.delete_rule(Actor.owner_ui(), rule)
    before = length(Journal.list_entries())

    assert PolicyRules.add_version(
             Actor.owner_ui(),
             rule,
             weight_cap(security, %{valid_from: Date.add(today(), 40)})
           ) == {:error, :not_found}

    assert PolicyRules.retire_rule(Actor.owner_ui(), rule, %{}) == {:error, :not_found}
    assert PolicyRules.delete_rule(Actor.owner_ui(), rule) == {:error, :not_found}
    assert length(Journal.list_entries()) == before
  end

  defp capture_queries(fun) do
    test_pid = self()
    handler = "policy-rule-lock-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if self() == test_pid, do: send(test_pid, {:query, query})
        end,
        nil
      )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    collect_queries([])
  end

  defp collect_queries(acc) do
    receive do
      {:query, query} -> collect_queries([query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
