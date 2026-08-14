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

  # Review finding: deleting a snapshot that vanished in another tab (or via
  # API/MCP) crashed the LiveView through a {:ok, _} match on :not_found.
  test "deleting an already-deleted snapshot does not crash", %{conn: conn} do
    seeded_world()

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Racy", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")

    {:ok, _} = Snapshots.delete_snapshot(Actor.owner_ui(), snapshot.id)

    html =
      view
      |> element("button[phx-click=delete_snapshot][phx-value-id='#{snapshot.id}']")
      |> render_click()

    refute html =~ "Racy"
    assert Snapshots.list_snapshots() == []
  end

  # Steve UAT finding: a failed create (duplicate name) used to collapse the
  # details and swallow the error — the form now stays open with an associated
  # error message.
  test "a duplicate snapshot name keeps the form open with a visible error", %{conn: conn} do
    seeded_world()

    {:ok, _} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Twice", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")

    html =
      view
      |> form("#snapshot-create-form", %{
        "snapshot" => %{"name" => "Twice", "as_of" => "2026-03-01", "view_id" => ""}
      })
      |> render_submit()

    assert html =~ ~s(id="snapshot-form-error")
    assert html =~ "has already been taken"
    assert has_element?(view, "details.snapshot-create[open]")
    assert has_element?(view, "input[name='snapshot[name]'][aria-invalid='true']")
  end

  test "shows the empty state until accounts exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/snapshots")
    assert html =~ "Create a depot and cash account first"
  end

  test "ignores crafted non-integer event payloads instead of crashing", %{conn: conn} do
    seeded_world()

    {:ok, _} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Sturdy", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")

    assert render_click(view, "select_snapshot", %{"id" => "abc"}) =~ "Sturdy"
    assert render_click(view, "delete_snapshot", %{"id" => "abc"}) =~ "Sturdy"
    assert [_] = Snapshots.list_snapshots()
  end

  test "selecting a vanished snapshot flashes an error instead of crashing", %{conn: conn} do
    seeded_world()

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Fleeting", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")
    {:ok, _} = Snapshots.delete_snapshot(Actor.owner_ui(), snapshot.id)

    html = render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})
    assert html =~ "Could not load the comparison"
    assert has_element?(view, "p.alert-error[role=alert]")
  end

  test "a view-scoped snapshot lists its view name; deleting another snapshot keeps the comparison",
       %{conn: conn} do
    seeded_world()
    {:ok, view_record} = Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "Stocks"})

    {:ok, scoped} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{
        name: "Scoped",
        as_of: ~D[2026-02-15],
        view_id: view_record.id
      })

    {:ok, other} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Other", as_of: ~D[2026-02-15]})

    {:ok, view, html} = live(conn, "/snapshots")
    assert html =~ "Stocks"

    render_click(view, "select_snapshot", %{"id" => "#{scoped.id}"})
    html = render_click(view, "delete_snapshot", %{"id" => "#{other.id}"})

    # The unrelated delete leaves the selected comparison on screen.
    assert has_element?(view, "[data-role=snapshot-comparison]")
    refute html =~ "Other"
  end

  test "a snapshot whose holdings are all unquoted renders the nothing-to-compare state",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Bare", currency: "EUR")
    ghost = WorldFixtures.create_security!(name: "Unquoted", ticker: "GHST", currency: "EUR")
    WorldFixtures.deposit!(world, "1000", ~D[2026-01-02], [])
    WorldFixtures.buy!(world, ghost, quantity: "3", price: "10", date: ~D[2026-01-20])

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Bare marker", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")
    render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})

    assert has_element?(view, "[data-role=comparison-empty]")
    assert has_element?(view, "[data-role=comparison-gaps]")
  end

  # User story (#671, EXPERIENCE.md → Component Patterns → Snapshots
  # comparison; DESIGN.md → data-note, disclosure, value-slot):
  # As a local portfolio maintainer reading the counterfactual comparison,
  # I want the snapshots surface to follow the design language — the
  # comparison primary, findings as data notes, the chart's table behind the
  # one quiet disclosure, and absent values quiet —
  # so that the surface conforms to the spec instead of its own idiom.
  #
  # Acceptance criteria:
  # - The comparison section renders above the snapshot list (the comparison
  #   is the surface; the list is secondary).
  # - The basis line states what is compared; the v1 gross/price-only
  #   limitation is a note-severity data note, not prose.
  # - Excluded securities render as an attention data note with glyph + word.
  # - A not-computable KPI renders as a quiet muted dash, not at value weight.
  # - The data-as-table disclosure is the quiet control with a stated purpose
  #   line (≤ 90 characters) and the defined chevron, as is the create form's.
  describe "design-language alignment (#671)" do
    test "the comparison renders above the snapshot list", %{conn: conn} do
      seeded_world()

      {:ok, snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Marker", as_of: ~D[2026-02-15]})

      {:ok, view, _html} = live(conn, "/snapshots")
      html = render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})

      comparison_at = :binary.match(html, ~s(data-role="snapshot-comparison")) |> elem(0)
      list_at = :binary.match(html, ~s(data-role="snapshot-list")) |> elem(0)
      assert comparison_at < list_at
    end

    test "the basis is a line and the v1 limitation a note-severity data note",
         %{conn: conn} do
      seeded_world()

      {:ok, snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Marker", as_of: ~D[2026-02-15]})

      {:ok, view, _html} = live(conn, "/snapshots")
      render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})

      basis = view |> element(~s([data-role="comparison-basis"])) |> render()
      assert basis =~ "2026-02-15"
      assert basis =~ "EUR"

      note = view |> element(~s([data-role="comparison-limitation"])) |> render()
      assert note =~ "data-note--note"
      assert note =~ "Note"
      assert note =~ "gross"
    end

    test "excluded securities render as an attention data note", %{conn: conn} do
      world = seeded_world()
      ghost = WorldFixtures.create_security!(name: "Unquoted", ticker: "GHST", currency: "EUR")
      WorldFixtures.buy!(world, ghost, quantity: "3", price: "10", date: ~D[2026-01-20])

      {:ok, snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Marker", as_of: ~D[2026-02-15]})

      {:ok, view, _html} = live(conn, "/snapshots")
      render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})

      gaps = view |> element(~s([data-role="comparison-gaps"])) |> render()
      assert gaps =~ "data-note--attention"
      assert gaps =~ "Attention"
      assert gaps =~ "Unquoted"
    end

    test "a not-computable KPI is a quiet dash, not at value weight", %{conn: conn} do
      world = WorldFixtures.base_world(name: "Bare", currency: "EUR")
      ghost = WorldFixtures.create_security!(name: "Unquoted", ticker: "GHST", currency: "EUR")
      WorldFixtures.deposit!(world, "1000", ~D[2026-01-02], [])
      WorldFixtures.buy!(world, ghost, quantity: "3", price: "10", date: ~D[2026-01-20])

      {:ok, snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Bare marker", as_of: ~D[2026-02-15]})

      {:ok, view, _html} = live(conn, "/snapshots")
      render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})

      assert has_element?(view, ".stat .stat-empty")
      refute has_element?(view, ".stat strong .stat-empty")
    end

    test "both disclosures use the quiet summary; the table states its purpose",
         %{conn: conn} do
      seeded_world()

      {:ok, snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Marker", as_of: ~D[2026-02-15]})

      {:ok, view, _html} = live(conn, "/snapshots")
      render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})

      create = view |> element(".snapshot-create summary") |> render()
      assert create =~ "disclosure-summary"
      assert create =~ "disclosure-chevron"

      table_disclosure =
        view |> element(~s(details[data-role="comparison-disclosure"])) |> render()

      assert table_disclosure =~ "disclosure-summary"
      assert table_disclosure =~ "Data as table"
      assert table_disclosure =~ ~s(data-role="disclosure-purpose")
    end
  end
end
