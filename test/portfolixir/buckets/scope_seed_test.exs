defmodule Portfolixir.Buckets.ScopeSeedTest do
  use Portfolixir.DataCase, async: true

  # These tests run the frozen seed (`Portfolixir.Buckets.ScopeSeed`, frozen
  # at migration 20260712130000's schema on purpose) against today's schema.
  # A later migration that adds a NOT NULL column to `audit_journal` or to a
  # table the seed writes can turn them red while every upgrade is fine,
  # because the migration runs the seed at its own version (the seeded case
  # in test/portfolixir/seeded_upgrade/app_code_migrations_test.exs proves
  # that). If that happens, move these tests into a seeded case at
  # 20260712130000 (`Portfolixir.SeededUpgrade`) instead of changing
  # `ScopeSeed`, whose moduledoc says why it never changes.

  import Portfolixir.WorldFixtures, only: [base_world: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Journal
  alias Portfolixir.Journal.Serializer

  @seed_actor Actor.system_job("portfolio_scope_seed")

  # Bucket and view names are unique instance-wide and async modules write at
  # the same time (#947), so every portfolio name here is unique.
  defp unique(base), do: "#{base} #{System.unique_integer([:positive])}"

  # User story (#1042, Sprint 19 B1):
  # As the operator upgrading an instance from before the buckets-and-views
  # model,
  # I want the seed its migration calls to run against the schema that
  # migration had,
  # so that a column a later migration adds to an account, a bucket or the
  # journal never stops the upgrade at this migration.
  #
  # Acceptance criteria:
  # - The code the immutable migration calls names no schema and no
  #   application module but `Portfolixir.Actor`: its columns, its naming
  #   rule and its journal write are frozen into `Portfolixir.Buckets.ScopeSeed`.
  # - The context's two functions the migration names delegate to it.
  # - Each journal entry the seed writes is the one the context's writers
  #   wrote: a bucket's create carries the row as the journal's serializer
  #   images it, an account's assignment carries its new bucket set.
  test "the seed the migration calls names no schema and no application module but Actor" do
    migration = File.read!("priv/repo/migrations/20260712130000_seed_portfolio_scope_buckets.exs")
    assert migration =~ "Buckets.seed_portfolio_scope_buckets(seed_actor())"
    assert migration =~ "Buckets.rollback_portfolio_scope_seed(seed_actor())"

    assert application_modules(File.read!("lib/portfolixir/buckets/scope_seed.ex")) == [
             [:Portfolixir, :Actor],
             [:Portfolixir, :Buckets, :ScopeSeed]
           ]

    buckets = File.read!("lib/portfolixir/buckets.ex")

    assert buckets =~
             "def seed_portfolio_scope_buckets(%Actor{} = actor), do: ScopeSeed.seed(Repo, actor)"

    assert buckets =~
             "def rollback_portfolio_scope_seed(%Actor{} = actor), do: ScopeSeed.rollback(Repo, actor)"
  end

  test "each journal entry the seed writes is the one the context's writers wrote" do
    world = base_world(name: unique("Alpha"), cash_name: "A Cash", depot_name: "A Depot")
    {:ok, tag} = Buckets.create_bucket(Actor.owner_ui(), %{name: unique("Tag")})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [tag.id])

    {:ok, _summary} = Buckets.seed_portfolio_scope_buckets(@seed_actor)

    %{buckets: [seeded]} = Buckets.migration_summary()

    assert [create] = seed_entries("bucket")
    assert create.operation == :create
    assert create.resource_id == Integer.to_string(seeded.id)
    assert create.before == nil
    assert create.after == Serializer.snapshot(Repo.get!(Bucket, seeded.id))

    assert [depot] = seed_entries("depot_bucket_assignment")
    assert {depot.operation, depot.resource_id, depot.before} == {:update, nil, nil}

    assert depot.after ==
             Serializer.snapshot(%{
               id: nil,
               securities_account_id: world.depot.id,
               bucket_ids: [tag.id, seeded.id]
             })

    assert [cash] = seed_entries("cash_account_bucket_assignment")

    assert cash.after ==
             Serializer.snapshot(%{
               id: nil,
               cash_account_id: world.cash.id,
               bucket_ids: [seeded.id]
             })

    assert seed_entries("view") == []
  end

  # The guard's setting for an actor without a label is its type alone, and
  # the journal stores no label for it (the Wealth page tests seed as the
  # owner).
  test "a seed under an actor without a label journals its type and no label" do
    base_world(name: unique("Owner"), cash_name: "O Cash", depot_name: "O Depot")

    assert {:ok, %{buckets_created: 1, accounts_tagged: 2}} =
             Buckets.seed_portfolio_scope_buckets(Actor.owner_ui())

    entries =
      Enum.filter(Journal.list_entries(actor_type: "owner_ui"), fn entry ->
        entry.resource_type in ~w(bucket depot_bucket_assignment cash_account_bucket_assignment)
      end)

    assert length(entries) == 3
    assert Enum.all?(entries, &is_nil(&1.actor_label))
  end

  # User story (#1042, Sprint 19 B1):
  # As a local portfolio maintainer who reverts the upgrade,
  # I want each seeded bucket's delete journaled with what was deleted,
  # so that the audit journal still says which buckets the rollback removed.
  #
  # Acceptance criteria:
  # - Each seeded bucket's delete is journaled under the rollback's actor
  #   with the bucket's row on both sides; the operator's bucket is kept.
  test "the rollback journals each seeded bucket's delete with its row on both sides" do
    base_world(name: unique("Alpha"), cash_name: "A Cash", depot_name: "A Depot")
    {:ok, own} = Buckets.create_bucket(Actor.owner_ui(), %{name: unique("Own")})

    {:ok, _summary} = Buckets.seed_portfolio_scope_buckets(@seed_actor)
    %{buckets: [seeded]} = Buckets.migration_summary()
    image = Serializer.snapshot(Repo.get!(Bucket, seeded.id))

    :ok = Buckets.rollback_portfolio_scope_seed(@seed_actor)

    assert [delete] =
             Enum.filter(seed_entries("bucket"), &(&1.operation == :delete))

    assert {delete.resource_id, delete.before, delete.after} ==
             {Integer.to_string(seeded.id), image, image}

    assert Repo.get(Bucket, seeded.id) == nil
    assert Repo.get(Bucket, own.id)
  end

  defp seed_entries(resource_type) do
    [resource_type: resource_type, actor_type: "system_job"]
    |> Journal.list_entries()
    |> Enum.filter(&(&1.actor_label == "portfolio_scope_seed"))
    |> Enum.reverse()
  end

  # Every `Portfolixir.*` module the source names, the repo excepted.
  defp application_modules(source) do
    {_ast, modules} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:__aliases__, _meta, [:Portfolixir | rest] = parts} = node, acc ->
          if match?([:Repo | _], rest), do: {node, acc}, else: {node, [parts | acc]}

        node, acc ->
          {node, acc}
      end)

    modules |> Enum.uniq() |> Enum.sort()
  end
end
