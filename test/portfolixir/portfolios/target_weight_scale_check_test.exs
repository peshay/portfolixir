defmodule Portfolixir.Portfolios.TargetWeightScaleCheckTest do
  # E25 S4, G14 (#889): the changesets bound a weight's scale, and the
  # database refuses a finer one on every writer that bypasses them.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Portfolios.TargetPlan
  alias Portfolixir.Portfolios.Targets

  defp as_actor(fun) do
    Repo.transaction(fn ->
      {type, _label} = Actor.to_columns(Actor.owner_ui())
      Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])
      fun.()
    end)
  end

  test "a raw write of a weight finer than six decimal places violates the check" do
    world = base_world(name: "Scale check")
    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, growth} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Growth"
      })

    {:ok, [target]} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, tree.id, [
        %{"category_id" => growth.id, "target_weight" => "0.123456"}
      ])

    assert_raise Postgrex.Error, ~r/portfolio_targets_target_weight_scale_check/, fn ->
      as_actor(fn ->
        Target
        |> where(id: ^target.id)
        |> Repo.update_all(set: [target_weight: Decimal.new("0.1234567")])
      end)
    end

    assert_raise Postgrex.Error, ~r/portfolio_target_plans_cash_target_weight_scale_check/, fn ->
      as_actor(fn ->
        TargetPlan
        |> where(id: ^target.plan_id)
        |> Repo.update_all(set: [cash_target_weight: Decimal.new("0.0500001")])
      end)
    end

    assert Decimal.equal?(Repo.reload(target).target_weight, Decimal.new("0.123456"))
  end
end
