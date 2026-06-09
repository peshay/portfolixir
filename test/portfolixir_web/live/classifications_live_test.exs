defmodule PortfolixirWeb.ClassificationsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

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
    {:ok, security} = Catalog.create_security(Map.merge(base, attrs))
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

  defp assignments(classification_id) do
    Classifications.list_trees()
    |> Enum.find(&(&1.classification.id == classification_id))
    |> Map.fetch!(:assignments)
  end
end
