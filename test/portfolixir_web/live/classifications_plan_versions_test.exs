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

  # Review finding: after deleting the active plan while a draft survives, the
  # lone draft used to be unreachable (picker hidden, editor in empty state).
  # The editor now falls back to the first remaining version.
  test "a lone surviving draft stays reachable and activatable", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = plan_world()

    [active] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    {:ok, draft} = Targets.duplicate_plan(Actor.owner_ui(), active.id, %{name: "Survivor"})
    {:ok, _} = Targets.delete_plan_version(Actor.owner_ui(), active.id)

    {:ok, view, html} = live_drained(conn, "/classifications/#{classification.id}")

    # The draft is selected (name visible), editable and activatable.
    assert html =~ "Survivor"
    assert has_element?(view, "button[phx-click='activate_soll_plan']")

    view |> element("button[phx-click='activate_soll_plan']") |> render_click()

    [survivor] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    assert survivor.id == draft.id
    assert survivor.status == "active"
  end

  # Review finding: deleting a draft that vanished in another tab crashed the
  # LiveView through a {:ok, _} match on {:error, :not_found}.
  test "deleting an already-deleted draft does not crash", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = plan_world()

    [active] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    {:ok, draft} = Targets.duplicate_plan(Actor.owner_ui(), active.id, %{name: "Gone"})

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    view
    |> element("form.soll-plan-picker")
    |> render_change(%{"soll_plan" => "#{draft.id}"})

    # The draft vanishes out-of-band (other tab / API / MCP).
    {:ok, _} = Targets.delete_plan_version(Actor.owner_ui(), draft.id)

    html = view |> element("button[phx-click='delete_soll_plan']") |> render_click()
    assert html =~ "Plan deleted"
  end

  # Steve UAT finding: the Σ check must not call a complete plan broken while
  # a draft is selected — the cash row shows (and Σ counts) the view scope's
  # ACTIVE steering cash, with a visible lock hint instead of a title tooltip.
  test "a draft shows and counts the active steering cash target", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = plan_world()

    :ok = Targets.set_cash_target(Actor.owner_ui(), portfolio.id, Decimal.new("0.2"))

    [active] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    {:ok, draft} = Targets.duplicate_plan(Actor.owner_ui(), active.id, %{name: "Draft"})

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    view
    |> element("form.soll-plan-picker")
    |> render_change(%{"soll_plan" => "#{draft.id}"})

    html = render(view)
    assert html =~ ~s(id="soll-cash-target")
    assert html =~ ~s(value="20")
    assert has_element?(view, "#soll-cash-target[disabled]")
    assert has_element?(view, "[data-role=soll-cash-lock-hint]")
    # Σ counts weights (80) + active cash (20) = 100.
    assert view |> element("[data-role=soll-sum]") |> render() =~ "100"
  end

  # Steve UAT finding: plans need renaming in the UI (drop the "(Entwurf)"
  # suffix after activation, fix "(copy)" names).
  test "renames the selected plan from the version row", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = plan_world()

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    view
    |> form("details.plan-rename form", %{"plan_name" => "Plan 2026"})
    |> render_submit()

    [plan] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    assert plan.name == "Plan 2026"
    assert render(view) =~ "Plan renamed"
  end

  test "an archived version gets its own banner and garbage picker input is ignored",
       %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = plan_world()

    [original] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    {:ok, draft} = Targets.duplicate_plan(Actor.owner_ui(), original.id, %{name: "Successor"})
    {:ok, _} = Targets.activate_plan(Actor.owner_ui(), draft.id)

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    # Select the now-archived original: the banner says archived, not draft.
    view
    |> element("form.soll-plan-picker")
    |> render_change(%{"soll_plan" => "#{original.id}"})

    hint = view |> element("[data-role=soll-version-hint]") |> render()
    assert hint =~ "Archived"
    refute hint =~ "Draft"

    # A crafted non-integer picker payload changes nothing and does not crash.
    html = view |> element("form.soll-plan-picker") |> render_change(%{"soll_plan" => "abc"})
    assert html =~ "Archived"
  end

  test "a blank rename fails with feedback instead of silently succeeding", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = plan_world()

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    view
    |> form("details.plan-rename form", %{"plan_name" => "   "})
    |> render_submit()

    assert render(view) =~ "Could not rename the plan"
    [plan] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    assert plan.name == "Plan"
  end
end
