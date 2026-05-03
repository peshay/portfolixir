defmodule Portfolixir.TaxonomiesTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.SecurityCategoryAssignment
  alias Portfolixir.Taxonomies
  alias Portfolixir.Taxonomies.Category

  test "create taxonomy" do
    assert {:ok, taxonomy} =
             Taxonomies.create_taxonomy(%{
               name: "Custom Depot Categories",
               description: "Top level groups"
             })

    assert taxonomy.name == "Custom Depot Categories"
  end

  test "ensure_portfolio_performance_presets!/0 creates German PP-style taxonomies idempotently" do
    assert :ok = Taxonomies.ensure_portfolio_performance_presets!()

    taxonomy_names = Taxonomies.list_taxonomies() |> Enum.map(& &1.name)

    assert "Strategien" in taxonomy_names
    assert "Regionen" in taxonomy_names
    assert "Branchen" in taxonomy_names
    assert "Wertpapierarten" in taxonomy_names

    count_after_first_run = Repo.aggregate(Portfolixir.Taxonomies.Taxonomy, :count)

    assert :ok = Taxonomies.ensure_portfolio_performance_presets!()
    assert Repo.aggregate(Portfolixir.Taxonomies.Taxonomy, :count) == count_after_first_run
  end

  test "create category with description and persist description" do
    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Custom Depot Categories", description: "Top level"})

    {:ok, category} =
      Taxonomies.create_category(%{
        taxonomy_id: taxonomy.id,
        name: "Core ETF",
        description: "Core ETF holdings with broad market exposure"
      })

    fetched = Taxonomies.get_category!(category.id)
    assert fetched.name == "Core ETF"
    assert fetched.description == "Core ETF holdings with broad market exposure"
  end

  test "create child category under Core ETF" do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Custom Depot Categories"})

    {:ok, parent} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core ETF"})

    {:ok, child} =
      Taxonomies.create_category(%{
        taxonomy_id: taxonomy.id,
        parent_id: parent.id,
        name: "US Core ETF"
      })

    assert child.parent_id == parent.id
    assert child.taxonomy_id == taxonomy.id
  end

  test "create category without taxonomy fails" do
    assert {:error, changeset} = Taxonomies.create_category(%{name: "Orphan"})

    assert %{taxonomy_id: ["can't be blank"]} = errors_on(changeset)
  end

  test "create category without name fails" do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Custom Depot Categories"})

    assert {:error, changeset} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id})

    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "duplicate category names are allowed across taxonomies" do
    {:ok, taxonomy_one} = Taxonomies.create_taxonomy(%{name: "Allocation"})
    {:ok, taxonomy_two} = Taxonomies.create_taxonomy(%{name: "Regions"})

    assert {:ok, _} =
             Taxonomies.create_category(%{taxonomy_id: taxonomy_one.id, name: "Global"})

    assert {:ok, _} =
             Taxonomies.create_category(%{taxonomy_id: taxonomy_two.id, name: "Global"})
  end

  test "category names are unique within a taxonomy" do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Allocation"})

    assert {:ok, _} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core ETF"})

    assert {:error, changeset} =
             Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core ETF"})

    assert %{name: ["has already been taken"]} = errors_on(changeset)
  end

  test "list categories by taxonomy" do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Allocation"})
    {:ok, _} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core ETF"})
    {:ok, _} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "SMA"})

    categories = Taxonomies.list_categories(taxonomy.id)

    assert Enum.count(categories) == 2
    assert Enum.any?(categories, &(&1.name == "Core ETF"))
    assert Enum.any?(categories, &(&1.name == "SMA"))
  end

  test "delete category" do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Allocation"})
    {:ok, category} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Delete Me"})

    assert {:ok, %Category{}} = Taxonomies.delete_category(category)
    assert_raise Ecto.NoResultsError, fn -> Taxonomies.get_category!(category.id) end
  end

  test "upsert mapping creates and deterministically updates duplicate mapping" do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Regions"})

    {:ok, category_a} =
      Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "North America"})

    {:ok, category_b} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "USA"})

    assert {:ok, mapping} =
             Taxonomies.upsert_fund_allocation_category_mapping(%{
               allocation_type: "region",
               source_label: "North America",
               taxonomy_id: taxonomy.id,
               category_id: category_a.id
             })

    assert {:ok, mapping_updated} =
             Taxonomies.upsert_fund_allocation_category_mapping(%{
               allocation_type: "region",
               source_label: "North America",
               taxonomy_id: taxonomy.id,
               category_id: category_b.id
             })

    assert mapping.id == mapping_updated.id
    assert mapping_updated.category_id == category_b.id
  end

  test "resolve mapped allocation exposures returns mapped and unmapped entries without creating direct assignments" do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Sectors"})
    {:ok, category} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Technology"})

    {:ok, _currency} = Catalog.ensure_currency(%{code: "EUR", name: "Euro", minor_units: 2})

    {:ok, security} =
      Catalog.create_security(%{
        name: "ETF One",
        symbol: "ETF1",
        isin: "DE000ETF1000",
        currency_code: "EUR"
      })

    {:ok, allocation} =
      Catalog.create_fund_allocation(%{
        security_id: security.id,
        source: "factsheet",
        allocation_type: "sector"
      })

    {:ok, _item_mapped} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: allocation.id,
        label: "Technology",
        weight: Decimal.new("40.0")
      })

    {:ok, _item_unmapped} =
      Catalog.create_fund_allocation_item(%{
        fund_allocation_id: allocation.id,
        label: "Utilities",
        weight: Decimal.new("10.0")
      })

    assert {:ok, _mapping} =
             Taxonomies.upsert_fund_allocation_category_mapping(%{
               allocation_type: "sector",
               source_label: "Technology",
               taxonomy_id: taxonomy.id,
               category_id: category.id
             })

    assignments_before = Repo.aggregate(SecurityCategoryAssignment, :count, :id)

    result = Taxonomies.resolve_mapped_fund_allocation_exposures(security.id)

    assert Enum.any?(result.items, fn item ->
             item.status == :mapped and item.source_label == "Technology" and
               item.category_id == category.id
           end)

    assert Enum.any?(result.items, fn item ->
             item.status == :unmapped and item.source_label == "Utilities"
           end)

    assert Enum.any?(result.warnings, &String.contains?(&1, "sector:Utilities"))
    assert Repo.aggregate(SecurityCategoryAssignment, :count, :id) == assignments_before
  end
end
