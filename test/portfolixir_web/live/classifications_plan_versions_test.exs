defmodule PortfolixirWeb.ClassificationsPlanVersionsTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 0]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Targets

  # User story (Andi, 2026-07-16, ADR-0027):
  # As a portfolio maintainer about to restructure my allocation plan,
  # I want to duplicate the current plan into a named draft on the
  # classifications page, edit the draft while the active plan stays in
  # charge, and activate it when I commit to the new strategy,
  # so that the old and the new plan coexist and the switch is one click.
  #
  # Acceptance criteria:
  # - The SOLL editor offers "Duplicate plan"; the copy appears as a draft in
  #   a plan picker and the editor switches to it.
  # - Saving weights on the draft leaves the active plan's targets untouched.
  # - "Activate this plan" makes the draft active and archives the previous
  #   active plan; the editor follows the newly active plan.

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

    Map.merge(world, %{classification: classification, equity: equity})
  end

  defp live_drained(conn, path) do
    {:ok, view, html} = live(conn, path)
    render_async(view)
    {:ok, view, html}
  end

  test "duplicates the active plan into a draft the editor then edits", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = plan_world()

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    view |> element("button[phx-click='duplicate_soll_plan']") |> render_click()

    # A draft exists and the picker shows it selected.
    plans = Targets.list_plans(portfolio.id, classification_id: classification.id)
    assert [%{status: "active"}, %{status: "draft"} = draft] = plans
    assert has_element?(view, "select[name='soll_plan'] option[selected][value='#{draft.id}']")

    # Editing the draft leaves the active plan untouched.
    # The cash target stays with the active plan, so its input is disabled in
    # draft mode and only the category weights are submitted.
    view
    |> form("#soll-plan-form", %{"weights" => %{"#{equity.id}" => "50"}})
    |> render_submit()

    [active_target] =
      Targets.list_targets(portfolio.id, classification_id: classification.id)

    assert Decimal.equal?(active_target.target_weight, Decimal.new("0.8"))

    [draft_target] = Targets.list_targets(portfolio.id, plan: draft.id)
    assert Decimal.equal?(draft_target.target_weight, Decimal.new("0.5"))
  end

  test "activates a draft, archiving the previously active plan", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = plan_world()

    [active] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    {:ok, draft} = Targets.duplicate_plan(Actor.owner_ui(), active.id, %{name: "Plan 2027"})

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    # Switch the editor to the draft, then activate it.
    view
    |> element("form.soll-plan-picker")
    |> render_change(%{"soll_plan" => "#{draft.id}"})

    view |> element("button[phx-click='activate_soll_plan']") |> render_click()

    plans = Targets.list_plans(portfolio.id, classification_id: classification.id)
    statuses = Map.new(plans, &{&1.id, &1.status})
    assert statuses[draft.id] == "active"
    assert statuses[active.id] == "archived"
  end
end
