defmodule Portfolixir.ClassificationsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Classifications

  # User story:
  # As a portfolio maintainer (and the LLM over MCP),
  # I want classification trees — including built-in asset-class and currency
  # trees that are filled in automatically — into which securities are sorted,
  # so that I can organise holdings like folders without hand-maintaining the
  # groupings I can already derive.

  defp security!(attrs) do
    base = %{name: "Apple", ticker_symbol: "AAPL", currency_code: "USD", asset_class: "equity"}
    {:ok, security} = Catalog.create_security(Map.merge(base, attrs))
    security
  end

  defp tree(trees, key) do
    Enum.find(trees, fn %{classification: classification} -> classification.key == key end)
  end

  defp category(tree, key) do
    Enum.find(tree.categories, &(&1.key == key))
  end

  test "seeds built-in trees and derives assignments from security data" do
    security = security!(%{currency_code: "USD", asset_class: "equity"})

    trees = Classifications.list_trees()

    asset = tree(trees, "asset_class")
    assert asset.classification.built_in
    assert asset.classification.name == "Asset class"

    equity = category(asset, "equity")
    assert equity
    assert %{security_id: security.id, category_id: equity.id} in asset.assignments

    currency = tree(trees, "currency")
    usd = category(currency, "USD")
    assert %{security_id: security.id, category_id: usd.id} in currency.assignments
  end

  test "built-in trees are locked against editing" do
    Classifications.ensure_builtins()
    security = security!(%{})
    asset = Classifications.get_classification_by_key("asset_class")
    equity = Classifications.list_trees() |> tree("asset_class") |> category("equity")

    assert {:error, :builtin_locked} = Classifications.update_classification(asset, %{name: "X"})
    assert {:error, :builtin_locked} = Classifications.delete_classification(asset)

    assert {:error, :builtin_locked} =
             Classifications.create_category(%{classification_id: asset.id, name: "X"})

    assert {:error, :builtin_locked} =
             Classifications.assign_security(security.id, asset.id, equity.id)
  end

  test "supports custom trees with categories and security assignments" do
    security = security!(%{})
    {:ok, classification} = Classifications.create_classification(%{name: "My Strategy"})

    {:ok, core} =
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Core",
        color: "#7C3AED"
      })

    {:ok, satellite} =
      Classifications.create_category(%{classification_id: classification.id, name: "Satellite"})

    assert core.color == "#7c3aed"

    {:ok, _} = Classifications.assign_security(security.id, classification.id, core.id)

    custom = Classifications.list_trees() |> tree(nil)
    assert %{security_id: security.id, category_id: core.id} in custom.assignments

    # Re-assigning replaces the single slot for this (security, classification).
    {:ok, _} = Classifications.assign_security(security.id, classification.id, satellite.id)
    custom = Classifications.list_trees() |> tree(nil)
    assert [%{security_id: _, category_id: category_id}] = custom.assignments
    assert category_id == satellite.id

    assert {:ok, 1} = Classifications.unassign_security(security.id, classification.id)
    custom = Classifications.list_trees() |> tree(nil)
    assert custom.assignments == []
  end

  test "rejects assigning a security to a category from another classification" do
    security = security!(%{})
    {:ok, a} = Classifications.create_classification(%{name: "A"})
    {:ok, b} = Classifications.create_classification(%{name: "B"})
    {:ok, b_category} = Classifications.create_category(%{classification_id: b.id, name: "B1"})

    assert {:error, :category_mismatch} =
             Classifications.assign_security(security.id, a.id, b_category.id)
  end

  test "assigns and unassigns many securities at once" do
    one = security!(%{name: "One", ticker_symbol: "ONE"})
    two = security!(%{name: "Two", ticker_symbol: "TWO"})
    three = security!(%{name: "Three", ticker_symbol: "THREE"})

    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})
    cid = classification.id

    {:ok, core} = Classifications.create_category(%{classification_id: cid, name: "Core"})

    {:ok, satellite} =
      Classifications.create_category(%{classification_id: cid, name: "Satellite"})

    all_ids = [one.id, two.id, three.id]
    assert {:ok, 3} = Classifications.assign_securities(all_ids, cid, core.id)

    custom = Classifications.list_trees() |> tree(nil)
    assert length(custom.assignments) == 3
    assert Enum.all?(custom.assignments, &(&1.category_id == core.id))

    # Re-assigning the same pair moves it (upsert), it does not duplicate.
    pair = [one.id, two.id]
    assert {:ok, 2} = Classifications.assign_securities(pair, cid, satellite.id)

    custom = Classifications.list_trees() |> tree(nil)
    assert length(custom.assignments) == 3
    by_security = Map.new(custom.assignments, &{&1.security_id, &1.category_id})
    assert by_security[one.id] == satellite.id
    assert by_security[three.id] == core.id

    assert {:ok, 2} = Classifications.unassign_securities([one.id, three.id], cid)

    custom = Classifications.list_trees() |> tree(nil)
    assert [%{security_id: security_id}] = custom.assignments
    assert security_id == two.id
  end

  test "bulk assign rejects built-in classifications" do
    security = security!(%{})
    Classifications.ensure_builtins()
    asset = Classifications.get_classification_by_key("asset_class")

    assert {:error, :builtin_locked} =
             Classifications.assign_securities([security.id], asset.id, 0)
  end

  test "seeds asset-class categories with distinct default colors" do
    asset = Classifications.list_trees() |> tree("asset_class")

    equity = category(asset, "equity")
    bond = category(asset, "bond")

    assert equity.color == "#2563eb"
    refute equity.color == bond.color
  end

  test "recolors a built-in category without unlocking its structure" do
    asset = Classifications.list_trees() |> tree("asset_class")
    equity = category(asset, "equity")

    assert {:ok, updated} = Classifications.recolor_category(equity, "#123abc")
    assert updated.color == "#123abc"

    # Re-seeding must not clobber the user-chosen color.
    Classifications.ensure_builtins()
    reloaded = Classifications.list_trees() |> tree("asset_class") |> category("equity")
    assert reloaded.color == "#123abc"

    # Names/keys stay locked.
    assert {:error, :builtin_locked} =
             Classifications.update_category(equity, %{name: "Stocks"})
  end

  test "stores an optional category description and blanks whitespace to nil" do
    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})
    cid = classification.id

    {:ok, with_desc} =
      Classifications.create_category(%{
        classification_id: cid,
        name: "Core",
        description: "  Long-term holdings  "
      })

    assert with_desc.description == "Long-term holdings"

    {:ok, blank} =
      Classifications.create_category(%{
        classification_id: cid,
        name: "Satellite",
        description: "   "
      })

    assert blank.description == nil
  end

  # User story:
  # As a maintainer fixing asset classes,
  # I want dragging a security in the built-in asset-class tree to set its class,
  # so that wrong or missing classes are correctable, like in Portfolio Performance.
  test "reclassifying in the asset-class tree edits the security's asset_class" do
    Classifications.ensure_builtins()

    {:ok, security} =
      Catalog.create_security(%{name: "Opaque Holding XYZ", currency_code: "EUR"})

    trees = Classifications.list_trees()
    asset_class = Enum.find(trees, &(&1.classification.key == "asset_class"))
    etf = Enum.find(asset_class.categories, &(&1.key == "etf"))

    assert {:ok, 1} = Classifications.reclassify_securities([security.id], etf.id)
    assert Catalog.get_security(security.id).asset_class == "etf"

    # The derived asset-class assignment now reflects the edit.
    refreshed =
      Classifications.list_trees()
      |> Enum.find(&(&1.classification.key == "asset_class"))

    assert %{security_id: security.id, category_id: etf.id} in refreshed.assignments

    # Dragging to "Unsorted" resets it to automatic (inferred on read).
    assert {:ok, 1} = Classifications.reset_asset_class([security.id])
    assert Catalog.get_security(security.id).asset_class == nil

    # The currency tree is intrinsic and cannot be reassigned this way.
    currency = Enum.find(trees, &(&1.classification.key == "currency"))

    assert {:error, :not_reclassifiable} =
             Classifications.reclassify_securities([security.id], hd(currency.categories).id)
  end
end
