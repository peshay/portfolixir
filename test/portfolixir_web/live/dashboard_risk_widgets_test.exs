defmodule PortfolixirWeb.DashboardRiskWidgetsTest do
  # Sprint 32 W4 (I57; ADR-0062's amendment of 2026-11-25, points 3, 5 and
  # 7; plan D-7; planning board ux-design-2026-11-25-sprint32/02 ②): the
  # sections of Wealth's tab „Risiko“ as section widgets, and the starter
  # „Risiko“. Each widget's module draws its section on the tab and on a
  # dashboard, so one code path draws both, and every figure it draws is
  # compared with its route's for the same scope. The rule dialog, the
  # crash benchmark and the crash windows are set on the tab, linked. No
  # verdict (ADR-0047 §7; metrics_carry_no_verdict_test.exs walks the
  # kinds). Synthetic data only.
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Crashes
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Starters
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Repo
  alias PortfolixirWeb.Dashboard.Widgets.OwnRules, as: OwnRulesWidget
  alias PortfolixirWeb.Dashboard.Widgets.RiskLens, as: RiskLensWidget
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.WidgetsLive

  @kinds ~w(own_rules key_figures crash_section top_holdings concentration asset_class_limits)

  defp api(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp dashboard!(items) do
    layout =
      items
      |> Enum.with_index()
      |> Enum.map(fn {{kind, size}, index} ->
        %{"kind" => kind, "size" => size, "col" => 1, "row" => 1 + index * 4}
      end)

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Risiko", "layout" => layout})

    dashboard
  end

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    render_async(view)
    view
  end

  defp doc(view), do: view |> render() |> Floki.parse_document!()

  # Three equities and an ETF bought, quoted over a stretch with a fall in
  # it, and a hard cap of 10 % on the largest single name.
  defp world do
    today = Clock.today()
    world = base_world(name: "Risiko")
    deposit!(world, "20000", Date.add(today, -120))

    nordic = create_security!(name: "Nordic Grid AB", ticker: "NGA", asset_class: "equity")
    helios = create_security!(name: "Helios Solar SE", ticker: "HSS", asset_class: "equity")
    fjord = create_security!(name: "Fjord Freight ASA", ticker: "FFA", asset_class: "equity")
    world_etf = create_security!(name: "Welt Index ETF", ticker: "WIE", asset_class: "etf")

    for {security, quantity, price} <- [
          {nordic, "40", "100"},
          {helios, "20", "50"},
          {fjord, "30", "20"},
          {world_etf, "50", "80"}
        ] do
      buy!(world, security, quantity: quantity, price: price, date: Date.add(today, -110))
    end

    put_quotes!(nordic, [
      {Date.add(today, -110), "100"},
      {Date.add(today, -80), "80"},
      {Date.add(today, -60), "95"},
      {today, "120"}
    ])

    put_quotes!(helios, [
      {Date.add(today, -110), "50"},
      {Date.add(today, -80), "46"},
      {Date.add(today, -60), "52"},
      {today, "55"}
    ])

    put_quotes!(fjord, [
      {Date.add(today, -110), "20"},
      {Date.add(today, -80), "12"},
      {Date.add(today, -60), "15"},
      {today, "18"}
    ])

    put_quotes!(world_etf, [
      {Date.add(today, -110), "80"},
      {Date.add(today, -80), "76"},
      {Date.add(today, -60), "79"},
      {today, "84"}
    ])

    {:ok, rule} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          view_id: nil,
          name: "Nordic cap",
          version: %{
            subject_type: "security",
            security_id: nordic.id,
            measure: "weight",
            kind: "cap",
            threshold: "10",
            severity: "hard"
          }
        },
        today: today
      )

    {:ok, window} =
      Crashes.create_manual_window(Actor.owner_ui(), %{
        "name" => "Synthetic Spring Fall",
        "start" => Date.to_iso8601(Date.add(today, -110)),
        "trough" => Date.to_iso8601(Date.add(today, -80))
      })

    Map.merge(world, %{nordic: nordic, rule: rule, window: "m:#{window.id}"})
  end

  describe "the registry" do
    # User story:
    # As the operator, or the agent I run, composing a dashboard,
    # I want the six sections of „Risiko“ registered as kinds,
    # so that a layout can name them and the catalogue lists their reads.
    #
    # Acceptance criteria:
    # - own_rules, key_figures (Zeile, M), crash_section, top_holdings,
    #   concentration (Zeile, S) and asset_class_limits are registered,
    #   group risk, with the German titles board 02 ② draws; none takes a
    #   period; all but crash_section take a view (the crash section reads
    #   the view's holdings too: it takes one).
    # - key_figures, concentration and asset_class_limits, which the
    #   catalogue listed as coming, are no later kinds any more; GET
    #   /api/v1/widgets names all six.
    test "names the six sections with their sizes, titles and routes" do
      sizes = %{
        "own_rules" => ~w(row),
        "key_figures" => ~w(M row),
        "crash_section" => ~w(row),
        "top_holdings" => ~w(row),
        "concentration" => ~w(S row),
        "asset_class_limits" => ~w(row)
      }

      german = %{
        "own_rules" => "Eigene Regeln",
        "key_figures" => "Kennzahlen des Portfolios",
        "crash_section" => "Crashes",
        "top_holdings" => "Größte Einzelpositionen",
        "concentration" => "Klumpenrisiko",
        "asset_class_limits" => "Anlageklassen-Obergrenzen"
      }

      for key <- @kinds do
        assert {:ok, kind} = Widgets.fetch(key), key
        assert kind.sizes == sizes[key], key
        assert kind.group == "risk", key
        assert kind.period == :none, key
        assert kind.scope == :view, key

        Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
          assert Widgets.title(key) == german[key]
        end)
      end

      {:ok, lens} = Widgets.fetch("top_holdings")
      assert lens.source.routes == ["GET /api/v1/portfolios/:portfolio_id/risk"]
      {:ok, rules} = Widgets.fetch("own_rules")
      assert "GET /api/v1/portfolios/:portfolio_id/policy_findings" in rules.source.routes
      {:ok, crashes} = Widgets.fetch("crash_section")
      assert "GET /api/v1/crashes/:key/rankings" in crashes.source.routes

      later = Enum.map(WidgetsLive.later_kinds(), & &1.key)
      for key <- ~w(key_figures concentration asset_class_limits), do: refute(key in later)

      catalogue = Enum.map(api("/api/v1/widgets")["widgets"], & &1["key"])
      for key <- @kinds, do: assert(key in catalogue, key)
    end
  end

  describe "the lens' sections" do
    # User story:
    # As the operator who keeps „Risiko“ as a dashboard,
    # I want the largest single names, the HHI, the caps and the portfolio
    # metrics as widgets,
    # so that they stand on my dashboard as the tab shows them, each figure
    # the API's.
    #
    # Acceptance criteria:
    # - „Größte Einzelpositionen“ lists GET /api/v1/portfolios/:id/risk's
    #   top_holdings in order, each weight and value as the read gives it;
    #   the tab lists the same rows with the same module.
    # - „Klumpenrisiko“ shows the read's HHI and band; at S without the
    #   scale line.
    # - „Kennzahlen des Portfolios“ shows the volatility, the drawdown, the
    #   risk-adjusted return and the correlations' card as the tab does; at
    #   M the first three as headline figures (the volatility the read's),
    #   no correlations and no basis line.
    # - „Anlageklassen-Obergrenzen“ says no cap is configured and holds the
    #   correlations as the tab does.
    test "draw the lens' figures as the API and the tab do", %{conn: conn} do
      w = world()

      dashboard!([
        {"top_holdings", "row"},
        {"concentration", "row"},
        {"concentration", "S"},
        {"key_figures", "row"},
        {"key_figures", "M"},
        {"asset_class_limits", "row"}
      ])

      risk = api("/api/v1/portfolios/#{w.portfolio.id}/risk")
      page = conn |> open("/") |> doc()
      tab = conn |> open("/risk") |> doc()

      rows = Floki.find(page, "#dashboard-top-holdings table tbody tr")

      assert Enum.map(rows, &hd(Floki.attribute(&1, "data-security-id"))) ==
               Enum.map(risk["top_holdings"], &to_string(&1["security_id"]))

      for {row, holding} <- Enum.zip(rows, risk["top_holdings"]) do
        cells = row |> Floki.find("td") |> Enum.map(&text/1)
        assert Enum.at(cells, 0) == holding["security_name"]

        assert Enum.at(cells, 2) ==
                 Format.money(Decimal.new(holding["market_value"])) <>
                   " " <> risk["base_currency"]

        assert Enum.at(cells, 3) ==
                 Format.plain_decimal(Decimal.new(holding["weight"]), 1) <> " %"
      end

      assert text(Floki.find(tab, "#risk-top-holdings tbody")) ==
               text(Floki.find(page, "#dashboard-top-holdings table tbody"))

      hhi = Floki.find(page, "#dashboard-concentration [data-role='risk-hhi'] strong")
      assert [band] = Floki.attribute(hhi, "data-band")
      assert band == risk["hhi"]["band"]
      assert text(hhi) =~ Format.plain_decimal(Decimal.new(risk["hhi"]["value"]), 0)

      assert text(Floki.find(tab, "[data-role='risk-hhi']")) ==
               text(Floki.find(page, "#dashboard-concentration [data-role='risk-hhi']"))

      assert Floki.find(page, "#dashboard-concentration-2 [data-role='risk-hhi'] .stat__sub") ==
               []

      for role <- ~w(volatility max-drawdown risk-adjusted-return correlations) do
        selector = "[data-role='risk-metric-#{role}']"

        assert text(Floki.find(tab, selector)) ==
                 text(Floki.find(page, "#dashboard-key-figures " <> selector)),
               role
      end

      assert Floki.find(page, "#dashboard-key-figures-2 [data-role='risk-metric-correlations']") ==
               []

      assert Floki.find(page, "#dashboard-key-figures-2 [data-role='risk-basis']") == []

      volatility = risk["metrics"]["volatility"]["365d"]

      m_volatility =
        if volatility["insufficient_data"],
          do: "not computable",
          else: Format.percent(Decimal.new(volatility["value"])) <> " %"

      assert text(Floki.find(page, "#dashboard-key-figures-2 [data-role='risk-m-volatility']")) =~
               m_volatility

      for role <- ~w(max-drawdown risk-adjusted-return),
          do:
            assert(
              [_] = Floki.find(page, "#dashboard-key-figures-2 [data-role='risk-m-#{role}']")
            )

      caps = Floki.find(page, "#dashboard-asset-class-limits")
      assert text(caps) =~ "No cap configured"

      assert text(Floki.find(tab, "#risk-correlations")) ==
               text(Floki.find(caps, "details.perf-table-disclosure"))
    end
  end

  describe "the lens' sections on a spread, young book (Sprint 32 closing act, coverage)" do
    # Seven names bought five days ago at 100, quoted flat: two ETFs at 35
    # and 25 units, five equities at 9, 9, 8, 8 and 6. The HHI lands
    # between the bands' lines and the history is too short for any
    # metric.
    defp spread_world do
      today = Clock.today()
      world = base_world(name: "Streuung")
      deposit!(world, "20000", Date.add(today, -6))

      names = [
        {"Alder Index ETF", "35", "etf"},
        {"Birch Index ETF", "25", "etf"},
        {"Cedar Mills AG", "9", "equity"},
        {"Dogwood Rail SA", "9", "equity"},
        {"Elm Shipping NV", "8", "equity"},
        {"Fir Optics AB", "8", "equity"},
        {"Ginkgo Labs Ltd", "6", "equity"}
      ]

      for {{name, quantity, asset_class}, index} <- Enum.with_index(names) do
        security =
          create_security!(name: name, ticker: "SP#{index}", asset_class: asset_class)

        buy!(world, security, quantity: quantity, price: "100", date: Date.add(today, -5))
        put_quotes!(security, [{Date.add(today, -5), "100"}, {today, "100"}])
      end

      world
    end

    # User story:
    # As the operator whose book is spread and young,
    # I want the lens' widgets to name the band, the threshold each name
    # is above or below, and every metric the history cannot carry yet,
    # so that a figure is never shown where the read refuses one.
    #
    # Acceptance criteria:
    # - „Klumpenrisiko“ names GET /api/v1/portfolios/:id/risk's band
    #   „moderate“ and its HHI.
    # - „Größte Einzelpositionen“ marks each name with the read's severity:
    #   an equity at 9 % is „above 7 %“ (the warn line).
    # - „Kennzahlen des Portfolios“ at M says „not computable“ for the
    #   volatility and the risk-adjusted return, with the observations the
    #   read had and needed, and shows the drawdown the read computes.
    test "name the moderate band, the warn line and the refused metrics",
         %{conn: conn} do
      w = spread_world()

      dashboard!([
        {"concentration", "row"},
        {"top_holdings", "row"},
        {"key_figures", "M"}
      ])

      risk = api("/api/v1/portfolios/#{w.portfolio.id}/risk")
      assert risk["hhi"]["band"] == "moderate"
      page = conn |> open("/") |> doc()

      hhi = Floki.find(page, "#dashboard-concentration [data-role='risk-hhi'] strong")
      assert Floki.attribute(hhi, "data-band") == ["moderate"]
      assert text(hhi) =~ Format.plain_decimal(Decimal.new(risk["hhi"]["value"]), 0)
      assert text(hhi) =~ "moderate"

      rows = Floki.find(page, "#dashboard-top-holdings table tbody tr")

      for {row, holding} <- Enum.zip(rows, risk["top_holdings"]) do
        badge = Floki.find(row, "[data-severity]")
        assert Floki.attribute(badge, "data-severity") == [holding["severity"]]
      end

      cedar = Enum.find(rows, &(text(&1) =~ "Cedar Mills AG"))
      cedar_holding = Enum.find(risk["top_holdings"], &(&1["security_name"] == "Cedar Mills AG"))
      assert cedar_holding["severity"] == "warn"
      assert text(Floki.find(cedar, "[data-severity]")) == "above 7 %"

      metrics = risk["metrics"]

      m = fn role ->
        text(Floki.find(page, "#dashboard-key-figures [data-role='risk-m-#{role}']"))
      end

      for {role, metric} <- [
            {"volatility", metrics["volatility"]["365d"]},
            {"risk-adjusted-return", metrics["risk_adjusted_return"]["365d"]}
          ] do
        assert metric["insufficient_data"], role
        assert m.(role) =~ "not computable", role
        assert m.(role) =~ "#{metric["observations"]} of #{metric["required"]} observations", role
      end

      # The drawdown needs two observations, which five flat days give: no
      # fall, read as the read's 0, unsigned.
      drawdown = metrics["max_drawdown"]["365d"]
      refute drawdown["insufficient_data"]

      assert m.("max-drawdown") =~
               Format.plain_signed_decimal(Decimal.mult(Decimal.new(drawdown["value"]), 100), 1) <>
                 " %"
    end
  end

  describe "the lens on a view and on a vanished view (Sprint 32 closing act, coverage)" do
    # User story:
    # As the operator whose dashboard reads one view,
    # I want the risk widgets' way to the tab to keep that view, and a
    # view deleted meanwhile to read Everything,
    # so that the tab opens on what the widget showed and a deleted view
    # never leaves a widget without figures.
    #
    # Acceptance criteria:
    # - On a dashboard scoped to a view, „Ganze Ansicht“ of a lens widget
    #   and of „Eigene Regeln“ opens /risk?view=<id>.
    # - The lens' and the rules' read for a view that no longer exists
    #   answer what they answer for Everything.
    test "the way to the tab keeps the view, and a deleted view reads Everything",
         %{conn: conn} do
      w = world()

      {:ok, scope} =
        Buckets.create_view(Actor.owner_ui(), %{name: "Alles drin", include_all: true})

      {:ok, _} =
        Dashboards.create_dashboard(Actor.owner_ui(), %{
          "name" => "Ansicht",
          "view_id" => scope.id,
          "layout" => [
            %{"kind" => "concentration", "size" => "row", "col" => 1, "row" => 1},
            %{"kind" => "own_rules", "size" => "row", "col" => 1, "row" => 5}
          ]
        })

      page = conn |> open("/") |> doc()
      href = "/risk?view=#{scope.id}"
      assert [_] = Floki.find(page, "#dashboard-concentration a[href='#{href}']")
      assert [_] = Floki.find(page, "#dashboard-own-rules a[href='#{href}']")

      {:ok, gone} = Buckets.create_view(Actor.owner_ui(), %{name: "Weg", include_all: true})
      {:ok, _} = Buckets.delete_view(Actor.owner_ui(), gone)

      lens = RiskLensWidget.load(w.portfolio.id, gone.id)
      everything = RiskLensWidget.load(w.portfolio.id, nil)
      assert lens.hhi == everything.hhi
      assert lens.top_holdings == everything.top_holdings

      rules = OwnRulesWidget.load(w.portfolio.id, gone.id)
      assert rules.findings == OwnRulesWidget.load(w.portfolio.id, nil).findings
      assert [%{name: "Nordic cap"}] = Enum.map(rules.rules, &%{name: &1.name})
    end
  end

  describe "Eigene Regeln (own_rules)" do
    # User story:
    # As the operator who checks my own rules on a dashboard,
    # I want the findings as the tab shows them,
    # so that a breached rule stands where I look, its figure the API's,
    # while a rule is made and changed on the tab.
    #
    # Acceptance criteria:
    # - The findings are GET /api/v1/portfolios/:id/policy_findings', each
    #   rule's name and state; the counts head the widget; the tab draws
    #   the same rows with the same module.
    # - On the dashboard a rule's name opens no dialog (no edit event);
    #   „Regeln bearbeiten →“ leads to the tab.
    test "draws the findings as the API and the tab do, the dialog left on the tab",
         %{conn: conn} do
      w = world()
      dashboard!([{"own_rules", "row"}])
      findings = api("/api/v1/portfolios/#{w.portfolio.id}/policy_findings")

      widget = conn |> open("/") |> doc() |> Floki.find("#dashboard-own-rules")
      rows = Floki.find(widget, "table tbody tr")

      assert Enum.map(rows, &hd(Floki.attribute(&1, "data-state"))) ==
               Enum.map(findings["findings"], & &1["state"])

      assert text(Floki.find(widget, "[data-role='policy-rule-name']")) == "Nordic cap"
      assert text(Floki.find(widget, "[data-role='policy-rules-summary']")) =~ "1 breached"
      assert Floki.find(widget, "[phx-click='edit_rule'], [phx-click='new_rule']") == []
      assert [_] = Floki.find(widget, "a[href='/risk'][data-role='own-rules-edit']")

      tab = conn |> open("/risk") |> doc()

      assert Enum.map(
               Floki.find(tab, "#policy-findings tbody tr"),
               &(&1 |> Floki.find("td") |> Enum.drop(1) |> text())
             ) ==
               Enum.map(rows, &(&1 |> Floki.find("td") |> Enum.drop(1) |> text()))
    end
  end

  describe "Crashes (crash_section)" do
    # User story:
    # As the operator who watches falls from a dashboard,
    # I want the tab's whole section „Crashes“ as a widget,
    # so that the window, the list and the universe answer there as on the
    # tab, each list the API's, while the windows are set on the tab.
    #
    # Acceptance criteria:
    # - It opens on the newest window, „Im Depot“ and the losers: its rows
    #   are GET /api/v1/crashes/:key/rankings?universe=held&list=losers',
    #   rank, security and return.
    # - „Gewinner“ answers the winners' list in the widget; nothing is
    #   stored and the address does not change.
    # - The windows' disclosure and its forms stay on the tab: none is
    #   drawn; a write pushed by hand changes nothing.
    test "answers the window, the list and the universe as the API does", %{conn: conn} do
      w = world()
      dashboard = dashboard!([{"crash_section", "row"}])
      view = open(conn, "/")

      rows = fn view ->
        view
        |> doc()
        |> Floki.find("#dashboard-crash-section table.crash-table tbody tr")
        |> Enum.map(fn row ->
          {hd(Floki.attribute(row, "data-rank")), hd(Floki.attribute(row, "data-security-id")),
           hd(Floki.attribute(row, "data-return"))}
        end)
      end

      ranking = fn list ->
        api(
          "/api/v1/crashes/#{URI.encode_www_form(w.window)}/rankings?universe=held&list=#{list}"
        )
      end

      expected = fn data ->
        Enum.map(data["entries"], fn entry ->
          {to_string(entry["rank"]), to_string(entry["security"]["id"]),
           Decimal.to_string(Decimal.new(entry["return"]))}
        end)
      end

      normalize = fn rows ->
        Enum.map(rows, fn {rank, id, ret} -> {rank, id, Decimal.to_string(Decimal.new(ret))} end)
      end

      losers = ranking.("losers")
      assert losers["entries"] != []
      assert normalize.(rows.(view)) == expected.(losers)

      view
      |> element("#dashboard-crash-section [data-list='winners']")
      |> render_click()

      assert normalize.(rows.(view)) == expected.(ranking.("winners"))
      assert has_element?(view, "#dashboard-crash-section [data-list='winners'].is-active")

      refute has_element?(view, "#dashboard-crash-section #crash-windows")
      refute has_element?(view, "#dashboard-crash-section details.crash-windows")
      assert has_element?(view, "#dashboard-crash-section a[href='/risk']")

      assert Repo.get!(Dashboard, dashboard.id).lock_version == dashboard.lock_version
    end
  end

  describe "Crashes (crash_section), its window and a write pushed by hand" do
    # User story (Sprint 32 closing act, PR 2, coverage):
    # As the operator who reads two falls from a dashboard,
    # I want the widget's window choice to answer in the widget, and a
    # write sent to it by hand to change nothing,
    # so that the dashboard reads every window while the windows are kept
    # on the tab alone.
    #
    # Acceptance criteria:
    # - With a second, later manual window the widget opens on it; choosing
    #   the earlier one lists GET
    #   /api/v1/crashes/:key/rankings?universe=held&list=losers' securities
    #   for that window.
    # - „crash_manual_delete“ pushed to the widget leaves the window
    #   stored; „crash_pick“ pushed to the tab's section, which takes its
    #   choices by address, changes nothing.
    test "a window chosen answers in the widget, and a write pushed by hand changes nothing",
         %{conn: conn} do
      w = world()
      today = Clock.today()

      {:ok, _later} =
        Crashes.create_manual_window(Actor.owner_ui(), %{
          "name" => "Synthetic Late Dip",
          "start" => Date.to_iso8601(Date.add(today, -60)),
          "trough" => Date.to_iso8601(Date.add(today, -30))
        })

      dashboard!([{"crash_section", "row"}])
      view = open(conn, "/")
      section = "#dashboard-crash-section"

      [form_id] =
        view
        |> doc()
        |> Floki.find("#{section} form[id$='crash-window-form']")
        |> Floki.attribute("id")

      # The later window opens; the earlier is chosen.
      assert text(Floki.find(doc(view), section)) =~ "No security with an answer."
      view |> form("#" <> form_id, %{"crash" => w.window}) |> render_change()

      ids =
        view
        |> doc()
        |> Floki.find("#{section} table.crash-table tbody tr")
        |> Enum.map(&hd(Floki.attribute(&1, "data-security-id")))

      ranking =
        api("/api/v1/crashes/#{URI.encode_www_form(w.window)}/rankings?universe=held&list=losers")

      assert ids == Enum.map(ranking["entries"], &to_string(&1["security"]["id"]))
      assert ids != []

      [component] = view |> doc() |> Floki.find("#{section} [data-phx-component]") |> Enum.take(1)
      target = "[data-phx-component='#{hd(Floki.attribute(component, "data-phx-component"))}']"

      view
      |> with_target(target)
      |> render_click("crash_manual_delete", %{"key" => w.window})

      # Still stored: its rankings still answer.
      assert api(
               "/api/v1/crashes/#{URI.encode_www_form(w.window)}/rankings?universe=held&list=losers"
             ) ==
               ranking

      {:ok, tab, _html} = live(conn, "/risk")
      render_async(tab)
      before = render(tab)

      tab
      |> with_target("#risk-crashes")
      |> render_click("crash_pick", %{"key" => "crash_list", "choice" => "winners"})

      assert render(tab) == before
    end
  end

  describe "the starter „Risiko“" do
    # User story:
    # As the operator after the update,
    # I want „Risiko“ among my dashboards, stored once,
    # so that the tab is there as a dashboard I can change.
    #
    # Acceptance criteria:
    # - The template `risk` is a starter and lists exactly board 02 ②'s
    #   widgets in the tab's order, each in the size „Zeile“: Eigene
    #   Regeln, Kennzahlen des Portfolios, Crashes, Größte
    #   Einzelpositionen, Klumpenrisiko, Anlageklassen-Obergrenzen.
    # - The boot stores it once with its template key; its title is
    #   „Risiko“ in German.
    test "lists exactly the board's widgets in order and is stored once" do
      assert {:ok, template} = Templates.fetch("risk")
      assert template.starter
      refute template.asks_scope

      assert Enum.map(template.layout, &{&1["kind"], &1["size"], &1["col"], &1["row"]}) ==
               @kinds
               |> Enum.with_index(1)
               |> Enum.map(fn {kind, row} -> {kind, "row", 1, row} end)

      Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
        assert Templates.title("risk") == "Risiko"
      end)

      assert {:ok, %{stored: stored}} = Starters.seed()
      assert "risk" in stored
      assert {:ok, %{stored: []}} = Starters.seed()

      assert [risk] = Enum.filter(Dashboards.list_dashboards(), &(&1.template_key == "risk"))
      assert Enum.map(risk.layout, & &1["kind"]) == @kinds
    end
  end
end
