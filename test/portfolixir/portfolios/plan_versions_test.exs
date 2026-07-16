defmodule Portfolixir.Portfolios.PlanVersionsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets

  # User story (Andi, 2026-07-16, ADR-0027):
  # As a local portfolio maintainer who wants to restructure my allocation plan,
  # I want to duplicate a plan into a named draft, edit the draft while the old
  # plan stays visible, and activate the draft when I commit to the new strategy,
  # so that old and new plan coexist and every plan write is auditable.
  #
  # Acceptance criteria:
  # - A plan carries a name and a status: active / draft / archived.
  # - Existing plans keep working: loss-free migration defaults them to active.
  # - duplicate_plan/3 copies category targets and cash target into a draft.
  # - activate_plan/2 archives the previously active plan of the same
  #   (portfolio, view, classification) scope in the same transaction.
  # - Reads and the allocation engine consume ONLY the active plan; drafts and
  #   archived plans never leak into SOLL/IST.
  # - Every plan/target write is journaled (ADR-0017): actor-first signatures,
  #   entries in audit_journal, direct unjournaled writes are rejected by the
  #   guard trigger.

  defp setup_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Local Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, satellite} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Satellite"
      })

    %{portfolio: portfolio, classification: classification, core: core, satellite: satellite}
  end

  test "duplicate_plan copies targets and cash target into a named draft" do
    %{portfolio: portfolio, classification: classification, core: core, satellite: satellite} =
      setup_world()

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{category_id: core.id, target_weight: Decimal.new("0.6")},
        %{category_id: satellite.id, target_weight: Decimal.new("0.3")}
      ])

    :ok =
      Targets.set_cash_target(Actor.owner_ui(), portfolio.id, Decimal.new("0.1"),
        classification_id: classification.id
      )

    [active] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    assert active.status == "active"

    {:ok, draft} =
      Targets.duplicate_plan(Actor.owner_ui(), active.id, %{name: "Plan 2027"})

    assert draft.status == "draft"
    assert draft.name == "Plan 2027"
    assert draft.view_id == active.view_id
    assert Decimal.equal?(draft.cash_target_weight, Decimal.new("0.1"))

    draft_targets = Targets.list_targets(portfolio.id, plan: draft.id)
    assert length(draft_targets) == 2

    weights = Map.new(draft_targets, &{&1.category_id, &1.target_weight})
    assert Decimal.equal?(weights[core.id], Decimal.new("0.6"))
    assert Decimal.equal?(weights[satellite.id], Decimal.new("0.3"))
  end

  test "activate_plan archives the previously active plan of the same scope" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{category_id: core.id, target_weight: Decimal.new("0.8")}
      ])

    [old_active] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    {:ok, draft} = Targets.duplicate_plan(Actor.owner_ui(), old_active.id, %{name: "New plan"})

    {:ok, activated} = Targets.activate_plan(Actor.owner_ui(), draft.id)
    assert activated.status == "active"

    plans = Targets.list_plans(portfolio.id, classification_id: classification.id)
    statuses = Map.new(plans, &{&1.id, &1.status})
    assert statuses[draft.id] == "active"
    assert statuses[old_active.id] == "archived"
  end

  test "reads and drift consume only the active plan; drafts never leak" do
    %{portfolio: portfolio, classification: classification, core: core, satellite: satellite} =
      setup_world()

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{category_id: core.id, target_weight: Decimal.new("0.5")}
      ])

    [active] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    {:ok, draft} = Targets.duplicate_plan(Actor.owner_ui(), active.id, %{name: "Draft"})

    # Editing the draft must not change what the engine reads.
    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [%{category_id: satellite.id, target_weight: Decimal.new("0.4")}],
        plan: draft.id
      )

    visible = Targets.list_targets(portfolio.id, classification_id: classification.id)
    assert Enum.map(visible, & &1.category_id) == [core.id]

    # A view whose only plan is a draft has no plan for the SOLL surface.
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Stocks"})

    {:ok, _view_draft} =
      Targets.duplicate_plan(Actor.owner_ui(), active.id, %{name: "V", view_id: view.id})

    refute Targets.plan_exists?(portfolio.id, classification.id, view: view.id)
  end

  test "plan and target writes are journaled; direct writes are rejected" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{category_id: core.id, target_weight: Decimal.new("0.7")}
      ])

    assert [%{operation: :create}] = Journal.list_entries(resource_type: "target_plan")
    assert [%{operation: :upsert}] = Journal.list_entries(resource_type: "target")

    [active] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    {:ok, draft} = Targets.duplicate_plan(Actor.owner_ui(), active.id, %{name: "Copy"})
    {:ok, _} = Targets.activate_plan(Actor.owner_ui(), draft.id)

    plan_entries = Journal.list_entries(resource_type: "target_plan")
    assert Enum.count(plan_entries, &(&1.operation == :create)) == 2
    assert Enum.count(plan_entries, &(&1.operation == :update)) == 2

    # The guard trigger rejects a write that bypasses the journal seam.
    assert_raise Postgrex.Error, ~r/journal actor/i, fn ->
      Repo.insert_all("portfolio_target_plans", [
        %{
          portfolio_id: portfolio.id,
          name: "smuggled",
          status: "draft",
          inserted_at: NaiveDateTime.utc_now(:second),
          updated_at: NaiveDateTime.utc_now(:second)
        }
      ])
    end
  end

  test "repeated activations keep exactly one active plan per scope" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{category_id: core.id, target_weight: Decimal.new("0.7")}
      ])

    [active] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    {:ok, a} = Targets.duplicate_plan(Actor.owner_ui(), active.id, %{name: "A"})
    {:ok, b} = Targets.duplicate_plan(Actor.owner_ui(), active.id, %{name: "B"})

    {:ok, _} = Targets.activate_plan(Actor.owner_ui(), a.id)
    {:ok, _} = Targets.activate_plan(Actor.owner_ui(), b.id)
    # Re-activating the already-active plan is a no-op, not an error.
    {:ok, _} = Targets.activate_plan(Actor.owner_ui(), b.id)

    plans = Targets.list_plans(portfolio.id, classification_id: classification.id)
    assert Enum.count(plans, &(&1.status == "active")) == 1
    assert Enum.find(plans, &(&1.status == "active")).id == b.id
  end
end
