defmodule PortfolixirWeb.CategoryManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.{Catalog, Taxonomies}

  test "visiting /taxonomies renders shared app shell", %{conn: conn} do
    {:ok, view, html} = live(conn, "/taxonomies")

    assert has_element?(view, "a[href=\"/securities\"]")
    assert has_element?(view, "a[href=\"/taxonomies\"]")
    assert has_element?(view, "img#app-shell-brand-mark[src='/images/logo-mark.svg']")
    assert has_element?(view, ".app-shell-brand-text", "Portfolixir")
    assert has_element?(view, "#sidebar-toggle")
    assert has_element?(view, "#theme-toggle")
    assert html =~ "id=\"theme-toggle-script\""
    assert html =~ "Classifications"
    assert html =~ "Taxonomy tree"
    assert html =~ "Selected classification details"
    assert html =~ "Create Taxonomy"

    assert has_element?(
             view,
             "#no-taxonomy-selected[role='status'][aria-live='polite'][aria-labelledby='no-taxonomy-selected-title'][aria-describedby='no-taxonomy-selected-description']"
           )

    assert has_element?(
             view,
             "#no-taxonomy-selected-title",
             "Create or select a taxonomy first"
           )

    assert has_element?(
             view,
             "#no-taxonomy-selected-description",
             "Categories belong to one taxonomy, so choose the grouping system before adding them."
           )
  end

  test "category empty state announces deterministic semantics for assistive technology", %{
    conn: conn
  } do
    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{
        name: "Allocation",
        description: "Top level allocation groups"
      })

    {:ok, view, _html} = live(conn, "/taxonomies")

    assert has_element?(view, "#taxonomy-#{taxonomy.id}[disabled]", "Allocation")

    assert has_element?(
             view,
             "#no-categories[role='status'][aria-live='polite'][aria-labelledby='no-categories-title'][aria-describedby='no-categories-description']"
           )

    assert has_element?(view, "#no-categories-title", "No categories yet")

    assert has_element?(
             view,
             "#no-categories-description",
             "Add the first category for this taxonomy."
           )

    assert has_element?(view, "#category-form")

    assert has_element?(
             view,
             "#classification-tree-empty[role='status'][aria-live='polite'][aria-labelledby='classification-tree-empty-title'][aria-describedby='classification-tree-empty-description']"
           )

    assert has_element?(view, "#classification-tree-empty-title", "No categories yet")

    assert has_element?(
             view,
             "#classification-tree-empty-description",
             "Select a taxonomy and add categories to populate the category tree."
           )
  end

  test "classifications workspace explains taxonomy/category relationship", %{conn: conn} do
    {:ok, view, html} = live(conn, "/taxonomies")

    assert html =~ "user-defined grouping systems"
    assert has_element?(view, "#classification-workbench-toolbar")
    assert has_element?(view, "#classification-view-list[disabled]", "List")
    assert has_element?(view, "#classification-view-tree[disabled]", "Tree")
    assert has_element?(view, "#classification-view-chart[disabled]", "Chart")
    assert has_element?(view, "#classification-view-sunburst[disabled]", "Sunburst")
    assert has_element?(view, "#classification-workspace.app-shell-workspace-grid")
    assert has_element?(view, "#classification-tree-region[data-priority='primary']")
    assert has_element?(view, "#classification-details-region[data-priority='secondary']")
    assert has_element?(view, "#taxonomy-form.app-shell-form-grid")

    assert has_element?(
             view,
             "#no-taxonomies[role='status'][aria-live='polite'][aria-labelledby='no-taxonomies-heading'][aria-describedby='no-taxonomies-description']"
           )

    assert has_element?(view, "#no-taxonomies-heading", "No taxonomies yet")

    assert has_element?(
             view,
             "#no-taxonomies-description",
             "Create a taxonomy before adding categories."
           )

    assert has_element?(view, "#classification-details-region .app-shell-empty-state")
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

  test "German UI can create Portfolio Performance classification presets idempotently", %{
    conn: conn
  } do
    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, view, html} = live(conn, "/taxonomies")

    assert html =~ "Klassifizierungen"

    assert has_element?(
             view,
             "#portfolio-performance-presets",
             "Portfolio-Performance-Vorlagen anlegen"
           )

    html = view |> element("#portfolio-performance-presets") |> render_click()

    assert html =~ "Strategien"
    assert html =~ "Regionen"
    assert html =~ "Branchen"
    assert html =~ "Wertpapierarten"

    html = view |> element("#portfolio-performance-presets") |> render_click()

    assert html =~ "Portfolio-Performance-Vorlagen sind vorhanden."

    assert Taxonomies.list_taxonomies() |> Enum.filter(&(&1.name == "Strategien")) |> length() ==
             1
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

    assert html =~ "has already been taken"
    assert has_element?(view, "#category-form-error[role='alert']")
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

  test "renders deterministic nested classification tree with assignment counts", %{conn: conn} do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Allocation"})

    {:ok, parent} =
      Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Parent", sort_order: 1})

    {:ok, child} =
      Taxonomies.create_category(%{
        taxonomy_id: taxonomy.id,
        parent_id: parent.id,
        name: "Child",
        sort_order: 2
      })

    :ok = Catalog.ensure_mvp_currencies!()

    {:ok, security} =
      Catalog.create_security(%{
        name: "ETF",
        symbol: "ETF",
        isin: "US0000000001",
        currency_code: "EUR"
      })

    {:ok, _} = Catalog.assign_category_to_security(security.id, child.id)

    {:ok, view, _html} = live(conn, "/taxonomies")

    assert has_element?(view, "#tree-node-#{parent.id}", "Parent")
    assert has_element?(view, "#tree-node-#{child.id}", "Child")

    tree_html = render(view)
    assert tree_html =~ "assigned"
    assert tree_html =~ "1"
  end

  test "selecting a security loads current assignments before any write action", %{conn: conn} do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Allocation"})

    {:ok, category} =
      Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core"})

    :ok = Catalog.ensure_mvp_currencies!()

    {:ok, security} =
      Catalog.create_security(%{
        name: "ETF One",
        symbol: "ETF1",
        isin: "US0000000002",
        currency_code: "EUR"
      })

    {:ok, _} = Catalog.assign_category_to_security(security.id, category.id)

    {:ok, view, _html} = live(conn, "/taxonomies")

    refute has_element?(view, "#security-assignment-#{security.id}-#{category.id}")

    view
    |> form("#category-assignment-form", %{
      "assignment" => %{"security_id" => to_string(security.id), "category_id" => ""}
    })
    |> render_change()

    assert has_element?(view, "#security-assignment-#{security.id}-#{category.id}")
  end

  test "security assignment empty hint exposes deterministic semantics for assistive technology",
       %{
         conn: conn
       } do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Allocation"})
    {:ok, _category} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core"})

    {:ok, view, _html} = live(conn, "/taxonomies")

    assert has_element?(
             view,
             "#security-assignments-empty[role='status'][aria-live='polite'][aria-labelledby='security-assignments-empty-title'][aria-describedby='security-assignments-empty-description']"
           )

    assert has_element?(
             view,
             "#security-assignments-empty-title",
             "Select a security to view assignments."
           )

    assert has_element?(
             view,
             "#security-assignments-empty-description.app-shell-visually-hidden",
             "Select a security in the assignment form to review category assignments."
           )
  end

  test "assigns and removes category assignments through UI", %{conn: conn} do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Allocation"})

    {:ok, category} =
      Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core"})

    :ok = Catalog.ensure_mvp_currencies!()

    {:ok, security} =
      Catalog.create_security(%{
        name: "ETF One",
        symbol: "ETF1",
        isin: "US0000000002",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/taxonomies")

    html =
      view
      |> form("#category-assignment-form", %{
        "assignment" => %{
          "security_id" => to_string(security.id),
          "category_id" => to_string(category.id)
        }
      })
      |> render_submit()

    assert html =~ "Core"
    assert has_element?(view, "#security-assignment-#{security.id}-#{category.id}")

    view
    |> element("#remove-security-assignment-#{security.id}-#{category.id}")
    |> render_click()

    refute has_element?(view, "#security-assignment-#{security.id}-#{category.id}")
  end

  test "duplicate security/category assignment is shown as validation error", %{conn: conn} do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Allocation"})

    {:ok, category} =
      Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core"})

    :ok = Catalog.ensure_mvp_currencies!()

    {:ok, security} =
      Catalog.create_security(%{
        name: "ETF Two",
        symbol: "ETF2",
        isin: "US0000000003",
        currency_code: "EUR"
      })

    {:ok, _} = Catalog.assign_category_to_security(security.id, category.id)

    {:ok, view, _html} = live(conn, "/taxonomies")

    html =
      view
      |> form("#category-assignment-form", %{
        "assignment" => %{
          "security_id" => to_string(security.id),
          "category_id" => to_string(category.id)
        }
      })
      |> render_submit()

    assert html =~ "has already been taken"
    assert has_element?(view, "#category-assignment-error[role='alert']")
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
