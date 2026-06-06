defmodule PortfolixirWeb.ClassificationsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Classifications

  # User story:
  # As a portfolio maintainer,
  # I want a Classifications page that shows the built-in trees and lets me
  # build custom ones and drop securities into categories,
  # so that I can organise holdings like folders.

  defp security!(attrs \\ %{}) do
    base = %{name: "Apple", currency_code: "USD", asset_class: "equity"}
    {:ok, security} = Catalog.create_security(Map.merge(base, attrs))
    security
  end

  test "shows built-in trees and creates a custom classification", %{conn: conn} do
    security!()

    {:ok, view, html} = live(conn, "/classifications")

    assert html =~ "Asset class"
    assert html =~ "Apple"

    html =
      view
      |> form("#classification-form", classification: %{name: "My Strategy"})
      |> render_submit()

    assert html =~ "My Strategy"
  end

  test "assigns a security to a custom category via the drag event", %{conn: conn} do
    security = security!()
    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    {:ok, view, _html} = live(conn, "/classifications")

    render_hook(view, "assign_security", %{
      "security_id" => security.id,
      "classification_id" => classification.id,
      "category_id" => category.id
    })

    custom =
      Classifications.list_trees()
      |> Enum.find(&(&1.classification.id == classification.id))

    assert custom.assignments == [%{security_id: security.id, category_id: category.id}]
  end

  test "rejects dropping onto a built-in tree", %{conn: conn} do
    security = security!()
    Classifications.ensure_builtins()
    asset = Classifications.get_classification_by_key("asset_class")

    {:ok, view, _html} = live(conn, "/classifications")

    html =
      render_hook(view, "assign_security", %{
        "security_id" => security.id,
        "classification_id" => asset.id,
        "category_id" => 0
      })

    assert html =~ "cannot be edited"
  end
end
