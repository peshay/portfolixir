defmodule PortfolixirWeb.DashboardOwnScopeTest do
  # Sprint 32 S1 (ADR-0062's amendment of 2026-11-25, point 4; I61; board
  # ux-design-2026-11-25-sprint32/03 ②): a dashboard's own view is read
  # before the address's scope and the default view, an item's own view
  # overrides it, and a deleted one is read as the default and said in the
  # top bar. Synthetic data only.
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Dashboards
  alias PortfolixirWeb.Format

  defp api(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp seed do
    world = base_world()

    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-10])
    put_quote!(security, Portfolixir.Clock.today(), "120")
  end

  defp total(doc, id),
    do:
      doc
      |> Floki.find("##{id} [data-form='wide'] [data-count-digits]")
      |> Floki.text()
      |> String.trim()

  # User story:
  # As the operator who made a dashboard for one view,
  # I want its widgets to read that view wherever I open it from, an item's
  # own view still winning, and the bar to say the view is the dashboard's,
  # so that the dashboard shows what I made it for.
  #
  # Acceptance criteria:
  # - A dashboard with an own view reads it, also under `?scope=total`: the
  #   „Gesamtwert“ total equals GET /api/v1/views/:id/valuation's, not the
  #   Everything total; the bar names the view as the dashboard's own and
  #   offers no scope menu.
  # - An item with its own view reads that view.
  # - After the view's delete the dashboard reads the default (Everything),
  #   the bar says the own view no longer exists, and the scope menu is
  #   back.
  test "the dashboard's own view is read before the address's, and a deleted one is said",
       %{conn: conn} do
    seed()
    {:ok, empty} = Buckets.create_view(Actor.owner_ui(), %{name: "Leer", include_all: false})
    {:ok, all} = Buckets.create_view(Actor.owner_ui(), %{name: "Alles drin", include_all: true})

    layout = [
      %{"kind" => "total_value", "size" => "L", "col" => 1, "row" => 1},
      %{
        "kind" => "total_value",
        "size" => "L",
        "col" => 7,
        "row" => 1,
        "settings" => %{"view_id" => all.id}
      }
    ]

    {:ok, board} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Eigene Sicht",
        "layout" => layout,
        "view_id" => empty.id
      })

    own_total = api("/api/v1/views/#{empty.id}/valuation?include_positions=false")
    everything = api("/api/v1/valuation?include_positions=false")
    all_total = api("/api/v1/views/#{all.id}/valuation?include_positions=false")
    refute own_total["total_with_cash"] == everything["total_with_cash"]

    {:ok, view, _html} = live(conn, "/dashboards/#{board.id}?scope=total")
    render_async(view)
    doc = view |> render() |> Floki.parse_document!()

    assert total(doc, "dashboard-wealth") ==
             Format.money(Decimal.new(own_total["total_with_cash"]))

    assert total(doc, "dashboard-wealth-2") ==
             Format.money(Decimal.new(all_total["total_with_cash"]))

    assert has_element?(view, "[data-role='dashboard-scope-name']", "Leer")
    assert has_element?(view, "[data-role='dashboard-scope-own']")
    refute has_element?(view, "#dashboard-scope nav")
    assert has_element?(view, "#dashboard-wealth [data-role='widget-scope']", "View Leer")

    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), empty)

    {:ok, view, _html} = live(conn, "/dashboards/#{board.id}")
    render_async(view)
    doc = view |> render() |> Floki.parse_document!()

    assert total(doc, "dashboard-wealth") ==
             Format.money(Decimal.new(everything["total_with_cash"]))

    assert has_element?(
             view,
             "[data-role='dashboard-scope-dangling']",
             "This dashboard's own view no longer exists · reads Everything"
           )

    assert has_element?(view, "#dashboard-scope nav")
  end
end
