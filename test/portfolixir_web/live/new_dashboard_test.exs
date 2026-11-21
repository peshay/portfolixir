defmodule PortfolixirWeb.NewDashboardTest do
  # Sprint 31 D7 (FR-60; ADR-0062 §2, §3; ADR-0022's amendment of
  # 2026-11-21; planning board ux-design-2026-11-21-sprint31/01 ③): the page
  # „Neues Dashboard“ at /dashboards/new. A name and one of two starts,
  # „Leer beginnen“ (an empty layout) or „Aus Vorlage“ (a copy of
  # „Überblick“); „Anlegen“ stores it as one journaled create and opens it.
  # A refused name is said at the field; the 51st dashboard is refused.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable`); every module that creates one
  # joins this group.
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  defp journal, do: Journal.list_entries(resource_type: "dashboard", order: :asc)

  # User story:
  # As the operator who wants a dashboard for one question,
  # I want to name it and start from nothing,
  # so that it holds only the widgets I then add.
  #
  # Acceptance criteria:
  # - /dashboards/new is titled „Neues Dashboard“ and offers a name,
  #   „Leer beginnen“ (chosen) and „Aus Vorlage“ naming „Überblick“, and
  #   „Anlegen“. Opening it writes nothing.
  # - „Leer beginnen“ stores a dashboard with an empty layout under the
  #   name, at the end of the menu, one journaled create under the UI's
  #   actor, and opens it.
  # - The empty dashboard says it is empty and links „Alle Widgets“.
  test "„Leer beginnen“ stores an empty dashboard and opens it", %{conn: conn} do
    {:ok, older} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Alt"})
    before = length(journal())

    {:ok, view, _html} = live(conn, "/dashboards/new?locale=de")

    assert has_element?(view, "#app-topbar-title", "Neues Dashboard")
    assert has_element?(view, "#new-dashboard-form input[name='dashboard[name]']")

    assert has_element?(
             view,
             "#new-dashboard-form input[type='radio'][name='dashboard[start]'][value='empty'][checked]"
           )

    assert has_element?(view, "#new-dashboard-form label", "Leer beginnen")
    assert has_element?(view, "#new-dashboard-form label", "Aus Vorlage")
    assert has_element?(view, "#new-dashboard-form label", "Überblick")
    assert has_element?(view, "#new-dashboard-form button[type='submit']", "Anlegen")
    assert length(journal()) == before

    view
    |> form("#new-dashboard-form", %{
      "dashboard" => %{"name" => "Kurzfristig", "start" => "empty"}
    })
    |> render_submit()

    created = Enum.find(Dashboards.list_dashboards(), &(&1.name == "Kurzfristig"))
    assert created.layout == []
    assert created.position > older.position
    assert [%{operation: :create, actor_type: :owner_ui}] = Enum.drop(journal(), before)

    path = "/dashboards/#{created.id}"
    assert {^path, _flash} = assert_redirect(view)

    {:ok, opened, _html} = live(conn, path <> "?locale=de")
    assert has_element?(opened, "[data-role='dashboard-empty']", "leer")

    assert has_element?(
             opened,
             "[data-role='dashboard-empty'] a[href='/widgets']",
             "Alle Widgets"
           )
  end

  # User story:
  # As the operator who wants a second overview to change,
  # I want to start from the template,
  # so that I begin from the widgets it already arranges.
  #
  # Acceptance criteria:
  # - „Aus Vorlage“ stores the template „Überblick“'s layout under the name
  #   given, one journaled create, and opens it; the template is unchanged.
  test "„Aus Vorlage“ copies „Überblick“ under the name given", %{conn: conn} do
    {:ok, template} = Templates.fetch("overview")
    {:ok, view, _html} = live(conn, "/dashboards/new?locale=de")

    view
    |> form("#new-dashboard-form", %{
      "dashboard" => %{"name" => "Zweiter Blick", "start" => "template"}
    })
    |> render_submit()

    assert [created] = Dashboards.list_dashboards()
    assert created.name == "Zweiter Blick"
    assert created.layout == template.layout
    assert [%{operation: :create}] = journal()
    assert_redirect(view, "/dashboards/#{created.id}")
    assert Templates.fetch("overview") == {:ok, template}
  end

  # User story:
  # As the operator naming a dashboard,
  # I want a name the app refuses to be said at the field, in my language,
  # so that I can correct it where I typed it.
  #
  # Acceptance criteria:
  # - A blank name, a name of 61 characters and a name with a control
  #   character are each refused at the field; nothing is stored or
  #   journaled, and the form keeps what was typed and the start chosen.
  test "a refused name is said at the field and nothing is stored", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboards/new?locale=de")

    for {name, said} <- [
          {"  ", "darf nicht leer sein"},
          {String.duplicate("a", 61), "60"},
          {"Kurz\u0007fristig", ""}
        ] do
      view
      |> form("#new-dashboard-form", %{"dashboard" => %{"name" => name, "start" => "template"}})
      |> render_submit()

      assert has_element?(view, "#new-dashboard-name-error", said)

      assert has_element?(
               view,
               "#new-dashboard-form input[name='dashboard[name]'][aria-invalid='true']"
             )

      assert has_element?(
               view,
               "#new-dashboard-form input[name='dashboard[start]'][value='template'][checked]"
             )
    end

    assert Repo.aggregate(Dashboard, :count) == 0
    assert journal() == []
  end

  # User story:
  # As the operator with fifty dashboards,
  # I want the fifty-first refused with the reason,
  # so that I know why nothing was made.
  #
  # Acceptance criteria:
  # - With 50 stored, „Anlegen“ stores nothing and says fifty are the most
  #   an instance keeps.
  test "the fifty-first dashboard is refused", %{conn: conn} do
    for n <- 1..Dashboards.max_dashboards() do
      {:ok, _} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "D#{n}"})
    end

    before = length(journal())
    {:ok, view, _html} = live(conn, "/dashboards/new?locale=de")

    view
    |> form("#new-dashboard-form", %{
      "dashboard" => %{"name" => "Eins zu viel", "start" => "empty"}
    })
    |> render_submit()

    assert has_element?(view, "[data-role='new-dashboard-refused']", "fünfzig")
    assert Repo.aggregate(Dashboard, :count) == Dashboards.max_dashboards()
    assert length(journal()) == before
  end
end
