defmodule PortfolixirWeb.DashboardEditRebaseTest do
  # Sprint 31 closing act, order lens O1 (S2): „Weiter bearbeiten“ after a
  # stale „Fertig“ continued the edit on the stored dashboard's name and
  # lock_version but kept the layout read before the stale save, so
  # „Zurücksetzen“ went back to that old layout and the next „Fertig“
  # silently reverted the agent's change; and an edit made equal to the
  # old read counted as unchanged, so „Fertig“ stored nothing.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable` row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards

  @layout [
    %{"kind" => "performance", "size" => "L", "col" => 1, "row" => 1},
    %{"kind" => "movers", "size" => "L", "col" => 7, "row" => 1},
    %{"kind" => "crashes", "size" => "L", "col" => 1, "row" => 5}
  ]

  defp seed do
    world = base_world()

    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-10])
    put_quote!(security, Portfolixir.Clock.today(), "120")
    world
  end

  defp size(view, kind) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("[data-widget-kind='#{kind}']")
    |> Floki.attribute("data-size")
    |> hd()
  end

  defp key(view, kind, key) do
    view
    |> element("[data-widget-kind='#{kind}'] [data-role='edit-handle']")
    |> render_keydown(%{"key" => key})
  end

  # An edit on `name`, one step taken, then the agent sizes „Tops und
  # Flops“ to S, then „Fertig“ (refused as stale) and „Weiter
  # bearbeiten“. (A size, not a row: since Sprint 32 E2 every step closes
  # the gaps, so a row the agent leaves a gap above would float up.)
  defp kept_after_stale(conn, name) do
    seed()

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => name, "layout" => @layout})

    {:ok, view, _html} =
      conn
      |> put_preference_cookie("portfolixir_locale", "de")
      |> live("/dashboards/#{dashboard.id}")

    view |> element("[data-role='edit-start']") |> render_click()
    key(view, "performance", "ArrowRight")

    {:ok, _agents} =
      Dashboards.replace_dashboard(Actor.api_token_rw("agent"), dashboard.id, %{
        "name" => name,
        "layout" => List.update_at(@layout, 1, &Map.put(&1, "size", "S")),
        "lock_version" => dashboard.lock_version
      })

    view |> element("[data-role='edit-done']") |> render_click()
    assert has_element?(view, "[data-role='edit-stale']")
    view |> element("[data-role='edit-keep']") |> render_click()
    {view, dashboard}
  end

  # User story:
  # As the operator who continued an edit after another write,
  # I want „Zurücksetzen“ to go back to the version stored now, the one
  # the edit continues on,
  # so that a reset and a save never undo the other write unseen.
  #
  # Acceptance criteria:
  # - After „Weiter bearbeiten“, „Zurücksetzen“ draws the stored layout
  #   (the agent's „Tops und Flops“ at S), and a step and „Fertig“ then
  #   store it with the agent's change kept.
  test "„Zurücksetzen“ after „Weiter bearbeiten“ resets to the stored version", %{conn: conn} do
    {view, dashboard} = kept_after_stale(conn, "A")

    view |> element("[data-role='edit-reset']") |> render_click()
    assert size(view, "movers") == "S"

    key(view, "crashes", "ArrowDown")
    view |> element("[data-role='edit-done']") |> render_click()

    assert Enum.at(Dashboards.get_dashboard(dashboard.id).layout, 1)["size"] == "S"
  end

  # Acceptance criteria:
  # - After „Weiter bearbeiten“, an edit stepped back toward the layout
  #   read before the stale save (its „Tops und Flops“ still at L) differs
  #   from the stored version, so „Fertig“ stores it („Fertig“ replaces
  #   the stored version).
  test "an edit that differs from the stored version is stored on „Fertig“", %{conn: conn} do
    {view, dashboard} = kept_after_stale(conn, "B")

    key(view, "performance", "ArrowLeft")
    view |> element("[data-role='edit-done']") |> render_click()

    assert Enum.at(Dashboards.get_dashboard(dashboard.id).layout, 1)["size"] == "L"
  end
end
