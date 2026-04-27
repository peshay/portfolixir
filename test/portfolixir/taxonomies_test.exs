defmodule Portfolixir.TaxonomiesTest do
  use Portfolixir.DataCase, async: true

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
end
