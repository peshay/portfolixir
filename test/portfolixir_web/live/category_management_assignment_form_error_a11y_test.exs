defmodule PortfolixirWeb.CategoryManagementAssignmentFormErrorA11yTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.{Catalog, Taxonomies}

  test "assignment form error keeps deterministic assistive-tech linkage", %{conn: conn} do
    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Allocation"})
    {:ok, category} = Taxonomies.create_category(%{taxonomy_id: taxonomy.id, name: "Core"})

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

    form_html =
      view
      |> element("#category-assignment-form")
      |> render()

    {:ok, [assignment_form]} = Floki.parse_fragment(form_html)

    describedby_before_error =
      assignment_form
      |> Floki.attribute("aria-describedby")
      |> List.first()

    assert describedby_before_error == "category-assignment-feedback-context"

    view
    |> form("#category-assignment-form", %{
      "assignment" => %{
        "security_id" => to_string(security.id),
        "category_id" => to_string(category.id)
      }
    })
    |> render_submit()

    assert has_element?(view, "#category-assignment-error[role='alert']")

    form_html =
      view
      |> element("#category-assignment-form")
      |> render()

    {:ok, [assignment_form]} = Floki.parse_fragment(form_html)

    describedby_after_error =
      assignment_form
      |> Floki.attribute("aria-describedby")
      |> List.first()
      |> String.split(" ", trim: true)

    assert describedby_after_error == [
             "category-assignment-feedback-context",
             "category-assignment-error"
           ]

    view
    |> form("#category-assignment-form", %{
      "assignment" => %{
        "security_id" => to_string(security.id),
        "category_id" => to_string(category.id)
      }
    })
    |> render_submit()

    assert has_element?(view, "#category-assignment-error[role='alert']")

    form_html =
      view
      |> element("#category-assignment-form")
      |> render()

    {:ok, [assignment_form]} = Floki.parse_fragment(form_html)

    describedby_after_second_error =
      assignment_form
      |> Floki.attribute("aria-describedby")
      |> List.first()
      |> String.split(" ", trim: true)

    assert describedby_after_second_error == [
             "category-assignment-feedback-context",
             "category-assignment-error"
           ]
  end
end
