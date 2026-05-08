defmodule PortfolixirWeb.CategoryManagementTaxonomiesEmptyStateA11yTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  test "taxonomies empty state keeps deterministic title and description relationships", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/taxonomies")

    assert has_element?(view, "#no-taxonomies[role='status'][aria-live='polite']")

    empty_state_html =
      view
      |> element("#no-taxonomies")
      |> render()

    {:ok, [status_region]} = Floki.parse_fragment(empty_state_html)

    labelledby =
      status_region
      |> Floki.attribute("aria-labelledby")
      |> List.first()

    describedby =
      status_region
      |> Floki.attribute("aria-describedby")
      |> List.first()

    assert labelledby == "no-taxonomies-title"
    assert describedby == "no-taxonomies-description"

    assert has_element?(view, "##{labelledby}", "No taxonomies yet")
    assert has_element?(view, "##{describedby}", "Create a taxonomy before adding categories.")
  end
end
