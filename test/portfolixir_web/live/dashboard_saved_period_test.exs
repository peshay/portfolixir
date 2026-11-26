defmodule PortfolixirWeb.DashboardSavedPeriodTest do
  # Sprint 32 T2 and T5 (I59; ADR-0062's amendment of 2026-11-25, point 6):
  # an own period on the dashboard — in the address, and as a widget's pin
  # by reference — each widget reading it by its kind's rule, its figure
  # the API's for the same key. Every name and figure is synthetic.
  #
  # group: :periods -- a period's create takes the advisory lock that counts
  # the stored periods (`Portfolixir.LockTable` row 31); every module that
  # creates one joins this group. A dashboard, where one is made, is made
  # after the period, so the two count locks are always taken in one order.
  use PortfolixirWeb.ConnCase, async: true, group: :periods

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards
  alias Portfolixir.Periods
  alias PortfolixirWeb.Format

  defp seed do
    world = base_world()

    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    first = Date.new!(Clock.today().year - 1, 1, 10)
    buy!(world, security, quantity: "10", price: "100", date: first)
    put_quote!(security, first, "100")
    put_quote!(security, Date.new!(Clock.today().year - 1, 9, 30), "110")
    put_quote!(security, Clock.today(), "120")
    world
  end

  defp german(conn), do: put_preference_cookie(conn, "portfolixir_locale", "de")

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp document(view), do: view |> render() |> Floki.parse_document!()

  defp tag_text(view, kind) do
    view
    |> document()
    |> Floki.find("[data-widget-kind='#{kind}'] [data-role='widget-period']")
    |> text()
  end

  defp api(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  # User story (T2):
  # As the operator handing over a link on my own period,
  # I want the dashboard to open on it, each widget reading it by its
  # kind's rule and naming it by its name,
  # so that „Seit Umschichtung“ means the same on the screen and the API.
  #
  # Acceptance criteria:
  # - `/?period=saved:<id>` opens on it: „Gesamtwert“ says „folgt · Seit
  #   Umschichtung“ and its change line's TTWROR is the one
  #   GET /api/v1/performance answers for `period=saved:<id>`.
  # - Tops und Flops reads the window nearest the span and says so:
  #   „folgt · Seit Umschichtung → 1J“.
  # - A deleted period's key opens 1J.
  test "an own period in the address: its name, its figure the API's, tops and flops by length",
       %{conn: conn} do
    seed()

    {:ok, period} =
      Periods.create_saved(Actor.owner_ui(), %{
        "name" => "Seit Umschichtung",
        "from" => Date.new!(Clock.today().year - 1, 3, 1)
      })

    key = "saved:#{period.id}"
    {:ok, view, _html} = conn |> german() |> live("/?period=" <> key)
    render_async(view)

    assert tag_text(view, "total_value") == "folgt · Seit Umschichtung"
    assert tag_text(view, "movers") == "folgt · Seit Umschichtung → 1J"
    assert has_element?(view, "#dashboard-movers[data-window='1y']")

    figure =
      view
      |> document()
      |> Floki.find("[data-widget-kind='total_value'] [data-role='card-period-change']")
      |> text()

    ttwror = api("/api/v1/performance?period=" <> key)["ttwror"]
    assert figure =~ PortfolixirWeb.Format.signed_percent(Decimal.new(ttwror)) <> "%"
    assert figure =~ "TTWROR · Seit Umschichtung"

    {:ok, _} = Periods.delete_saved(Actor.owner_ui(), period.id)
    {:ok, view, _html} = conn |> german() |> live("/?period=" <> key)
    assert tag_text(view, "total_value") == "folgt · 1J"
  end

  # --- T5: a pin by reference ----------------------------------------------

  @layout [
    %{"kind" => "total_value", "size" => "S", "col" => 1, "row" => 1},
    %{"kind" => "performance", "size" => "L", "col" => 4, "row" => 1},
    %{"kind" => "movers", "size" => "L", "col" => 1, "row" => 5}
  ]

  defp own!(name, from, to \\ nil) do
    {:ok, own} =
      Periods.create_saved(Actor.owner_ui(), %{"name" => name, "from" => from, "to" => to})

    own
  end

  defp dashboard!(name) do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => name, "layout" => @layout})

    dashboard
  end

  # Opens the widget's ⋯ „Zeitraum festpinnen“, which opens the period
  # menu for it, and picks `key` there.
  defp pin(view, kind, key) do
    view |> element("[data-widget-kind='#{kind}'] [data-role='pin-menu']") |> render_click()
    assert has_element?(view, "#dashboard-period-menu[data-pin-kind='#{kind}']")

    view
    |> element("#dashboard-period-menu [data-role='period-option'][data-period='#{key}']")
    |> render_click()
  end

  defp stored_pin(id, kind) do
    id
    |> Dashboards.get_dashboard()
    |> Map.fetch!(:layout)
    |> Enum.find(&(&1["kind"] == kind))
    |> get_in(["settings", "period"])
  end

  defp foot(view, kind),
    do:
      view
      |> document()
      |> Floki.find("[data-widget-kind='#{kind}'] [data-role='widget-pin-dangling']")
      |> text()

  # The figures each kind draws for its pin, beside the API's for the same
  # key: the total's change line and the performance's TTWROR are
  # GET /api/v1/performance?period=<key>'s; tops and flops read the window
  # their rule names and show GET /api/v1/movers?window=<window>'s first
  # price return.
  defp assert_figures_are_the_api(view, key, window) do
    render_async(view)
    doc = document(view)
    ttwror = api("/api/v1/performance?period=" <> URI.encode_www_form(key))["ttwror"]
    percent = Format.signed_percent(Decimal.new(ttwror)) <> "%"

    assert doc
           |> Floki.find("[data-widget-kind='total_value'] [data-role='card-period-change']")
           |> text() =~
             percent

    assert doc
           |> Floki.find("[data-widget-kind='performance'] [data-role='performance-ttwror']")
           |> text() ==
             percent

    assert [_] = Floki.find(doc, "#dashboard-movers[data-window='#{window}']")
    movers = api("/api/v1/movers?window=#{window}")

    shown =
      doc
      |> Floki.find(
        "#dashboard-movers [data-role='movers-return'] [data-half='highest'] [data-role='movers-figure']"
      )
      |> Enum.map(&text/1)

    expected =
      Enum.map(
        movers["price_return"]["highest"],
        &(Format.signed_percent(Decimal.new(&1["return"])) <> "%")
      )

    assert Enum.take(shown, length(expected)) == expected
  end

  # User story (T5):
  # As the operator pinning a widget to my own period,
  # I want „Zeitraum festpinnen“ to open the same menu as the top bar, and
  # the pin to name the period by reference,
  # so that a change to „Seit Umschichtung“ reaches every widget pinned to
  # it.
  #
  # Acceptance criteria:
  # - The ⋯ menu's „Zeitraum festpinnen“ opens the period menu for that
  #   widget; a pick there stores the pin in the item's settings, an own
  #   period as `saved:<id>`, and the widget says „📌 eigener: <name>“.
  # - Per kind, for a calendar key and for an own period, the widget's
  #   figure is its route's for the same key (the total's change line and
  #   the performance's TTWROR GET /api/v1/performance's, tops and flops
  #   GET /api/v1/movers's for the window their rule names).
  # - A change to the own period reaches the pinned widget.
  test "a pin opens the same menu, stores an own period by reference, and each kind reads its route",
       %{conn: conn} do
    seed()
    own = own!("Seit Umschichtung", Date.new!(Clock.today().year - 1, 3, 1))
    key = "saved:#{own.id}"
    dashboard = dashboard!("Pins")
    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{dashboard.id}")
    render_async(view)

    for kind <- ~w(total_value performance movers), do: pin(view, kind, "prev_quarter")

    for kind <- ~w(total_value performance movers),
        do: assert(stored_pin(dashboard.id, kind) == "prev_quarter")

    assert tag_text(view, "performance") == "📌 eigener: Vorquartal"
    assert_figures_are_the_api(view, "prev_quarter", "quarter")

    for kind <- ~w(total_value performance movers), do: pin(view, kind, key)

    for kind <- ~w(total_value performance movers),
        do: assert(stored_pin(dashboard.id, kind) == key)

    assert tag_text(view, "performance") == "📌 eigener: Seit Umschichtung"
    assert tag_text(view, "movers") == "📌 eigener: Seit Umschichtung → 1J"
    assert_figures_are_the_api(view, key, "1y")

    {:ok, _} =
      Periods.replace_saved(Actor.api_token_rw("mcp"), own.id, %{
        "name" => "Letzte Wochen",
        "from" => Date.to_iso8601(Date.add(Clock.today(), -6)),
        "to" => nil,
        "lock_version" => own.lock_version
      })

    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{dashboard.id}")
    assert tag_text(view, "performance") == "📌 eigener: Letzte Wochen"
    assert tag_text(view, "movers") == "📌 eigener: Letzte Wochen → Woche"
    assert_figures_are_the_api(view, key, "week")
  end

  # User story (T5):
  # As the operator whose own period was deleted,
  # I want the widgets pinned to it to read the top bar's period and say
  # so, and the next save to let the pin go,
  # so that no widget reads a period that is not there, and none is lost
  # unseen.
  #
  # Acceptance criteria:
  # - The pinned widget follows the top bar („folgt · 1J“) and its footer
  #   says „eigener Zeitraum gelöscht · folgt 1J“; the stored pin is left
  #   as it is (a read never writes).
  # - The next save of the dashboard (another widget's pin) drops it, as a
  #   stale view is dropped; a new pin naming no own period is refused.
  test "a deleted own period leaves the pin dangling, said in the footer, dropped on the next save",
       %{conn: conn} do
    seed()
    own = own!("Sommer", "2025-06-01", "2025-08-31")
    key = "saved:#{own.id}"
    dashboard = dashboard!("Dangling")

    layout =
      Enum.map(@layout, fn
        %{"kind" => "performance"} = item -> Map.put(item, "settings", %{"period" => key})
        item -> item
      end)

    {:ok, dashboard} =
      Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, %{
        "name" => dashboard.name,
        "layout" => layout,
        "lock_version" => dashboard.lock_version
      })

    {:ok, _} = Periods.delete_saved(Actor.owner_ui(), own.id)

    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{dashboard.id}")
    render_async(view)
    assert tag_text(view, "performance") == "folgt · 1J"
    assert foot(view, "performance") == "eigener Zeitraum gelöscht · folgt 1J"
    assert stored_pin(dashboard.id, "performance") == key

    pin(view, "movers", "ytd")
    assert stored_pin(dashboard.id, "movers") == "ytd"
    assert stored_pin(dashboard.id, "performance") == nil
    assert foot(view, "performance") == ""

    stored = Dashboards.get_dashboard(dashboard.id)

    refused =
      Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, %{
        "name" => stored.name,
        "layout" =>
          Enum.map(stored.layout, fn
            %{"kind" => "performance"} = item -> put_in(item, ["settings", "period"], key)
            item -> item
          end),
        "lock_version" => stored.lock_version
      })

    assert {:error, %Ecto.Changeset{errors: [layout: {_message, meta}]}} = refused
    assert meta[:reason] == :unknown_period
    assert meta[:field] == "settings.period"
  end

  # User story (T5):
  # As the operator whose widget is pinned to a period that has not begun
  # yet — a year to come, or a quarter pinned last year that the new year
  # has not reached —,
  # I want the widget to read the top bar's period and say why,
  # so that no widget shows an empty span as if it were a figure.
  #
  # Acceptance criteria:
  # - The pinned widget follows the top bar („folgt · 1J“) and its footer
  #   says „festgepinnter Zeitraum noch nicht begonnen · folgt 1J“; its
  #   figure is the one GET /api/v1/performance answers for the bar's 1y.
  # - The stored pin is left as it is (a read never writes); a widget
  #   without a pin says nothing.
  test "a pin on a period not yet begun follows the top bar and says why", %{conn: conn} do
    seed()
    next_year = "year:#{Clock.today().year + 1}"

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Voraus",
        "layout" =>
          Enum.map(@layout, fn
            %{"kind" => "performance"} = item ->
              Map.put(item, "settings", %{"period" => next_year})

            item ->
              item
          end)
      })

    {:ok, view, _html} = conn |> german() |> live("/dashboards/#{dashboard.id}")
    render_async(view)

    assert tag_text(view, "performance") == "folgt · 1J"

    assert foot(view, "performance") ==
             "festgepinnter Zeitraum noch nicht begonnen · folgt 1J"

    ttwror = api("/api/v1/performance?period=1y")["ttwror"]

    assert view
           |> document()
           |> Floki.find("[data-widget-kind='performance']")
           |> text() =~ Format.signed_percent(Decimal.new(ttwror)) <> "%"

    assert stored_pin(dashboard.id, "performance") == next_year
    assert foot(view, "movers") == ""
  end
end
