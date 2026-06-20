defmodule Portfolixir.Portfolios.TargetPlansTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets

  # User story:
  # As a local portfolio maintainer who runs more than one coherent strategy,
  # I want each view to carry its own SOLL target plan per classification (or
  # none), with the portfolio-wide "Gesamt" plan as the default (today's
  # behaviour),
  # so that I can steer a stock view and a crypto view to 100% each on the same
  # classification without their targets colliding into a ~200% Σ (ADR-0020).
  #
  # Acceptance criteria:
  # - A plan belongs to (portfolio, view, classification); view_id = NULL is the
  #   Gesamt/Total plan.
  # - list/set/delete/get default to the Gesamt plan (view: nil) and load ONLY
  #   that plan — Gesamt and a named view are independent.
  # - The same classification can carry a different plan per view.
  # - Deleting a view removes that view's plan (FK cascade), leaving Gesamt and
  #   other views untouched.
  # - "no plan" (no row at all) is distinct from an "empty plan" (a plan row that
  #   exists but carries no category targets).

  defp setup_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Local Portfolio", base_currency_code: "EUR"})

    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    {:ok, satellite} =
      Classifications.create_category(%{classification_id: classification.id, name: "Satellite"})

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Stocks"})

    %{
      portfolio: portfolio,
      classification: classification,
      core: core,
      satellite: satellite,
      view: view
    }
  end

  test "the Gesamt plan and a named-view plan are independent" do
    %{portfolio: p, classification: c, core: core, view: view} = setup_world()

    {:ok, _} =
      Targets.set_targets(p.id, c.id, [%{"category_id" => core.id, "target_weight" => "0.6"}])

    {:ok, _} =
      Targets.set_targets(p.id, c.id, [%{"category_id" => core.id, "target_weight" => "0.3"}],
        view: view
      )

    # The default read loads ONLY the Gesamt plan.
    [gesamt] = Targets.list_targets(p.id)
    assert Decimal.equal?(gesamt.target_weight, Decimal.new("0.6"))

    # Reading the named view loads ONLY that view's plan.
    [stocks] = Targets.list_targets(p.id, view: view)
    assert Decimal.equal?(stocks.target_weight, Decimal.new("0.3"))
  end

  test "the same classification carries a different plan per view" do
    %{portfolio: p, classification: c, core: core, satellite: satellite, view: view} =
      setup_world()

    {:ok, other_view} = Buckets.create_view(Actor.owner_ui(), %{name: "Crypto"})

    {:ok, _} =
      Targets.set_targets(p.id, c.id, [%{"category_id" => core.id, "target_weight" => "1.0"}],
        view: view
      )

    {:ok, _} =
      Targets.set_targets(
        p.id,
        c.id,
        [%{"category_id" => satellite.id, "target_weight" => "1.0"}],
        view: other_view
      )

    assert [%{category_id: cat_a}] = Targets.list_targets(p.id, view: view)
    assert cat_a == core.id

    assert [%{category_id: cat_b}] = Targets.list_targets(p.id, view: other_view)
    assert cat_b == satellite.id

    # Gesamt has no plan and therefore no targets.
    assert Targets.list_targets(p.id) == []
  end

  test "deleting a view removes its plan but leaves Gesamt and other views intact" do
    %{portfolio: p, classification: c, core: core, view: view} = setup_world()

    {:ok, _} =
      Targets.set_targets(p.id, c.id, [%{"category_id" => core.id, "target_weight" => "0.6"}])

    {:ok, _} =
      Targets.set_targets(p.id, c.id, [%{"category_id" => core.id, "target_weight" => "0.3"}],
        view: view
      )

    assert [_] = Targets.list_targets(p.id, view: view)

    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), view)

    # The view's plan (and its targets) are gone with the view (FK cascade).
    assert Targets.list_targets(p.id, view: view) == []

    # The Gesamt plan is untouched.
    assert [gesamt] = Targets.list_targets(p.id)
    assert Decimal.equal?(gesamt.target_weight, Decimal.new("0.6"))
  end

  test "an explicit empty plan is distinct from no plan at all" do
    %{portfolio: p, classification: c, view: view} = setup_world()

    # No plan exists yet for this view.
    refute Targets.plan_exists?(p.id, c.id, view: view)

    # Creating an empty plan (no category targets) materialises a plan row.
    {:ok, _plan} = Targets.ensure_plan(p.id, c.id, view: view)

    assert Targets.plan_exists?(p.id, c.id, view: view)
    assert Targets.list_targets(p.id, view: view) == []

    # The Gesamt plan still does not exist.
    refute Targets.plan_exists?(p.id, c.id)
  end

  # User story:
  # As a maintainer clearing a view's plan,
  # I want deleting the whole plan to default to the Gesamt plan and to be a
  # no-op when no plan exists,
  # so the delete path is safe to call without a `view:` option (ADR-0020).
  #
  # Acceptance criteria:
  # - `delete_plan/2` (default `view: nil` = Gesamt) removes the Gesamt plan and
  #   reports the number of plan rows removed.
  # - Deleting again (or with no plan at all) returns `{:ok, 0}` and leaves
  #   `plan_exists?/3` false.
  test "delete_plan defaults to the Gesamt plan and is a no-op when none exists" do
    %{portfolio: p, classification: c, core: core} = setup_world()

    # No plan yet: deleting is a harmless no-op (zero rows removed).
    assert {:ok, 0} = Targets.delete_plan(p.id, c.id)

    # Materialise a Gesamt plan, then delete it via the default (view: nil) path.
    {:ok, _} =
      Targets.set_targets(p.id, c.id, [%{"category_id" => core.id, "target_weight" => "0.6"}])

    assert Targets.plan_exists?(p.id, c.id)
    assert {:ok, 1} = Targets.delete_plan(p.id, c.id)

    refute Targets.plan_exists?(p.id, c.id)
    # A second delete finds nothing and stays a no-op.
    assert {:ok, 0} = Targets.delete_plan(p.id, c.id)
  end

  test "deleting a target only affects the addressed plan" do
    %{portfolio: p, classification: c, core: core, view: view} = setup_world()

    {:ok, _} =
      Targets.set_targets(p.id, c.id, [%{"category_id" => core.id, "target_weight" => "0.6"}])

    {:ok, _} =
      Targets.set_targets(p.id, c.id, [%{"category_id" => core.id, "target_weight" => "0.3"}],
        view: view
      )

    assert {:ok, 1} = Targets.delete_target(p.id, core.id, view: view)

    # The view's target is gone; the Gesamt one remains.
    assert Targets.list_targets(p.id, view: view) == []
    assert [_] = Targets.list_targets(p.id)
  end

  test "the view option accepts a raw view id as well as a %View{}" do
    %{portfolio: p, classification: c, core: core, view: view} = setup_world()

    # Write addressing the view by its integer id; read it back by the struct.
    {:ok, _} =
      Targets.set_targets(p.id, c.id, [%{"category_id" => core.id, "target_weight" => "0.25"}],
        view: view.id
      )

    [by_id] = Targets.list_targets(p.id, view: view.id)
    [by_struct] = Targets.list_targets(p.id, view: view)
    assert Decimal.equal?(by_id.target_weight, Decimal.new("0.25"))
    assert by_id.id == by_struct.id
  end

  test "get_target reads only the addressed plan" do
    %{portfolio: p, classification: c, core: core, view: view} = setup_world()

    {:ok, _} =
      Targets.set_targets(p.id, c.id, [%{"category_id" => core.id, "target_weight" => "0.6"}])

    assert %{target_weight: gesamt_w} = Targets.get_target(p.id, core.id)
    assert Decimal.equal?(gesamt_w, Decimal.new("0.6"))

    # The named view has no plan, so it has no target for this category.
    assert Targets.get_target(p.id, core.id, view: view) == nil
  end

  # User story:
  # As a maintainer steering a cash quote per view,
  # I want the cash target to live on the plan instead of a single global
  # portfolio field,
  # so that each view's plan carries its own coherent cash steering (ADR-0020).
  #
  # Acceptance criteria:
  # - The legacy portfolio-wide cash target is reachable via the portfolio's
  #   Gesamt plan (the migration carries it over).
  # - A view's plan can carry its own cash target, independent of Gesamt.
  test "cash target lives on the plan, per view" do
    %{portfolio: p, classification: c, view: view} = setup_world()

    :ok = Targets.set_cash_target(p.id, Decimal.new("0.05"))
    :ok = Targets.set_cash_target(p.id, Decimal.new("0.10"), view: view)

    assert Decimal.equal?(Targets.get_cash_target(p.id), Decimal.new("0.05"))
    assert Decimal.equal?(Targets.get_cash_target(p.id, view: view), Decimal.new("0.10"))

    # Per-classification override on the Gesamt plan is independent of the
    # portfolio-wide cash target.
    :ok = Targets.set_cash_target(p.id, Decimal.new("0.07"), classification_id: c.id)

    assert Decimal.equal?(
             Targets.get_cash_target(p.id, classification_id: c.id),
             Decimal.new("0.07")
           )

    # The portfolio-wide Gesamt cash target is unchanged.
    assert Decimal.equal?(Targets.get_cash_target(p.id), Decimal.new("0.05"))
  end
end
