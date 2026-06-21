defmodule PortfolixirWeb.ClassificationsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures

  alias Portfolixir.Catalog
  alias Portfolixir.Classifications

  # User story:
  # As a portfolio maintainer,
  # I want a Portfolio-Performance-style classifications view: a sidebar list of
  # trees with a "+" to add more, and a detail pane per tree with an "Unsorted"
  # folder I can drag securities out of into (nested) categories,
  # so that organising holdings feels like working with folders.

  defp security!(attrs \\ %{}) do
    base = %{name: "Apple", currency_code: "USD", asset_class: "equity"}

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), Map.merge(base, attrs))

    security
  end

  test "index lists the built-in trees in the sidebar", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/classifications")

    assert html =~ "Asset class"
    assert html =~ "Currency"
    assert html =~ "Pick a classification"
  end

  test "shows a built-in tree as read-only with an Unsorted folder", %{conn: conn} do
    security!()
    Classifications.ensure_builtins()
    asset = Classifications.get_classification_by_key("asset_class")

    {:ok, _view, html} = live(conn, "/classifications/#{asset.id}")

    assert html =~ "Built-in"
    assert html =~ "Unsorted"
    # built-in trees expose no editing affordances
    refute html =~ "Delete classification"
  end

  test "creates a custom classification and redirects to its detail", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/classifications/new")

    assert {:ok, _detail, html} =
             view
             |> form("#classification-form", classification: %{name: "Strategy"})
             |> render_submit()
             |> follow_redirect(conn)

    assert html =~ "Strategy"
    assert html =~ "Delete classification"
  end

  # User story:
  # As a maintainer with many securities in a tree,
  # I want categories collapsed by default, long names truncated with a tooltip,
  # and the ticker shown, so the view is not one long wall of expanded rows.
  test "collapses categories by default, expands on search, shows ticker + tooltip", %{conn: conn} do
    security = security!(%{name: "Some Very Long ETF Name UCITS Acc", ticker_symbol: "VLN"})
    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    {:ok, _} = Classifications.assign_security(security.id, classification.id, category.id)

    {:ok, view, html} = live(conn, "/classifications/#{classification.id}")

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
    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")

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
    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")

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
    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, _category} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    {:ok, _view, html} = live(conn, "/classifications/#{classification.id}")

    assert html =~ "data-select-toolbar"
    assert html =~ "Move to category"
  end

  test "exposes a parent select for building nested categories", %{conn: conn} do
    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, _parent} =
      Classifications.create_category(%{classification_id: classification.id, name: "Equity"})

    {:ok, _view, html} = live(conn, "/classifications/#{classification.id}")

    assert html =~ "Top level"
    assert html =~ "Equity"
  end

  test "rejects dropping onto a built-in tree", %{conn: conn} do
    security = security!()
    Classifications.ensure_builtins()
    asset = Classifications.get_classification_by_key("asset_class")

    {:ok, view, _html} = live(conn, "/classifications/#{asset.id}")

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
    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, view, html} = live(conn, "/classifications/#{classification.id}")
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
    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")

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

    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    {:ok, _} = Classifications.assign_security(active.id, classification.id, category.id)
    {:ok, _} = Classifications.assign_security(sold.id, classification.id, category.id)

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")

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
    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, equity} =
      Classifications.create_category(%{classification_id: classification.id, name: "Equity"})

    {:ok, bonds} =
      Classifications.create_category(%{classification_id: classification.id, name: "Bonds"})

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

    {:ok, view, html} = live(conn, "/classifications/#{classification.id}")

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
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.75"}],
        view: nil
      )

    :ok = Targets.set_cash_target(portfolio.id, "0.25", view: nil)

    {:ok, view, html} = live(conn, "/classifications/#{classification.id}")

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
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.5"}],
        view: nil
      )

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")

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
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.8"}],
        view: nil
      )

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
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
        portfolio.id,
        classification.id,
        [
          %{category_id: equity.id, target_weight: "0.7"},
          %{category_id: bonds.id, target_weight: "0.3"}
        ],
        view: nil
      )

    :ok = Targets.set_cash_target(portfolio.id, "0.0", view: nil)

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")

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

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
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

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
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

    {:ok, _view, html} = live(conn, "/classifications/#{classification.id}?locale=de")

    assert html =~ "Soll-Plan für Sicht"
    assert html =~ "Plan anlegen"
    assert html =~ "Gesamt"
  end

  # User story:
  # As a maintainer steering a nested classification,
  # I want each parent row to show its direct children's running Σ and flag it
  # when the children don't add up to the parent's own weight,
  # so I can spot inconsistent sub-allocations at a glance.
  #
  # Acceptance criteria:
  # - A parent category whose children carry weights renders a "children Σ" hint.
  # - When the children's Σ differs from the parent's own weight the hint and row
  #   carry the mismatch styling.
  test "renders the children-Σ hint and flags a parent/children mismatch", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = soll_world()

    {:ok, child} =
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Large caps",
        parent_id: equity.id
      })

    # Equity is steered to 60% but its only child carries 30% → mismatch.
    {:ok, _} =
      Targets.set_targets(
        portfolio.id,
        classification.id,
        [
          %{category_id: equity.id, target_weight: "0.6"},
          %{category_id: child.id, target_weight: "0.3"}
        ],
        view: nil
      )

    {:ok, _view, html} = live(conn, "/classifications/#{classification.id}")

    # The parent row exposes its direct children's running Σ as a hint…
    assert html =~ ~s(data-role="soll-child-hint")
    assert html =~ "children Σ"
    assert html =~ "30%"
    # …and, since 30% ≠ the parent's 60%, the consistency styling is applied.
    assert html =~ "is-target-mismatch"
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
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Large caps",
        parent_id: equity.id
      })

    # The single top-level category is steered to 100%; its child carries its own
    # 100% (a fully-allocated sub-plan). The Σ must read 100%, not 200%.
    {:ok, _} =
      Targets.set_targets(
        portfolio.id,
        classification.id,
        [
          %{category_id: equity.id, target_weight: "1.0"},
          %{category_id: child.id, target_weight: "1.0"}
        ],
        view: nil
      )

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")

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
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Large caps",
        parent_id: equity.id
      })

    {:ok, small} =
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Small caps",
        parent_id: equity.id
      })

    # The Equity parent is left blank; only its children carry weights (60 + 40).
    # The Σ must roll these up to 100%, not ignore the un-weighted parent.
    {:ok, _} =
      Targets.set_targets(
        portfolio.id,
        classification.id,
        [
          %{category_id: large.id, target_weight: "0.6"},
          %{category_id: small.id, target_weight: "0.4"}
        ],
        view: nil
      )

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")

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
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Government",
        parent_id: bonds.id
      })

    # Equity is explicit at 50%; Bonds is blank but its only child carries 50%.
    # Σ = 50 (explicit) + 50 (rolled up) = 100%.
    {:ok, _} =
      Targets.set_targets(
        portfolio.id,
        classification.id,
        [
          %{category_id: equity.id, target_weight: "0.5"},
          %{category_id: govies.id, target_weight: "0.5"}
        ],
        view: nil
      )

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")

    sum = view |> element("[data-role='soll-sum']") |> render()

    assert sum =~ "100%"
    refute view |> element("tr.soll-row--sum") |> render() =~ "is-target-mismatch"
  end

  # User story:
  # As a maintainer typing into the live Σ,
  # I want blank, non-numeric and otherwise odd values to be treated as absent
  # rather than crash the running total,
  # so editing the plan never breaks the form.
  #
  # Acceptance criteria:
  # - A live change with a blank weight, an unparseable weight and a blank cash
  #   target keeps the LiveView alive and shows a numeric running Σ.
  test "live Σ tolerates blank, unparseable and missing values", %{conn: conn} do
    %{classification: classification, equity: equity, bonds: bonds} = soll_world()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    # One good weight, one blank, one unparseable; cash target blank.
    html =
      view
      |> element("#soll-plan-form")
      |> render_change(%{
        "weights" => %{
          "#{equity.id}" => "40",
          "#{bonds.id}" => "",
          "999999" => "not-a-number"
        },
        "cash_target" => ""
      })

    assert Process.alive?(view.pid)
    assert html =~ ~s(data-role="soll-sum")
    # Only the parseable 40 counts; blank/garbage drop out of the Σ.
    assert html =~ "40"

    # A crafted live change with a non-string weight value and no cash_target key
    # must also be tolerated (the lenient live-Σ parsers treat both as absent).
    odd =
      render_hook(view, "soll_sum", %{"weights" => %{"#{equity.id}" => ["nope"]}})

    assert Process.alive?(view.pid)
    assert odd =~ ~s(data-role="soll-sum")
  end

  # User story:
  # As a maintainer (and against a crafted socket payload),
  # I want odd-shaped live-Σ params (a non-map weights value) to be ignored,
  # so a malformed change event can never crash the running total.
  #
  # Acceptance criteria:
  # - A `soll_sum` event whose `weights` is not a map leaves the LiveView alive.
  test "live Σ ignores a non-map weights payload", %{conn: conn} do
    %{classification: classification} = soll_world()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    html = render_hook(view, "soll_sum", %{"weights" => "nonsense", "cash_target" => "5"})

    assert Process.alive?(view.pid)
    assert html =~ ~s(data-role="soll-sum")
  end

  # User story:
  # As a maintainer leaving some categories and the cash target blank,
  # I want saving to skip the blanks and still write the weights I entered,
  # so a partial plan saves cleanly.
  #
  # Acceptance criteria:
  # - Saving with a blank weight and no cash target writes only the filled
  #   category weights and stores no cash target.
  test "saves a plan that skips blank weights and a blank cash target", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity, bonds: bonds} =
      soll_world()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    view
    |> form("#soll-plan-form", %{
      "weights" => %{
        "#{equity.id}" => "100",
        "#{bonds.id}" => ""
      },
      "cash_target" => ""
    })
    |> render_submit()

    targets =
      portfolio.id
      |> Targets.list_targets(classification_id: classification.id, view: nil)
      |> Map.new(&{&1.category_id, &1.target_weight})

    assert Decimal.equal?(targets[equity.id], Decimal.new("1.0"))
    refute Map.has_key?(targets, bonds.id)
    assert is_nil(Targets.get_cash_target(portfolio.id, view: nil))
  end

  # User story:
  # As a maintainer (and against a crafted socket payload),
  # I want a save whose `weights`/`cash_target` arrive as non-strings to be
  # rejected gracefully, so a malformed submit never crashes the editor.
  #
  # Acceptance criteria:
  # - A save with a list-valued weight and a list-valued cash target keeps the
  #   LiveView alive and persists nothing.
  test "rejects a save with non-string weight and cash values", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = soll_world()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    render_hook(view, "save_soll_plan", %{
      "weights" => %{"#{equity.id}" => ["nope"]},
      "cash_target" => ["nope"]
    })

    assert Process.alive?(view.pid)

    assert Targets.list_targets(portfolio.id, classification_id: classification.id, view: nil) ==
             []
  end

  # User story:
  # As a maintainer (and against a crafted socket payload),
  # I want a save whose `weights` is not a map at all to be a clean no-op,
  # so a malformed submit never crashes the editor.
  #
  # Acceptance criteria:
  # - A save with a non-map `weights` keeps the LiveView alive and persists
  #   nothing.
  test "tolerates a save with a non-map weights payload", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = soll_world()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    render_hook(view, "save_soll_plan", %{"weights" => "nonsense", "cash_target" => "0"})

    assert Process.alive?(view.pid)

    assert Targets.list_targets(portfolio.id, classification_id: classification.id, view: nil) ==
             []
  end

  # User story:
  # As a maintainer who typed an out-of-range weight,
  # I want the save to surface the validation error instead of crashing,
  # so I can correct the value.
  #
  # Acceptance criteria:
  # - Saving a weight above 100% surfaces an error and persists no target.
  test "surfaces a changeset error for an out-of-range weight", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = soll_world()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    # 150% → fraction 1.5, which the Target schema rejects (must be ≤ 1).
    html =
      view
      |> form("#soll-plan-form", %{
        "weights" => %{"#{equity.id}" => "150"},
        "cash_target" => "0"
      })
      |> render_submit()

    assert html =~ "alert-error"

    assert Targets.list_targets(portfolio.id, classification_id: classification.id, view: nil) ==
             []
  end

  # User story:
  # As a maintainer who opened the copy picker but changed my mind,
  # I want choosing the blank "— Choose a view —" option to do nothing,
  # so an empty copy selection leaves the editor untouched.
  #
  # Acceptance criteria:
  # - A `copy_soll_plan` change with a blank value is a no-op.
  test "copying from a blank view selection is a no-op", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = soll_world()
    {:ok, named} = Buckets.create_view(Portfolixir.Actor.owner_ui(), %{name: "Stocks"})

    # Give Gesamt a plan so the empty named view shows a copy picker.
    {:ok, _} = Targets.ensure_plan(portfolio.id, classification.id, view: nil)

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")

    switched =
      view
      |> element("form[phx-change='select_soll_view']")
      |> render_change(%{"soll_view" => "#{named.id}"})

    assert switched =~ "Create plan"

    # Selecting the blank option must not change the editor.
    unchanged =
      view
      |> element("form[phx-change='copy_soll_plan']")
      |> render_change(%{"copy_from" => ""})

    assert Process.alive?(view.pid)
    assert unchanged =~ "Create plan"
  end

  # User story:
  # As a maintainer building a fresh view's plan,
  # I want the copy picker to list other views that already carry a plan for this
  # classification, so I can start from one of them.
  #
  # Acceptance criteria:
  # - On the Gesamt plan, a named view that has its own plan appears as a copy
  #   source.
  test "lists a named view's plan as a copy source on Gesamt", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, equity: equity} = soll_world()
    {:ok, named} = Buckets.create_view(Portfolixir.Actor.owner_ui(), %{name: "Stocks"})

    # The named view carries a plan; Gesamt does not yet.
    {:ok, _} =
      Targets.set_targets(
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.5"}],
        view: named.id
      )

    {:ok, _view, html} = live(conn, "/classifications/#{classification.id}")

    # The copy-from picker offers the named view (its id is rendered as an option).
    assert html =~ "Copy from another view"
    assert html =~ ~s(<option value="#{named.id}">)
  end

  # User story:
  # As a maintainer switching the SOLL view selector,
  # I want a non-numeric view value to fall back to Gesamt rather than crash,
  # so a crafted selector payload is handled safely.
  #
  # Acceptance criteria:
  # - Selecting a non-numeric view keeps the LiveView alive on the Gesamt plan.
  test "selecting a non-numeric view falls back to Gesamt", %{conn: conn} do
    %{classification: classification} = soll_world()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")

    html =
      view
      |> element("form[phx-change='select_soll_view']")
      |> render_change(%{"soll_view" => "not-an-id"})

    assert Process.alive?(view.pid)
    # Falls back to the Gesamt plan, which has no plan yet → empty state.
    assert html =~ "Create plan"
  end

  # User story:
  # As a maintainer,
  # I want the SOLL editor to appear only for editable custom trees with a
  # portfolio, so built-in trees never show a plan editor.
  #
  # Acceptance criteria:
  # - A built-in (read-only) tree renders no SOLL editor.
  test "hides the SOLL editor on a built-in (read-only) tree", %{conn: conn} do
    base_world()
    Classifications.ensure_builtins()
    currency = Classifications.get_classification_by_key("currency")

    {:ok, _view, html} = live(conn, "/classifications/#{currency.id}")

    refute html =~ "soll-editor"
    refute html =~ "Target plan for view"
  end

  # User story:
  # As a maintainer (and against a crafted socket payload),
  # I want a save and a live-Σ change that arrive with the weights/cash keys
  # missing entirely to be handled as "nothing entered",
  # so an empty submit clears the plan rather than crashing.
  #
  # Acceptance criteria:
  # - A save with no `weights` and no `cash_target` keys persists no targets and
  #   no cash target.
  # - A live-Σ change with no `weights` key keeps the LiveView alive.
  test "handles a save and a live-Σ change with the keys missing", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = soll_world()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    # A live-Σ change carrying neither key is a no-op total.
    summed = render_hook(view, "soll_sum", %{})
    assert Process.alive?(view.pid)
    assert summed =~ ~s(data-role="soll-sum")

    # A save with neither key writes nothing.
    render_hook(view, "save_soll_plan", %{})
    assert Process.alive?(view.pid)

    assert Targets.list_targets(portfolio.id, classification_id: classification.id, view: nil) ==
             []

    assert is_nil(Targets.get_cash_target(portfolio.id, view: nil))
  end

  # User story:
  # As a maintainer who accidentally typed only spaces into a weight,
  # I want a whitespace-only value treated as blank,
  # so it neither saves a bogus target nor crashes the live Σ.
  #
  # Acceptance criteria:
  # - A whitespace-only weight in the live Σ is dropped from the running total.
  test "treats a whitespace-only weight as blank in the live Σ", %{conn: conn} do
    %{classification: classification, equity: equity} = soll_world()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    view |> element("button[phx-click='create_soll_plan']") |> render_click()

    html =
      view
      |> element("#soll-plan-form")
      |> render_change(%{
        "weights" => %{"#{equity.id}" => "   "},
        "cash_target" => "  "
      })

    assert Process.alive?(view.pid)
    assert html =~ ~s(data-role="soll-sum")
  end

  # User story:
  # As a maintainer (and against a crafted socket payload),
  # I want a save attempted with no portfolio behind the editor to fail safely,
  # so the editor never crashes when there is nothing to steer.
  #
  # Acceptance criteria:
  # - With no portfolio, a save_soll_plan event surfaces an error and keeps the
  #   LiveView alive without persisting.
  test "fails the save gracefully when no portfolio exists", %{conn: conn} do
    # No portfolio in this world — only a classification with a category.
    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, equity} =
      Classifications.create_category(%{classification_id: classification.id, name: "Equity"})

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")

    html =
      render_hook(view, "save_soll_plan", %{
        "weights" => %{"#{equity.id}" => "100"},
        "cash_target" => "0"
      })

    assert Process.alive?(view.pid)
    assert html =~ "alert-error"
  end

  # User story:
  # As a maintainer following a stale link to a deleted classification,
  # I want a missing tree to show a "not found" notice without a SOLL editor,
  # so the page degrades gracefully.
  #
  # Acceptance criteria:
  # - A non-existent classification id renders the not-found state and no SOLL
  #   editor.
  test "shows not found and no SOLL editor for a missing classification", %{conn: conn} do
    base_world()

    {:ok, _view, html} = live(conn, "/classifications/999999")

    assert html =~ "Classification not found"
    refute html =~ "Target plan for view"
  end

  defp assignments(classification_id) do
    Classifications.list_trees()
    |> Enum.find(&(&1.classification.id == classification_id))
    |> Map.fetch!(:assignments)
  end
end
