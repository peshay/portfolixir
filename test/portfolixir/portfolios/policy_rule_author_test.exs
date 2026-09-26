defmodule Portfolixir.Portfolios.PolicyRuleAuthorTest do
  # E25 S7, G30 and decision T-8 of the 2026-09-24 triage: every policy-rule
  # version stores who wrote it, derived from the actor of the write — never
  # taken from input — so a rule an API token wrote reads as the agent's.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRuleAuthorBackfill
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.PolicyRuleVersion

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

  defp create!(actor, world, version) do
    {:ok, rule} =
      PolicyRules.create_rule(actor, %{
        portfolio_id: world.portfolio.id,
        name: "Single name at most 10 %",
        version: version
      })

    rule
  end

  # A version as the tables held it before authors were stored: no author,
  # created under `actor`'s journal entry — or, with `nil`, under none.
  # `opts` name the rule it belongs to (a new one by default) and its period:
  # a version closed days before the upgrade is what every rule edited or
  # retired on the previous release holds (CR-1).
  defp legacy_version!(world, security, actor, opts \\ []) do
    rule = Keyword.get_lazy(opts, :rule, fn -> legacy_rule!(world) end)

    changeset =
      %PolicyRuleVersion{}
      |> PolicyRuleVersion.changeset(
        weight_cap(security, %{
          policy_rule_id: rule.id,
          valid_from: Keyword.get(opts, :valid_from, Date.add(today(), 10))
        })
      )
      |> Ecto.Changeset.put_change(:valid_until, Keyword.get(opts, :valid_until))

    if actor do
      {:ok, %{record: version}} =
        Multi.new()
        |> Multi.insert(:record, changeset)
        |> Journal.record(actor,
          resource_type: "policy_rule_version",
          operation: :create,
          source: :record
        )
        |> Repo.transaction()

      version
    else
      raw!(fn -> Repo.insert!(changeset) end)
    end
  end

  defp legacy_rule!(world) do
    {:ok, %{record: rule}} =
      Multi.new()
      |> Multi.insert(
        :record,
        PolicyRule.changeset(%PolicyRule{}, %{portfolio_id: world.portfolio.id, name: "Legacy"})
      )
      |> Journal.record(Actor.owner_ui(),
        resource_type: "policy_rule",
        operation: :create,
        source: :record
      )
      |> Repo.transaction()

    rule
  end

  # A write with the journal actor set, so the journal guard is not what
  # refuses it.
  defp raw!(fun) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'system_job', true)")
        fun.()
      end)

    result
  end

  defp raw_error(sql, params) do
    assert_raise Postgrex.Error, fn -> raw!(fn -> Repo.query!(sql, params) end) end
  end

  setup do
    world = base_world(name: "Author Portfolio")
    security = create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH")
    %{world: world, security: security}
  end

  # User story (E25 S7, G30, T-8):
  # As the operator whose agent writes policy rules with its API token,
  # I want every version to carry its author — operator for what I save on
  # the Risk page, agent for what an API or MCP token writes —
  # so that I can tell the agent's lines from my own without the journal.
  #
  # Acceptance criteria:
  # - A version created or added by the UI actor stores author operator; by
  #   a read-write or read-only API token, named or not, author agent.
  # - An `author` in the input is never read: the actor decides.
  # - A rename adds no version and changes no version's author; closing a
  #   version (an edit) keeps its author.
  test "a version's author is derived from the actor of the write, never from input",
       %{world: world, security: security} do
    rule = create!(Actor.owner_ui(), world, weight_cap(security, %{author: "agent"}))
    assert [%PolicyRuleVersion{author: :operator}] = rule.versions

    {:ok, agent_version} =
      PolicyRules.add_version(
        Actor.api_token_rw("mcp"),
        rule,
        weight_cap(security, %{
          threshold: "12",
          valid_from: Date.add(today(), 3),
          author: "operator"
        })
      )

    assert agent_version.author == :agent

    {:ok, _renamed} = PolicyRules.rename_rule(Actor.api_token_rw(), rule, %{name: "Renamed"})

    assert [%{author: :operator, valid_until: until}, %{author: :agent}] =
             PolicyRules.get_rule(rule.id).versions

    assert until == Date.add(today(), 2)

    unnamed = create!(Actor.api_token_rw(), world, weight_cap(security))
    assert [%{author: :agent}] = unnamed.versions

    read_only = create!(Actor.api_token_ro("reader"), world, weight_cap(security))
    assert [%{author: :agent}] = read_only.versions

    assert PolicyRuleVersion.author_for(Actor.owner_ui()) == :operator
    assert PolicyRuleVersion.author_for(Actor.api_token_rw("scripts")) == :agent
  end

  # User story (E25 S7, G30):
  # As the operator relying on the author to tell the agent's lines apart,
  # I want the database to refuse a raw change of a version's author once it
  # is recorded, and any value outside operator and agent,
  # so that no path around the context can relabel who drew a line.
  #
  # Acceptance criteria:
  # - A raw UPDATE of a recorded author, to another value or to NULL, raises
  #   restrict_violation.
  # - A version stored before authors existed may be given one once (the
  #   upgrade's backfill); a value outside operator and agent raises
  #   check_violation.
  test "the database keeps a recorded author and the closed set", %{
    world: world,
    security: security
  } do
    rule =
      create!(Actor.owner_ui(), world, weight_cap(security, %{valid_from: Date.add(today(), 5)}))

    [version] = rule.versions

    for value <- ["agent", nil] do
      error =
        raw_error("UPDATE policy_rule_versions SET author = $1 WHERE id = $2", [value, version.id])

      assert error.postgres.code == :restrict_violation
    end

    legacy = legacy_version!(world, security, nil)
    assert legacy.author == nil

    error =
      raw_error("UPDATE policy_rule_versions SET author = 'robot' WHERE id = $1", [legacy.id])

    assert error.postgres.code == :check_violation

    raw!(fn ->
      Repo.query!("UPDATE policy_rule_versions SET author = 'agent' WHERE id = $1", [legacy.id])
    end)

    assert Repo.get!(PolicyRuleVersion, legacy.id).author == :agent
  end

  # User story (E25 S7, G30):
  # As the operator upgrading an instance whose agent already wrote rules,
  # I want the versions written before authors were stored to get the author
  # the journal recorded for their creation,
  # so that the agent's existing lines are marked from the first day.
  #
  # Acceptance criteria:
  # - A version with no author whose create entry names an API token gets
  #   agent; one the UI created gets operator; each backfilled row is
  #   journaled under the system_job actor it runs as.
  # - A version with no create entry keeps no author, and the report counts
  #   it as untraced.
  # - A second run writes and journals nothing.
  test "the backfill takes a stored version's author from its journaled creation", %{
    world: world,
    security: security
  } do
    by_agent = legacy_version!(world, security, Actor.api_token_rw("mcp"))
    by_operator = legacy_version!(world, security, Actor.owner_ui())
    untraced = legacy_version!(world, security, nil)

    assert Enum.all?([by_agent, by_operator, untraced], &is_nil(&1.author))

    backfill_entries = fn ->
      [resource_type: "policy_rule_version", actor_type: :system_job, limit: 1000]
      |> Journal.list_entries()
      |> length()
    end

    assert backfill_entries.() == 0

    assert {:ok, %{agent: 1, operator: 1, untraced: 1}} =
             PolicyRuleAuthorBackfill.run(Actor.system_job("policy_author_backfill"))

    assert Repo.get!(PolicyRuleVersion, by_agent.id).author == :agent
    assert Repo.get!(PolicyRuleVersion, by_operator.id).author == :operator
    assert Repo.get!(PolicyRuleVersion, untraced.id).author == nil
    assert backfill_entries.() == 2

    assert {:ok, %{agent: 0, operator: 0, untraced: 1}} =
             PolicyRuleAuthorBackfill.run(Actor.system_job("policy_author_backfill"))

    assert backfill_entries.() == 2
  end

  # User story (E25 S7, G30; closing-act finding CR-1):
  # As the operator upgrading an instance on which I edited and retired rules
  # on the previous release,
  # I want the author backfill to reach the versions those writes closed,
  # so that the upgrade finishes and the instance starts.
  #
  # Acceptance criteria:
  # - A version closed well before the upgrade (an edit's predecessor, or a
  #   retired rule's last line) gets its author like any other, and its
  #   period is unchanged.
  # - The database still refuses a raw write that moves such a version's
  #   end, or backdates an open one: only an unchanged end is let through.
  test "the backfill reaches versions an edit or a retirement closed days ago", %{
    world: world,
    security: security
  } do
    edited = legacy_rule!(world)
    agent = Actor.api_token_rw("mcp")

    predecessor =
      legacy_version!(world, security, agent,
        rule: edited,
        valid_from: Date.add(today(), -30),
        valid_until: Date.add(today(), -10)
      )

    successor =
      legacy_version!(world, security, agent, rule: edited, valid_from: Date.add(today(), -9))

    retired =
      legacy_version!(world, security, Actor.owner_ui(),
        valid_from: Date.add(today(), -20),
        valid_until: Date.add(today(), -5)
      )

    assert {:ok, %{agent: 2, operator: 1, untraced: 0}} =
             PolicyRuleAuthorBackfill.run(Actor.system_job("policy_author_backfill"))

    for {version, author} <- [{predecessor, :agent}, {successor, :agent}, {retired, :operator}] do
      stored = Repo.get!(PolicyRuleVersion, version.id)
      assert stored.author == author
      assert {stored.valid_from, stored.valid_until} == {version.valid_from, version.valid_until}
    end

    moved =
      raw_error("UPDATE policy_rule_versions SET valid_until = valid_until + 1 WHERE id = $1", [
        predecessor.id
      ])

    assert moved.postgres.code == :restrict_violation

    backdated =
      raw_error("UPDATE policy_rule_versions SET valid_until = $1 WHERE id = $2", [
        Date.add(today(), -3),
        successor.id
      ])

    assert backdated.postgres.code == :restrict_violation
  end
end
