defmodule PortfolixirWeb.DashboardStarterNameTest do
  # The S32 closing act (the orchestrator's decision, flippable by the
  # owner): the boot stores the starter „Überblick“ under the release
  # default locale's title, „Overview“, so the German sidebar and title
  # said „Overview“ while the gallery said „Überblick“. While a dashboard
  # is unrenamed — its `template_key` set and its stored name the
  # template's untranslated source title — every screen that shows its
  # name shows the template's title in the page's language; the stored
  # name and the API, which is locale-free, stay as stored. Every name is
  # synthetic.
  #
  # group: :dashboards -- the starters' seed and a create take the count
  # lock (`Portfolixir.LockTable` row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Starters

  defp german(conn), do: put_preference_cookie(conn, "portfolixir_locale", "de")

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp find(view, selector),
    do: view |> render() |> Floki.parse_document!() |> Floki.find(selector)

  defp api_name(id) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("accept-language", "de")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get("/api/v1/dashboards/#{id}")
    |> json_response(200)
    |> get_in(["data", "name"])
  end

  # „Überblick“ and the other starters (Sprint 32 W2: „Allokation &
  # Ziele“), „Überblick“ first.
  defp seeded! do
    {:ok, %{stored: ["overview" | _screens]}} = Starters.seed()
    [overview | _screens] = Dashboards.list_dashboards()
    overview
  end

  # User story:
  # As the operator whose page speaks German,
  # I want the starter dashboard named „Überblick“ wherever its name
  # stands until I rename it,
  # so that the sidebar, the title and the gallery speak one language.
  #
  # Acceptance criteria:
  # - The seeded starter is stored as „Overview“ with its template key.
  # - On a German page its sidebar entry, the page title and the dashboard
  #   switcher say „Überblick“; on an English page „Overview“.
  # - „Alle Widgets“' picker offers it as „Überblick“.
  # - The gallery counts the name as taken: the dialog for „Überblick“
  #   suggests „Überblick (2)“.
  # - The API answers the stored name, „Overview“, whatever the language
  #   asked for.
  test "an unrenamed starter is named in the page's language; the stored name stays", %{
    conn: conn
  } do
    overview = seeded!()
    assert {overview.name, overview.template_key} == {"Overview", "overview"}

    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{overview.id}")
    assert text(find(view, "#nav-dashboard-#{overview.id}")) == "Überblick"
    assert text(find(view, "#app-topbar-title .topbar-title-text")) == "Überblick"
    assert text(find(view, "#app-topbar-title .topbar-switcher__name")) == "Überblick"
    refute render(view) =~ ">Overview<"

    {:ok, english, _html} = live(conn, "/dashboards/#{overview.id}?locale=en")
    assert text(find(english, "#nav-dashboard-#{overview.id}")) == "Overview"
    assert text(find(english, "#app-topbar-title .topbar-title-text")) == "Overview"

    {:ok, widgets, _html} = conn |> german() |> live("/widgets")
    widgets |> element("[data-role='add-widget'][phx-value-kind='snapshots']") |> render_click()
    # The picker lists every stored dashboard, the other starters after it
    # (Sprint 32 W2).
    assert text(find(widgets, "li:first-child [data-role='add-to']")) == "Überblick"

    {:ok, gallery, _html} = conn |> german() |> live("/dashboards/new")
    gallery |> element("[data-template='overview']") |> render_click()

    assert gallery
           |> find("#new-dashboard-form input[name='dashboard[name]']")
           |> Floki.attribute("value") ==
             ["Überblick (2)"]

    assert api_name(overview.id) == "Overview"
    assert Dashboards.get_dashboard(overview.id).name == "Overview"
  end

  # User story:
  # As the operator who renamed the starter,
  # I want my name shown as I wrote it, in every language,
  # so that a rename is never translated away.
  #
  # Acceptance criteria:
  # - After a rename to „Mein Blick“ the German page, the sidebar and the
  #   picker say „Mein Blick“; so does the English page.
  test "a renamed starter shows the name it was given", %{conn: conn} do
    overview = seeded!()
    {:ok, _renamed} = Dashboards.rename_dashboard(Actor.owner_ui(), overview.id, "Mein Blick")

    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{overview.id}")
    assert text(find(view, "#nav-dashboard-#{overview.id}")) == "Mein Blick"
    assert text(find(view, "#app-topbar-title .topbar-title-text")) == "Mein Blick"

    {:ok, english, _html} = live(conn, "/dashboards/#{overview.id}?locale=en")
    assert text(find(english, "#nav-dashboard-#{overview.id}")) == "Mein Blick"

    {:ok, widgets, _html} = conn |> german() |> live("/widgets")
    widgets |> element("[data-role='add-widget'][phx-value-kind='snapshots']") |> render_click()
    assert text(find(widgets, "li:first-child [data-role='add-to']")) == "Mein Blick"

    assert api_name(overview.id) == "Mein Blick"
  end
end
