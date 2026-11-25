defmodule PortfolixirWeb.DashboardEditArrangeTest do
  # Sprint 32 E2 (ADR-0062's amendment of 2026-11-25, point 1; I58;
  # planning board ux-design-2026-11-25-sprint32/01 ①, ③): the edit mode
  # arranges instead of refusing. A resize, a move by the arrow keys, a
  # drop and an add take the place they were given and the others make
  # room (`Portfolixir.Dashboards.Arrange`); the widgets that moved are
  # marked until the next step; the feedback stands at the widget acted
  # on, in a polite live region, with „Rückgängig“ (and Ctrl+Z, the
  # DashboardEdit hook's `edit_undo`) for that one step; the bar's status
  # line carries no step. The browser half (the note in the viewport after
  # a click at the page's foot, Ctrl+Z) is
  # test/browser/dashboard_edit_test.exs.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable` row 30).
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

  defp dashboard!(layout \\ @layout) do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Alpha", "layout" => layout})

    dashboard
  end

  defp open_editing(conn, dashboard) do
    {:ok, view, _html} =
      conn
      |> put_preference_cookie("portfolixir_locale", "de")
      |> live("/dashboards/#{dashboard.id}")

    view |> element("[data-role='edit-start']") |> render_click()
    view
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp document(view), do: view |> render() |> Floki.parse_document!()

  # The note at the widget of `kind`: its words, and whether „Rückgängig“
  # stands beside it.
  defp note(view, kind) do
    doc = document(view)

    {doc |> Floki.find("[data-widget-kind='#{kind}'] [data-role='edit-note']") |> text(),
     doc |> Floki.find("[data-widget-kind='#{kind}'] [data-role='edit-undo']") |> length() == 1}
  end

  # Every note on the page that says something, by the widget it stands at.
  defp notes(view) do
    for widget <- Floki.find(document(view), "[data-widget-kind]"),
        said = widget |> Floki.find("[data-role='edit-note']") |> text(),
        said != "",
        do: {widget |> Floki.attribute("data-widget-kind") |> hd(), said}
  end

  defp bar(view), do: view |> document() |> Floki.find("#dashboard-edit-status") |> text()

  defp place(view, kind) do
    [widget] = Floki.find(document(view), "[data-widget-kind='#{kind}']")

    {widget |> Floki.attribute("data-col") |> hd() |> String.to_integer(),
     widget |> Floki.attribute("data-row") |> hd() |> String.to_integer(),
     widget |> Floki.attribute("data-size") |> hd()}
  end

  defp moved(view) do
    view
    |> document()
    |> Floki.find("[data-widget-kind][data-moved='true']")
    |> Enum.flat_map(&Floki.attribute(&1, "data-widget-kind"))
    |> Enum.sort()
  end

  defp size(view, kind, size) do
    view
    |> element("[data-widget-kind='#{kind}'] [data-role='edit-size'][data-size='#{size}']")
    |> render_click()
  end

  defp key(view, kind, key) do
    view
    |> element("[data-widget-kind='#{kind}'] [data-role='edit-handle']")
    |> render_keydown(%{"key" => key})
  end

  defp item_key(view, kind) do
    view
    |> document()
    |> Floki.find("[data-widget-kind='#{kind}'] [data-role='edit-handle']")
    |> Floki.attribute("data-item")
    |> hd()
  end

  defp journal_count, do: length(Journal.list_entries(resource_type: "dashboard"))

  # User story:
  # As the operator making a widget larger,
  # I want the widgets in its way to make room, and to see at the widget
  # what happened, with a way back,
  # so that I never delete a widget to make room and never look for the
  # answer at the top of the page.
  #
  # Acceptance criteria:
  # - „Crashes im Vergleich“ to L covers „Tops und Flops“: the size is
  #   taken (moved left to stay on the grid), „Tops und Flops“ moves below
  #   it and is marked as moved; nothing is refused.
  # - The note stands at „Crashes im Vergleich“, in a polite live region,
  #   with the step and how many made room: „… auf Größe L gestellt,
  #   Spalte 5, Zeile 4 · 1 Widget ist nachgerückt“, „Rückgängig“ beside
  #   it; no other widget says anything, and the bar's status line says
  #   nothing.
  # - „Rückgängig“ takes back that one step: the layout as before, said at
  #   the same widget, and no second „Rückgängig“. Ctrl+Z (the hook's
  #   `edit_undo`) does the same after the next step.
  # - The marks last until the next step; nothing is written.
  test "a resize arranges, its note stands at the widget, „Rückgängig“ takes it back",
       %{conn: conn} do
    seed()
    dashboard = dashboard!()
    view = open_editing(conn, dashboard)

    size(view, "crashes", "L")

    assert place(view, "crashes") == {5, 4, "L"}
    assert place(view, "movers") == {1, 7, "M"}
    assert place(view, "performance") == {1, 1, "L"}
    assert moved(view) == ["movers"]

    assert note(view, "crashes") ==
             {"Crashes im Vergleich auf Größe L gestellt, Spalte 5, Zeile 4 · 1 Widget ist nachgerückt",
              true}

    assert [{"crashes", _}] = notes(view)
    assert bar(view) == ""

    crashes = item_key(view, "crashes")

    assert has_element?(
             view,
             "[data-widget-kind='crashes'] #dashboard-edit-note-#{crashes}[role='status'][aria-live='polite']"
           )

    assert has_element?(
             view,
             "#dashboard-edit-handle-#{crashes}[aria-describedby~='dashboard-edit-note-#{crashes}']"
           )

    view |> element("[data-widget-kind='crashes'] [data-role='edit-undo']") |> render_click()

    assert place(view, "crashes") == {7, 4, "M"}
    assert place(view, "movers") == {1, 4, "M"}
    assert note(view, "crashes") == {"Letzter Schritt rückgängig gemacht", false}
    assert moved(view) == ["movers"]
    assert bar(view) == ""

    # The next step clears the marks; Ctrl+Z takes it back.
    key(view, "performance", "ArrowRight")
    assert place(view, "performance") == {2, 1, "L"}
    assert moved(view) == []
    render_hook(view, "edit_undo", %{})
    assert place(view, "performance") == {1, 1, "L"}
    assert note(view, "performance") == {"Letzter Schritt rückgängig gemacht", false}

    # One step only: a second undo changes nothing.
    render_hook(view, "edit_undo", %{})
    assert place(view, "performance") == {1, 1, "L"}

    assert Dashboards.get_dashboard(dashboard.id).layout == dashboard.layout
    assert journal_count() == 1
  end

  # User story:
  # As the operator moving a widget by keyboard or by pointer,
  # I want it to land where I put it and the others to give way,
  # so that a move onto another widget is never refused.
  #
  # Acceptance criteria:
  # - ArrowDown on „Wertentwicklung“ moves it a row down; „Tops und Flops“
  #   and „Crashes im Vergleich“ below make room, said at „Wertentwicklung“
  #   with „· 2 Widgets sind nachgerückt“; ArrowUp brings it back and the
  #   two float up again.
  # - A drop of „Tops und Flops“ onto „Crashes im Vergleich“ lands there
  #   and „Crashes im Vergleich“ gives way.
  # - Only a step off the grid is refused, said at the widget, without
  #   „Rückgängig“; the bar's status line stays silent.
  test "the arrow keys and a drop arrange; only a step off the grid is refused",
       %{conn: conn} do
    seed()
    dashboard = dashboard!()
    view = open_editing(conn, dashboard)

    key(view, "performance", "ArrowDown")
    assert place(view, "performance") == {1, 2, "L"}
    assert place(view, "movers") == {1, 5, "M"}
    assert place(view, "crashes") == {7, 5, "M"}
    assert moved(view) == ["crashes", "movers"]

    assert note(view, "performance") ==
             {"Wertentwicklung nach unten verschoben, Spalte 1, Zeile 2 · 2 Widgets sind nachgerückt",
              true}

    key(view, "performance", "ArrowUp")
    assert place(view, "performance") == {1, 1, "L"}
    assert place(view, "movers") == {1, 4, "M"}
    assert place(view, "crashes") == {7, 4, "M"}

    key(view, "performance", "ArrowLeft")
    assert place(view, "performance") == {1, 1, "L"}

    assert note(view, "performance") ==
             {"Wertentwicklung kann nicht nach links: Es verließe das Raster.", false}

    assert bar(view) == ""

    movers = item_key(view, "movers")
    render_hook(view, "edit_place", %{"item" => movers, "col" => 7, "row" => 4})
    assert place(view, "movers") == {7, 4, "M"}
    assert place(view, "crashes") == {1, 4, "M"}

    assert note(view, "movers") ==
             {"Tops und Flops an Spalte 7, Zeile 4 gesetzt · 1 Widget ist nachgerückt", true}

    assert bar(view) == ""
  end

  # User story:
  # As the operator whose dashboard is full,
  # I want an add that cannot be done to be said where I asked for it,
  # so that I see why nothing was added.
  #
  # Acceptance criteria:
  # - With 40 widgets, a catalogue entry adds nothing and the catalogue's
  #   own polite region says why; no widget and not the bar says it.
  test "the 41st widget is refused at the catalogue", %{conn: conn} do
    seed()

    forty =
      for n <- 0..39,
          do: %{
            "kind" => "due",
            "size" => "S",
            "col" => 1 + rem(n, 4) * 3,
            "row" => 1 + div(n, 4)
          }

    dashboard = dashboard!(forty)
    view = open_editing(conn, dashboard)

    view |> element("[data-role='edit-add'][data-kind='snapshots']") |> render_click()
    refute has_element?(view, "[data-widget-kind='snapshots']")

    assert view
           |> document()
           |> Floki.find("#dashboard-catalogue-status[role='status'][aria-live='polite']")
           |> text() ==
             "Snapshots kann nicht hinzugefügt werden: Ein Dashboard hält höchstens 40 Widgets."

    assert notes(view) == []
    assert bar(view) == ""
  end
end
