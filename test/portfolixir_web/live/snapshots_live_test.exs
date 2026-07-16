defmodule PortfolixirWeb.SnapshotsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.WorldFixtures

  # User story (Andi, 2026-07-16, ADR-0027):
  # As a local portfolio maintainer restructuring my strategy,
  # I want a Wealth tab where I freeze the current state as a named snapshot
  # and later see, as numbers and as a chart, whether keeping those holdings
  # would have beaten my real performance since,
  # so that the "was the restructuring worth it?" answer lives in the app.
  #
  # Acceptance criteria:
  # - The Snapshots tab lists snapshots and creates one (name, scope, as-of).
  # - Selecting a snapshot shows the comparison: as-of value, frozen value
  #   today, snapshot price return, real TTWROR since — plus the basis
  #   (gross, price-return only) as microcopy (UX-DR11).
  # - The chart's data is also reachable as a table (UX-DR10).
  # - Unvalued securities are surfaced as a gap notice, never silently.
  # - Deleting a snapshot removes it from the list.

  defp seeded_world do
    world = WorldFixtures.base_world(name: "Snap", currency: "EUR")
    sec = WorldFixtures.create_security!(name: "EUR Stock", ticker: "EURS", currency: "EUR")

    WorldFixtures.deposit!(world, "10000", ~D[2026-01-02], [])
    WorldFixtures.buy!(world, sec, quantity: "5", price: "100", date: ~D[2026-01-05])
    WorldFixtures.put_quote!(sec, ~D[2026-02-14], "110")
    WorldFixtures.put_quote!(sec, ~D[2026-03-10], "120")

    Map.put(world, :security, sec)
  end

  test "creates a snapshot from the form and lists it", %{conn: conn} do
    seeded_world()

    {:ok, view, _html} = live(conn, "/snapshots")

    view
    |> form("#snapshot-create-form", %{
      "snapshot" => %{"name" => "Before restructuring", "as_of" => "2026-02-15", "view_id" => ""}
    })
    |> render_submit()

    assert render(view) =~ "Before restructuring"
    assert [snapshot] = Snapshots.list_snapshots()
    assert snapshot.name == "Before restructuring"
    assert snapshot.as_of == ~D[2026-02-15]
    assert snapshot.view_id == nil
  end

  test "selecting a snapshot renders the comparison with basis and table", %{conn: conn} do
    seeded_world()

    {:ok, _snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{
        name: "Before restructuring",
        as_of: ~D[2026-02-15]
      })

    {:ok, view, _html} = live(conn, "/snapshots")

    html =
      view
      |> element("[data-role=snapshot-row] button[phx-click=select_snapshot]")
      |> render_click()

    # KPI values: frozen 5 × 110 = 550 at as-of; 5 × 120 = 600 today.
    assert html =~ "550.00"
    assert html =~ "600.00"

    # Self-describing basis (UX-DR11) and chart-as-table (UX-DR10).
    assert html =~ "gross"
    assert has_element?(view, "[data-role=comparison-table]")
    assert has_element?(view, "svg[role=img]")
  end

  test "unvalued securities appear as a gap notice", %{conn: conn} do
    world = seeded_world()
    ghost = WorldFixtures.create_security!(name: "Unquoted", ticker: "GHST", currency: "EUR")
    WorldFixtures.buy!(world, ghost, quantity: "3", price: "10", date: ~D[2026-01-20])

    {:ok, _} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Marker", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")

    html =
      view
      |> element("[data-role=snapshot-row] button[phx-click=select_snapshot]")
      |> render_click()

    assert html =~ "Unquoted"
    assert has_element?(view, "[data-role=comparison-gaps]")
  end

  test "deletes a snapshot", %{conn: conn} do
    seeded_world()

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Old marker", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")

    view
    |> element("button[phx-click=delete_snapshot][phx-value-id='#{snapshot.id}']")
    |> render_click()

    refute render(view) =~ "Old marker"
    assert Snapshots.list_snapshots() == []
  end
end
