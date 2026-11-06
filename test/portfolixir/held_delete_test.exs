defmodule Portfolixir.HeldDeleteTest do
  # Sprint 26 V4 (F21, #894; board 04, "the confirm holds to the list it
  # showed"): the screen's delete dialog lists what the dry run says a delete
  # removes, and its confirm runs the delete held to that list. The delete,
  # the comparison and the commit or the rollback are one transaction
  # (`Portfolixir.DryRun.held_to/3`), so no row can land between a check and
  # the delete it allowed.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.Portfolios.Targets

  defp owner, do: Actor.owner_ui()

  # A custom tree with a root and a child holding one security, a plan with
  # a target on the child, and a view with a plan of its own and a snapshot.
  defp world do
    world = base_world(name: "Held Delete Portfolio")
    security = create_security!(name: "Northwind Harbour Logistics AG", ticker: "NHL")
    other = create_security!(name: "Larkspur Robotics Inc", ticker: "LRK")
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
        %{category_id: child.id, target_weight: Decimal.new("0.4")}
      ])

    {:ok, view} =
      Buckets.create_view(owner(), %{name: "Held scope #{System.unique_integer([:positive])}"})

    {:ok, _view_targets} =
      Targets.set_targets(
        owner(),
        world.portfolio.id,
        classification.id,
        [%{category_id: root.id, target_weight: Decimal.new("0.5")}],
        view: view
      )

    %{
      world: world,
      other: other,
      classification: classification,
      root: root,
      child: child,
      view: view
    }
  end

  # Every table of the database with its row count.
  defp table_counts do
    %{rows: tables} =
      Repo.query!("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY 1")

    Map.new(tables, fn [table] ->
      %{rows: [[count]]} = Repo.query!(~s[SELECT count(*) FROM "#{table}"])
      {table, count}
    end)
  end

  # User story (V4, #894):
  # As the operator confirming a delete the dialog listed,
  # I want the delete to remove exactly the rows the list named,
  # so that what I confirmed is what happened.
  #
  # Acceptance criteria:
  # - Held to the dry run's answer, each of the three deletes removes the
  #   rows and answers what it removed, equal to the dry run's answer.
  test "a delete held to its dry run's answer removes those rows" do
    t = world()

    {:ok, answer} = Classifications.dry_run_delete_category(owner(), t.root)
    assert {:ok, ^answer} = Classifications.delete_category(owner(), t.root, held_to: answer)
    refute Classifications.get_category(t.root.id)
    refute Classifications.get_category(t.child.id)

    {:ok, answer} = Buckets.dry_run_delete_view(owner(), t.view)
    assert {:ok, ^answer} = Buckets.delete_view(owner(), t.view, held_to: answer)
    refute Buckets.get_view(t.view.id)

    {:ok, answer} = Classifications.dry_run_delete_classification(owner(), t.classification)

    assert {:ok, ^answer} =
             Classifications.delete_classification(owner(), t.classification, held_to: answer)

    refute Classifications.get_classification(t.classification.id)
  end

  # User story (V4, #894; board 04, "F21 ohne Abgleich" not taken):
  # As the operator whose tree changed while the delete dialog was open,
  # I want the confirm to delete nothing and tell me what the delete removes
  # now,
  # so that I never delete a row the dialog did not show me.
  #
  # Acceptance criteria:
  # - A security assigned after the dry run makes the held delete answer
  #   `{:error, {:changed, now}}`, `now` the dry run's answer as it is now.
  # - Every table, the journal included, counts the same as before the
  #   confirm.
  test "a delete held to an answer that no longer holds deletes nothing" do
    t = world()

    {:ok, category_answer} = Classifications.dry_run_delete_category(owner(), t.root)

    {:ok, classification_answer} =
      Classifications.dry_run_delete_classification(owner(), t.classification)

    {:ok, _} =
      Classifications.assign_security(owner(), t.other.id, t.classification.id, t.root.id)

    {:ok, category_now} = Classifications.dry_run_delete_category(owner(), t.root)
    assert category_now.assignments.count == category_answer.assignments.count + 1

    counts = table_counts()

    assert {:error, {:changed, ^category_now}} =
             Classifications.delete_category(owner(), t.root, held_to: category_answer)

    assert table_counts() == counts

    assert {:error, {:changed, changed}} =
             Classifications.delete_classification(owner(), t.classification,
               held_to: classification_answer
             )

    assert changed.assignments.count == classification_answer.assignments.count + 1
    assert table_counts() == counts
  end

  # Acceptance criteria:
  # - A view that gained a snapshot after its dry run is not deleted held to
  #   the old answer; the answer names the snapshot.
  test "a view held to an answer without its new snapshot is not deleted" do
    t = world()
    {:ok, answer} = Buckets.dry_run_delete_view(owner(), t.view)
    assert answer.depot_snapshots.count == 0

    {:ok, snapshot} =
      Snapshots.create_snapshot(owner(), %{
        name: "Later",
        view_id: t.view.id,
        as_of: ~D[2026-07-01]
      })

    assert {:error, {:changed, now}} = Buckets.delete_view(owner(), t.view, held_to: answer)
    assert now.depot_snapshots.ids == [snapshot.id]
    assert Buckets.get_view(t.view.id)
  end

  # Acceptance criteria:
  # - A refusal the delete answers (a built-in tree) is the held delete's
  #   answer too, and nothing is deleted.
  test "a refused delete is refused held as well" do
    builtin = %Classification{id: 0, name: "Asset class", built_in: true}

    assert {:error, :builtin_locked} =
             Classifications.delete_classification(owner(), builtin, held_to: %{})
  end
end
