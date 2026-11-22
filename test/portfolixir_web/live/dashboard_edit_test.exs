defmodule PortfolixirWeb.DashboardEditTest do
  # Sprint 31 D6 (FR-60; ADR-0062 §2, §7; idea board
  # ux-design-2026-11-21-idea-i56 03, its edit-mode frame): the edit mode.
  # „Bearbeiten“ on a stored dashboard gives each widget a handle, a size
  # switch with its kind's sizes and ×, opens the catalogue beside the grid,
  # and „Fertig“ saves the edit as one journaled replace with the
  # lock_version the page read. Each step is validated on the server and
  # announced in a polite live region; a step the layout refuses is
  # announced, not applied. The keyboard path is the handle's keydown (the
  # arrow keys, Delete), the pointer path the DashboardEdit hook's
  # `edit_place`, the compact class's reorder the up and down buttons. The
  # hook itself (the drag, the focus) runs in a real browser in
  # test/browser/dashboard_edit_test.exs.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable` row 30); every module that creates
  # one joins this group.
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Journal

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

  defp german(conn), do: put_preference_cookie(conn, "portfolixir_locale", "de")

  defp dashboard!(name \\ "Alpha", layout \\ @layout) do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => name, "layout" => layout})

    dashboard
  end

  defp open_editing(conn, dashboard) do
    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{dashboard.id}")
    view |> element("[data-role='edit-start']") |> render_click()
    view
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp document(view), do: view |> render() |> Floki.parse_document!()

  defp announced(view), do: view |> document() |> Floki.find("#dashboard-edit-status") |> text()

  defp handle(view, kind),
    do: element(view, "[data-widget-kind='#{kind}'] [data-role='edit-handle']")

  defp key(view, kind, key), do: view |> handle(kind) |> render_keydown(%{"key" => key})

  defp place(view, kind), do: view |> document() |> place_in(kind)

  defp place_in(doc, kind) do
    [widget] = Floki.find(doc, "[data-widget-kind='#{kind}']")

    {widget |> Floki.attribute("data-col") |> hd() |> String.to_integer(),
     widget |> Floki.attribute("data-row") |> hd() |> String.to_integer(),
     widget |> Floki.attribute("data-size") |> hd()}
  end

  defp item_key(view, kind) do
    view
    |> document()
    |> Floki.find("[data-widget-kind='#{kind}'] [data-role='edit-handle']")
    |> Floki.attribute("data-item")
    |> hd()
  end

  defp journal_count, do: length(Journal.list_entries(resource_type: "dashboard"))

  defp stored_layout(id), do: Dashboards.get_dashboard(id).layout

  # User story:
  # As the operator looking at a dashboard of my own,
  # I want „Bearbeiten“ to give each widget a handle, its sizes and ×, and
  # the catalogue beside the grid,
  # so that I can rearrange it where I read it.
  #
  # Acceptance criteria:
  # - A stored dashboard offers „Bearbeiten“; the template does not (it
  #   offers „Anpassen“), and an edit event sent to it changes nothing.
  # - In the edit mode each widget has a handle, ×, and a size switch with
  #   exactly the grid sizes its kind takes (never „full“), its own
  #   pressed; the ⋯ menu is hidden; „Zurücksetzen“ and „Fertig“ replace
  #   „Bearbeiten“.
  # - The catalogue lists every registered kind under its group, with its
  #   sizes, as a button that adds it.
  # - The live region says the edit mode began; nothing is written.
  test "„Bearbeiten“ opens the edit mode with handles, sizes, × and the catalogue",
       %{conn: conn} do
    seed()
    {:ok, template, _html} = conn |> german() |> live("/")
    refute has_element?(template, "[data-role='edit-start']")
    render_click(template, "edit_start", %{})
    refute has_element?(template, "[data-role='edit-handle']")

    dashboard = dashboard!()
    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{dashboard.id}")
    assert has_element?(view, "[data-role='edit-start']", "Bearbeiten")
    assert has_element?(view, "[data-widget-kind='performance'] [data-role='widget-menu']")
    refute has_element?(view, "[data-role='edit-handle']")
    assert has_element?(view, "#dashboard-edit-status[role='status'][aria-live='polite']")

    view |> element("[data-role='edit-start']") |> render_click()

    refute has_element?(view, "[data-role='edit-start']")
    assert has_element?(view, "[data-role='edit-reset']", "Zurücksetzen")
    assert has_element?(view, "[data-role='edit-done']", "Fertig")
    refute has_element?(view, "[data-role='widget-menu']")
    assert has_element?(view, "[data-role='dashboard-grid'][data-editing='true']")
    assert announced(view) =~ "Bearbeiten"

    doc = document(view)

    for kind <- ~w(performance movers crashes) do
      assert [_] = Floki.find(doc, "[data-widget-kind='#{kind}'] [data-role='edit-handle']")
      assert [_] = Floki.find(doc, "[data-widget-kind='#{kind}'] [data-role='edit-remove']")
    end

    sizes = fn kind ->
      doc
      |> Floki.find("[data-widget-kind='#{kind}'] [data-role='edit-size']")
      |> Enum.map(&{text(&1), Floki.attribute(&1, "aria-pressed")})
    end

    assert sizes.("performance") == [{"S", ["false"]}, {"M", ["false"]}, {"L", ["true"]}]
    assert sizes.("movers") == [{"S", ["false"]}, {"M", ["true"]}]
    assert sizes.("crashes") == [{"M", ["true"]}, {"L", ["false"]}]

    assert doc |> Floki.find("[data-role='edit-catalogue'] h2") |> text() == "Widget hinzufügen"

    added =
      doc
      |> Floki.find("[data-role='edit-catalogue'] [data-role='edit-add']")
      |> Enum.flat_map(&Floki.attribute(&1, "data-kind"))

    assert Enum.sort(added) == Enum.sort(Enum.map(Dashboards.widgets(), & &1.key))

    assert doc
           |> Floki.find("[data-role='edit-add'][data-kind='performance']")
           |> text() =~ ~r/Wertentwicklung\s+S M L/

    assert journal_count() == 1
  end

  # User story:
  # As the operator without a mouse, or reading with a screen reader,
  # I want to move, size and remove a widget from its handle by keyboard,
  # each step said aloud,
  # so that the edit mode does not need a pointer or sight.
  #
  # Acceptance criteria:
  # - On the handle, an arrow key moves the widget one grid step (column
  #   ±1, row ±1) and the live region says where: „Wertentwicklung nach
  #   rechts verschoben, Spalte 2, Zeile 1“; the focus stays on its handle
  #   (`dashboard-edit-focus`).
  # - A step that would leave the grid or overlap a widget is refused and
  #   said, naming the widget it would overlap; the layout stays.
  # - The size switch's buttons size the widget, said with its place; a
  #   size that would overlap is refused and said.
  # - Delete removes the widget and says so; the focus moves to the next
  #   handle in reading order.
  # - None of it writes: the lock_version and the journal stay.
  test "the keyboard path moves, sizes and removes, each step announced", %{conn: conn} do
    seed()
    dashboard = dashboard!()
    view = open_editing(conn, dashboard)
    perf = item_key(view, "performance")

    key(view, "performance", "ArrowRight")
    assert place(view, "performance") == {2, 1, "L"}
    assert announced(view) == "Wertentwicklung nach rechts verschoben, Spalte 2, Zeile 1"

    assert_push_event(view, "dashboard-edit-focus", %{
      ids: ["dashboard-edit-handle-" <> ^perf | _]
    })

    key(view, "performance", "ArrowLeft")
    assert place(view, "performance") == {1, 1, "L"}
    assert announced(view) == "Wertentwicklung nach links verschoben, Spalte 1, Zeile 1"

    key(view, "performance", "ArrowLeft")
    assert place(view, "performance") == {1, 1, "L"}

    assert announced(view) ==
             "Wertentwicklung kann nicht nach links: Es verließe das Raster."

    key(view, "performance", "ArrowUp")
    assert place(view, "performance") == {1, 1, "L"}
    assert announced(view) == "Wertentwicklung kann nicht nach oben: Es verließe das Raster."

    key(view, "performance", "ArrowDown")
    assert place(view, "performance") == {1, 1, "L"}

    assert announced(view) ==
             "Wertentwicklung kann nicht nach unten: Es würde „Tops und Flops“ überdecken."

    key(view, "movers", "ArrowDown")
    assert place(view, "movers") == {1, 5, "M"}
    assert announced(view) == "Tops und Flops nach unten verschoben, Spalte 1, Zeile 5"

    key(view, "movers", "ArrowUp")
    assert announced(view) == "Tops und Flops nach oben verschoben, Spalte 1, Zeile 4"

    # A key the handle does not answer changes nothing.
    key(view, "movers", "a")
    assert place(view, "movers") == {1, 4, "M"}

    # The size switch: Tops und Flops to S, then back to M.
    view
    |> element("[data-widget-kind='movers'] [data-role='edit-size'][data-size='S']")
    |> render_click()

    assert place(view, "movers") == {1, 4, "S"}
    assert announced(view) == "Tops und Flops auf Größe S gestellt, Spalte 1, Zeile 4"

    assert has_element?(
             view,
             "[data-widget-kind='movers'] [data-role='edit-size'][data-size='S'][aria-pressed='true']"
           )

    # Crashes im Vergleich at L (8 wide) from column 7: moved left to
    # column 5 to stay on the grid; Tops und Flops is 3 wide now, so it fits.
    view
    |> element("[data-widget-kind='crashes'] [data-role='edit-size'][data-size='L']")
    |> render_click()

    assert place(view, "crashes") == {5, 4, "L"}
    assert announced(view) == "Crashes im Vergleich auf Größe L gestellt, Spalte 5, Zeile 4"

    # Tops und Flops back to M would now overlap it.
    view
    |> element("[data-widget-kind='movers'] [data-role='edit-size'][data-size='M']")
    |> render_click()

    assert place(view, "movers") == {1, 4, "S"}

    assert announced(view) ==
             "Tops und Flops kann nicht Größe M annehmen: Es würde „Crashes im Vergleich“ überdecken."

    assert Dashboards.get_dashboard(dashboard.id).lock_version == dashboard.lock_version
    assert journal_count() == 1

    # Delete removes; Backspace (the Mac's delete key) does too.
    crashes = item_key(view, "crashes")
    key(view, "movers", "Delete")
    refute has_element?(view, "[data-widget-kind='movers']")
    assert announced(view) == "Tops und Flops entfernt"

    assert_push_event(view, "dashboard-edit-focus", %{
      ids: ["dashboard-edit-handle-" <> ^crashes | _]
    })

    key(view, "crashes", "Backspace")
    refute has_element?(view, "[data-widget-kind='crashes']")
    assert announced(view) == "Crashes im Vergleich entfernt"

    assert stored_layout(dashboard.id) == dashboard.layout
    assert journal_count() == 1
  end

  # User story:
  # As the operator with a mouse on the wide grid,
  # I want to drag a widget by its handle to another place,
  # so that I can place it where I see it.
  #
  # Acceptance criteria:
  # - The hook's `edit_place` (the cell under the dragged widget's corner)
  #   moves the widget there and says so: „Tops und Flops an Spalte 7,
  #   Zeile 6 gesetzt“.
  # - A place that overlaps or leaves the grid is refused and said; a
  #   place that is not a whole number, or an item that does not exist,
  #   changes nothing.
  # - × removes the widget; a drag writes nothing.
  test "the pointer path places a widget where it was dropped", %{conn: conn} do
    seed()
    dashboard = dashboard!()
    view = open_editing(conn, dashboard)
    movers = item_key(view, "movers")

    render_hook(view, "edit_place", %{"item" => movers, "col" => 7, "row" => 6})
    assert place(view, "movers") == {7, 6, "M"}
    assert announced(view) == "Tops und Flops an Spalte 7, Zeile 6 gesetzt"

    render_hook(view, "edit_place", %{"item" => movers, "col" => 7, "row" => 4})
    assert place(view, "movers") == {7, 6, "M"}

    assert announced(view) ==
             "Tops und Flops kann nicht an Spalte 7, Zeile 4: Es würde „Crashes im Vergleich“ überdecken."

    render_hook(view, "edit_place", %{"item" => movers, "col" => 8, "row" => 9})
    assert place(view, "movers") == {7, 6, "M"}

    assert announced(view) ==
             "Tops und Flops kann nicht an Spalte 8, Zeile 9: Es verließe das Raster."

    render_hook(view, "edit_place", %{"item" => movers, "col" => "x", "row" => 1})
    render_hook(view, "edit_place", %{"item" => "999", "col" => 1, "row" => 9})
    assert place(view, "movers") == {7, 6, "M"}

    view |> element("[data-widget-kind='crashes'] [data-role='edit-remove']") |> render_click()
    refute has_element?(view, "[data-widget-kind='crashes']")
    assert announced(view) == "Crashes im Vergleich entfernt"

    assert stored_layout(dashboard.id) == dashboard.layout
    assert journal_count() == 1
  end

  # User story:
  # As the operator composing a dashboard,
  # I want to add a widget from the catalogue in one tap,
  # so that I need not find a free place first.
  #
  # Acceptance criteria:
  # - A catalogue entry adds its kind in its smallest grid size at the
  #   first free place (row by row, column by column) and says where:
  #   „Snapshots hinzugefügt, Spalte 9, Zeile 1, Größe S“.
  # - The added widget reads its source (its body is drawn, not a hole),
  #   and the focus goes to its handle.
  # - A kind the registry does not hold changes nothing.
  test "the catalogue adds a widget at the first free place in its smallest size",
       %{conn: conn} do
    seed()
    dashboard = dashboard!()
    view = open_editing(conn, dashboard)

    view |> element("[data-role='edit-add'][data-kind='snapshots']") |> render_click()
    assert place(view, "snapshots") == {9, 1, "S"}
    assert announced(view) == "Snapshots hinzugefügt, Spalte 9, Zeile 1, Größe S"
    assert_push_event(view, "dashboard-edit-focus", %{ids: ["dashboard-edit-handle-" <> _ | _]})

    view |> element("[data-role='edit-add'][data-kind='allocation_drift']") |> render_click()
    # M is 6 wide: no room beside Wertentwicklung, the first free place is
    # under the row of Tops und Flops and Crashes.
    assert place(view, "allocation_drift") == {1, 6, "M"}

    render_async(view)
    assert has_element?(view, "[data-widget-kind='snapshots'] [data-form='wide']")

    render_click(view, "edit_add", %{"kind" => "nonsense"})
    assert view |> document() |> Floki.find("[data-widget-kind]") |> length() == 5
    assert journal_count() == 1
  end

  # User story:
  # As the operator who rearranged a dashboard,
  # I want „Fertig“ to store the edit as one change,
  # so that the journal says what I did once, not per drag.
  #
  # Acceptance criteria:
  # - Several moves, a resize, a removal and an add, then „Fertig“: one
  #   journal entry, an update under the UI's actor, and the stored layout
  #   is the edited one; the lock_version rises by one.
  # - The edit mode ends, the dashboard is drawn as stored, the ⋯ menu is
  #   back and the region says „Dashboard gespeichert.“
  test "„Fertig“ saves the whole edit as one journaled write", %{conn: conn} do
    seed()
    dashboard = dashboard!()
    view = open_editing(conn, dashboard)
    movers = item_key(view, "movers")

    key(view, "performance", "ArrowRight")
    key(view, "performance", "ArrowRight")
    render_hook(view, "edit_place", %{"item" => movers, "col" => 1, "row" => 8})

    view
    |> element("[data-widget-kind='crashes'] [data-role='edit-size'][data-size='L']")
    |> render_click()

    view
    |> element("[data-widget-kind='performance'] [data-role='edit-remove']")
    |> render_click()

    view |> element("[data-role='edit-add'][data-kind='snapshots']") |> render_click()

    assert journal_count() == 1
    assert Dashboards.get_dashboard(dashboard.id).lock_version == dashboard.lock_version

    view |> element("[data-role='edit-done']") |> render_click()

    entries = Journal.list_entries(resource_type: "dashboard") |> Enum.sort_by(& &1.id)
    assert [%{operation: :create}, %{operation: :update, actor_type: :owner_ui}] = entries

    stored = Dashboards.get_dashboard(dashboard.id)
    assert stored.lock_version == dashboard.lock_version + 1

    assert stored.layout == [
             %{"kind" => "movers", "size" => "M", "col" => 1, "row" => 8, "settings" => %{}},
             %{"kind" => "crashes", "size" => "L", "col" => 5, "row" => 4, "settings" => %{}},
             %{"kind" => "snapshots", "size" => "S", "col" => 1, "row" => 1, "settings" => %{}}
           ]

    refute has_element?(view, "[data-role='edit-handle']")
    assert has_element?(view, "[data-role='edit-start']")
    assert has_element?(view, "[data-widget-kind='crashes'] [data-role='widget-menu']")
    assert announced(view) == "Dashboard gespeichert."

    # „Fertig“ with nothing changed writes nothing.
    view |> element("[data-role='edit-start']") |> render_click()
    view |> element("[data-role='edit-done']") |> render_click()
    assert journal_count() == 2
  end

  # User story:
  # As the operator who changed my mind halfway,
  # I want „Zurücksetzen“ to discard the unsaved edit,
  # so that the dashboard is as stored again.
  #
  # Acceptance criteria:
  # - After moves and a removal, „Zurücksetzen“ draws the layout as read,
  #   stays in the edit mode and says „Ungespeicherte Änderungen
  #   verworfen.“; nothing was written.
  # - „Fertig“ after it writes nothing.
  # - While editing, a pin sent to the page writes nothing.
  test "„Zurücksetzen“ discards the unsaved edit", %{conn: conn} do
    seed()
    dashboard = dashboard!()
    view = open_editing(conn, dashboard)

    key(view, "performance", "ArrowRight")
    view |> element("[data-widget-kind='movers'] [data-role='edit-remove']") |> render_click()
    render_click(view, "pin_period", %{"index" => "0", "period" => "max"})

    view |> element("[data-role='edit-reset']") |> render_click()
    assert place(view, "performance") == {1, 1, "L"}
    assert place(view, "movers") == {1, 4, "M"}
    assert has_element?(view, "[data-role='edit-handle']")
    assert announced(view) == "Ungespeicherte Änderungen verworfen."

    view |> element("[data-role='edit-done']") |> render_click()
    assert journal_count() == 1
    assert Dashboards.get_dashboard(dashboard.id).lock_version == dashboard.lock_version
  end

  # User story (Sprint 31 closing act, DS4; board
  # ux-design-2026-11-21-sprint31/02 ④):
  # As the operator editing at a desk narrower than 1400 px,
  # I want the catalogue to open over the page when I ask for it,
  # so that the widgets keep their width while I arrange them.
  #
  # Acceptance criteria:
  # - The edit mode draws „Widget hinzufügen“ (aria-expanded false) and
  #   the catalogue closed; the button opens it (aria-expanded true, the
  #   focus on its ×).
  # - × and Esc close it, the focus back on „Widget hinzufügen“.
  test "„Widget hinzufügen“ opens the catalogue, × and Esc close it", %{conn: conn} do
    seed()
    dashboard = dashboard!()
    view = open_editing(conn, dashboard)

    assert has_element?(view, "#dashboard-catalogue-toggle[aria-expanded='false']")
    refute has_element?(view, "#dashboard-catalogue.is-open")

    view |> element("#dashboard-catalogue-toggle") |> render_click()
    assert has_element?(view, "#dashboard-catalogue.is-open")
    assert has_element?(view, "#dashboard-catalogue-toggle[aria-expanded='true']")
    assert_push_event(view, "dashboard-edit-focus", %{ids: ["dashboard-catalogue-close"]})

    view |> element("#dashboard-catalogue-close") |> render_click()
    refute has_element?(view, "#dashboard-catalogue.is-open")
    assert_push_event(view, "dashboard-edit-focus", %{ids: ["dashboard-catalogue-toggle"]})

    view |> element("#dashboard-catalogue-toggle") |> render_click()
    view |> element("#dashboard-catalogue") |> render_keydown(%{"key" => "Escape"})
    refute has_element?(view, "#dashboard-catalogue.is-open")
  end

  # User story (Sprint 31 closing act, the accessibility lens's smaller
  # findings):
  # As the operator who edits with a screen reader,
  # I want each control to name its widget in the words the announcement
  # uses, and a refusal said again when I repeat the step,
  # so that I know whose control I am on and that my second press was
  # heard.
  #
  # Acceptance criteria:
  # - A widget's ⓘ is „Zu „Crashes im Vergleich““, its ⋯ „Menü für
  #   „Crashes im Vergleich““.
  # - „nach oben“ and „nach unten“ read „… nach oben verschieben“, as the
  #   announcement „… nach oben verschoben“.
  # - The same refusal twice changes the live region's text, so it is
  #   announced again; the words stay the same.
  test "the edit controls name their widget and a repeated refusal is said again",
       %{conn: conn} do
    seed()
    dashboard = dashboard!()
    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{dashboard.id}")

    assert has_element?(
             view,
             "[data-widget-kind='crashes'] [data-role='section-info'] > summary[aria-label='Zu „Crashes im Vergleich“']"
           )

    assert has_element?(
             view,
             "[data-widget-kind='crashes'] [data-role='widget-menu'] > summary[aria-label='Menü für „Crashes im Vergleich“']"
           )

    view |> element("[data-role='edit-start']") |> render_click()

    assert has_element?(
             view,
             "[data-widget-kind='crashes'] [data-role='edit-up'][aria-label='Crashes im Vergleich nach oben verschieben']"
           )

    assert has_element?(
             view,
             "[data-widget-kind='crashes'] [data-role='edit-down'][aria-label='Crashes im Vergleich nach unten verschieben']"
           )

    raw = fn ->
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#dashboard-edit-status")
      |> Floki.text()
    end

    key(view, "performance", "ArrowLeft")
    first = raw.()
    key(view, "performance", "ArrowLeft")
    second = raw.()

    assert first != second
    assert String.trim(first, "\u00A0") == String.trim(second, "\u00A0")
    assert String.trim(first, "\u00A0") =~ "kann nicht"
  end

  # User story:
  # As the operator saving while my agent changed the same dashboard,
  # I want to see the stored layout and choose,
  # so that neither change is lost unseen.
  #
  # Acceptance criteria:
  # - A replace between opening the edit and „Fertig“ (the agent's `put`)
  #   makes „Fertig“ write nothing; the page stays in the edit mode, says
  #   the dashboard was changed elsewhere and draws the stored layout,
  #   with „Gespeicherte Fassung laden“ and „Weiter bearbeiten“.
  # - „Gespeicherte Fassung laden“ ends the edit and draws the stored
  #   dashboard; the focus goes to „Bearbeiten“.
  # - „Weiter bearbeiten“ keeps the edit, the focus on „Fertig“; the next
  #   „Fertig“ replaces the stored version knowingly, under its name: one
  #   more journal entry.
  test "a stale save shows the stored layout and offers to load it", %{conn: conn} do
    seed()
    dashboard = dashboard!()
    agent = Actor.api_token_rw("test-agent")

    elsewhere = fn version, row ->
      layout = List.update_at(@layout, 1, &Map.put(&1, "row", row))

      {:ok, stored} =
        Dashboards.replace_dashboard(agent, dashboard.id, %{
          "name" => "Agent's",
          "layout" => layout,
          "lock_version" => version
        })

      stored
    end

    view = open_editing(conn, dashboard)
    key(view, "performance", "ArrowRight")
    agents = elsewhere.(dashboard.lock_version, 7)

    view |> element("[data-role='edit-done']") |> render_click()

    assert Dashboards.get_dashboard(dashboard.id).lock_version == agents.lock_version
    assert stored_layout(dashboard.id) == agents.layout
    assert journal_count() == 2

    assert has_element?(view, "[data-role='edit-handle']")
    assert place(view, "performance") == {2, 1, "L"}
    assert has_element?(view, "[data-role='edit-stale']", "anderswo geändert")

    shown =
      view
      |> document()
      |> Floki.find("[data-role='edit-stale'] [data-role='stored-item']")
      |> Enum.map(&text/1)

    assert shown == [
             "Wertentwicklung L · Spalte 1, Zeile 1",
             "Crashes im Vergleich M · Spalte 7, Zeile 4",
             "Tops und Flops M · Spalte 1, Zeile 7"
           ]

    view |> element("[data-role='edit-load-stored']") |> render_click()
    assert_push_event(view, "dashboard-edit-focus", %{ids: ["dashboard-edit-start"]})
    refute has_element?(view, "[data-role='edit-handle']")
    refute has_element?(view, "[data-role='edit-stale']")
    assert place(view, "movers") == {1, 7, "M"}
    assert place(view, "performance") == {1, 1, "L"}

    # Again, and this time keep editing: the next save replaces knowingly.
    view |> element("[data-role='edit-start']") |> render_click()
    key(view, "performance", "ArrowRight")
    agents = elsewhere.(agents.lock_version, 8)
    view |> element("[data-role='edit-done']") |> render_click()
    assert has_element?(view, "[data-role='edit-stale']")

    view |> element("[data-role='edit-keep']") |> render_click()
    assert_push_event(view, "dashboard-edit-focus", %{ids: ["dashboard-edit-done"]})
    refute has_element?(view, "[data-role='edit-stale']")
    assert has_element?(view, "[data-role='edit-handle']")
    view |> element("[data-role='edit-done']") |> render_click()

    stored = Dashboards.get_dashboard(dashboard.id)
    assert stored.lock_version == agents.lock_version + 1
    assert stored.name == "Agent's"
    assert Enum.at(stored.layout, 0)["col"] == 2
    assert Enum.at(stored.layout, 1)["row"] == 7
    assert journal_count() == 4
  end

  # User story:
  # As the operator on a phone,
  # I want to reorder, size and remove widgets without placing them on a
  # grid I cannot see,
  # so that I can edit where I read.
  #
  # Acceptance criteria:
  # - Each widget has „nach oben“ and „nach unten“ (the compact class
  #   shows them in place of the handle); a reorder swaps the widget with
  #   its neighbour in reading order and says its new position:
  #   „Crashes im Vergleich nach oben verschoben, Position 2 von 3“.
  # - Where the two differ in size and their places cannot be swapped,
  #   the layout is laid out again in the new reading order (each widget
  #   at the first free place after the one before it).
  # - The first cannot go up and the last cannot go down; both are said.
  # - The focus stays on the button used, on the widget it moved (the
  #   compact class hides the handle; Sprint 31 closing act, Y1).
  test "the compact reorder swaps in reading order and maps back onto the grid",
       %{conn: conn} do
    seed()
    dashboard = dashboard!()
    view = open_editing(conn, dashboard)

    reorder = fn kind, direction ->
      view
      |> element("[data-widget-kind='#{kind}'] [data-role='edit-#{direction}']")
      |> render_click()
    end

    crashes = item_key(view, "crashes")
    reorder.("crashes", "up")
    assert place(view, "crashes") == {1, 4, "M"}
    assert place(view, "movers") == {7, 4, "M"}
    assert announced(view) == "Crashes im Vergleich nach oben verschoben, Position 2 von 3"

    assert_push_event(view, "dashboard-edit-focus", %{
      ids: ["dashboard-edit-up-" <> ^crashes, "dashboard-edit-handle-" <> ^crashes | _]
    })

    reorder.("crashes", "up")
    assert place(view, "crashes") == {1, 1, "M"}
    assert place(view, "performance") == {1, 3, "L"}
    assert place(view, "movers") == {1, 6, "M"}
    assert announced(view) == "Crashes im Vergleich nach oben verschoben, Position 1 von 3"

    reorder.("crashes", "up")
    assert announced(view) == "Crashes im Vergleich steht schon an erster Stelle."

    reorder.("movers", "down")
    assert announced(view) == "Tops und Flops steht schon an letzter Stelle."

    reorder.("performance", "down")
    assert place(view, "movers") == {1, 3, "M"}
    assert announced(view) == "Wertentwicklung nach unten verschoben, Position 3 von 3"

    view |> element("[data-role='edit-done']") |> render_click()
    assert journal_count() == 2
  end
end
