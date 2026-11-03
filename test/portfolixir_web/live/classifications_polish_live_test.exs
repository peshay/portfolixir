defmodule PortfolixirWeb.ClassificationsPolishLiveTest do
  # Two lines of the Classifications polish list (#1362) that Sprint 23's
  # Lane I page story fixes: #1226 (by its recommendation, a duplicated plan
  # version is named in the reader's language) and #1324 (a dismissed
  # result was focused twice). Every name is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 0]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Targets

  defp plan_world do
    world = base_world()

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, equity} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Equity"
      })

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, classification.id, [
        %{category_id: equity.id, target_weight: Decimal.new("0.8")}
      ])

    [plan] = Targets.list_plans(world.portfolio.id, classification_id: classification.id)
    Map.merge(world, %{classification: classification, plan: plan, equity: equity})
  end

  defp draft_name(portfolio, classification) do
    portfolio.id
    |> Targets.list_plans(classification_id: classification.id)
    |> Enum.find(&(&1.status == "draft"))
    |> Map.fetch!(:name)
  end

  # User story (#1226; the Sprint 21 design pass, board 06):
  # As the operator duplicating a plan version on a German screen,
  # I want the copy named "… (Kopie)",
  # so that the stored name reads in my language, not "… (copy)" for good.
  #
  # Acceptance criteria:
  # - On the German screen „Plan duplizieren“ names the draft „<name>
  #   (Kopie)“; on the English screen "<name> (copy)".
  # - The name is clamped to 120 code points, as the store's default is.
  # - The API and MCP keep their optional `name` and the English default
  #   (unchanged here).
  test "a duplicated plan is named in the reader's language", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, plan: plan} = plan_world()
    {:ok, _} = Targets.rename_plan(Actor.owner_ui(), plan.id, "Kernplan")

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}?locale=de")
    render_async(view)
    view |> element("button[phx-click='duplicate_soll_plan']") |> render_click()

    assert draft_name(portfolio, classification) == "Kernplan (Kopie)"
  end

  test "a duplicated plan's name is clamped to 120 code points", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, plan: plan} = plan_world()
    long = String.duplicate("ä", 118)
    {:ok, _} = Targets.rename_plan(Actor.owner_ui(), plan.id, long)

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    render_async(view)
    view |> element("button[phx-click='duplicate_soll_plan']") |> render_click()

    assert draft_name(portfolio, classification) == long <> " ("
  end

  # User story (#1324; #1166's pick N13 A):
  # As the operator dismissing a result on the classification screen,
  # I want the focus to go back once, where the shared rule puts it,
  # so that it does not land on the trigger and then jump to a heading.
  #
  # Acceptance criteria:
  # - The dismiss pushes no focus of the page's own ("focus-into-view"):
  #   the shared `InlineResult` hook alone gives the focus back (the
  #   trigger, else the tree's heading).
  # - A refusal that names an input names it as the result's
  #   `data-focus-return`, so the dismiss returns there, as before.
  test "a dismiss leaves the focus to the shared hook, a refused input named (#1324)",
       %{conn: conn} do
    %{classification: classification, equity: equity} = plan_world()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    render_async(view)

    view
    |> form("#soll-plan-form", %{"weights" => %{"#{equity.id}" => "150"}})
    |> render_submit()

    # The refusal itself is brought into view (#945), as before.
    assert_push_event(view, "focus-into-view", %{id: "classifications-result"})

    assert has_element?(
             view,
             "#classifications-result[data-focus-return='#soll-weight-#{equity.id}']"
           )

    view |> element("#classifications-result [data-role='result-dismiss']") |> render_click()
    refute_push_event(view, "focus-into-view", %{})
    refute has_element?(view, "#classifications-result[data-focus-return]")

    view
    |> form("#soll-plan-form", %{"weights" => %{"#{equity.id}" => "60"}})
    |> render_submit()

    view |> element("#classifications-result [data-role='result-dismiss']") |> render_click()
    refute_push_event(view, "focus-into-view", %{})
  end
end
