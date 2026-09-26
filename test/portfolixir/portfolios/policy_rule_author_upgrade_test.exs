defmodule Portfolixir.Portfolios.PolicyRuleAuthorUpgradeTest do
  # Closing-act finding CR-1: the author migration of E25 S7 backfills every
  # stored version, and the in-force guard of Sprint 15 refused that write on
  # a version whose end lay more than two days back — so an instance whose
  # operator had edited or retired a rule stopped at boot. This test runs the
  # upgrade itself: it takes the database back to the state before the two
  # migrations, seeds what a Sprint 15 instance holds, and migrates.
  #
  # async: false — the migration alters policy_rule_versions, a lock every
  # concurrent policy-rule test would wait on. The sandbox rolls the schema
  # change back with the rest of the test. The migrator's own lock is off: it
  # holds a transaction on the one sandboxed connection that the migration's
  # task then waits for.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRuleVersion

  @migrations [
    {20_260_926_121_400, "20260926121400_scope_policy_rule_backdated_end_guard.exs",
     Portfolixir.Repo.Migrations.ScopePolicyRuleBackdatedEndGuard},
    {20_260_926_121_500, "20260926121500_add_author_to_policy_rule_versions.exs",
     Portfolixir.Repo.Migrations.AddAuthorToPolicyRuleVersions}
  ]

  defp today, do: Portfolixir.Clock.today()

  # The migration modules as `Ecto.Migrator` source, each file compiled once
  # per VM: a second compile would redefine the module.
  defp migration_source do
    dir = Ecto.Migrator.migrations_path(Repo)

    for {version, file, module} <- @migrations do
      unless Code.ensure_loaded?(module), do: Code.require_file(Path.join(dir, file))
      {version, module}
    end
  end

  defp rule!(world, name) do
    {:ok, %{record: rule}} =
      Multi.new()
      |> Multi.insert(
        :record,
        PolicyRule.changeset(%PolicyRule{}, %{portfolio_id: world.portfolio.id, name: name})
      )
      |> Journal.record(Actor.owner_ui(),
        resource_type: "policy_rule",
        operation: :create,
        source: :record
      )
      |> Repo.transaction()

    rule
  end

  # A version as a Sprint 15 instance stored it: no author, its creation
  # journaled under `actor`, its period whatever the context's writes left.
  defp version!(rule, security, actor, valid_from, valid_until \\ nil) do
    changeset =
      %PolicyRuleVersion{}
      |> PolicyRuleVersion.changeset(%{
        policy_rule_id: rule.id,
        subject_type: "security",
        security_id: security.id,
        measure: "weight",
        kind: "cap",
        threshold: "10",
        severity: "hard",
        valid_from: valid_from
      })
      |> Ecto.Changeset.put_change(:valid_until, valid_until)

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
  end

  defp author_column? do
    %{num_rows: rows} =
      Repo.query!("""
      SELECT 1 FROM information_schema.columns
       WHERE table_name = 'policy_rule_versions' AND column_name = 'author'
      """)

    rows == 1
  end

  # User story (E25 S7, G30; closing-act finding CR-1):
  # As the operator upgrading an instance on which I edited and retired
  # policy rules on the previous release,
  # I want the upgrade's migrations to finish,
  # so that the instance starts and every stored version carries its author.
  #
  # Acceptance criteria:
  # - Taken back to the schema before the author migration, a database
  #   holding an edit's predecessor closed ten days ago, its open successor
  #   and a rule retired five days ago migrates up without an error.
  # - Each of those versions carries the author its journaled creation names,
  #   and its period is unchanged.
  test "the upgrade migrates a database holding versions closed days before it" do
    world = base_world(name: "Upgrade Portfolio")
    security = create_security!(name: "Aurora Basin Minerals Ltd", ticker: "ABM")
    agent = Actor.api_token_rw("mcp")

    edited = rule!(world, "Edited on the previous release")

    predecessor =
      version!(edited, security, agent, Date.add(today(), -30), Date.add(today(), -10))

    successor = version!(edited, security, agent, Date.add(today(), -9))

    retired_rule = rule!(world, "Retired on the previous release")

    retired =
      version!(
        retired_rule,
        security,
        Actor.owner_ui(),
        Date.add(today(), -20),
        Date.add(today(), -5)
      )

    source = migration_source()

    assert Ecto.Migrator.run(Repo, source, :down, all: true, log: false, migration_lock: false) ==
             [20_260_926_121_500, 20_260_926_121_400]

    refute author_column?()

    assert Ecto.Migrator.run(Repo, source, :up, all: true, log: false, migration_lock: false) ==
             [20_260_926_121_400, 20_260_926_121_500]

    assert author_column?()

    for {version, author} <- [{predecessor, :agent}, {successor, :agent}, {retired, :operator}] do
      stored = Repo.get!(PolicyRuleVersion, version.id)
      assert stored.author == author
      assert {stored.valid_from, stored.valid_until} == {version.valid_from, version.valid_until}
    end
  end
end
