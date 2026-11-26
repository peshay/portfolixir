defmodule PortfolixirWeb.WidgetCatalogueTest do
  # Sprint 31 D7 (FR-60; ADR-0062 §1, §2; ADR-0022's amendment of
  # 2026-11-21; planning board ux-design-2026-11-21-sprint31/01 ②): the
  # page „Alle Widgets“ under „Entdecken“. It lists the registry's kinds
  # by group with their sizes and „hinzufügen ›“, which opens the choice of
  # dashboard and adds the widget at the first free place through the
  # journaled replace with the lock_version read; and, dashed, the kinds
  # each later pass brings, which are no registered kind and never add.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable`); every module that creates one
  # joins this group.
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Journal
  alias Portfolixir.Repo
  alias PortfolixirWeb.WidgetsLive

  defp item(kind, size, col, row),
    do: %{"kind" => kind, "size" => size, "col" => col, "row" => row, "settings" => %{}}

  defp journal, do: Journal.list_entries(resource_type: "dashboard", order: :asc)

  defp chips(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("[data-role='widget-size']")
    |> Enum.map(&String.trim(Floki.text(&1)))
  end

  # User story:
  # As the operator looking for what a dashboard can show,
  # I want every widget the app has on one page, grouped by topic, with
  # the sizes each takes,
  # so that I find a function without knowing which screen holds it.
  #
  # Acceptance criteria:
  # - The page answers at /widgets, titled „Alle Widgets“ in German.
  # - Every registered kind is listed once, under its group in the
  #   registry's group order, with its sizes as chips in the registry's
  #   order (`full` reads „Voll“) and „hinzufügen ›“.
  # - The kinds listed are exactly the registry's: none more, none fewer.
  test "the catalogue lists the registry's kinds by group, with their sizes", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/widgets?locale=de")

    assert has_element?(view, "#app-topbar-title", "Alle Widgets")

    listed =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("[data-role='widget-card'][data-widget-kind]")
      |> Enum.flat_map(&Floki.attribute(&1, "data-widget-kind"))

    assert Enum.sort(listed) == Enum.sort(Widgets.keys())

    groups =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("[data-role='widget-group']")
      |> Enum.flat_map(&Floki.attribute(&1, "data-group"))

    assert Enum.take(groups, length(Widgets.groups())) == Widgets.groups()

    for kind <- Widgets.kinds() do
      card = "[data-group='#{kind.group}'] [data-widget-kind='#{kind.key}']"
      assert has_element?(view, card, german_title(kind.key))

      expected =
        Enum.map(kind.sizes, fn
          "full" -> "Voll"
          "row" -> "Zeile"
          size -> size
        end)

      assert chips(view, card) == expected

      assert has_element?(view, card <> " [data-role='add-widget']", "hinzufügen ›")
    end
  end

  defp german_title(key),
    do: Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn -> Widgets.title(key) end)

  # User story:
  # As the operator reading the catalogue,
  # I want the widgets the later passes bring shown dashed, with when they
  # come, and never offered for a dashboard,
  # so that the catalogue says what is coming without promising it now.
  #
  # Acceptance criteria:
  # - The kinds of board ② not yet built (eight since Sprint 32 W2 built
  #   „Allokation“) stand dashed under their groups, „Einkommen
  #   und Steuer“ last, each with „kommt mit dem Umbau seines Screens“ and
  #   no „hinzufügen“.
  # - None of them is a registered kind, and a layout naming one is
  #   refused as an unknown kind.
  test "the later kinds stand dashed, are no kind and never validate", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/widgets?locale=de")

    later = WidgetsLive.later_kinds()

    assert Enum.map(later, & &1.key) ==
             ~w(contribution key_figures concentration asset_class_limits predictions income fees_and_taxes tax_allowance)

    assert has_element?(
             view,
             "[data-role='widget-group'][data-group='income_tax'] h2",
             "Einkommen und Steuer"
           )

    for kind <- later do
      card = "[data-group='#{kind.group}'] [data-later-kind='#{kind.key}'].widget-card--later"
      assert has_element?(view, card, "kommt mit dem Umbau seines Screens")
      refute has_element?(view, card <> " [data-role='add-widget']")

      refute kind.key in Widgets.keys()

      assert {:error, %{reason: :unknown_kind, index: 0}} =
               Layout.validate([item(kind.key, hd(kind.sizes), 1, 1)])
    end

    assert has_element?(view, "[data-later-kind='contribution']", "Beiträge je Position")
    assert has_element?(view, "[data-later-kind='tax_allowance']", "Freibetrag")

    # Sprint 32 W2 registered „Allokation“: no longer a later kind.
    refute has_element?(view, "[data-later-kind='allocation']")
    assert has_element?(view, "[data-widget-kind='allocation']")
  end

  # User story:
  # As the operator who knows the widget's name,
  # I want to type it and see only the matching widgets,
  # so that I do not read the whole catalogue for one.
  #
  # Acceptance criteria:
  # - „Suchen …“ keeps the kinds whose title holds the text, ignoring case,
  #   registered and later alike; a group with none left is not shown.
  test "the search keeps the matching widgets", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/widgets?locale=de")

    view |> form("#widget-search", %{"q" => "zykl"}) |> render_change()

    assert has_element?(view, "[data-widget-kind='bitcoin_cycle']")
    refute has_element?(view, "[data-widget-kind='total_value']")
    refute has_element?(view, "[data-group='overview']")

    view |> form("#widget-search", %{"q" => "STEUER"}) |> render_change()
    assert has_element?(view, "[data-later-kind='fees_and_taxes']")
    refute has_element?(view, "[data-widget-kind]")

    view |> form("#widget-search", %{"q" => ""}) |> render_change()
    assert has_element?(view, "[data-widget-kind='total_value']")
  end

  # User story:
  # As the operator who found a widget in the catalogue,
  # I want „hinzufügen“ to ask which dashboard and put it there where it
  # fits,
  # so that I add it without rearranging anything by hand.
  #
  # Acceptance criteria:
  # - „hinzufügen ›“ opens a dialog listing the stored dashboards in the
  #   menu's order.
  # - Choosing one adds the kind at its first size, at the first free place
  #   of that dashboard's grid, as one journaled update under the UI's
  #   actor; lock_version rises by one; the other dashboard is untouched.
  # - The page says where it went and links the dashboard.
  test "„hinzufügen“ adds the widget at the first free place, journaled", %{conn: conn} do
    {:ok, first} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Kurzfristig",
        "layout" => [item("total_value", "S", 1, 1), item("due", "S", 4, 1)]
      })

    {:ok, second} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Langfristig", "layout" => []})

    before = length(journal())

    {:ok, view, _html} = live(conn, "/widgets?locale=de")

    view |> element("[data-widget-kind='movers'] [data-role='add-widget']") |> render_click()

    assert has_element?(view, "dialog#widget-add-dialog", "Tops und Flops")

    assert view
           |> render()
           |> Floki.parse_document!()
           |> Floki.find("#widget-add-dialog [data-role='add-to']")
           |> Enum.map(&String.trim(Floki.text(&1))) == ["Kurzfristig", "Langfristig"]

    view
    |> element("#widget-add-dialog [data-role='add-to'][phx-value-id='#{first.id}']")
    |> render_click()

    stored = Repo.get!(Dashboard, first.id)
    assert stored.lock_version == first.lock_version + 1
    assert List.last(stored.layout) == item("movers", "S", 7, 1)
    assert Repo.get!(Dashboard, second.id).layout == []

    assert [entry] = Enum.drop(journal(), before)
    assert entry.operation == :update
    assert entry.resource_id == to_string(first.id)
    assert entry.actor_type == :owner_ui

    refute has_element?(view, "dialog#widget-add-dialog")
    assert has_element?(view, "[data-role='widget-added']", "Kurzfristig")
    assert has_element?(view, "[data-role='widget-added'] a[href='/dashboards/#{first.id}']")
  end

  # User story:
  # As the operator adding a widget while my agent rearranged the same
  # dashboard,
  # I want the add refused rather than written over the agent's change,
  # so that neither write is lost unseen.
  #
  # Acceptance criteria:
  # - A dashboard changed since the dialog read it answers the replace's
  #   409: nothing is added, nothing more is journaled, the dialog says so
  #   and lists the dashboards as now stored; choosing again adds it.
  test "a dashboard changed since the dialog read it is not written over", %{conn: conn} do
    {:ok, board} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Kurzfristig",
        "layout" => [item("total_value", "S", 1, 1)]
      })

    {:ok, view, _html} = live(conn, "/widgets?locale=de")
    view |> element("[data-widget-kind='due'] [data-role='add-widget']") |> render_click()

    # The agent's write, after the dialog read lock_version 1.
    {:ok, changed} =
      Dashboards.replace_dashboard(Actor.api_token_rw("agent"), board.id, %{
        "name" => "Kurzfristig",
        "layout" => [item("total_value", "S", 1, 1), item("off_target", "S", 4, 1)],
        "lock_version" => board.lock_version
      })

    before = length(journal())
    view |> element("[data-role='add-to'][phx-value-id='#{board.id}']") |> render_click()

    assert Repo.get!(Dashboard, board.id) == changed
    assert length(journal()) == before
    assert has_element?(view, "#widget-add-dialog [data-role='widget-add-stale']")

    view |> element("[data-role='add-to'][phx-value-id='#{board.id}']") |> render_click()

    stored = Repo.get!(Dashboard, board.id)
    assert stored.lock_version == changed.lock_version + 1
    assert List.last(stored.layout) == item("due", "S", 7, 1)
  end

  # User story:
  # As the operator adding a widget to a dashboard my agent deleted
  # meanwhile,
  # I want to be told it no longer exists, and the choice to list what is
  # stored now,
  # so that nothing is written and I can choose another.
  #
  # Acceptance criteria:
  # - A dashboard deleted since the dialog read it answers the replace's
  #   404: nothing is stored or journaled, the dialog says „… gibt es
  #   nicht mehr“ by its name and no longer offers it; the other stays.
  test "a dashboard deleted since the dialog read it is said gone", %{conn: conn} do
    {:ok, board} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Verworfen",
        "layout" => [item("total_value", "S", 1, 1)]
      })

    {:ok, other} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Bleibt"})

    {:ok, view, _html} = live(conn, "/widgets?locale=de")
    view |> element("[data-widget-kind='due'] [data-role='add-widget']") |> render_click()

    {:ok, _} = Dashboards.delete_dashboard(Actor.api_token_rw("agent"), board.id)
    before = length(journal())

    view |> element("[data-role='add-to'][phx-value-id='#{board.id}']") |> render_click()

    assert length(journal()) == before
    assert Repo.get(Dashboard, board.id) == nil

    assert has_element?(
             view,
             "#widget-add-dialog [data-role='widget-add-stale']",
             "Verworfen gibt es nicht mehr"
           )

    refute has_element?(view, "[data-role='add-to'][phx-value-id='#{board.id}']")
    assert has_element?(view, "[data-role='add-to'][phx-value-id='#{other.id}']")
  end

  # User story:
  # As the operator adding a widget to a dashboard that is full,
  # I want to be told so,
  # so that the widget is never dropped or stacked unseen.
  #
  # Acceptance criteria:
  # - A dashboard of 40 widgets answers „hält schon 40 Widgets“ in the
  #   dialog; nothing is written or journaled.
  test "a full dashboard is refused in the dialog", %{conn: conn} do
    forty = for row <- 1..40, do: item("due", "S", 1, 2 * row - 1)

    {:ok, board} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Voll", "layout" => forty})

    before = length(journal())
    {:ok, view, _html} = live(conn, "/widgets?locale=de")
    view |> element("[data-widget-kind='due'] [data-role='add-widget']") |> render_click()
    view |> element("[data-role='add-to'][phx-value-id='#{board.id}']") |> render_click()

    assert has_element?(view, "#widget-add-dialog [data-role='widget-add-refused']", "40")
    assert Repo.get!(Dashboard, board.id).lock_version == board.lock_version
    assert length(journal()) == before
  end

  # User story:
  # As the operator on a fresh instance, where no dashboard is stored,
  # I want „hinzufügen“ to offer to make one,
  # so that the catalogue is never a dead end.
  #
  # Acceptance criteria:
  # - The dialog says no dashboard is stored yet, offers to copy
  #   „Überblick“ with this widget and links „Neues Dashboard“.
  # - Opening the dialog writes nothing.
  # - The copy is one journaled create: the template's layout with the
  #   widget at its first free place, under the template's title; the
  #   page opens it.
  test "on a fresh instance the choice offers to create a dashboard", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/widgets?locale=de")
    view |> element("[data-widget-kind='movers'] [data-role='add-widget']") |> render_click()

    assert has_element?(view, "#widget-add-dialog", "Noch kein Dashboard")
    assert has_element?(view, "#widget-add-dialog a[href='/dashboards/new']", "Neues Dashboard")
    assert Repo.aggregate(Dashboard, :count) == 0
    assert journal() == []

    view |> element("#widget-add-dialog [data-role='add-to-template']") |> render_click()

    assert [created] = Dashboards.list_dashboards()
    {:ok, template} = Templates.fetch("overview")
    assert created.name == "Überblick"
    assert created.layout == template.layout ++ [item("movers", "S", 10, 15)]
    assert [%{operation: :create}] = journal()
    assert_redirect(view, "/dashboards/#{created.id}")
  end
end
