defmodule PortfolixirWeb.TargetWeightLegacyTest do
  # E25 S4, G14 (#889), from the S3/S4 review round: before this sprint a
  # target or cash-target weight of any precision was accepted, so an instance
  # can hold one finer than the six decimal places the bound now allows. The
  # bound's migration added its database CHECK `NOT VALID` whatever it found,
  # and PostgreSQL checks such a constraint against the whole row on every
  # update — so archiving, renaming, duplicating or saving a plan that carried
  # such a weight failed, though none of them changed it.
  #
  # The migrator cannot be driven under the SQL sandbox, so, like
  # import_hash_kind_check_test.exs, this test rebuilds the state inside the
  # sandbox transaction (the constraints dropped, a legacy weight written past
  # the changeset) and runs the migration's own step on it. Everything rolls
  # back at the end of the test.
  #
  # async: false — the test drops and re-adds constraints on the plan tables,
  # which takes a lock every concurrent test on the targets would wait on.
  use PortfolixirWeb.ConnCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Portfolios.TargetPlan
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Repo

  @migration "priv/repo/migrations/20260925180000_keep_target_weight_scale_checks_valid.exs"
  @migration_module Portfolixir.Repo.Migrations.KeepTargetWeightScaleChecksValid

  @checks [
    {"portfolio_targets", "portfolio_targets_target_weight_scale_check", "target_weight"},
    {"portfolio_target_plans", "portfolio_target_plans_cash_target_weight_scale_check",
     "cash_target_weight"}
  ]

  setup do
    for {table, name, _column} <- @checks do
      Repo.query!("ALTER TABLE #{table} DROP CONSTRAINT #{name}")
    end

    world = base_world(name: "Legacy weights")

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, growth} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Growth"
      })

    {:ok, [target]} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, tree.id, [
        %{"category_id" => growth.id, "target_weight" => "0.333333"}
      ])

    :ok =
      Targets.set_cash_target(Actor.owner_ui(), world.portfolio.id, Decimal.new("0.05"),
        classification_id: tree.id
      )

    %{world: world, tree: tree, growth: growth, target: target, plan_id: target.plan_id}
  end

  # A weight stored before the bound existed, written past the changeset the
  # way the old writers stored it.
  defp store_legacy_weights!(%{target: target, plan_id: plan_id}) do
    as_actor(fn ->
      Target
      |> where(id: ^target.id)
      |> Repo.update_all(set: [target_weight: Decimal.new("0.3333333333")])

      TargetPlan
      |> where(id: ^plan_id)
      |> Repo.update_all(set: [cash_target_weight: Decimal.new("0.0500000001")])
    end)
  end

  defp as_actor(fun) do
    Repo.transaction(fn ->
      {type, _label} = Actor.to_columns(Actor.owner_ui())
      Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])
      fun.()
    end)
  end

  # The state the bound's migration left: each CHECK added NOT VALID.
  defp add_checks_not_valid! do
    for {table, name, column} <- @checks do
      Repo.query!("""
      ALTER TABLE #{table}
        ADD CONSTRAINT #{name} CHECK (#{column} = round(#{column}, 6)) NOT VALID
      """)
    end
  end

  defp check_state(name) do
    case Repo.query!("SELECT convalidated FROM pg_constraint WHERE conname = $1", [name]) do
      %{rows: [[true]]} -> :validated
      %{rows: [[false]]} -> :not_valid
      %{rows: []} -> :absent
    end
  end

  defp migration do
    case Code.ensure_loaded(@migration_module) do
      {:module, module} ->
        module

      {:error, _not_loaded} ->
        [{module, _bytecode}] = Code.require_file(@migration)
        module
    end
  end

  # User story:
  # As an operator upgrading an instance whose agent once stored a weight
  # finer than six decimal places,
  # I want the upgrade to keep the database's weight-scale check only where my
  # stored weights meet it, and to tell me where they do not,
  # so that no plan of mine becomes impossible to archive, rename, duplicate
  # or save.
  #
  # Acceptance criteria:
  # - With such a weight stored, the check left NOT VALID is removed, and the
  #   upgrade logs how many weights are finer and how to round them.
  # - Without one, the check is validated.
  test "the upgrade keeps the weight-scale check only where the stored weights meet it",
       context do
    add_checks_not_valid!()
    log = capture_log(fn -> migration().reconcile(Repo) end)

    for {_table, name, _column} <- @checks, do: assert(check_state(name) == :validated)
    refute log =~ "decimal places"

    for {table, name, _column} <- @checks do
      Repo.query!("ALTER TABLE #{table} DROP CONSTRAINT #{name}")
    end

    store_legacy_weights!(context)
    add_checks_not_valid!()
    log = capture_log(fn -> migration().reconcile(Repo) end)

    for {_table, name, _column} <- @checks, do: assert(check_state(name) == :absent)
    assert log =~ "portfolio_targets"
    assert log =~ "portfolio_target_plans"
    assert log =~ "more than 6 decimal places"
  end

  # User story:
  # As an operator whose plan carries a weight stored before the bound,
  # I want to archive it by activating another plan, rename it, duplicate it
  # and save it from the SOLL editor,
  # so that a weight I never changed does not lock the plan.
  #
  # Acceptance criteria:
  # - Renaming the plan and activating another plan of its scope succeed.
  # - Duplicating it succeeds; the copy's weights are rounded half up to six
  #   decimal places.
  # - The SOLL editor shows the stored weight at the precision a plan holds,
  #   and saving the untouched form succeeds; the saved weight is the one
  #   shown, and the change is journaled.
  test "a plan carrying a weight stored before the bound stays editable",
       %{conn: conn, world: world, tree: tree, plan_id: plan_id} = context do
    store_legacy_weights!(context)

    assert {:ok, _renamed} = Targets.rename_plan(Actor.owner_ui(), plan_id, "Legacy plan")

    assert {:ok, copy} = Targets.duplicate_plan(Actor.owner_ui(), plan_id, %{name: "Copy"})
    assert Decimal.equal?(copy.cash_target_weight, Decimal.new("0.05"))

    [copied] = Repo.all(from(t in Target, where: t.plan_id == ^copy.id))
    assert Decimal.equal?(copied.target_weight, Decimal.new("0.333333"))

    assert {:ok, _active} = Targets.activate_plan(Actor.owner_ui(), copy.id)
    assert {:ok, _active} = Targets.activate_plan(Actor.owner_ui(), plan_id)

    {:ok, view, _html} = live(conn, "/classifications/#{tree.id}")
    render_async(view)

    assert has_element?(view, "input[name='weights[#{context.growth.id}]'][value='33.3333']")

    view |> form("#soll-plan-form") |> render_submit()
    assert render(view) =~ "Plan saved"

    stored = Repo.get_by!(Target, plan_id: plan_id, category_id: context.growth.id)
    assert Decimal.equal?(stored.target_weight, Decimal.new("0.333333"))

    assert Enum.any?(
             Journal.list_entries(resource_type: "target"),
             &(&1.resource_id == to_string(stored.id) and &1.operation == :upsert)
           )

    assert world.portfolio.id == stored.portfolio_id
  end
end
