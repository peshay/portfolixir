defmodule PortfolixirWeb.DashboardSavedPeriodTest do
  # Sprint 32 T2 and T5 (I59; ADR-0062's amendment of 2026-11-25, point 6):
  # an own period on the dashboard — in the address, and as a widget's pin
  # by reference — each widget reading it by its kind's rule, its figure
  # the API's for the same key. Every name and figure is synthetic.
  #
  # group: :periods -- a period's create takes the advisory lock that counts
  # the stored periods (`Portfolixir.LockTable` row 31); every module that
  # creates one joins this group. A dashboard, where one is made, is made
  # after the period, so the two count locks are always taken in one order.
  use PortfolixirWeb.ConnCase, async: true, group: :periods

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Periods

  defp seed do
    world = base_world()

    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    first = Date.new!(Clock.today().year - 1, 1, 10)
    buy!(world, security, quantity: "10", price: "100", date: first)
    put_quote!(security, first, "100")
    put_quote!(security, Date.new!(Clock.today().year - 1, 9, 30), "110")
    put_quote!(security, Clock.today(), "120")
    world
  end

  defp german(conn), do: put_preference_cookie(conn, "portfolixir_locale", "de")

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp document(view), do: view |> render() |> Floki.parse_document!()

  defp tag_text(view, kind) do
    view
    |> document()
    |> Floki.find("[data-widget-kind='#{kind}'] [data-role='widget-period']")
    |> text()
  end

  defp api(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  # User story (T2):
  # As the operator handing over a link on my own period,
  # I want the dashboard to open on it, each widget reading it by its
  # kind's rule and naming it by its name,
  # so that „Seit Umschichtung“ means the same on the screen and the API.
  #
  # Acceptance criteria:
  # - `/?period=saved:<id>` opens on it: „Gesamtwert“ says „folgt · Seit
  #   Umschichtung“ and its change line's TTWROR is the one
  #   GET /api/v1/performance answers for `period=saved:<id>`.
  # - Tops und Flops reads the window nearest the span and says so:
  #   „folgt · Seit Umschichtung → 1J“.
  # - A deleted period's key opens 1J.
  test "an own period in the address: its name, its figure the API's, tops and flops by length",
       %{conn: conn} do
    seed()

    {:ok, period} =
      Periods.create_saved(Actor.owner_ui(), %{
        "name" => "Seit Umschichtung",
        "from" => Date.new!(Clock.today().year - 1, 3, 1)
      })

    key = "saved:#{period.id}"
    {:ok, view, _html} = conn |> german() |> live("/?period=" <> key)
    render_async(view)

    assert tag_text(view, "total_value") == "folgt · Seit Umschichtung"
    assert tag_text(view, "movers") == "folgt · Seit Umschichtung → 1J"
    assert has_element?(view, "#dashboard-movers[data-window='1y']")

    figure =
      view
      |> document()
      |> Floki.find("[data-widget-kind='total_value'] [data-role='card-period-change']")
      |> text()

    ttwror = api("/api/v1/performance?period=" <> key)["ttwror"]
    assert figure =~ PortfolixirWeb.Format.signed_percent(Decimal.new(ttwror)) <> "%"
    assert figure =~ "TTWROR · Seit Umschichtung"

    {:ok, _} = Periods.delete_saved(Actor.owner_ui(), period.id)
    {:ok, view, _html} = conn |> german() |> live("/?period=" <> key)
    assert tag_text(view, "total_value") == "folgt · 1J"
  end
end
