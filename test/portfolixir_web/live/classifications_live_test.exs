defmodule PortfolixirWeb.ClassificationsLiveTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Actor

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures

  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets

  # User story:
  # As a portfolio maintainer,
  # I want a Portfolio-Performance-style classifications view: a sidebar list of
  # trees with a "+" to add more, and a detail pane per tree with an "Unsorted"
  # folder I can drag securities out of into (nested) categories,
  # so that organising holdings feels like working with folders.

  # Mounts the LiveView and drains its async holdings load before returning.
  # Every mount starts a holdings task (issue #334); a test exiting while the
  # task is in flight races the shared sandbox owner teardown and fails a
  # later test (flake). No test here asserts the pre-async skeleton.
  defp live_drained(conn, path) do
    {:ok, view, html} = live(conn, path)
    render_async(view)
    {:ok, view, html}
  end

  defp security!(attrs \\ %{}) do
    base = %{name: "Apple", currency_code: "USD", asset_class: "equity"}

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), Map.merge(base, attrs))

    security
  end

  # User story:
  # As a new user who created categories but hasn't sorted holdings into them
  # yet, I want the Classifications page to tell me holdings are still unassigned
  # and how to fix it, so the portfolio's large "Unassigned" share is not a dead
  # end (#499).
  test "nudges to assign securities when categories exist but some are unsorted (#499)",
       %{conn: conn} do
    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, _core} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    _sec = security!(%{name: "Unassigned Co"})

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    # Show all securities so the unassigned one is listed under Unsorted.
    view
    |> element("form[phx-change='toggle_current_only']")
    |> render_change(%{"current_only" => "false"})

    assert has_element?(view, "[data-role='assignment-nudge']")
    assert render(view) =~ "category"
  end

  # User story:
  # As a maintainer setting target weights, I want the editor to warn me when a
  # target sits on a category with nothing assigned to it (#501), so I don't set
  # a target that can never be reached and shows permanent drift.
  test "warns when a target is set on a category with no assigned positions (#501)",
       %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "P",
        base_currency_code: "EUR"
      })

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, empty} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Empty"
      })

    {:ok, filled} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Filled"
      })

    security = security!(%{name: "Held Co"})

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        security.id,
        classification.id,
        filled.id
      )

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), portfolio.id, classification.id, [
        %{"category_id" => empty.id, "target_weight" => "0.5"},
        %{"category_id" => filled.id, "target_weight" => "0.5"}
      ])

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    # Exactly one warning — on the empty category, not the one with an assignment.
    assert has_element?(view, "[data-role='empty-category-warning']")

    warnings =
      view |> render() |> :binary.matches(~s(data-role="empty-category-warning")) |> length()

    assert warnings == 1
  end

  # User story (ADR-0022):
  # As a local portfolio maintainer,
  # I want the Classifications page itself to list my trees,
  # so that every tree stays reachable now that the per-classification tree
  # left the sidebar — the page owns tree management.
  #
  # Acceptance criteria:
  # - /classifications lists each classification as a link to its detail page,
  #   built-ins marked as such.
  # - The page offers the New-classification action.
  # - The stale "pick a classification on the left" copy is gone.
  test "index lists the classification trees as links", %{conn: conn} do
    Classifications.ensure_builtins()
    asset = Classifications.get_classification_by_key("asset_class")

    {:ok, view, html} = live_drained(conn, "/classifications")

    assert has_element?(
             view,
             ~s([data-role="classification-index"] a[href="/classifications/#{asset.id}"]),
             "Asset class"
           )

    assert html =~ "Currency"
    assert has_element?(view, ~s(a[href="/classifications/new"]))
    refute html =~ "on the left"
  end

  test "shows a built-in tree as read-only with an Unsorted folder", %{conn: conn} do
    security!()
    Classifications.ensure_builtins()
    asset = Classifications.get_classification_by_key("asset_class")

    {:ok, _view, html} = live_drained(conn, "/classifications/#{asset.id}")

    assert html =~ "Built-in"
    assert html =~ "Unsorted"
    # built-in trees expose no editing affordances
    refute html =~ "Delete classification"
  end

  test "creates a custom classification and redirects to its detail", %{conn: conn} do
    {:ok, view, _html} = live_drained(conn, "/classifications/new")

    assert {:ok, detail, html} =
             view
             |> form("#classification-form", classification: %{name: "Strategy"})
             |> render_submit()
             |> follow_redirect(conn)

    assert html =~ "Strategy"
    assert html =~ "Delete classification"

    # Drain the detail view's async holdings load before the test (and with
    # it the shared sandbox owner) exits — otherwise the in-flight task races
    # the ownership teardown and fails a later test (flake).
    render_async(detail)
  end

  # User story:
  # As a maintainer with many securities in a tree,
  # I want categories collapsed by default, long names truncated with a tooltip,
  # and the ticker shown, so the view is not one long wall of expanded rows.
  test "collapses categories by default, expands on search, shows ticker + tooltip", %{conn: conn} do
    security = security!(%{name: "Some Very Long ETF Name UCITS Acc", ticker_symbol: "VLN"})

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        security.id,
        classification.id,
        category.id
      )

    {:ok, view, html} = live_drained(conn, "/classifications/#{classification.id}")

    # Categories start collapsed (no `open` attribute on the cat-node details).
    refute html =~ ~r/<details class="cat-node" open/
    # The ticker is shown and the full name is available via a title tooltip.
    assert html =~ "VLN"
    assert html =~ ~s(title="Some Very Long ETF Name UCITS Acc")

    # Searching expands matching categories so results stay visible.
    filtered =
      view
      |> form(".tree-search", %{"query" => "Long"})
      |> render_change()

    assert filtered =~ ~r/<details class="cat-node" open/
  end

  test "assigns and unassigns a security via the drag events", %{conn: conn} do
    security = security!()

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    render_hook(view, "assign_security", %{
      "security_id" => security.id,
      "classification_id" => classification.id,
      "category_id" => category.id
    })

    expected = [%{security_id: security.id, category_id: category.id}]
    assert assignments(classification.id) == expected

    render_hook(view, "unassign", %{
      "security_id" => security.id,
      "classification_id" => classification.id
    })

    assert assignments(classification.id) == []
  end

  test "assigns and unassigns many securities via the bulk events", %{conn: conn} do
    one = security!(%{name: "One"})
    two = security!(%{name: "Two"})

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    render_hook(view, "assign_securities", %{
      "security_ids" => [one.id, two.id],
      "classification_id" => classification.id,
      "category_id" => category.id
    })

    assert length(assignments(classification.id)) == 2

    render_hook(view, "unassign_many", %{
      "security_ids" => [one.id, two.id],
      "classification_id" => classification.id
    })

    assert assignments(classification.id) == []
  end

  test "renders the multiselect toolbar on an editable tree", %{conn: conn} do
    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, _category} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, _view, html} = live_drained(conn, "/classifications/#{classification.id}")

    assert html =~ "data-select-toolbar"
    assert html =~ "Move to category"
  end

  test "exposes a parent select for building nested categories", %{conn: conn} do
    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, _parent} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Equity"
      })

    {:ok, _view, html} = live_drained(conn, "/classifications/#{classification.id}")

    assert html =~ "Top level"
    assert html =~ "Equity"
  end

  test "rejects dropping onto a built-in tree", %{conn: conn} do
    security = security!()
    Classifications.ensure_builtins()
    asset = Classifications.get_classification_by_key("asset_class")

    {:ok, view, _html} = live_drained(conn, "/classifications/#{asset.id}")

    html =
      render_hook(view, "assign_security", %{
        "security_id" => security.id,
        "classification_id" => asset.id,
        "category_id" => 0
      })

    assert html =~ "cannot be edited"
  end

  test "filters the tree to securities matching the search", %{conn: conn} do
    security!(%{name: "Apple"})
    security!(%{name: "Microsoft"})

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, view, html} = live_drained(conn, "/classifications/#{classification.id}")
    assert html =~ "Apple"
    assert html =~ "Microsoft"

    filtered =
      view
      |> form("form.tree-search", %{"query" => "micro"})
      |> render_change()

    assert filtered =~ "Microsoft"
    refute filtered =~ "Apple"
  end

  test "edits an existing category's name and description inline", %{conn: conn} do
    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    view
    |> element("button[phx-click='edit_category'][phx-value-id='#{category.id}']")
    |> render_click()

    assert has_element?(view, "form.cat-edit-form")

    view
    |> form("form.cat-edit-form", %{
      "category" => %{
        "id" => "#{category.id}",
        "name" => "Core holdings",
        "description" => "Buy and hold"
      }
    })
    |> render_submit()

    reloaded = Classifications.get_category(category.id)
    assert reloaded.name == "Core holdings"
    assert reloaded.description == "Buy and hold"
  end

  # User story:
  # As a portfolio maintainer reviewing a classification tree,
  # I want each assigned security to show its current quantity and market value
  # and, by default, to hide securities I no longer hold (with a per-category
  # "+N without holdings" counter), so legacy/sold positions don't clutter the
  # view and the category totals reflect what I actually own.
  #
  # Acceptance criteria:
  # - Each assigned security shows current quantity (summed across all
  #   securities accounts) and current EUR market value.
  # - A "current positions only" toggle (default ON) hides zero-holding
  #   securities; a per-category counter shows "+N without holdings".
  # - Category rows aggregate value and position count of the VISIBLE
  #   securities.
  test "shows holdings/value, hides sold positions by default, toggles to show all", %{conn: conn} do
    world = base_world()
    active = create_security!(name: "Active ETF", ticker: "ACT", currency: "EUR")
    sold = create_security!(name: "Sold ETF", ticker: "SLD", currency: "EUR")

    # Fund the cash account, then build one active and one fully sold position.
    deposit!(world, "10000", ~D[2026-01-01])
    buy!(world, active, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(world, sold, quantity: "5", price: "50", date: ~D[2026-01-02])
    sell!(world, sold, quantity: "5", price: "60", date: ~D[2026-01-03])

    # Price the active position via a quote: 10 * 110 = 1,100.00 EUR.
    put_quote!(active, ~D[2026-01-05], "110")

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        active.id,
        classification.id,
        category.id
      )

    {:ok, _} =
      Classifications.assign_security(
        Portfolixir.Actor.owner_ui(),
        sold.id,
        classification.id,
        category.id
      )

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    # The async holdings load completes; render the up-to-date DOM.
    html = render(view)

    # Default (current positions only ON): the active position is shown with its
    # quantity and EUR market value; the sold position is hidden.
    assert html =~ "Active ETF"
    assert html =~ "10"
    assert html =~ "1,100.00"
    refute html =~ "Sold ETF"

    # The per-category counter discloses the hidden zero-holding security.
    assert html =~ ~r/data-role="without-holdings"[^>]*>\s*\+1/

    # The category aggregates the value and count of the VISIBLE securities.
    assert html =~ ~r/data-role="category-value"[^>]*>\s*1,100\.00/
    assert html =~ ~r/data-role="category-positions"[^>]*>\s*1\b/

    # Toggling "current positions only" OFF reveals the sold position too.
    shown =
      view
      |> element("form[phx-change='toggle_current_only']")
      |> render_change(%{"current_only" => "false"})

    assert shown =~ "Active ETF"
    assert shown =~ "Sold ETF"

    # With every position visible, the "+N without holdings" counter is gone and
    # the category now aggregates both positions (1,100.00 + 0.00 sold = still
    # 1,100.00 in value, but two visible positions).
    refute shown =~ ~r/data-role="without-holdings"/
    assert shown =~ ~r/data-role="category-positions"[^>]*>\s*2\b/
  end

  # =====================================================================
  # SOLL plan editor (ADR-0020, Story 4 / issue #467)
  # =====================================================================

  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios.Targets

  # A custom classification with two categories on top of the base world, so the
  # SOLL editor has a portfolio, a view and categories to steer.
  defp soll_world do
    world = base_world()

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, equity} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Equity"
      })

    {:ok, bonds} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Bonds"
      })

    Map.merge(world, %{classification: classification, equity: equity, bonds: bonds})
  end

  # User story:
  # As a portfolio maintainer,
  # I want to define a view's SOLL plan (per-category target weights and a cash
  # target) for a classification on the classifications page, with a view
  # selector defaulting to "Gesamt",
  # so that each view carries its own coherent 100% steering plan.
  #
  # Acceptance criteria:
  # - The SOLL area shows a view selector ("Soll-Plan für Sicht: [Gesamt ▾]").
  # - With no plan yet, the editor shows the empty state ("Plan anlegen").
  # - Saving per-category weights plus a cash target writes the (Gesamt,
  #   classification) plan; the values round-trip into the Targets context.
  test "creates a Gesamt SOLL plan with category weights and a cash target", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity, bonds: bonds} =
      soll_world()

    {:ok, view, html} = live_drained(conn, "/classifications/#{classification.id}")

    # The view selector defaults to Gesamt and the empty state invites a plan.
    assert html =~ "Target plan for view"
    assert has_element?(view, "select[name='soll_view']")
    assert html =~ "Create plan"

    # Materialise the empty plan, then save weights and a cash target.
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    view
    |> form("#soll-plan-form", %{
      "weights" => %{
        "#{equity.id}" => "60",
        "#{bonds.id}" => "30"
      },
      "cash_target" => "10"
    })
    |> render_submit()

    targets =
      portfolio.id
      |> Targets.list_targets(classification_id: classification.id, view: nil)
      |> Map.new(&{&1.category_id, &1.target_weight})

    assert Decimal.equal?(targets[equity.id], Decimal.new("0.6"))
    assert Decimal.equal?(targets[bonds.id], Decimal.new("0.3"))
    assert Decimal.equal?(Targets.get_cash_target(portfolio.id, view: nil), Decimal.new("0.1"))
  end

  # User story:
  # As a maintainer reopening an existing plan,
  # I want the editor pre-filled with the plan's stored weights and cash target,
  # so I can review and edit it rather than re-enter it.
  #
  # Acceptance criteria:
  # - A plan that exists renders filled inputs and a "Plan löschen" action.
  test "shows an existing plan filled, with a delete action", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = soll_world()

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.75"}],
        view: nil
      )

    :ok = Targets.set_cash_target(Actor.owner_ui(), portfolio.id, "0.25", view: nil)

    {:ok, view, html} = live_drained(conn, "/classifications/#{classification.id}")

    assert html =~ "Delete plan"
    # Weights are shown as percentages (75% / 25%).
    assert has_element?(view, "input[name='weights[#{equity.id}]'][value='75']")
    assert has_element?(view, "input[name='cash_target'][value='25']")
  end

  # User story:
  # As a maintainer who set up a plan under one view,
  # I want to delete a view's plan,
  # so the portfolio page falls back to IST-only for that view.
  #
  # Acceptance criteria:
  # - "Plan löschen" removes the plan; afterwards no plan exists.
  test "deletes a plan and falls back to no plan", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = soll_world()

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.5"}],
        view: nil
      )

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    view
    |> element("button[phx-click='delete_soll_plan']")
    |> render_click()

    refute Targets.plan_exists?(portfolio.id, classification.id, view: nil)
    assert render(view) =~ "Create plan"
  end

  # User story:
  # As a maintainer steering several views,
  # I want a named view's plan to be independent from the Gesamt plan,
  # so the same classification can carry a different 100% plan per view.
  #
  # Acceptance criteria:
  # - Switching the view selector loads that (view, classification) plan only.
  # - A named view's plan does not see the Gesamt plan's weights.
  test "Gesamt and a named view carry independent plans", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = soll_world()
    {:ok, named} = Buckets.create_view(Portfolixir.Actor.owner_ui(), %{name: "Stocks"})

    # Gesamt has Equity at 80%.
    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.8"}],
        view: nil
      )

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")
    assert has_element?(view, "input[name='weights[#{equity.id}]'][value='80']")

    # Switching to the named view shows its own (empty) plan, not Gesamt's 80%.
    switched =
      view
      |> element("form[phx-change='select_soll_view']")
      |> render_change(%{"soll_view" => "#{named.id}"})

    refute switched =~ ~s(name="weights[#{equity.id}]" value="80")
    assert switched =~ "Create plan"
  end

  # User story:
  # As a maintainer building a view's plan from scratch,
  # I want to copy another view's plan for the same classification,
  # so I can start from an existing plan instead of re-entering it.
  #
  # Acceptance criteria:
  # - "Aus anderer Sicht übernehmen…" prefills the editor from a source plan;
  #   saving writes the target view's plan from those values.
  test "copies a plan from another view to prefill the editor", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity, bonds: bonds} =
      soll_world()

    {:ok, named} = Buckets.create_view(Portfolixir.Actor.owner_ui(), %{name: "Stocks"})

    # Gesamt holds the source plan.
    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [
          %{category_id: equity.id, target_weight: "0.7"},
          %{category_id: bonds.id, target_weight: "0.3"}
        ],
        view: nil
      )

    :ok = Targets.set_cash_target(Actor.owner_ui(), portfolio.id, "0.0", view: nil)

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    # Switch to the empty named view, then copy from Gesamt.
    view
    |> element("form[phx-change='select_soll_view']")
    |> render_change(%{"soll_view" => "#{named.id}"})

    copied =
      view
      |> element("form[phx-change='copy_soll_plan']")
      |> render_change(%{"copy_from" => "total"})

    # The form is now prefilled with Gesamt's weights for the named view.
    assert copied =~ ~s(name="weights[#{equity.id}]" value="70")
    assert copied =~ ~s(name="weights[#{bonds.id}]" value="30")

    # Saving writes the named view's plan from those values.
    view
    |> form("#soll-plan-form", %{
      "weights" => %{"#{equity.id}" => "70", "#{bonds.id}" => "30"},
      "cash_target" => "0"
    })
    |> render_submit()

    named_targets =
      portfolio.id
      |> Targets.list_targets(classification_id: classification.id, view: named.id)
      |> Map.new(&{&1.category_id, &1.target_weight})

    assert Decimal.equal?(named_targets[equity.id], Decimal.new("0.7"))
    assert Decimal.equal?(named_targets[bonds.id], Decimal.new("0.3"))
    # Gesamt is untouched.
    assert Decimal.equal?(
             Targets.get_cash_target(portfolio.id, view: nil),
             Decimal.new("0.0")
           )
  end

  # User story:
  # As a maintainer typing target weights,
  # I want a live Σ badge that sums the category weights and the cash target,
  # so I immediately see whether the plan adds up to 100%.
  #
  # Acceptance criteria:
  # - The Σ badge shows the running total and an OK marker at exactly 100%.
  # - Off 100% it shows a not-OK marker and the mismatch styling.
  test "live Σ badge tracks the running total as you type", %{conn: conn} do
    %{classification: classification, equity: equity, bonds: bonds} = soll_world()

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    # 60 + 30 + 10 = 100 → OK.
    balanced =
      view
      |> element("#soll-plan-form")
      |> render_change(%{
        "weights" => %{"#{equity.id}" => "60", "#{bonds.id}" => "30"},
        "cash_target" => "10"
      })

    assert balanced =~ "100"
    assert balanced =~ ~s(data-role="soll-sum")
    refute balanced =~ "is-target-mismatch"

    # 60 + 30 + 20 = 110 → mismatch.
    off =
      view
      |> element("#soll-plan-form")
      |> render_change(%{
        "weights" => %{"#{equity.id}" => "60", "#{bonds.id}" => "30"},
        "cash_target" => "20"
      })

    assert off =~ "110"
    assert off =~ "is-target-mismatch"
  end

  # User story:
  # As a maintainer (and against a crafted socket payload),
  # I want non-numeric or non-finite weights to be rejected gracefully,
  # so a bad value never crashes the plan editor.
  #
  # Acceptance criteria:
  # - A "NaN"/"Infinity" weight (which the number input's min/max can't stop on a
  #   crafted payload) does not crash the LiveView; nothing is persisted.
  test "rejects non-finite weights without crashing", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = soll_world()

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    # A crafted submit with a non-finite value: the process must survive.
    view
    |> form("#soll-plan-form", %{
      "weights" => %{"#{equity.id}" => "NaN"},
      "cash_target" => "Infinity"
    })
    |> render_submit()

    assert Process.alive?(view.pid)
    # Nothing crept into the plan from the bad payload.
    assert Targets.list_targets(portfolio.id, classification_id: classification.id, view: nil) ==
             []

    assert is_nil(Targets.get_cash_target(portfolio.id, view: nil))
  end

  # User story:
  # As a German-speaking maintainer,
  # I want the SOLL editor labels in German,
  # so the plan editor reads in my language.
  #
  # Acceptance criteria:
  # - With locale=de the view selector reads "Soll-Plan für Sicht:" and the empty
  #   state offers "Plan anlegen".
  test "renders the SOLL editor labels in German", %{conn: conn} do
    %{classification: classification} = soll_world()

    {:ok, _view, html} = live_drained(conn, "/classifications/#{classification.id}?locale=de")

    assert html =~ "Soll-Plan für Sicht"
    assert html =~ "Plan anlegen"
    assert html =~ "Gesamt"
  end

  # User story:
  # As a maintainer steering a nested classification,
  # I want the running Σ to count only the top-level category weights (plus the
  # cash target), exactly like the portfolio page's allocation engine,
  # so a hierarchical plan whose parents already sum to 100% is not double-counted
  # by also adding the children's weights.
  #
  # Acceptance criteria:
  # - With a parent at 100% and a child under it at 100%, the Σ badge shows the
  #   top-level total (100%), not the doubled ~200%.
  # - The Σ row carries the OK styling (no mismatch) because the top-level total
  #   plus cash is exactly 100%.
  test "Σ counts only top-level categories for a hierarchical plan", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = soll_world()

    {:ok, child} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Large caps",
        parent_id: equity.id
      })

    # The single top-level category is steered to 100%; its child carries its own
    # 100% (a fully-allocated sub-plan). The Σ must read 100%, not 200%.
    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [
          %{category_id: equity.id, target_weight: "1.0"},
          %{category_id: child.id, target_weight: "1.0"}
        ],
        view: nil
      )

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    sum = view |> element("[data-role='soll-sum']") |> render()

    # Only the top-level Equity (100%) feeds the Σ; the child's 100% is excluded.
    assert sum =~ "100%"
    refute sum =~ "200%"
    # 100% top-level + no cash target == 100% → OK, no mismatch styling.
    refute view |> element("tr.soll-row--sum") |> render() =~ "is-target-mismatch"
  end

  # User story:
  # As a maintainer steering a nested classification,
  # I want the running Σ to roll a blank parent's weight up from its children's
  # weights,
  # so a plan defined only on sub-categories still counts toward 100% instead of
  # being silently ignored.
  #
  # Acceptance criteria:
  # - With a top-level parent left blank but two children carrying 60% and 40%,
  #   the Σ badge rolls up to the children's total (100%).
  # - The Σ row carries the OK styling (no mismatch) because the rolled-up
  #   top-level total plus cash is exactly 100%.
  test "Σ rolls up a blank parent's weight from its children", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = soll_world()

    {:ok, large} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Large caps",
        parent_id: equity.id
      })

    {:ok, small} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Small caps",
        parent_id: equity.id
      })

    # The Equity parent is left blank; only its children carry weights (60 + 40).
    # The Σ must roll these up to 100%, not ignore the un-weighted parent.
    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [
          %{category_id: large.id, target_weight: "0.6"},
          %{category_id: small.id, target_weight: "0.4"}
        ],
        view: nil
      )

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    sum = view |> element("[data-role='soll-sum']") |> render()

    # 60% + 40% roll up to the blank Equity parent → Σ reads 100%.
    assert sum =~ "100%"
    # 100% rolled-up top-level + no cash target == 100% → OK, no mismatch styling.
    refute view |> element("tr.soll-row--sum") |> render() =~ "is-target-mismatch"
  end

  # User story:
  # As a maintainer steering a nested classification,
  # I want the running Σ to mix an explicit top-level weight with a blank parent
  # whose weight rolls up from its child,
  # so a partly-flat, partly-nested plan still totals correctly.
  #
  # Acceptance criteria:
  # - With one top-level parent set explicitly to 50% and another top-level
  #   parent left blank but carrying a single 50% child, the Σ badge reads 100%.
  # - The Σ row carries the OK styling (no mismatch).
  test "Σ mixes an explicit top-level weight with a rolled-up blank parent",
       %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity, bonds: bonds} =
      soll_world()

    {:ok, govies} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Government",
        parent_id: bonds.id
      })

    # Equity is explicit at 50%; Bonds is blank but its only child carries 50%.
    # Σ = 50 (explicit) + 50 (rolled up) = 100%.
    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [
          %{category_id: equity.id, target_weight: "0.5"},
          %{category_id: govies.id, target_weight: "0.5"}
        ],
        view: nil
      )

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    sum = view |> element("[data-role='soll-sum']") |> render()

    assert sum =~ "100%"
    refute view |> element("tr.soll-row--sum") |> render() =~ "is-target-mismatch"
  end

  # User story (#468, deep-link target):
  # As a maintainer who clicked the "Create a plan for this view" hint on the
  # Portfolio page (a view that had no plan),
  # I want the classifications editor to open with that view AND classification
  # already selected,
  # so that I edit the right (view, classification) plan instead of starting on
  # Gesamt and re-picking the view.
  #
  # Acceptance criteria:
  # - /classifications/<id>?soll_view=<view_id> selects the named view in the
  #   SOLL view selector (its option is selected).
  # - The editor loads that (view, classification) plan, not the Gesamt plan.
  test "the SOLL deep-link pre-selects the view from the soll_view param", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = soll_world()
    {:ok, named} = Buckets.create_view(Portfolixir.Actor.owner_ui(), %{name: "Strategie"})

    # Gesamt has Equity at 80%; the named view has its own (different) plan.
    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.8"}],
        view: nil
      )

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.4"}],
        view: named.id
      )

    {:ok, view, _html} =
      live_drained(conn, "/classifications/#{classification.id}?soll_view=#{named.id}")

    # The named view's option is pre-selected in the SOLL view selector.
    assert has_element?(
             view,
             "select[name='soll_view'] option[value='#{named.id}'][selected]"
           )

    # The editor loads the named view's plan (40%), not Gesamt's (80%).
    assert has_element?(view, "input[name='weights[#{equity.id}]'][value='40']")
    refute has_element?(view, "input[name='weights[#{equity.id}]'][value='80']")
  end

  # User story (#468, deep-link target — Gesamt):
  # As a maintainer who clicked the hint from the Total (Gesamt) view,
  # I want the deep-link with soll_view=total to land on the Gesamt plan,
  # so the bridge works for the portfolio-wide plan too.
  #
  # Acceptance criteria:
  # - /classifications/<id>?soll_view=total keeps Gesamt selected and loads it.
  test "the SOLL deep-link with soll_view=total selects Gesamt", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = soll_world()

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.8"}],
        view: nil
      )

    {:ok, view, _html} =
      live_drained(conn, "/classifications/#{classification.id}?soll_view=total")

    assert has_element?(view, "select[name='soll_view'] option[value='total'][selected]")
    assert has_element?(view, "input[name='weights[#{equity.id}]'][value='80']")
  end

  # Exercises the category/classification lifecycle events end to end (the writes
  # are now actor-first + journaled, #353): create a category, recolor it, delete
  # it, then delete the classification.
  test "creates, recolors and deletes categories and the classification via live events",
       %{conn: conn} do
    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Lifecycle"})

    {:ok, view, _html} = live_drained(conn, "/classifications/#{classification.id}")

    render_hook(view, "create_category", %{
      "category" => %{"classification_id" => to_string(classification.id), "name" => "Core"}
    })

    category =
      Portfolixir.Repo.get_by(Portfolixir.Classifications.Category,
        classification_id: classification.id,
        name: "Core"
      )

    assert category

    render_hook(view, "recolor_category", %{
      "category_id" => to_string(category.id),
      "color" => "#abcdef"
    })

    assert Portfolixir.Repo.get(Portfolixir.Classifications.Category, category.id).color ==
             "#abcdef"

    render_hook(view, "delete_category", %{"id" => to_string(category.id)})
    refute Portfolixir.Repo.get(Portfolixir.Classifications.Category, category.id)

    render_hook(view, "delete_classification", %{})
    refute Classifications.get_classification(classification.id)
  end

  defp assignments(classification_id) do
    Classifications.list_trees()
    |> Enum.find(&(&1.classification.id == classification_id))
    |> Map.fetch!(:assignments)
  end

  # User story:
  # As a maintainer using the new-category form on a classification tree,
  # I want the "Current positions only" checkbox and its label on one line,
  # so that the pair reads as one control instead of a bare box with a bold
  # label stacked underneath running into the next field (UX-DR19, issue
  # 635 — the global grid label stacked its children).
  #
  # Acceptance criteria:
  # - A label wrapping a checkbox lays out as a one-line flex control.
  # - The checkbox loses the 34px text-input min-height and takes the
  #   accent colour. (The markup was correct; the defect was CSS-level.)
  test "checkbox labels lay out box and label on one line (issue 635)" do
    css = File.read!("priv/static/app.css")

    assert css =~ ~r/label:has\(> input\[type="checkbox"\]\)\s*\{[^}]*display:\s*flex/s
    assert css =~ ~r/input\[type="checkbox"\]\s*\{[^}]*min-height:\s*0/s
    assert css =~ ~r/input\[type="checkbox"\]\s*\{[^}]*accent-color:\s*var\(--color-accent\)/s
  end
end
