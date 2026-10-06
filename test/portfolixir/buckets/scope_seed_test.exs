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
  alias Portfolixir.Buckets.ScopeSeed
  alias Portfolixir.Journal
  alias Portfolixir.Journal.Serializer

  # A repo that delegates to `Portfolixir.Repo` and makes the database refuse
  # the bucket insert of the portfolio the test names in its process
  # dictionary, with a real statement error, as a constraint would.
  defmodule RefusingRepo do
    @moduledoc false
    alias Portfolixir.Repo

    def transaction(fun), do: Repo.transaction(fun)
    def rollback(value), do: Repo.rollback(value)

    def query!(sql, params \\ []) do
      if sql =~ ~r/^\s*INSERT INTO buckets/ and
           Enum.at(params, 2) == Process.get(:refuse_portfolio) do
        Repo.query!("SELECT 1 / 0")
      else
        Repo.query!(sql, params)
      end
    end
  end

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
  # - The context's two functions the migration names delegate to it, the
  #   head seed does not, and the migration names the two.
  # - Each journal entry the seed writes is the one the context's writers
  #   wrote: a bucket's create carries the row as the journal's serializer
  #   images it, an account's assignment carries its new bucket set.
  test "the seed the migration calls names no schema and no application module but Actor" do
    migration =
      quoted("priv/repo/migrations/20260712130000_seed_portfolio_scope_buckets.exs")

    assert calls?(migration, :Buckets, :seed_portfolio_scope_buckets)
    assert calls?(migration, :Buckets, :rollback_portfolio_scope_seed)

    assert application_modules(File.read!("lib/portfolixir/buckets/scope_seed.ex")) == [
             [:Portfolixir, :Actor],
             [:Portfolixir, :Buckets, :ScopeSeed]
           ]

    buckets = quoted("lib/portfolixir/buckets.ex")
    assert calls?(function_body(buckets, :seed_portfolio_scope_buckets), :ScopeSeed, :seed)
    assert calls?(function_body(buckets, :rollback_portfolio_scope_seed), :ScopeSeed, :rollback)
    refute calls?(function_body(buckets, :seed_scope_buckets_at_head), :ScopeSeed, :seed)
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

  # User story (#1042, review pass 1):
  # As the operator upgrading an instance whose portfolio names are longer
  # than a bucket name may be,
  # I want the seeded bucket and view to carry the same name within the
  # bound, without the whitespace the cut leaves,
  # so that the pair reads as one unit and the name is what the changesets
  # would have stored.
  #
  # Acceptance criteria:
  # - A name whose 100-code-point cut ends in a space seeds a bucket whose
  #   name has no trailing whitespace, and a view of the same name.
  # - A name past 100 code points whose cut another bucket holds falls back
  #   to "<cut> (Portfolio)" within 100 code points, for the bucket and the
  #   view alike.
  # - The migration's frozen seed and the head seed share the rule.
  for {label, seed} <- [
        {"the migration's frozen seed", :seed_portfolio_scope_buckets},
        {"the head seed", :seed_scope_buckets_at_head}
      ] do
    test "#{label}: a cut that ends in a space leaves no trailing whitespace" do
      prefix = String.pad_trailing(unique("Cut"), 99, "x")
      base_world(name: prefix <> " tail end", cash_name: "C Cash", depot_name: "C Depot")

      assert {:ok, %{buckets_created: 1, views_created: 1}} =
               apply(Buckets, unquote(seed), [@seed_actor])

      assert %{buckets: [bucket], views: [view]} = Buckets.migration_summary()
      assert bucket.name == prefix
      assert view.name == bucket.name
    end

    test "#{label}: the fallback for a taken cut stays within the bound" do
      name = String.pad_trailing(unique("Long"), 120, "y")
      {:ok, _taken} = Buckets.create_bucket(Actor.owner_ui(), %{name: String.slice(name, 0, 100)})
      base_world(name: name, cash_name: "L Cash", depot_name: "L Depot")

      assert {:ok, %{buckets_created: 1, views_created: 1}} =
               apply(Buckets, unquote(seed), [@seed_actor])

      assert %{buckets: [bucket], views: [view]} = Buckets.migration_summary()
      assert bucket.name == String.slice(name, 0, 88) <> " (Portfolio)"
      assert length(String.codepoints(bucket.name)) == 100
      assert view.name == bucket.name
    end
  end

  # User story (#1042, review pass 1):
  # As the operator whose upgrade stops at the portfolio scope seed,
  # I want the failure to name the portfolio and leave nothing half seeded,
  # so that the upgrade can be retried over the database as it was.
  #
  # Acceptance criteria:
  # - A statement the database refuses at the second portfolio answers
  #   `{:error, %{portfolio_id, portfolio_name, reason}}` naming that
  #   portfolio, with the database's error as the reason.
  # - Nothing of the first portfolio's seed remains: no seeded bucket or
  #   view, no assignment and no journal entry.
  test "a statement the database refuses stops the seed at its portfolio and writes nothing" do
    first = base_world(name: unique("First"), cash_name: "F Cash", depot_name: "F Depot")
    second = base_world(name: unique("Second"), cash_name: "S Cash", depot_name: "S Depot")
    journal_before = Journal.list_entries([])

    Process.put(:refuse_portfolio, second.portfolio.id)

    assert {:error, %{portfolio_id: id, portfolio_name: name, reason: %Postgrex.Error{}}} =
             ScopeSeed.seed(RefusingRepo, @seed_actor)

    assert {id, name} == {second.portfolio.id, second.portfolio.name}
    assert Buckets.migration_summary() == %{migrated?: false, buckets: [], views: []}
    assert Buckets.depot_default_bucket_ids(first.depot.id) == []
    assert Buckets.cash_account_bucket_ids(first.cash.id) == []
    assert Journal.list_entries([]) == journal_before
  end

  defp seed_entries(resource_type) do
    [resource_type: resource_type, actor_type: "system_job"]
    |> Journal.list_entries()
    |> Enum.filter(&(&1.actor_label == "portfolio_scope_seed"))
    |> Enum.reverse()
  end

  defp quoted(path), do: path |> File.read!() |> Code.string_to_quoted!()

  # The body of the public function `name` in `ast`, whatever its layout.
  defp function_body(ast, name) do
    {_ast, body} =
      Macro.prewalk(ast, nil, fn
        {:def, _meta, [{^name, _head_meta, _args}, [do: body]]} = node, nil -> {node, body}
        node, found -> {node, found}
      end)

    assert body, "no def #{name} found"
    body
  end

  # Whether `ast` calls `<...>.Module.fun(...)`, the module named by its last
  # alias segment.
  defp calls?(ast, module, fun) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {{:., _, [{:__aliases__, _, segments}, ^fun]}, _, _args} = node, acc ->
          {node, acc or List.last(segments) == module}

        node, acc ->
          {node, acc}
      end)

    found?
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
