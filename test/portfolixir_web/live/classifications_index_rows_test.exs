defmodule PortfolixirWeb.ClassificationsIndexRowsTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications

  # User story (#808, review C11; #815 is the closing act's duplicate of it and
  # is closed by hand with this as the evidence — D-4 of the Sprint 13 plan):
  # As a local portfolio maintainer opening Classifications,
  # I want one row per tree saying what it holds,
  # so that the index answers a tree's size, its assignment state and whether
  # it carries a plan, instead of being three names and a sentence.
  #
  # Acceptance criteria:
  # - Each row shows the category count, assigned of total securities with the
  #   unassigned count as an attention word, and the plan the tree carries.
  # - The row is a link to the tree; the kebab carries the actions; `+` in the
  #   heading replaces the full-width button and the "choose a tree" sentence
  #   is gone.
  # - The counts come from the existing tree and plan reads.

  setup do
    world = base_world(name: "Index World", cash_name: "IW Cash", depot_name: "IW Depot")
    assigned = create_security!(name: "Assigned Co", ticker: "ASG")
    unassigned = create_security!(name: "Unassigned Co", ticker: "UNA")
    buy!(world, assigned, quantity: "1", price: "100", date: ~D[2026-01-05])
    buy!(world, unassigned, quantity: "1", price: "100", date: ~D[2026-01-05])

    {:ok, tree} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy", key: "strategy"})

    {:ok, growth} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Growth"
      })

    {:ok, _value} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Value"
      })

    {:ok, _} = Classifications.assign_security(Actor.owner_ui(), assigned.id, tree.id, growth.id)

    %{world: world, tree: tree}
  end

  test "the index is rows that say what each tree holds", %{conn: conn, tree: tree} do
    {:ok, view, html} = live(conn, "/classifications")

    assert has_element?(view, "#classification-index")
    refute html =~ "Choose a classification"

    row = view |> element("#classification-row-#{tree.id}") |> render()
    assert row =~ "Strategy"
    # Two categories, one of two securities assigned.
    assert row =~ "2"

    assert view
           |> element("#classification-row-#{tree.id} [data-role='tree-categories']")
           |> render() =~ "2"

    assigned_cell =
      view |> element("#classification-row-#{tree.id} [data-role='tree-assigned']") |> render()

    assert assigned_cell =~ "1"
    assert assigned_cell =~ "2"

    # The unassigned count reads as an attention word, not as a bare number.
    assert has_element?(view, "#classification-row-#{tree.id} [data-role='tree-unassigned']")

    # The row is a link to the tree.
    assert has_element?(
             view,
             "#classification-row-#{tree.id} a[href='/classifications/#{tree.id}']"
           )

    # `+` in the heading, not a full-width button at the foot.
    assert has_element?(view, "#new-classification[href='/classifications/new']")
  end

  test "the kebab carries the tree's actions", %{conn: conn, tree: tree} do
    {:ok, view, _html} = live(conn, "/classifications")

    refute has_element?(view, "#tree-row-menu-#{tree.id}")
    view |> element("#tree-kebab-#{tree.id}") |> render_click()

    assert has_element?(view, "#tree-row-menu-#{tree.id}")
    assert has_element?(view, "#tree-open-#{tree.id}")
    assert has_element?(view, "#tree-delete-#{tree.id}")
  end

  test "a built-in tree is marked and cannot be deleted from the kebab", %{conn: conn} do
    Classifications.ensure_builtins()
    {:ok, view, _html} = live(conn, "/classifications")

    builtin = Enum.find(Classifications.list_classifications(), & &1.built_in)

    assert view |> element("#classification-row-#{builtin.id}") |> render() =~ "Built-in"

    view |> element("#tree-kebab-#{builtin.id}") |> render_click()
    assert has_element?(view, "#tree-open-#{builtin.id}")
    refute has_element?(view, "#tree-delete-#{builtin.id}")
  end

  # User story (found by the edge-case hunter in the Sprint 13 closing act):
  # As the operator who re-homed a category under its own descendant,
  # I want the index to still open,
  # so that one ordinary write cannot brick the only page that could undo it.
  #
  # Acceptance criteria:
  # - A parent cycle (and a self-parent) renders instead of looping: the
  #   walk is bounded the way `Classifications`' own root path already is.
  # - The row still renders its counts.
  @tag timeout: 20_000
  test "a category parent cycle does not hang the index", %{conn: conn} do
    {:ok, cyc} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Cyc", key: "cyc"})

    {:ok, a} =
      Classifications.create_category(Actor.owner_ui(), %{classification_id: cyc.id, name: "A"})

    {:ok, b} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: cyc.id,
        name: "B",
        parent_id: a.id
      })

    {:ok, _} = Classifications.update_category(Actor.owner_ui(), a, %{parent_id: b.id})

    {:ok, _view, html} = live(conn, "/classifications")
    assert html =~ "Cyc"

    {:ok, selfie} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Selfie", key: "selfie"})

    {:ok, only} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: selfie.id,
        name: "Only"
      })

    {:ok, _} = Classifications.update_category(Actor.owner_ui(), only, %{parent_id: only.id})

    {:ok, _view, html} = live(conn, "/classifications")
    assert html =~ "Selfie"
  end
end
