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
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.8"}],
        view: nil
      )

    {:ok, _} =
      Targets.set_targets(
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.4"}],
        view: named.id
      )

    {:ok, view, _html} =
      live(conn, "/classifications/#{classification.id}?soll_view=#{named.id}")

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
        portfolio.id,
        classification.id,
        [%{category_id: equity.id, target_weight: "0.8"}],
        view: nil
      )

    {:ok, view, _html} =
      live(conn, "/classifications/#{classification.id}?soll_view=total")

    assert has_element?(view, "select[name='soll_view'] option[value='total'][selected]")
    assert has_element?(view, "input[name='weights[#{equity.id}]'][value='80']")
  end

  defp assignments(classification_id) do
    Classifications.list_trees()
    |> Enum.find(&(&1.classification.id == classification_id))
    |> Map.fetch!(:assignments)
  end
end
