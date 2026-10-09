defmodule PortfolixirWeb.ClassificationsResultReloadTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications

  # A custom tree, Equity > Core and Satellite beside it, over one EUR
  # portfolio: Alpha AG (cost 1,000.00) is filed under Core, so Core and its
  # parent Equity state 1,000.00 invested; Bravo AG (cost 500.00) is held and
  # unsorted; Satellite holds nothing.
  setup do
    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    equity = category!(classification, "Equity")
    core = category!(classification, "Core", equity)
    satellite = category!(classification, "Satellite")

    world = base_world()
    alpha = create_security!(name: "Alpha AG", ticker: "ALP")
    bravo = create_security!(name: "Bravo AG", ticker: "BRV")
    deposit!(world, "10000", ~D[2026-01-01])
    buy!(world, alpha, quantity: "10", price: "100")
    buy!(world, bravo, quantity: "5", price: "100")
    put_quote!(alpha, Date.utc_today(), "150")
    put_quote!(bravo, Date.utc_today(), "120")

    assign!(alpha, classification, core)

    %{
      world: world,
      classification: classification,
      equity: equity,
      core: core,
      satellite: satellite,
      alpha: alpha,
      bravo: bravo
    }
  end

  defp category!(classification, name, parent \\ nil) do
    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: name,
        parent_id: parent && parent.id
      })

    category
  end

  defp assign!(security, classification, category) do
    {:ok, _} =
      Classifications.assign_security(
        Actor.owner_ui(),
        security.id,
        classification.id,
        category.id
      )
  end

  defp open!(conn, classification) do
    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    render_async(view)
    view
  end

  # What the category's own row states as invested: "1,000.00", or "—" while
  # nothing filed there has a cost.
  defp invested(view, category) do
    view
    |> render_async()
    |> Floki.parse_document!()
    |> Floki.find(
      ~s(details[data-category="#{category.id}"] > summary [data-role="category-invested"])
    )
    |> Floki.text()
    |> String.trim()
  end

  defp excluded_note(view) do
    view
    |> render_async()
    |> Floki.parse_document!()
    |> Floki.find(~s([data-role="category-result-excluded"]))
    |> Floki.text()
  end

  # User story (#1110; ADR-0041 §1, the result is a statement about the
  # current composition):
  # As a local portfolio maintainer editing my strategy tree,
  # I want each category's cost, result and partial count to follow the edit
  # I just made,
  # so that a deleted category's members no longer count in its parent, and
  # the note does not name a member that is no longer filed.
  #
  # Acceptance criteria:
  # - An edit that changes the tree restarts the category result: a create,
  #   a delete, an assignment (one security or many) or a move (securities
  #   between categories, or a category under another parent).
  # - A filter change does not: the search and the current-positions toggle
  #   rebuild the tree's rows from the result already computed, and so does
  #   a rename.
  test "a deleted category's members leave its parent's figures", %{conn: conn} = ctx do
    view = open!(conn, ctx.classification)
    assert invested(view, ctx.equity) == "1,000.00"

    render_hook(view, "delete_category", %{"id" => to_string(ctx.core.id)})

    assert invested(view, ctx.equity) == "—"
  end

  test "a security assigned by drag counts in its category", %{conn: conn} = ctx do
    view = open!(conn, ctx.classification)
    assert invested(view, ctx.satellite) == "—"

    render_hook(view, "assign_security", %{
      "security_id" => ctx.bravo.id,
      "classification_id" => ctx.classification.id,
      "category_id" => ctx.satellite.id
    })

    assert invested(view, ctx.satellite) == "500.00"
  end

  test "securities moved in bulk count where they now are", %{conn: conn} = ctx do
    view = open!(conn, ctx.classification)

    render_hook(view, "assign_securities", %{
      "security_ids" => [ctx.alpha.id, ctx.bravo.id],
      "classification_id" => ctx.classification.id,
      "category_id" => ctx.satellite.id
    })

    assert invested(view, ctx.satellite) == "1,500.00"
    assert invested(view, ctx.core) == "—"
    assert invested(view, ctx.equity) == "—"
  end

  test "an unassigned member leaves its category and the note", %{conn: conn} = ctx do
    # Charlie AG has no quote, so the roll-up leaves it out and names it.
    charlie = create_security!(name: "Charlie AG", ticker: "CHA")
    buy!(ctx.world, charlie, quantity: "2", price: "40")
    assign!(charlie, ctx.classification, ctx.core)

    view = open!(conn, ctx.classification)
    assert excluded_note(view) =~ "Charlie AG"

    render_hook(view, "unassign", %{
      "security_id" => charlie.id,
      "classification_id" => ctx.classification.id
    })

    refute excluded_note(view) =~ "Charlie AG"
    assert invested(view, ctx.core) == "1,000.00"

    render_hook(view, "unassign_many", %{
      "security_ids" => [ctx.alpha.id],
      "classification_id" => ctx.classification.id
    })

    assert invested(view, ctx.core) == "—"
  end

  test "a category moved under another parent counts there", %{conn: conn} = ctx do
    view = open!(conn, ctx.classification)

    render_hook(view, "update_category", %{
      "category" => %{"id" => to_string(ctx.core.id), "parent_id" => to_string(ctx.satellite.id)}
    })

    assert invested(view, ctx.satellite) == "1,000.00"
    assert invested(view, ctx.equity) == "—"
  end

  # A create changes no figure of its own (the new category holds nothing),
  # so an assignment made elsewhere -- another tab, the API -- is what shows
  # that the result was computed again.
  test "a created category restarts the result", %{conn: conn} = ctx do
    view = open!(conn, ctx.classification)
    assign!(ctx.bravo, ctx.classification, ctx.satellite)
    assert invested(view, ctx.satellite) == "—"

    render_hook(view, "create_category", %{
      "category" => %{"classification_id" => to_string(ctx.classification.id), "name" => "Bonds"}
    })

    assert invested(view, ctx.satellite) == "500.00"
  end

  # The same assignment made elsewhere is not picked up by a filter change
  # or a rename, because neither computes the result again; the create at
  # the end shows the assignment was there to be picked up.
  test "a filter change or a rename does not restart the result", %{conn: conn} = ctx do
    view = open!(conn, ctx.classification)
    assign!(ctx.bravo, ctx.classification, ctx.satellite)

    view |> form("#tree-search-form", %{"query" => "AG"}) |> render_change()
    assert invested(view, ctx.satellite) == "—"

    view |> form("#current-only-form", %{"current_only" => "false"}) |> render_change()
    assert invested(view, ctx.satellite) == "—"

    render_hook(view, "update_category", %{
      "category" => %{"id" => to_string(ctx.satellite.id), "name" => "Satellites"}
    })

    assert invested(view, ctx.satellite) == "—"

    render_hook(view, "create_category", %{
      "category" => %{"classification_id" => to_string(ctx.classification.id), "name" => "Bonds"}
    })

    assert invested(view, ctx.satellite) == "500.00"
  end
end
