defmodule Portfolixir.Portfolios.TargetPlanViewsTest do
  @moduledoc """
  `Targets.plan_views/2` (#1091, review round): the views in which one tree
  has a plan, read once for the classification screen's plan dots and its
  copy picker. Every name is invented.
  """
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets

  defp unique(name), do: "#{name} #{System.unique_integer([:positive])}"

  defp tree! do
    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: unique("Tree")})

    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {classification, category}
  end

  defp plan!(portfolio, {classification, category}, view_id, weight) do
    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [%{category_id: category.id, target_weight: weight}],
        view: view_id
      )
  end

  # User story (#1091, review round):
  # As a local portfolio maintainer on the classification screen,
  # I want the plan dot on a view's chip to mean that this tree has a plan
  # for that view -- the plan its editor shows, active or draft --
  # so that the dot never contradicts the editor below it.
  #
  # Acceptance criteria:
  # - Each view (`nil` for Everything) with a plan of this tree maps to
  #   whether one of its plans is active; a draft-only view maps to false.
  # - A portfolio-wide cash target alone is no plan of this tree.
  # - Another tree's plan in a view is not this tree's.
  # - Another portfolio's plan is not this portfolio's.
  test "maps each view in which the tree has a plan to whether it is active" do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: unique("Plans"),
        base_currency_code: "EUR"
      })

    {:ok, other_portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: unique("Other plans"),
        base_currency_code: "EUR"
      })

    tree = tree!()
    other_tree = tree!()

    views =
      for name <- ~w(Drafted Cash Other Foreign) do
        {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: unique(name)})
        view
      end

    [drafted, cash, other, foreign] = views

    plan!(portfolio, tree, nil, "0.6")

    plan!(portfolio, tree, drafted.id, "0.3")

    [active] =
      Targets.list_plans(portfolio.id, classification_id: elem(tree, 0).id, view: drafted.id)

    {:ok, _draft} = Targets.duplicate_plan(Actor.owner_ui(), active.id)
    {:ok, _} = Targets.delete_plan_version(Actor.owner_ui(), active.id)

    :ok = Targets.set_cash_target(Actor.owner_ui(), portfolio.id, "0.1", view: cash.id)
    plan!(portfolio, other_tree, other.id, "1")
    plan!(other_portfolio, tree, foreign.id, "1")

    assert Targets.plan_views(portfolio.id, elem(tree, 0).id) == %{
             nil => true,
             drafted.id => false
           }

    # A view with an active plan and a draft beside it is active.
    plan!(portfolio, tree, other.id, "0.5")

    [other_active] =
      Targets.list_plans(portfolio.id, classification_id: elem(tree, 0).id, view: other.id)

    {:ok, _} = Targets.duplicate_plan(Actor.owner_ui(), other_active.id)

    assert Targets.plan_views(portfolio.id, elem(tree, 0).id) ==
             %{nil => true, drafted.id => false, other.id => true}
  end
end
