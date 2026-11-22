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
    %{"kind" => "movers", "size" => "M", "col" => 1, "row" => 4},
    %{"kind" => "crashes", "size" => "M", "col" => 7, "row" => 4}
  ]

  defp seed do
    world = base_world()

    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-10])
    put_quote!(security, Portfolixir.Clock.today(), "120")
    world
  end

  defp place(view, kind) do
    [widget] =
      view |> render() |> Floki.parse_document!() |> Floki.find("[data-widget-kind='#{kind}']")

    {widget |> Floki.attribute("data-col") |> hd() |> String.to_integer(),
     widget |> Floki.attribute("data-row") |> hd() |> String.to_integer()}
  end

  defp key(view, kind, key) do
    view
    |> element("[data-widget-kind='#{kind}'] [data-role='edit-handle']")
    |> render_keydown(%{"key" => key})
  end

  # An edit on `name`, one step taken, then the agent moves „Tops und
  # Flops“ to row 7, then „Fertig“ (refused as stale) and „Weiter
  # bearbeiten“.
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
        "layout" => List.update_at(@layout, 1, &Map.put(&1, "row", 7)),
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
  #   (the agent's „Tops und Flops“ at row 7), and a step and „Fertig“
  #   then store it with the agent's change kept.
  test "„Zurücksetzen“ after „Weiter bearbeiten“ resets to the stored version", %{conn: conn} do
    {view, dashboard} = kept_after_stale(conn, "A")

    view |> element("[data-role='edit-reset']") |> render_click()
    assert place(view, "movers") == {1, 7}

    key(view, "crashes", "ArrowDown")
    view |> element("[data-role='edit-done']") |> render_click()

    assert Enum.at(Dashboards.get_dashboard(dashboard.id).layout, 1)["row"] == 7
  end

  # Acceptance criteria:
  # - After „Weiter bearbeiten“, an edit made equal to the layout read
  #   before the stale save differs from the stored version, so „Fertig“
  #   stores it („Fertig“ replaces the stored version).
  test "an edit that differs from the stored version is stored on „Fertig“", %{conn: conn} do
    {view, dashboard} = kept_after_stale(conn, "B")

    key(view, "performance", "ArrowLeft")
    view |> element("[data-role='edit-done']") |> render_click()

    assert Enum.at(Dashboards.get_dashboard(dashboard.id).layout, 1)["row"] == 4
  end
end
