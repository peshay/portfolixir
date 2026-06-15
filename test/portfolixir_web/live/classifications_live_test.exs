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

  defp assignments(classification_id) do
    Classifications.list_trees()
    |> Enum.find(&(&1.classification.id == classification_id))
    |> Map.fetch!(:assignments)
  end
end
