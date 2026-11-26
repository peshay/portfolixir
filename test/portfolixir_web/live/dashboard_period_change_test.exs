defmodule PortfolixirWeb.DashboardPeriodChangeTest do
  # Sprint 32 closing act (findings on Lane T's period menu): an own period
  # changed, deleted here or deleted elsewhere while the dashboard is open,
  # and a quick choice that names a period deleted elsewhere. Each figure is
  # compared with the API's answer for the same key; every name and figure
  # is synthetic.
  #
  # group: :periods -- a period's create takes the count lock of
  # `Portfolixir.LockTable` row 31; every module that creates one joins it.
  # A dashboard, where one is made, is made after the periods.
  use PortfolixirWeb.ConnCase, async: true, group: :periods

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards
  alias Portfolixir.Periods
  alias PortfolixirWeb.Format

  @year Clock.today().year - 1

  # A deposit of 1000 spent on 10 January of last year on ten shares at
  # 100, quoted 110 on 30 September and 120 today: a period from 1 February and one from
  # 1 October return different figures.
  defp seed do
    world = base_world()

    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    first = Date.new!(@year, 1, 10)
    deposit!(world, "1000", first)
    buy!(world, security, quantity: "10", price: "100", date: first)
    put_quote!(security, first, "100")
    put_quote!(security, Date.new!(@year, 9, 30), "110")
    put_quote!(security, Clock.today(), "120")
    world
  end

  defp german(conn), do: put_preference_cookie(conn, "portfolixir_locale", "de")

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp document(view), do: view |> render() |> Floki.parse_document!()

  defp find(view, selector), do: view |> document() |> Floki.find(selector)

  defp api(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp api_percent(key) do
    ttwror = api("/api/v1/performance?period=" <> URI.encode_www_form(key))["ttwror"]
    Format.signed_percent(Decimal.new(ttwror)) <> "%"
  end

  defp total_change(view),
    do:
      view |> find("[data-widget-kind='total_value'] [data-role='card-period-change']") |> text()

  defp performance_ttwror(view),
    do:
      view |> find("[data-widget-kind='performance'] [data-role='performance-ttwror']") |> text()

  defp tag_text(view, kind),
    do: view |> find("[data-widget-kind='#{kind}'] [data-role='widget-period']") |> text()

  defp own!(name, from) do
    {:ok, own} =
      Periods.create_saved(Actor.owner_ui(), %{"name" => name, "from" => from, "to" => nil})

    own
  end

  defp dashboard!(layout) do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Perioden", "layout" => layout})

    dashboard
  end

  defp toggle(view), do: view |> element("[data-role='period-menu-toggle']") |> render_click()

  defp pin_menu(view, kind),
    do: view |> element("[data-widget-kind='#{kind}'] [data-role='pin-menu']") |> render_click()

  defp edit(view, key),
    do: view |> element("[data-role='period-edit'][data-period='#{key}']") |> render_click()

  defp save(view, name, from, quick) do
    view
    |> form("#period-form",
      period: %{name: name, from: Date.to_iso8601(from), to_mode: "today", quick: quick}
    )
    |> render_submit()
  end

  # User story:
  # As the operator changing my own period while the dashboard shows it,
  # I want every figure to follow the new dates at once,
  # so that the bar's dates and the figures under it never disagree.
  #
  # Acceptance criteria:
  # - On `?period=saved:<id>`, a change of the period's start from
  #   1 February to 1 October („Speichern und anwenden“) shows Gesamtwert's
  #   change and Wertentwicklung's TTWROR as GET /api/v1/performance
  #   answers for `period=saved:<id>` after the change.
  test "a change to the dashboard's own period reads its figures again", %{conn: conn} do
    seed()
    own = own!("Mine", Date.new!(@year, 2, 1))
    key = "saved:#{own.id}"

    dashboard =
      dashboard!([
        %{"kind" => "total_value", "size" => "S", "col" => 1, "row" => 1},
        %{"kind" => "performance", "size" => "L", "col" => 4, "row" => 1}
      ])

    {:ok, view, _html} =
      conn |> german() |> live("/dashboards/#{dashboard.id}?period=" <> key)

    render_async(view)
    before = api_percent(key)
    assert performance_ttwror(view) == before

    toggle(view)
    edit(view, key)
    save(view, "Mine", Date.new!(@year, 10, 1), "false")
    render_async(view)

    after_change = api_percent(key)
    refute after_change == before
    assert performance_ttwror(view) == after_change
    assert total_change(view) =~ after_change
  end

  # User story:
  # As the operator changing my own period from a widget pinned to it,
  # I want the pinned widget to follow the new dates,
  # so that a pin by reference means what the period now says.
  #
  # Acceptance criteria:
  # - A Wertentwicklung pinned to `saved:<id>` on a dashboard on 1J: the
  #   change saved from its „Zeitraum festpinnen“ menu shows the TTWROR
  #   GET /api/v1/performance answers for the new span; Gesamtwert stays
  #   on 1J's.
  test "a change to a pinned own period reads the pinned widget again", %{conn: conn} do
    seed()
    own = own!("Mine", Date.new!(@year, 2, 1))
    key = "saved:#{own.id}"

    dashboard =
      dashboard!([
        %{"kind" => "total_value", "size" => "S", "col" => 1, "row" => 1},
        %{
          "kind" => "performance",
          "size" => "L",
          "col" => 4,
          "row" => 1,
          "settings" => %{"period" => key}
        }
      ])

    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{dashboard.id}")
    render_async(view)
    before = api_percent(key)
    assert performance_ttwror(view) == before

    pin_menu(view, "performance")
    edit(view, key)
    save(view, "Mine", Date.new!(@year, 10, 1), "false")
    render_async(view)

    after_change = api_percent(key)
    refute after_change == before
    assert performance_ttwror(view) == after_change
    assert total_change(view) =~ api_percent("1y")
  end

  # User story:
  # As the operator deleting my own period that a widget is pinned to,
  # I want that widget to show the dashboard's period's figures at once,
  # so that it never waits on a read nobody started.
  #
  # Acceptance criteria:
  # - A Wertentwicklung pinned to `saved:<id>` on a dashboard on 1J: after
  #   „Löschen“ in the menu, it shows 1J's TTWROR as the API answers it,
  #   and no skeleton remains.
  test "deleting a pinned own period reads the dashboard's period for the widget",
       %{conn: conn} do
    seed()
    own = own!("Mine", Date.new!(@year, 2, 1))
    key = "saved:#{own.id}"

    dashboard =
      dashboard!([
        %{
          "kind" => "performance",
          "size" => "L",
          "col" => 1,
          "row" => 1,
          "settings" => %{"period" => key}
        }
      ])

    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{dashboard.id}")
    render_async(view)

    toggle(view)
    edit(view, key)
    view |> element("#period-dialog [data-role='period-delete']") |> render_click()
    render_async(view)

    assert Periods.list_saved() == []
    refute has_element?(view, "[data-role='performance-skeleton']")
    assert performance_ttwror(view) == api_percent("1y")
  end

  # User story:
  # As the operator whose agent deleted the own period the dashboard shows,
  # I want the page to read the default period from then on instead of
  # failing,
  # so that a pin or an edit still works.
  #
  # Acceptance criteria:
  # - On `?period=saved:<id>`, the period deleted elsewhere: a pin from a
  #   widget's ⋯ menu is stored, the page lives on, Gesamtwert follows 1J
  #   with the API's figure, and Tops und Flops reads the 1J window.
  test "a dashboard period deleted elsewhere reads as the default on the next action",
       %{conn: conn} do
    seed()
    own = own!("Mine", Date.new!(@year, 2, 1))
    key = "saved:#{own.id}"

    dashboard =
      dashboard!([
        %{"kind" => "total_value", "size" => "S", "col" => 1, "row" => 1},
        %{"kind" => "performance", "size" => "L", "col" => 4, "row" => 1},
        %{"kind" => "movers", "size" => "L", "col" => 1, "row" => 5}
      ])

    {:ok, view, _html} =
      conn |> german() |> live("/dashboards/#{dashboard.id}?period=" <> key)

    render_async(view)
    {:ok, _} = Periods.delete_saved(Actor.api_token_rw("mcp"), own.id)

    pin_menu(view, "performance")

    view
    |> element("#dashboard-period-menu [data-role='period-option'][data-period='ytd']")
    |> render_click()

    render_async(view)

    stored =
      dashboard.id
      |> Dashboards.get_dashboard()
      |> Map.fetch!(:layout)
      |> Enum.find(&(&1["kind"] == "performance"))

    assert get_in(stored, ["settings", "period"]) == "ytd"
    assert performance_ttwror(view) == api_percent("ytd")
    assert tag_text(view, "total_value") == "folgt · 1J"
    assert total_change(view) =~ api_percent("1y")
    assert has_element?(view, "#dashboard-movers[data-window='1y']")
  end

  # User story:
  # As the operator saving an own period while another of my quick choice
  # was deleted elsewhere,
  # I want the quick choice stored without the deleted one,
  # so that the save neither fails nor blames a full quick choice.
  #
  # Acceptance criteria:
  # - Quick choice 1W, A, B; A deleted elsewhere; B saved with „in der
  #   Schnellwahl“ unticked: the page lives on, the quick choice is 1W.
  # - Quick choice 1W, A; A deleted elsewhere; B saved ticked: the quick
  #   choice is 1W, B, and the status line says B is stored and applied.
  test "a save stores the quick choice without a period deleted elsewhere", %{conn: conn} do
    seed()
    a = own!("Alpha", Date.new!(@year, 2, 1))
    b = own!("Beta", Date.new!(@year, 3, 1))
    a_key = "saved:#{a.id}"
    b_key = "saved:#{b.id}"
    {:ok, _} = Periods.put_quick_choice(Actor.owner_ui(), ["1w", a_key, b_key])

    {:ok, view, _html} = conn |> german() |> live("/")
    {:ok, _} = Periods.delete_saved(Actor.api_token_rw("mcp"), a.id)

    toggle(view)
    edit(view, b_key)
    save(view, "Beta", Date.new!(@year, 4, 1), "false")

    assert Periods.quick_choice().keys == ["1w"]
    assert %{from: from} = Periods.get_saved(b.id)
    assert from == Date.new!(@year, 4, 1)
    assert has_element?(view, "[data-role='period-say']", "Beta")

    c = own!("Gamma", Date.new!(@year, 5, 1))
    c_key = "saved:#{c.id}"
    {:ok, _} = Periods.put_quick_choice(Actor.owner_ui(), ["1w", c_key])

    {:ok, view, _html} = conn |> german() |> live("/")
    {:ok, _} = Periods.delete_saved(Actor.api_token_rw("mcp"), c.id)

    toggle(view)
    edit(view, b_key)
    save(view, "Beta", Date.new!(@year, 4, 1), "true")

    assert Periods.quick_choice().keys == ["1w", b_key]
    refute has_element?(view, "[data-role='period-say']", "höchstens")
    assert has_element?(view, "[data-role='period-say']", "Beta")
  end

  # User story:
  # As the operator starring a period while one of my quick choice was
  # deleted elsewhere,
  # I want the star stored without the deleted one,
  # so that no star fails until a reload.
  #
  # Acceptance criteria:
  # - Quick choice 1W, A; A deleted elsewhere; ☆ on Max: the quick choice
  #   is 1W, Max, and the status line says Max joined it.
  test "a star stores the quick choice without a period deleted elsewhere", %{conn: conn} do
    seed()
    a = own!("Alpha", Date.new!(@year, 2, 1))
    {:ok, _} = Periods.put_quick_choice(Actor.owner_ui(), ["1w", "saved:#{a.id}"])

    {:ok, view, _html} = conn |> german() |> live("/")
    {:ok, _} = Periods.delete_saved(Actor.api_token_rw("mcp"), a.id)

    toggle(view)
    view |> element("[data-role='period-star'][data-period='max']") |> render_click()

    assert Periods.quick_choice().keys == ["1w", "max"]
    refute has_element?(view, "[data-role='period-say']", "Schnellwahl konnte")
    assert has_element?(view, "[data-role='period-say']", "Max")
  end
end
