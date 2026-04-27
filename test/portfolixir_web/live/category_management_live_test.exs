defmodule PortfolixirWeb.CategoryManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Taxonomies

  test "visiting /taxonomies renders category management", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/taxonomies")

    assert html =~ "Category Management"
    assert html =~ "Taxonomies"
    assert html =~ "Categories"
    assert html =~ "Create Taxonomy"
  end

  test "creating a taxonomy appears in the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/taxonomies")

    html =
      view
      |> form("#taxonomy-form", %{
        "taxonomy" => %{"name" => "Allocation", "description" => "Top level allocation groups"}
      })
      |> render_submit()

    assert html =~ "Allocation"
    assert html =~ "Top level allocation groups"
  end

  test "creating and updating a category with description", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/taxonomies")

    view
    |> form("#taxonomy-form", %{
      "taxonomy" => %{"name" => "Allocation", "description" => "Base taxonomies"}
    })
    |> render_submit()

    html =
      view
      |> form("#category-form", %{
        "category" => %{
          "name" => "Core ETF",
          "description" => "Core ETF holdings with broad market exposure"
        }
      })
      |> render_submit()

    assert html =~ "Core ETF"
    assert html =~ "Core ETF holdings with broad market exposure"

    created_category =
      Taxonomies.list_categories(Taxonomies.list_taxonomies() |> List.first() |> Map.get(:id))
      |> hd()

    html =
      view
      |> form("#edit-category-form-#{created_category.id}", %{
        "category" => %{
          "name" => "Core ETF",
          "description" => "Updated core ETF description"
        }
      })
      |> render_submit()

    assert html =~ "Updated core ETF description"
  end

  test "duplicate category names in a taxonomy are rejected", %{conn: conn} do
    {:ok, _taxonomy} =
      Taxonomies.create_taxonomy(%{
        name: "Allocation",
        description: "Base taxonomies"
      })

    {:ok, _} =
      Taxonomies.create_category(%{
        taxonomy_id: Taxonomies.list_taxonomies() |> List.first() |> Map.get(:id),
        name: "Core ETF"
      })

    {:ok, view, _html} = live(conn, "/taxonomies")

    html =
      view
      |> form("#category-form", %{
        "category" => %{"name" => "Core ETF", "description" => "Duplicate name in same taxonomy"}
      })
      |> render_submit()

    assert html =~ "name has already been taken"
  end

  test "same category name in different taxonomies is allowed", %{conn: conn} do
    {:ok, first_taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Allocation", description: "Base taxonomies"})

    {:ok, _} =
      Taxonomies.create_category(%{
        taxonomy_id: first_taxonomy.id,
        name: "Core ETF"
      })

    {:ok, second_taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Regions", description: "Region groups"})

    {:ok, view, _html} = live(conn, "/taxonomies")

    view
    |> element("#taxonomy-#{second_taxonomy.id}")
    |> render_click()

    html =
      view
      |> form("#category-form", %{
        "category" => %{"name" => "Core ETF", "description" => "Region ETF"}
      })
      |> render_submit()

    assert html =~ "Core ETF"
    assert html =~ "Region ETF"
  end

  test "deleting a category removes it from the list", %{conn: conn} do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Allocation"})

    {:ok, category} =
      Taxonomies.create_category(%{
        taxonomy_id: taxonomy.id,
        name: "Delete Me",
        description: "Will be deleted"
      })

    {:ok, view, _html} = live(conn, "/taxonomies")
    assert render(view) =~ "Delete Me"

    view
    |> element("#delete-category-#{category.id}")
    |> render_click()

    refute render(view) =~ "Delete Me"
  end
end
