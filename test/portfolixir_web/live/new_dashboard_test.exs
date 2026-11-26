defmodule PortfolixirWeb.NewDashboardTest do
  # Sprint 32 S4 (ADR-0062's amendment of 2026-11-25, point 5; I61; board
  # ux-design-2026-11-25-sprint32/03 ①, ②), after Sprint 31 D7: „Neues
  # Dashboard“ at /dashboards/new opens a gallery — „Leer beginnen“, the
  # starters, then the themes, each card its grid in miniature, its widget
  # count and names; a template whose kinds are not all built is not shown.
  # A click opens a dialog with the name (a taken one suggests „… (2)“)
  # and, for a template that asks for one, the scope; „Anlegen“ stores one
  # copy, journaled, and opens it. A refused name is said at the field; the
  # 51st dashboard is refused.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable`); every module that creates one
  # joins this group.
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 0, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  defp journal, do: Journal.list_entries(resource_type: "dashboard", order: :asc)

  defp german(fun), do: Gettext.with_locale(PortfolixirWeb.Gettext, "de", fun)

  # User story:
  # As the operator who wants a new dashboard,
  # I want a gallery of what I can start from, each card showing its grid,
  # how many widgets and which,
  # so that I choose by what I will see.
  #
  # Acceptance criteria:
  # - /dashboards/new is titled „Neues Dashboard“ and shows „Leer
  #   beginnen“, then the group of the starters with every starter, then
  #   the group „Themen“ with every other offered template; opening it
  #   writes nothing.
  # - Each template card names the template, its widget count („11
  #   Widgets“), its widgets' titles, and draws one miniature cell per
  #   widget at its place (its column and row spans).
  test "the gallery shows „Leer beginnen“, the starters and the themes, each with its grid",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboards/new?locale=de")

    assert has_element?(view, "#app-topbar-title", "Neues Dashboard")
    assert has_element?(view, "[data-role='gallery-empty']", "Leer beginnen")
    assert journal() == []

    doc = view |> render() |> Floki.parse_document!()

    keys = fn group ->
      doc
      |> Floki.find("[data-role='#{group}'] [data-template]")
      |> Enum.flat_map(&Floki.attribute(&1, "data-template"))
    end

    offered = Templates.offered(Templates.templates())
    assert keys.("gallery-starters") == for(t <- offered, t.starter, do: t.key)
    assert keys.("gallery-themes") == for(t <- offered, not t.starter, do: t.key)
    assert "overview" in keys.("gallery-starters")

    for template <- offered do
      [card] = Floki.find(doc, "[data-template='#{template.key}']")
      text = card |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ")
      assert text =~ german(fn -> Templates.title(template.key) end)
      assert text =~ "#{length(template.layout)} Widgets"

      for item <- template.layout do
        assert text =~ german(fn -> Widgets.title(item["kind"]) end)
      end

      cells = Floki.find(card, "[data-role='gallery-cell']")
      assert length(cells) == length(template.layout)

      for {cell, item} <- Enum.zip(cells, template.layout) do
        {:ok, {w, h}} = Widgets.dimensions(item["size"])
        [style] = Floki.attribute(cell, "style")

        assert style ==
                 "--cell-col: #{item["col"]}; --cell-row: #{item["row"]}; " <>
                   "--cell-w: #{w}; --cell-h: #{h};"
      end
    end
  end

  # User story:
  # As the operator who wants a second „Überblick“ to change,
  # I want to pick it, see its name suggested and not clash with mine,
  # and have it stored and opened,
  # so that I start from the widgets it arranges.
  #
  # Acceptance criteria:
  # - A click on „Überblick“ opens the dialog „Dashboard aus „Überblick““;
  #   with dashboards „Überblick“ and „Überblick (2)“ stored, the name
  #   suggested is „Überblick (3)“. „Überblick“ asks for no scope: no scope
  #   field.
  # - „Abbrechen“ closes the dialog and stores nothing.
  # - „Anlegen“ stores one copy under the name, its template_key recorded,
  #   one journaled create, and opens it; the template is unchanged.
  test "a starter's card opens the dialog, suggests a free name and stores one copy",
       %{conn: conn} do
    {:ok, template} = Templates.fetch("overview")
    {:ok, _} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Überblick"})
    {:ok, _} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Überblick (2)"})
    before = length(journal())

    {:ok, view, _html} = live(conn, "/dashboards/new?locale=de")

    view |> element("[data-template='overview']") |> render_click()
    assert has_element?(view, "#new-dashboard-dialog", "Dashboard aus „Überblick“")

    assert has_element?(
             view,
             "#new-dashboard-form input[name='dashboard[name]'][value='Überblick (3)']"
           )

    refute has_element?(view, "#new-dashboard-form select[name='dashboard[view_id]']")

    view |> element("#new-dashboard-dialog [data-role='new-dashboard-cancel']") |> render_click()
    refute has_element?(view, "#new-dashboard-dialog")
    assert length(journal()) == before

    view |> element("[data-template='overview']") |> render_click()

    view
    |> form("#new-dashboard-form", %{"dashboard" => %{"name" => "Zweiter Blick"}})
    |> render_submit()

    created = Enum.find(Dashboards.list_dashboards(), &(&1.name == "Zweiter Blick"))
    assert created.layout == template.layout
    assert created.template_key == "overview"
    assert [%{operation: :create, actor_type: :owner_ui}] = Enum.drop(journal(), before)
    assert_redirect(view, "/dashboards/#{created.id}")
    assert Templates.fetch("overview") == {:ok, template}
  end

  # User story:
  # As the operator who wants a dashboard for one question,
  # I want to name it and start from nothing,
  # so that it holds only the widgets I then add.
  #
  # Acceptance criteria:
  # - „Leer beginnen“ opens the dialog „Leeres Dashboard“ with an empty
  #   name; „Anlegen“ stores a dashboard with an empty layout under the
  #   name, at the end of the menu, one journaled create under the UI's
  #   actor, and opens it in the edit mode with the catalogue open, the
  #   focus in the catalogue.
  # - Outside the edit the empty dashboard says it is empty and links
  #   „Alle Widgets“.
  test "„Leer beginnen“ stores an empty dashboard and opens it", %{conn: conn} do
    {:ok, older} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Alt"})
    before = length(journal())

    {:ok, view, _html} = live(conn, "/dashboards/new?locale=de")
    view |> element("[data-role='gallery-empty']") |> render_click()

    assert has_element?(view, "#new-dashboard-dialog", "Leeres Dashboard")
    assert has_element?(view, "#new-dashboard-form input[name='dashboard[name]'][value='']")
    assert has_element?(view, "#new-dashboard-form button[type='submit']", "Anlegen")

    view
    |> form("#new-dashboard-form", %{"dashboard" => %{"name" => "Kurzfristig"}})
    |> render_submit()

    created = Enum.find(Dashboards.list_dashboards(), &(&1.name == "Kurzfristig"))
    assert created.layout == []
    assert created.template_key == nil
    assert created.position > older.position
    assert [%{operation: :create, actor_type: :owner_ui}] = Enum.drop(journal(), before)

    path = "/dashboards/#{created.id}"
    asked = path <> "?edit=catalogue"
    assert {^asked, _flash} = assert_redirect(view)
    deposit!(base_world(), "100", Portfolixir.Clock.today())

    {:ok, editing, _html} = live(conn, asked)
    assert has_element?(editing, "[data-role='dashboard-grid'][data-editing='true']")
    assert has_element?(editing, "#dashboard-catalogue.is-open")
    assert_push_event(editing, "dashboard-edit-focus", %{ids: ["dashboard-catalogue-close" | _]})

    {:ok, opened, _html} = live(conn, path <> "?locale=de")
    assert has_element?(opened, "[data-role='dashboard-empty']", "leer")

    assert has_element?(
             opened,
             "[data-role='dashboard-empty'] a[href='/widgets']",
             "Alle Widgets"
           )
  end

  # User story:
  # As the operator naming a dashboard,
  # I want a name the app refuses to be said at the field, in my language,
  # so that I can correct it where I typed it.
  #
  # Acceptance criteria:
  # - A blank name, a name of 61 characters and a name with a control
  #   character are each refused at the field; nothing is stored or
  #   journaled, and the dialog stays open with what was typed.
  test "a refused name is said at the field and nothing is stored", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboards/new?locale=de")
    view |> element("[data-template='overview']") |> render_click()

    for {name, said} <- [
          {"  ", "darf nicht leer sein"},
          {String.duplicate("a", 61), "60"},
          {"Kurz\u0007fristig", ""}
        ] do
      view
      |> form("#new-dashboard-form", %{"dashboard" => %{"name" => name}})
      |> render_submit()

      assert has_element?(view, "#new-dashboard-name-error", said)

      assert has_element?(
               view,
               "#new-dashboard-form input[name='dashboard[name]'][aria-invalid='true']"
             )

      assert has_element?(view, "#new-dashboard-dialog", "Dashboard aus „Überblick“")
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
    view |> element("[data-role='gallery-empty']") |> render_click()

    view
    |> form("#new-dashboard-form", %{"dashboard" => %{"name" => "Eins zu viel"}})
    |> render_submit()

    assert has_element?(view, "[data-role='new-dashboard-refused']", "fünfzig")
    assert Repo.aggregate(Dashboard, :count) == Dashboards.max_dashboards()
    assert length(journal()) == before
  end

  # User story (Sprint 32 S5; board 03 ②, „Dashboard aus ‚Krypto Lover‘“):
  # As the operator starting from the theme „Krypto Lover“,
  # I want to be asked for the view it reads,
  # so that the theme shows my crypto, not everything.
  #
  # Acceptance criteria:
  # - The themes „Krypto Lover“ and „Rücksetzer“ stand in „Themen“.
  # - „Krypto Lover“'s dialog asks for the view: „Keine“ and every view;
  #   „Rücksetzer“'s asks for none.
  # - „Anlegen“ with a view stores the copy with that view as its own and
  #   template_key krypto_lover, and opens it.
  test "a theme that asks for a scope stores the view chosen as the dashboard's own",
       %{conn: conn} do
    {:ok, krypto} =
      Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "Krypto", include_all: true})

    {:ok, view, _html} = live(conn, "/dashboards/new?locale=de")

    assert has_element?(
             view,
             "[data-role='gallery-themes'] [data-template='krypto_lover']",
             "Krypto Lover"
           )

    assert has_element?(
             view,
             "[data-role='gallery-themes'] [data-template='pullbacks']",
             "Rücksetzer"
           )

    view |> element("[data-template='pullbacks']") |> render_click()
    refute has_element?(view, "#new-dashboard-form select[name='dashboard[view_id]']")
    view |> element("#new-dashboard-dialog [data-role='new-dashboard-cancel']") |> render_click()

    view |> element("[data-template='krypto_lover']") |> render_click()
    assert has_element?(view, "#new-dashboard-dialog", "Dashboard aus „Krypto Lover“")

    assert has_element?(
             view,
             "#new-dashboard-form select[name='dashboard[view_id]'] option[value='']",
             "Keine"
           )

    assert has_element?(view, "#new-dashboard-form option[value='#{krypto.id}']", "Krypto")

    view
    |> form("#new-dashboard-form", %{
      "dashboard" => %{"name" => "Mein Krypto", "view_id" => to_string(krypto.id)}
    })
    |> render_submit()

    created = Enum.find(Dashboards.list_dashboards(), &(&1.name == "Mein Krypto"))
    assert {created.view_id, created.template_key} == {krypto.id, "krypto_lover"}
    assert_redirect(view, "/dashboards/#{created.id}")
  end

  # User story (the S32 closing act; board 03 ②, where „Krypto Lover“'s
  # dialog shows „Krypto ▾“):
  # As the operator who keeps a view named „Krypto“,
  # I want „Krypto Lover“'s dialog to offer it already chosen,
  # so that the theme reads my crypto without a second click.
  #
  # Acceptance criteria:
  # - With views „Aktien“ and „krypto“ stored, „Krypto Lover“'s dialog
  #   preselects „krypto“, on a German page and on an English one: the
  #   first view whose name is the template's suggested scope in any
  #   language the release speaks („Krypto“, „Crypto“), any case.
  # - Without such a view it preselects „Keine“, as before.
  # - „Rücksetzer“ suggests no scope and asks for none.
  test "„Krypto Lover“ preselects the view named like its suggested scope", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboards/new?locale=de")
    view |> element("[data-template='krypto_lover']") |> render_click()

    assert has_element?(
             view,
             "#new-dashboard-form select[name='dashboard[view_id]'] option[value=''][selected]"
           )

    {:ok, _stocks} =
      Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "Aktien", include_all: true})

    {:ok, krypto} =
      Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "krypto", include_all: true})

    for locale <- ~w(de en) do
      {:ok, view, _html} = live(conn, "/dashboards/new?locale=#{locale}")
      view |> element("[data-template='krypto_lover']") |> render_click()

      assert has_element?(
               view,
               "#new-dashboard-form select[name='dashboard[view_id]'] option[value='#{krypto.id}'][selected]"
             ),
             locale

      refute has_element?(
               view,
               "#new-dashboard-form select[name='dashboard[view_id]'] option[value=''][selected]"
             )
    end

    assert Templates.suggested_scope("pullbacks") == nil
  end
end
