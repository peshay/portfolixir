defmodule Portfolixir.DryRunDeleteTest do
  # Sprint 25 X1 (#894, idea F21; plan D-4): the three cascading deletes —
  # a classification, a category, a view — answer a dry run by running the
  # real delete in a transaction that always rolls back, so the answer is
  # what the delete does, refusals included, never a count computed beside
  # it. D-8.2: the rollback is checked by counting every table and the
  # journal before and after.
  #
  # Not async: the refresher and the post-commit process are stood in for by
  # this test's own process under their registered names, which are global.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Buckets.ViewExcludeBucket
  alias Portfolixir.Buckets.ViewIncludeBucket
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Assignment
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.Journal.Cascades
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.Snapshot
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Portfolios.TargetPlan
  alias Portfolixir.Portfolios.Targets

  defp owner, do: Actor.owner_ui()

  # The kinds a dry run answers, and the table each one reads.
  @kinds %{
    classifications: Classification,
    categories: Category,
    assignments: Assignment,
    target_plans: TargetPlan,
    targets: Target,
    depot_snapshots: Snapshot,
    view_include_buckets: ViewIncludeBucket,
    view_exclude_buckets: ViewExcludeBucket,
    views: View
  }

  # A custom tree with a root, a child holding one security, an active
  # plan with a category and a position target on the child, and a view
  # including one bucket and excluding another, with a plan of its own on
  # the tree and a depot snapshot in its scope.
  defp world do
    world = base_world(name: "Dry Run Portfolio")
    security = create_security!(name: "Northwind Harbour Logistics AG", ticker: "NHL")
    {:ok, classification} = Classifications.create_classification(owner(), %{name: "Strategy"})

    {:ok, root} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Growth"
      })

    {:ok, child} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Growth income",
        parent_id: root.id
      })

    {:ok, _assignment} =
      Classifications.assign_security(owner(), security.id, classification.id, child.id)

    {:ok, _targets} =
      Targets.set_targets(owner(), world.portfolio.id, classification.id, [
        %{category_id: child.id, target_weight: Decimal.new("0.4")},
        %{category_id: child.id, security_id: security.id, target_weight: Decimal.new("0.2")}
      ])

    suffix = System.unique_integer([:positive])
    {:ok, view} = Buckets.create_view(owner(), %{name: "Strategy scope #{suffix}"})
    {:ok, kept} = Buckets.create_bucket(owner(), %{name: "Kept #{suffix}", dimension: "tag"})
    {:ok, left} = Buckets.create_bucket(owner(), %{name: "Left out #{suffix}", dimension: "tag"})
    :ok = Buckets.set_view_buckets(owner(), view, [kept.id], [left.id])

    {:ok, _view_targets} =
      Targets.set_targets(
        owner(),
        world.portfolio.id,
        classification.id,
        [%{category_id: root.id, target_weight: Decimal.new("0.5")}],
        view: view
      )

    {:ok, _snapshot} =
      Snapshots.create_snapshot(owner(), %{
        name: "Before the change",
        view_id: view.id,
        as_of: ~D[2026-07-01]
      })

    %{
      world: world,
      security: security,
      classification: classification,
      root: root,
      child: child,
      view: view
    }
  end

  # Every table of the database with its row count: a dry run that wrote
  # anything anywhere, the journal and the derived layer's version log
  # included, changes one of them.
  defp table_counts do
    %{rows: tables} =
      Repo.query!("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY 1")

    Map.new(tables, fn [table] ->
      %{rows: [[count]]} = Repo.query!(~s[SELECT count(*) FROM "#{table}"])
      {table, count}
    end)
  end

  defp ids_by_kind(kinds) do
    Map.new(kinds, fn kind ->
      {kind, @kinds |> Map.fetch!(kind) |> select([r], r.id) |> Repo.all() |> MapSet.new()}
    end)
  end

  # What the real delete removed, per kind: the ids before it ran and not
  # after, read by the test itself.
  defp removed_by(kinds, delete) do
    before = ids_by_kind(kinds)
    assert {:ok, _} = delete.()
    after_delete = ids_by_kind(kinds)

    Map.new(kinds, fn kind ->
      ids = MapSet.difference(before[kind], after_delete[kind]) |> Enum.sort()
      {kind, %{count: length(ids), ids: ids}}
    end)
  end

  # Stands in for the refresher and the post-commit process, which a write
  # tells, outside its transaction, that the derived layer moved.
  # A forwarder registered under each name hands every message it gets to
  # the test, tagged with the name.
  @listened [Portfolixir.Derived.Refresher, Portfolixir.Derived.PostCommit]

  defp listen_for_derived_notifications do
    test = self()

    for name <- @listened do
      refute Process.whereis(name), "#{inspect(name)} runs in the test env"
      forwarder = spawn(fn -> forward(name, test) end)
      Process.register(forwarder, name)

      on_exit(fn ->
        ref = Process.monitor(forwarder)
        Process.exit(forwarder, :kill)
        assert_receive {:DOWN, ^ref, :process, ^forwarder, _reason}
      end)
    end
  end

  defp forward(name, test) do
    receive do
      {:flush, from} -> send(from, {:flushed, name})
      message -> send(test, {:told, name, message})
    end

    forward(name, test)
  end

  # Every message the test process sent a forwarder before this call has
  # reached the test once each forwarder answers: one sender, one order.
  defp flush_forwarders do
    for name <- @listened do
      send(name, {:flush, self()})
      assert_receive {:flushed, ^name}
    end
  end

  defp refute_derived_notified do
    flush_forwarders()
    refute_received {:told, _name, _message}
  end

  defp assert_derived_notified do
    flush_forwarders()
    assert_received {:told, Portfolixir.Derived.Refresher, {:"$gen_cast", {:notify, _bases}}}
    assert_received {:told, Portfolixir.Derived.PostCommit, :notified}
  end

  # User story (X1, #894):
  # As the operator's agent about to delete a classification,
  # I want to ask what the delete would remove before it runs,
  # so that I can name to the operator every category, assignment, plan and
  # target the tree takes with it, and only then delete.
  #
  # Acceptance criteria:
  # - The dry run answers, per kind, the count and the ids of the rows the
  #   delete would remove, and the real delete that follows removes exactly
  #   those rows (ids per kind equal).
  # - Every table, the journal included, counts the same after the dry run
  #   as before it (D-8.2).
  # - Nothing outside the transaction is told: neither the derived layer's
  #   refresher nor its post-commit process hears of the dry run; the real
  #   delete does tell them (the control).
  test "a classification's dry run names the rows its delete removes, and writes nothing" do
    t = world()
    listen_for_derived_notifications()
    counts = table_counts()

    assert {:ok, answer} =
             Classifications.dry_run_delete_classification(owner(), t.classification)

    assert table_counts() == counts
    refute_derived_notified()

    kinds = [:classifications, :categories, :assignments, :target_plans, :targets]
    assert Map.keys(answer) |> Enum.sort() == Enum.sort(kinds)
    assert answer.classifications == %{count: 1, ids: [t.classification.id]}
    assert answer.categories.ids == Enum.sort([t.root.id, t.child.id])
    assert answer.target_plans.count == 2
    assert answer.targets.count == 3

    real =
      removed_by(kinds, fn ->
        Classifications.delete_classification(owner(), t.classification)
      end)

    assert answer == real
    assert_derived_notified()
  end

  # User story (X1, #894):
  # As the operator's agent about to delete one branch of a tree,
  # I want the dry run to name the sub-categories, assignments and targets
  # the branch takes with it,
  # so that the operator sees what goes before it goes.
  #
  # Acceptance criteria:
  # - The dry run's ids per kind are the rows the real delete then removes.
  # - Nothing is written and nothing outside the transaction is told.
  test "a category's dry run names the rows its delete removes, and writes nothing" do
    t = world()
    listen_for_derived_notifications()
    counts = table_counts()

    assert {:ok, answer} = Classifications.dry_run_delete_category(owner(), t.root)

    assert table_counts() == counts
    refute_derived_notified()

    kinds = [:categories, :assignments, :targets]
    assert Map.keys(answer) |> Enum.sort() == Enum.sort(kinds)
    assert answer.categories.ids == Enum.sort([t.root.id, t.child.id])
    assert answer.assignments.count == 1
    assert answer.targets.count == 3

    real = removed_by(kinds, fn -> Classifications.delete_category(owner(), t.root) end)

    assert answer == real
    assert_derived_notified()
  end

  # User story (X1, #894):
  # As the operator's agent about to delete a view,
  # I want the dry run to name its bucket sets, the plans scoped to it with
  # their targets and its depot snapshots,
  # so that deleting a scope never silently takes the steering set on it.
  #
  # Acceptance criteria:
  # - The dry run's ids per kind, the bucket-set rows included, are the rows
  #   the real delete then removes.
  # - Nothing is written and nothing outside the transaction is told.
  test "a view's dry run names the rows its delete removes, and writes nothing" do
    t = world()
    listen_for_derived_notifications()
    counts = table_counts()

    assert {:ok, answer} = Buckets.dry_run_delete_view(owner(), t.view)

    assert table_counts() == counts
    refute_derived_notified()

    kinds = [
      :views,
      :view_include_buckets,
      :view_exclude_buckets,
      :target_plans,
      :targets,
      :depot_snapshots
    ]

    assert Map.keys(answer) |> Enum.sort() == Enum.sort(kinds)
    assert answer.views == %{count: 1, ids: [t.view.id]}
    assert answer.view_include_buckets.count == 1
    assert answer.view_exclude_buckets.count == 1
    assert answer.target_plans.count == 1
    assert answer.targets.count == 1
    assert answer.depot_snapshots.count == 1

    real = removed_by(kinds, fn -> Buckets.delete_view(owner(), t.view) end)

    assert answer == real
    assert_derived_notified()
  end

  # User story (X1, #894):
  # As the operator's agent asking what a delete would do,
  # I want a delete the real call refuses to be refused by the dry run in
  # the same words,
  # so that the dry run never promises a delete that would not happen.
  #
  # Acceptance criteria:
  # - A built-in classification's dry run answers {:error, :builtin_locked}.
  # - A classification, a category and a view a policy rule reads answer
  #   {:error, {:policy_rules, rules}} with the rules the real delete names.
  # - A view deleted meanwhile answers {:error, :not_found}, as the real
  #   delete does.
  # - Every refusal writes nothing.
  test "a refused delete's dry run answers the same refusal and writes nothing" do
    t = world()
    Classifications.ensure_builtins()
    asset = Classifications.get_classification_by_key("asset_class")

    {:ok, _category_rule} =
      PolicyRules.create_rule(owner(), %{
        portfolio_id: t.world.portfolio.id,
        name: "Growth income in band",
        version: %{
          "subject_type" => "category",
          "classification_id" => t.classification.id,
          "category_id" => t.child.id,
          "measure" => "drift",
          "kind" => "band",
          "lower" => "-3",
          "upper" => "3",
          "severity" => "warn"
        }
      })

    {:ok, _view_rule} =
      PolicyRules.create_rule(owner(), %{
        portfolio_id: t.world.portfolio.id,
        view_id: t.view.id,
        name: "Cash floor in the view",
        version: %{
          "subject_type" => "cash",
          "measure" => "weight",
          "kind" => "floor",
          "threshold" => "5",
          "severity" => "warn"
        }
      })

    {:ok, gone} = Buckets.create_view(owner(), %{name: "Gone #{System.unique_integer()}"})
    {:ok, _} = Buckets.delete_view(owner(), gone)

    pairs = [
      {&Classifications.dry_run_delete_classification/2, &Classifications.delete_classification/2,
       asset},
      {&Classifications.dry_run_delete_classification/2, &Classifications.delete_classification/2,
       t.classification},
      {&Classifications.dry_run_delete_category/2, &Classifications.delete_category/2, t.root},
      {&Buckets.dry_run_delete_view/2, &Buckets.delete_view/2, t.view},
      {&Buckets.dry_run_delete_view/2, &Buckets.delete_view/2, gone}
    ]

    for {dry_run, delete, record} <- pairs do
      counts = table_counts()
      assert {:error, refusal} = dry_run.(owner(), record)
      assert table_counts() == counts
      assert delete.(owner(), record) == {:error, refusal}
      assert table_counts() == counts
    end

    assert Classifications.dry_run_delete_classification(owner(), asset) ==
             {:error, :builtin_locked}

    assert {:error, {:policy_rules, [_rule]}} = Buckets.dry_run_delete_view(owner(), t.view)
    assert Buckets.dry_run_delete_view(owner(), gone) == {:error, :not_found}
  end

  # User story (X1, #894):
  # As the operator's agent reading a dry run,
  # I want every kind of row a delete can remove named in its answer, with
  # a count of 0 where it removes none,
  # so that a cascade added later cannot remove rows the dry run never lists.
  #
  # Acceptance criteria:
  # - Each dry run answers every kind, and its kinds' tables cover every
  #   table a cascading foreign key of `Journal.Cascades` removes for that
  #   delete and for the deletes it calls (a category's, a plan version's).
  test "a dry run names every table its delete's cascades reach" do
    {:ok, classification} = Classifications.create_classification(owner(), %{name: "Empty"})

    {:ok, category} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Alone"
      })

    {:ok, view} = Buckets.create_view(owner(), %{name: "Empty #{System.unique_integer()}"})

    plan = {Targets, :delete_plan_version, 2}
    category_delete = {Classifications, :delete_category, 2}

    for {dry_run, record, reached} <- [
          {&Classifications.dry_run_delete_classification/2, classification,
           [{Classifications, :delete_classification, 2}, category_delete, plan]},
          {&Classifications.dry_run_delete_category/2, category, [category_delete]},
          {&Buckets.dry_run_delete_view/2, view, [{Buckets, :delete_view, 2}, plan]}
        ] do
      assert {:ok, answer} = dry_run.(owner(), record)

      tables =
        MapSet.new(answer, fn {kind, %{count: _, ids: _}} ->
          @kinds |> Map.fetch!(kind) |> then(& &1.__schema__(:source))
        end)

      cascaded =
        Cascades.cascades()
        |> Enum.filter(&(&1.removed_by in reached))
        |> MapSet.new(& &1.table)

      assert MapSet.subset?(cascaded, tables),
             "#{inspect(record.__struct__)}: #{inspect(MapSet.difference(cascaded, tables))} unnamed"

      assert MapSet.member?(tables, record.__struct__.__schema__(:source))
    end
  end
end
