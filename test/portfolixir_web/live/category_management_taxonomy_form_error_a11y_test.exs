defmodule PortfolixirWeb.CategoryManagementTaxonomyFormErrorA11yTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  test "taxonomy form error keeps deterministic assistive-tech linkage", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/taxonomies")

    form_html =
      view
      |> element("#taxonomy-form")
      |> render()

    {:ok, [taxonomy_form]} = Floki.parse_fragment(form_html)

    describedby_before_error =
      taxonomy_form
      |> Floki.attribute("aria-describedby")
      |> List.first()

    assert describedby_before_error == "taxonomy-feedback-context"

    view
    |> form("#taxonomy-form", %{
      "taxonomy" => %{"name" => "", "description" => "Top level allocation groups"}
    })
    |> render_submit()

    assert has_element?(view, "#taxonomy-form-error[role='alert']")

    form_html =
      view
      |> element("#taxonomy-form")
      |> render()

    {:ok, [taxonomy_form]} = Floki.parse_fragment(form_html)

    describedby_after_error =
      taxonomy_form
      |> Floki.attribute("aria-describedby")
      |> List.first()
      |> String.split(" ", trim: true)

    assert describedby_after_error == ["taxonomy-feedback-context", "taxonomy-form-error"]

    view
    |> form("#taxonomy-form", %{
      "taxonomy" => %{"name" => "", "description" => "Different description"}
    })
    |> render_submit()

    assert has_element?(view, "#taxonomy-form-error[role='alert']")

    form_html =
      view
      |> element("#taxonomy-form")
      |> render()

    {:ok, [taxonomy_form]} = Floki.parse_fragment(form_html)

    describedby_after_second_error =
      taxonomy_form
      |> Floki.attribute("aria-describedby")
      |> List.first()
      |> String.split(" ", trim: true)

    assert describedby_after_second_error == ["taxonomy-feedback-context", "taxonomy-form-error"]
  end
end
