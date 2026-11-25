defmodule PortfolixirWeb.DashboardIndexEditTest do
  # Sprint 31 closing act, order lens O3 (S3): on `/`, which opens the
  # first stored dashboard, every address change (a period or a scope
  # pick) read the menu's first dashboard again; once an agent moved
  # another dashboard first, the pick dropped the open edit unsaved, and
  # the status line still described the last edit step.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable` row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PeriodMenuHelpers
  import PortfolixirWeb.PreferenceCookieHelpers
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards

  @layout [%{"kind" => "performance", "size" => "L", "col" => 1, "row" => 1}]

  defp seed do
    world = base_world()

    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-10])
    put_quote!(security, Portfolixir.Clock.today(), "120")

    {:ok, a} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "A", "layout" => @layout})

    {:ok, b} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "B", "layout" => []})
    {a, b}
  end

  defp editing(conn, locale) do
    {:ok, view, _html} =
      conn |> put_preference_cookie("portfolixir_locale", locale) |> live("/")

    view |> element("[data-role='edit-start']") |> render_click()

    view
    |> element("[data-widget-kind='performance'] [data-role='edit-handle']")
    |> render_keydown(%{"key" => "ArrowDown"})

    view
  end

  defp status(view),
    do:
      view
      |> element("#dashboard-edit-status")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.text()

  # User story:
  # As the operator editing the dashboard `/` opened,
  # I want a period or a scope pick to keep my edit on that dashboard,
  # so that an agent reordering the menu meanwhile neither drops my edit
  # nor shows me another dashboard.
  #
  # Acceptance criteria:
  # - With an edit open on `/`, the agent moves another dashboard first;
  #   a period pick keeps the edit, on the dashboard it edits, its step
  #   still applied.
  # - Where the edited dashboard was deleted elsewhere, the pick ends the
  #   edit and the status line says so.
  test "on /, a period pick keeps the open edit on its dashboard", %{conn: conn} do
    {a, b} = seed()
    view = editing(conn, "de")

    {:ok, _} = Dashboards.update_dashboard(Actor.api_token_rw("agent"), a.id, %{"position" => 5})
    assert hd(Dashboards.list_dashboards()).id == b.id
    pick_period(view, "3m")

    assert has_element?(view, "[data-role='edit-handle']")
    assert has_element?(view, "#app-topbar-title", "A")
    assert has_element?(view, "[data-widget-kind='performance'][data-row='2']")
  end

  test "on /, an edit whose dashboard was deleted elsewhere ends, and says so", %{conn: conn} do
    {a, _b} = seed()
    view = editing(conn, "en")

    :ok = delete!(a)
    pick_period(view, "3m")

    refute has_element?(view, "[data-role='edit-handle']")
    assert status(view) =~ "deleted elsewhere; the edit ended unsaved"
  end

  defp delete!(dashboard) do
    case Dashboards.delete_dashboard(Actor.api_token_rw("agent"), dashboard.id) do
      {:ok, _deleted} -> :ok
      :ok -> :ok
    end
  end
end
