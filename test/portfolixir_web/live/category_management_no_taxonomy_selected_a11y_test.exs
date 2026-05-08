defmodule PortfolixirWeb.CategoryManagementNoTaxonomySelectedA11yTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  test "no taxonomy selected status keeps deterministic assistive relationships", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/taxonomies")

    assert has_element?(view, "#no-taxonomy-selected[role='status'][aria-live='polite']")

    empty_state_html =
      view
      |> element("#no-taxonomy-selected")
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

    assert labelledby == "no-taxonomy-selected-status-title"
    assert describedby == "no-taxonomy-selected-status-description"

    assert has_element?(
             view,
             "##{labelledby}.app-shell-visually-hidden",
             "Create or select a taxonomy first"
           )

    assert has_element?(
             view,
             "##{describedby}.app-shell-visually-hidden",
             "Categories belong to one taxonomy, so choose the grouping system before adding them."
           )

    assert has_element?(view, "#no-taxonomy-selected-title", "Create or select a taxonomy first")

    assert has_element?(
             view,
             "#no-taxonomy-selected-description",
             "Categories belong to one taxonomy, so choose the grouping system before adding them."
           )
  end
end
