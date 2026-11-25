defmodule PortfolixirWeb.DashboardRowSizeTest do
  # Sprint 32 S2 (ADR-0062's amendment of 2026-11-25, point 3; board
  # ux-design-2026-11-25-sprint32/02 ①, ③): the page draws a „Zeile“ item
  # at its content's height. LiveViewTest applies no CSS, so here the
  # markup the CSS reads is checked — the item's class and the grid's row
  # template —; test/browser/dashboard_row_test.exs measures the heights.
  # Synthetic data only.
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, sell!: 3, put_quote!: 3]
  import PortfolixirWeb.PreferenceCookieHelpers

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards

  defp seed do
    world = base_world()

    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-10])
    sell!(world, security, quantity: "4", price: "110", date: ~D[2026-03-10])
    put_quote!(security, Portfolixir.Clock.today(), "120")
  end

  # User story:
  # As the operator who placed a section as „Zeile“,
  # I want it drawn across the grid as tall as its content, the rows after
  # it starting below it, and its size named „Zeile“ in the edit mode,
  # so that a section reads as it does on its screen.
  #
  # Acceptance criteria:
  # - The item is drawn with `widget--row` and `data-size="row"`, spanning
  #   the 12 columns.
  # - The grid names its row template: every row of the layout 7rem, the
  #   row a „Zeile“ item stands on `auto`; a layout without one names none.
  # - In the edit mode its size switch offers L and „Zeile“ (German), the
  #   one active pressed.
  test "a „Zeile“ item is drawn across the grid on a row as tall as its content",
       %{conn: conn} do
    seed()

    layout = [
      %{"kind" => "due", "size" => "S", "col" => 1, "row" => 1},
      %{"kind" => "sale_review", "size" => "row", "col" => 1, "row" => 3},
      %{"kind" => "data_quality", "size" => "S", "col" => 1, "row" => 4}
    ]

    {:ok, board} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Zeilen", "layout" => layout})

    conn = put_preference_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(conn, "/dashboards/#{board.id}")
    render_async(view)
    doc = view |> render() |> Floki.parse_document!()

    [section] = Floki.find(doc, "[data-widget-kind='sale_review']")
    assert Floki.attribute(section, "data-size") == ["row"]
    assert hd(Floki.attribute(section, "class")) =~ "widget--row"
    assert hd(Floki.attribute(section, "style")) =~ "--widget-w: 12; --widget-h: 1;"

    [grid] = Floki.attribute(doc, "#dashboard-grid", "style")
    assert grid =~ "--dashboard-rows: 7rem 7rem auto 7rem 7rem;"

    view |> element("[data-role='edit-start']") |> render_click()

    sizes =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("[data-widget-kind='sale_review'] [data-role='edit-size']")

    assert Enum.map(sizes, &String.trim(Floki.text(&1))) == ["L", "Zeile"]
    assert Enum.map(sizes, &hd(Floki.attribute(&1, "aria-pressed"))) == ["false", "true"]

    {:ok, plain} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Ohne",
        "layout" => [hd(layout)]
      })

    {:ok, view, _html} = live(conn, "/dashboards/#{plain.id}")
    refute view |> render() |> Floki.parse_document!() |> Floki.raw_html() =~ "--dashboard-rows"
  end
end
