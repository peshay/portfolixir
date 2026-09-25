defmodule Portfolixir.Journal.CascadeRemovalsTest do
  # E25 S6 (#891), F43: deleting a classification, a category, a plan or a
  # view removed its children — categories, stored assignments, plans and
  # their targets, depot snapshots — through the database's ON DELETE
  # CASCADE, so the journal recorded only the parent. Each delete now removes
  # its children through their journaled context functions first (the #481
  # pattern), one entry per row, and the cascades stay as a backstop that
  # finds nothing left. ADR-0050 §11 covered the account, depot and security
  # share; this covers the rest.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.Portfolios.Targets

  defp owner, do: Actor.owner_ui()

  defp deleted(type) do
    [resource_type: type, operation: :delete]
    |> Journal.list_entries()
    |> MapSet.new(&String.to_integer(&1.resource_id))
  end

  # A custom tree `Strategy` with a root category, a child under it holding
  # one security, and an active plan carrying a category target and a
  # position target on the child.
  defp tree do
    world = base_world(name: "Cascade Portfolio")
    security = create_security!(name: "Harbor Light Utilities SE", ticker: "HLU")
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

    {:ok, assignment} =
      Classifications.assign_security(owner(), security.id, classification.id, child.id)

    {:ok, targets} =
      Targets.set_targets(owner(), world.portfolio.id, classification.id, [
        %{category_id: child.id, target_weight: Decimal.new("0.4")},
        %{category_id: child.id, security_id: security.id, target_weight: Decimal.new("0.2")}
      ])

    [plan] = Targets.list_plans(world.portfolio.id, classification_id: classification.id)

    %{
      world: world,
      security: security,
      classification: classification,
      root: root,
      child: child,
      assignment: assignment,
      targets: targets,
      plan: plan
    }
  end

  # User story:
  # As the operator reading the audit journal after deleting a strategy tree,
  # I want every row the delete removed to have its own journal entry,
  # so that the tree's categories, assignments and targets are traceable
  # after it is gone, not only its name.
  #
  # Acceptance criteria:
  # - Deleting a classification journals a delete for each of its
  #   categories, each stored assignment, each plan and each of its targets,
  #   and then for the classification itself.
  test "deleting a classification removes its categories, assignments, plans and targets per row" do
    t = tree()

    assert {:ok, _} = Classifications.delete_classification(owner(), t.classification)

    assert MapSet.subset?(MapSet.new([t.root.id, t.child.id]), deleted("category"))
    assert MapSet.member?(deleted("security_category_assignment"), t.assignment.id)
    assert MapSet.member?(deleted("target_plan"), t.plan.id)
    assert MapSet.subset?(MapSet.new(t.targets, & &1.id), deleted("target"))
    assert MapSet.member?(deleted("classification"), t.classification.id)
  end

  # User story:
  # As the operator deleting one branch of a tree,
  # I want the categories below it, the securities assigned there and the
  # targets set on them journaled one by one,
  # so that the branch can be reconstructed from the journal.
  #
  # Acceptance criteria:
  # - Deleting a category journals a delete for each descendant category,
  #   each assignment and each target in the subtree, and the category last.
  # - The plan itself stays.
  test "deleting a category removes its subtree's categories, assignments and targets per row" do
    t = tree()

    assert {:ok, _} = Classifications.delete_category(owner(), t.root)

    assert MapSet.subset?(MapSet.new([t.root.id, t.child.id]), deleted("category"))
    assert MapSet.member?(deleted("security_category_assignment"), t.assignment.id)
    assert MapSet.subset?(MapSet.new(t.targets, & &1.id), deleted("target"))
    refute MapSet.member?(deleted("target_plan"), t.plan.id)
  end

  # User story:
  # As the operator cleaning up a plan version,
  # I want its targets journaled as they go,
  # so that the version's weights stay readable in the journal.
  #
  # Acceptance criteria:
  # - Deleting a plan version journals each of its targets, then the plan.
  test "deleting a plan version removes its targets per row" do
    t = tree()

    assert {:ok, _} = Targets.delete_plan_version(owner(), t.plan.id)

    assert MapSet.subset?(MapSet.new(t.targets, & &1.id), deleted("target"))
    assert MapSet.member?(deleted("target_plan"), t.plan.id)
  end

  # User story:
  # As the operator deleting a view,
  # I want the plans and snapshots scoped to it journaled one by one,
  # so that deleting a scope does not silently take the steering set on it.
  #
  # Acceptance criteria:
  # - Deleting a view journals each plan scoped to it with its targets, each
  #   depot snapshot scoped to it, and then the view.
  test "deleting a view removes its plans, their targets and its snapshots per row" do
    t = tree()

    {:ok, view} =
      Buckets.create_view(owner(), %{name: "Strategy scope #{System.unique_integer([:positive])}"})

    {:ok, [view_target]} =
      Targets.set_targets(
        owner(),
        t.world.portfolio.id,
        t.classification.id,
        [%{category_id: t.child.id, target_weight: Decimal.new("0.5")}],
        view: view
      )

    [view_plan] =
      Targets.list_plans(t.world.portfolio.id, classification_id: t.classification.id, view: view)

    {:ok, snapshot} =
      Snapshots.create_snapshot(owner(), %{
        name: "Before the change",
        view_id: view.id,
        as_of: ~D[2026-07-01]
      })

    assert {:ok, _} = Buckets.delete_view(owner(), view)

    assert MapSet.member?(deleted("target"), view_target.id)
    assert MapSet.member?(deleted("target_plan"), view_plan.id)
    assert MapSet.member?(deleted("snapshot"), snapshot.id)
    assert MapSet.member?(deleted("view"), view.id)
    refute MapSet.member?(deleted("target_plan"), t.plan.id)
  end

  # User story:
  # As the operator moving securities between asset classes in bulk,
  # I want each security's previous asset class in the journal,
  # so that a mistaken bulk move can be read back and undone.
  #
  # Acceptance criteria:
  # - The bulk write's entry carries, as its before-image, every affected
  #   security with the asset class it had.
  test "a bulk asset-class write journals each security's prior asset class" do
    {:ok, equity} =
      Catalog.create_security(owner(), %{
        name: "Kestrel Industrial Group NV",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, bond} =
      Catalog.create_security(owner(), %{
        name: "Lockstep Rail 2031",
        currency_code: "EUR",
        asset_class: "bond"
      })

    assert Catalog.set_asset_class(owner(), [equity.id, bond.id], "etf") == 2

    [entry | _] = Journal.list_entries(resource_type: "security", operation: :update)
    assert entry.after["asset_class"] == "etf"

    assert Enum.sort_by(entry.before["asset_classes"], & &1["security_id"]) ==
             Enum.sort_by(
               [
                 %{"security_id" => equity.id, "asset_class" => "equity"},
                 %{"security_id" => bond.id, "asset_class" => "bond"}
               ],
               & &1["security_id"]
             )
  end
end
