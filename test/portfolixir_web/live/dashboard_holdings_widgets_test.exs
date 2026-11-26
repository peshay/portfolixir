defmodule PortfolixirWeb.DashboardHoldingsWidgetsTest do
  # Sprint 32 W1 (I57; ADR-0062's amendment of 2026-11-25, points 3 and 5;
  # plan D-7; planning board ux-design-2026-11-25-sprint32/02 ①): the
  # sections of Wealth's tab „Bestände“ as section widgets. Each widget's
  # module draws its section on Wealth and on a dashboard, so one code path
  # draws both, and every figure it draws is compared with its route's
  # for the same scope and period. Synthetic data only.
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards
  alias PortfolixirWeb.Format

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
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Bestände", "layout" => layout})

    dashboard
  end

  defp rendered(conn, path) do
    {:ok, view, _html} = live(conn, path)
    render_async(view)
    view |> render() |> Floki.parse_document!()
  end

  # Two portfolios, each with a cash account and a deposit, one security
  # bought, so the totals hold securities and cash.
  defp seed do
    today = Clock.today()
    home = base_world(name: "Home", cash_name: "Home Cash", depot_name: "Home Depot")
    away = base_world(name: "Away", cash_name: "Away Cash", depot_name: "Away Depot")
    deposit!(home, "12000.25", Date.add(today, -400))
    deposit!(away, "3000.10", Date.add(today, -300))
    security = create_security!(name: "Alpha Werke")
    put_quotes!(security, [{Date.add(today, -390), "100"}, {today, "112.5"}])
    buy!(home, security, quantity: "40", price: "100", date: Date.add(today, -390))
    %{home: home, away: away, security: security}
  end

  describe "Verrechnungskonten (cash_accounts)" do
    # User story:
    # As the operator who keeps Wealth's sections as a dashboard,
    # I want the section „Verrechnungskonten“ as a widget,
    # so that each cash account's balance stands on my dashboard as Wealth
    # shows it, and the same as the API answers.
    #
    # Acceptance criteria:
    # - At „Zeile“ it lists each cash account of the scope with its balance
    #   and currency, equal to GET /api/v1/valuation's cash_balances, in
    #   the order Wealth lists them; Wealth's section lists the same rows.
    # - At S it shows the scope's cash, GET /api/v1/valuation's total_cash,
    #   and how many accounts it sums.
    # - Setting a balance stays on Accounts & depots: the widget links there.
    test "draws each cash account's balance as Wealth and the valuation read do",
         %{conn: conn} do
      seed()
      dashboard!([{"cash_accounts", "row"}, {"cash_accounts", "S"}])
      valuation = api("/api/v1/valuation")
      doc = rendered(conn, "/")

      rows =
        Floki.find(doc, "#dashboard-cash-accounts [data-form='wide'] [data-role='cash-account']")

      assert Enum.map(rows, &hd(Floki.attribute(&1, "data-cash-account-id"))) ==
               Enum.map(valuation["cash_balances"], &to_string(&1["cash_account_id"]))

      for {row, cash} <- Enum.zip(rows, valuation["cash_balances"]) do
        assert text(Floki.find(row, "td:first-child")) =~ cash["name"]

        assert text(Floki.find(row, "td.num")) ==
                 Format.money(Decimal.new(cash["balance"])) <> " " <> cash["currency"]
      end

      assert [_] = Floki.find(doc, "#dashboard-cash-accounts a[href='/portfolios']")

      small = Floki.find(doc, "#dashboard-cash-accounts-2 [data-role='cash-total']")
      assert text(small) =~ Format.money(Decimal.new(valuation["total_cash"]))

      wealth = rendered(conn, "/portfolio")
      wealth_rows = Floki.find(wealth, "#portfolio-cash [data-role='cash-account']")
      assert Enum.map(wealth_rows, &text/1) == Enum.map(rows, &text/1)
    end

    # €1,000 free and a €5,000 reserve beside €4,000 in securities, and a
    # dollar account no rate converts: the cash all valued accounts sum is
    # 6,000, the deployable cash the cash quote counts 1,000.
    defp reserve_seed do
      today = Clock.today()
      home = base_world(name: "Home", cash_name: "Free Cash", depot_name: "Home Depot")
      deposit!(home, "5000", Date.add(today, -20))
      security = create_security!(name: "Alpha Werke")
      put_quotes!(security, [{Date.add(today, -10), "100"}])
      buy!(home, security, quantity: "40", price: "100", date: Date.add(today, -10))

      reserve =
        add_depot(home.portfolio,
          cash_name: "Reserve Cash",
          depot_name: "Reserve Depot",
          liquidity_role: "reserve"
        )

      deposit!(%{portfolio: home.portfolio, cash: reserve.cash}, "5000", Date.add(today, -20))

      dollars =
        add_depot(home.portfolio,
          cash_currency: "USD",
          cash_name: "Dollar Cash",
          depot_name: "Dollar Depot"
        )

      deposit!(%{portfolio: home.portfolio, cash: dollars.cash}, "250", Date.add(today, -20),
        currency: "USD"
      )

      %{dollars: dollars.cash}
    end

    # User story (Sprint 32 closing act, PR 2, the correctness lens):
    # As the operator who reads „Cash“ at S beside a reserve,
    # I want its ⓘ to name the basis the figure really has, and its count
    # to count the accounts the figure sums,
    # so that a reserve inside the figure is not read as deployable cash.
    #
    # Acceptance criteria:
    # - The figure is GET /api/v1/valuation's total_cash, 6,000.00: every
    #   valued account, the reserve included, the dollar account without a
    #   rate left out; its line counts the two accounts it sums, not three.
    # - Its ⓘ says so: all valued cash accounts, reserves and credit lines
    #   included, and that the cash quote counts only the deployable share;
    #   it never calls the figure deployable cash.
    test "at S the cash figure states its true basis and counts the accounts it sums",
         %{conn: conn} do
      reserve_seed()
      dashboard!([{"cash_accounts", "S"}])
      valuation = api("/api/v1/valuation")
      assert Decimal.equal?(Decimal.new(valuation["total_cash"]), 6000)
      assert Decimal.equal?(Decimal.new(valuation["counting_cash"]), 1000)
      summed = Enum.count(valuation["cash_balances"], & &1["valued"])
      assert summed == 2 and length(valuation["cash_balances"]) == 3

      widget = Floki.find(rendered(conn, "/"), "#dashboard-cash-accounts")
      small = text(Floki.find(widget, "[data-role='cash-total']"))
      assert small =~ money(valuation["total_cash"])
      assert small =~ "2 accounts"

      info = text(Floki.find(widget, "[data-role='section-info']"))
      assert info =~ "reserves and credit lines included"
      assert info =~ "The cash quote counts only the deployable share"
      refute info =~ "deployable cash in the base currency"
    end

    # User story (Sprint 32 closing act, PR 2, the edge-case lens):
    # As the operator who reads the cash accounts on a phone,
    # I want an account no rate converts marked there as on the wide form,
    # so that its balance is not read as part of the totals.
    #
    # Acceptance criteria:
    # - The compact row of the dollar account without a rate says
    #   „⚠ no exchange rate“; the rows of valued accounts do not.
    test "the compact form marks an account without an exchange rate", %{conn: conn} do
      %{dollars: dollars} = reserve_seed()
      dashboard!([{"cash_accounts", "row"}])
      widget = Floki.find(rendered(conn, "/"), "#dashboard-cash-accounts [data-form='compact']")
      rows = Floki.find(widget, "[data-compact-role='cash-account']")
      assert length(rows) == 3

      for row <- rows do
        marked = text(row) =~ "⚠ no exchange rate"
        assert marked == (Floki.attribute(row, "data-cash-account-id") == ["#{dollars.id}"])
      end
    end
  end

  describe "Kennzahlen (wealth_key_figures)" do
    alias PortfolixirWeb.Dashboard.Widgets.KeyFigures

    defp money(value), do: Format.money(Decimal.new(value))
    defp signed(value), do: Format.signed_decimal(Decimal.new(value), 2)
    defp pct(value), do: Format.signed_percent(Decimal.new(value)) <> "%"

    # User story:
    # As the operator who reads Wealth's key figures on a dashboard,
    # I want the section „Kennzahlen“ as board 06 draws its variant A,
    # so that the total, its split, the period's result, TTWROR and IRR and
    # the value bridge stand in one widget, each figure the API's.
    #
    # Acceptance criteria:
    # - The total incl. cash, the securities, the cash and the cash quote
    #   equal GET /api/v1/valuation's; Ergebnis, TTWROR and IRR equal GET
    #   /api/v1/performance?period=1y's (Ergebnis its end_value −
    #   start_value − net_external_flows, the figure Wealth calls the
    #   period's gain).
    # - The bridge Anfang + Nettoflüsse + Ergebnis = heute shows the
    #   performance read's start_value, net_external_flows, the result and
    #   end_value, and its displayed figures add up to the cent, with the
    #   multiplier the read's wealth_multiple.
    # - Wealth's key-figure band shows the same TTWROR and result.
    test "draws the totals, the returns and a bridge that adds up, as the API answers",
         %{conn: conn} do
      seed()
      dashboard!([{"wealth_key_figures", "row"}])
      valuation = api("/api/v1/valuation")
      perf = api("/api/v1/performance?period=1y")
      doc = rendered(conn, "/")
      widget = Floki.find(doc, "#dashboard-wealth-key-figures [data-form='wide']")
      at = fn role -> widget |> Floki.find("[data-role='#{role}']") |> text() end

      assert at.("kf-total") =~ money(valuation["total_with_cash"])
      assert at.("kf-securities") =~ money(valuation["total_value"])
      assert at.("kf-cash") =~ money(valuation["total_cash"])
      assert at.("kf-cash") =~ Format.percent(Decimal.new(valuation["cash_quote"]))

      result =
        perf["end_value"]
        |> Decimal.new()
        |> Decimal.sub(Decimal.new(perf["start_value"]))
        |> Decimal.sub(Decimal.new(perf["net_external_flows"]))

      assert at.("kf-result") =~ Format.signed_decimal(result, 2)
      assert at.("kf-ttwror") =~ pct(perf["ttwror"])
      assert at.("kf-irr") =~ pct(perf["irr"])

      assert at.("bridge-start") =~ money(perf["start_value"])
      assert at.("bridge-flows") =~ signed(perf["net_external_flows"])
      assert at.("bridge-result") =~ Format.signed_decimal(result, 2)
      assert at.("bridge-end") =~ money(perf["end_value"])

      assert at.("bridge-multiple") =~
               Format.plain_decimal(Decimal.new(perf["wealth_multiple"]), 2)

      cents = fn value -> Decimal.round(Decimal.new(value), 2) end

      assert Decimal.equal?(
               Decimal.add(
                 Decimal.add(cents.(perf["start_value"]), cents.(perf["net_external_flows"])),
                 Decimal.round(result, 2)
               ),
               cents.(perf["end_value"])
             )

      assert Floki.find(widget, "[data-role='bridge-gap']") == []
      # A period that ends today ends its bridge „heute“.
      assert perf["end_date"] == Date.to_iso8601(Clock.today())
      assert at.("bridge-end") =~ "today"

      wealth = rendered(conn, "/portfolio")
      assert text(Floki.find(wealth, "#kpi-ttwror strong")) == at.("kf-ttwror-value")
      assert text(Floki.find(wealth, "[data-role='period-gain'] b")) == at.("kf-result-value")
    end

    # User story (Sprint 32 closing act, PR 2, coverage):
    # As the operator who changes the own period my dashboard reads,
    # I want „Kennzahlen“ and „Performance“ to read the changed period at
    # once,
    # so that no figure of the old period stays under the new name.
    #
    # Acceptance criteria:
    # - On the own period „Seit Umbau“ (from 200 days back), the widget's
    #   TTWROR is GET /api/v1/performance?period=saved:<id>'s.
    # - After the dialog moves its start to 60 days back, the widget's
    #   TTWROR and the performance Zeile's badge are the route's for the
    #   changed period, which differs from the first.
    test "an own period changed in the dialog is read again", %{conn: conn} do
      %{security: security} = seed()
      today = Clock.today()
      put_quotes!(security, [{Date.add(today, -100), "105"}])
      dashboard!([{"wealth_key_figures", "row"}, {"performance", "row"}])

      {:ok, own} =
        Portfolixir.Periods.create_saved(Actor.owner_ui(), %{
          "name" => "Seit Umbau",
          "from" => Date.to_iso8601(Date.add(today, -200))
        })

      key = "saved:#{own.id}"
      path = "/api/v1/performance?period=" <> URI.encode_www_form(key)
      before = api(path)["ttwror"]
      {:ok, view, _html} = live(conn, "/?" <> URI.encode_query(%{"period" => key}))
      render_async(view)

      ttwror = fn ->
        view
        |> render()
        |> Floki.parse_document!()
        |> Floki.find(
          "#dashboard-wealth-key-figures [data-form='wide'] [data-role='kf-ttwror-value']"
        )
        |> text()
      end

      assert ttwror.() == pct(before)

      view |> element("[data-role='period-menu-toggle']") |> render_click()
      view |> element("[data-role='period-edit'][data-period='#{key}']") |> render_click()

      view
      |> form("#period-form",
        period: %{
          name: "Seit Umbau",
          from: Date.to_iso8601(Date.add(today, -60)),
          to_mode: "today"
        }
      )
      |> render_submit()

      render_async(view)
      changed = api(path)
      refute changed["ttwror"] == before
      assert ttwror.() == pct(changed["ttwror"])

      assert view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find(
               "#dashboard-performance-section [data-form='wide'] [data-role='period-badge']"
             )
             |> text() =~ pct(changed["ttwror"])
    end

    # User story (Sprint 32 closing act, PR 2, the correctness lens):
    # As the operator who reads the total's split beside a reserve,
    # I want the percentage after the cash named as the cash quote,
    # so that 20 % of deployable cash is not read as the share of the
    # 6,000 the legend names.
    #
    # Acceptance criteria:
    # - The legend's cash reads „Cash <total_cash> · Cash quote <cash_quote>
    #   %“, both GET /api/v1/valuation's: the amount every valued account
    #   sums, the quote the deployable share (1,000 of 5,000).
    test "the split names its percentage the cash quote, apart from the cash it sums",
         %{conn: conn} do
      reserve_seed()
      dashboard!([{"wealth_key_figures", "S"}])
      valuation = api("/api/v1/valuation")
      assert Decimal.equal?(Decimal.new(valuation["cash_quote"]), Decimal.new("0.2"))

      cash =
        conn
        |> rendered("/")
        |> Floki.find("#dashboard-wealth-key-figures [data-form='wide'] [data-role='kf-cash']")
        |> text()

      assert cash ==
               "Cash " <>
                 money(valuation["total_cash"]) <>
                 " · Cash quote " <> Format.percent(Decimal.new(valuation["cash_quote"])) <> " %"
    end

    # User story (Sprint 32 closing act, PR 2, the correctness lens):
    # As the operator who reads „Kennzahlen“ over a period that has ended,
    # I want the bridge to end on the period's last day and no warning to
    # set that day's value against today's total,
    # so that last year's figures read as last year's and no false gap
    # appears.
    #
    # Acceptance criteria:
    # - On prev_year the bridge's end is the performance read's end_value
    #   labelled „am“ its end_date, a day before today, never „heute“.
    # - On year:1999, before the first booking, the read walks no day: it
    #   answers start_date null and the value 0. The widget draws no bridge
    #   for a window with nothing in it, so none ends „heute“.
    # - On both, the footer's warning that the read's end value and the
    #   valuation's total are apart is not drawn: today's total is set only
    #   against a walked window that ends today.
    test "a period that has ended ends its bridge on its last day and sets nothing against today",
         %{conn: conn} do
      seed()
      dashboard!([{"wealth_key_figures", "row"}])
      today = Clock.today()

      perf = api("/api/v1/performance?period=prev_year")
      end_date = Date.from_iso8601!(perf["end_date"])
      assert end_date == Date.new!(today.year - 1, 12, 31)

      widget = Floki.find(rendered(conn, "/?period=prev_year"), "#dashboard-wealth-key-figures")
      bridge_end = text(Floki.find(widget, "[data-role='bridge-end']"))

      assert bridge_end =~ "on " <> Format.date(end_date)
      assert bridge_end =~ money(perf["end_value"])
      refute bridge_end =~ "today"
      assert Floki.find(widget, "[data-role='key-figures-apart']") == []

      empty = api("/api/v1/performance?period=year:1999")
      assert empty["start_date"] == nil
      assert empty["end_value"] == "0"

      widget = Floki.find(rendered(conn, "/?period=year:1999"), "#dashboard-wealth-key-figures")
      assert Floki.find(widget, "[data-role='kf-result']") != []
      assert Floki.find(widget, "[data-role='key-figures-bridge']") == []
      assert Floki.find(widget, "[data-role='key-figures-apart']") == []
    end

    # User story:
    # As the operator who trusts the bridge to add up,
    # I want a bridge whose rounded figures do not add up to say so,
    # so that a cent is never moved from one figure to another to hide it.
    #
    # Acceptance criteria:
    # - Figures that each round up (1,005 + 0 + 1,005 = 2,01) give the
    #   bridge its four figures as each reads at two places and the gap
    #   −0,01, which the widget draws; nothing is adjusted.
    # - Figures that add up give no gap.
    test "a bridge whose rounded figures do not add up shows the gap, never a fudged figure" do
      off = %{
        start_value: Decimal.new("1.005"),
        net_external_flows: Decimal.new("0"),
        end_value: Decimal.new("2.01")
      }

      bridge = KeyFigures.bridge(off)
      assert Decimal.equal?(bridge.start, Decimal.new("1.01"))
      assert Decimal.equal?(bridge.result, Decimal.new("1.01"))
      assert Decimal.equal?(bridge.end, Decimal.new("2.01"))
      assert Decimal.equal?(bridge.gap, Decimal.new("-0.01"))

      even = %{off | start_value: Decimal.new("1.00"), end_value: Decimal.new("2.50")}
      assert KeyFigures.bridge(even).gap == nil

      html =
        render_component(&KeyFigures.bridge_line/1,
          bridge: bridge,
          currency: "EUR",
          start_date: ~D[2025-11-26],
          multiple: nil
        )

      assert text(Floki.find(Floki.parse_fragment!(html), "[data-role='bridge-gap']")) =~
               Format.signed_decimal(Decimal.new("-0.01"), 2)
    end
  end

  describe "Beitrag je Position (contribution)" do
    defp contribution_seed do
      %{home: home} = seed()
      today = Clock.today()

      for {name, n} <-
            Enum.with_index(~w(Beta Gamma Delta Epsilon Zeta Eta Theta Iota Kappa Lambda), 1) do
        security = create_security!(name: name <> " Linien")
        put_quotes!(security, [{Date.add(today, -380), "50"}, {today, Integer.to_string(50 + n)}])
        buy!(home, security, quantity: "2", price: "50", date: Date.add(today, -380))
      end
    end

    defp rows_text(nodes), do: Enum.map(nodes, &text/1)

    # User story:
    # As the operator who wants to see which position made the period's
    # result,
    # I want Wealth's table „Beitrag je Position“ as a widget, as a Zeile
    # and as a short list at L,
    # so that the same contributions stand on my dashboard as on Wealth and
    # in the API.
    #
    # Acceptance criteria:
    # - At „Zeile“ the table lists the ten largest positions in the order
    #   GET /api/v1/performance/contribution?period=1y answers, each its
    #   contribution, its sum row the read's totals.result; Wealth's table
    #   on the same period lists the same rows.
    # - „Alle 11 anzeigen“ opens every position in the widget, as on Wealth.
    # - At L the largest contributions stand as rows with their figure and
    #   bar, the figures the route's.
    test "draws the contributions of the period as Wealth and the API do", %{conn: conn} do
      contribution_seed()
      dashboard!([{"contribution", "row"}, {"contribution", "L"}])
      read = api("/api/v1/performance/contribution?period=1y")
      {:ok, view, _html} = live(conn, "/")
      render_async(view)
      doc = view |> render() |> Floki.parse_document!()

      wide = "#dashboard-contribution [data-form='wide'] table [data-role='contribution-row']"
      rows = Floki.find(doc, wide)
      assert length(rows) == 10
      positions = Map.new(read["positions"], &{to_string(&1["security_id"]), &1})

      for row <- rows do
        position = positions[hd(Floki.attribute(row, "data-security-id"))]

        assert text(Floki.find(row, ".contribution-table__figure")) ==
                 Format.signed_decimal(Decimal.new(position["contribution"]), 2)
      end

      assert text(
               Floki.find(doc, "#dashboard-contribution [data-role='contribution-sum-figure']")
             ) =~
               Format.signed_decimal(Decimal.new(read["totals"]["result"]), 2)

      wealth = rendered(conn, "/portfolio")

      assert rows_text(Floki.find(wealth, "#contribution-table [data-role='contribution-row']")) ==
               rows_text(
                 Floki.find(doc, "#dashboard-contribution table [data-role='contribution-row']")
               )

      view
      |> element("#dashboard-contribution table [data-role='contribution-show-all']")
      |> render_click()

      assert view |> render() |> Floki.parse_document!() |> Floki.find(wide) |> length() == 11

      large =
        Floki.find(
          doc,
          "#dashboard-contribution-2 [data-form='wide'] [data-role='contribution-item']"
        )

      assert length(large) == 5

      # The largest contributions by their absolute amount, largest first.
      largest =
        read["positions"]
        |> Enum.sort_by(&Decimal.abs(Decimal.new(&1["contribution"])), {:desc, Decimal})
        |> Enum.take(5)
        |> Enum.map(&to_string(&1["security_id"]))

      assert Enum.map(large, &hd(Floki.attribute(&1, "data-security-id"))) == largest

      # The widget's head names the table; the table repeats no title.
      assert Floki.find(doc, "#dashboard-contribution h3") == []

      for item <- large do
        position = positions[hd(Floki.attribute(item, "data-security-id"))]

        assert text(Floki.find(item, ".widget-row__figure")) =~
                 Format.signed_decimal(Decimal.new(position["contribution"]), 2)
      end
    end
  end

  describe "Positionen (positions)" do
    # User story:
    # As the operator who keeps Wealth's position table on a dashboard,
    # I want the section „Positionen“ as a widget with its column picker,
    # so that the positions read as on Wealth, in the columns I picked.
    #
    # Acceptance criteria:
    # - The widget lists one row per depot and security, the rows Wealth's
    #   table lists, each quantity the holdings read's
    #   (GET /api/v1/portfolios/:id/holdings).
    # - Its column picker adds the market value, which equals the view
    #   valuation's market_value for the same depot and security
    #   (GET /api/v1/valuation); the choice is written to the same browser
    #   key as Wealth's.
    test "lists the positions and takes its columns as Wealth does", %{conn: conn} do
      %{home: home, security: security} = seed()
      dashboard!([{"positions", "row"}])
      holdings = api("/api/v1/portfolios/#{home.portfolio.id}/holdings")
      valuation = api("/api/v1/valuation")

      {:ok, view, _html} = live(conn, "/")
      render_async(view)
      doc = view |> render() |> Floki.parse_document!()

      rows = Floki.find(doc, "#dashboard-positions table [data-role='holdings-position']")

      assert Enum.map(rows, &hd(Floki.attribute(&1, "data-security-id"))) == [
               to_string(security.id)
             ]

      [row] = rows
      [holding] = holdings

      assert text(Floki.find(row, "[data-column='quantity']")) ==
               Format.exact(Decimal.new(holding["quantity"]))

      wealth = rendered(conn, "/portfolio")

      assert Enum.map(
               Floki.find(wealth, "#holdings-positions-table [data-role='holdings-position']"),
               &text/1
             ) ==
               Enum.map(rows, &text/1)

      view |> element("#dashboard-positions-column-toggle") |> render_click()

      view
      |> form("#dashboard-positions-column-form", %{"columns" => ["security", "market_value"]})
      |> render_change()

      assert_push_event(view, "column-prefs-changed", %{
        key: "wealth.holdings.columns",
        columns: ["security", "market_value"]
      })

      [position] = valuation["positions"]

      cell =
        view |> element("#dashboard-positions table [data-column='market_value']") |> render()

      assert cell =~ Format.money(Decimal.new(position["market_value"]))
    end
  end

  describe "Positionen (positions), the optional columns and the signs" do
    # User story (Sprint 32 closing act, PR 2, coverage):
    # As the operator who picks WKN, currency and the P&L columns,
    # I want each cell as the holdings read gives it, a loss in the loss
    # colour and a position at its cost unsigned,
    # so that the widget's table reads as Wealth's in every column.
    #
    # Acceptance criteria:
    # - With the columns security, WKN, currency, P&L and P&L % chosen,
    #   each row's WKN and currency are GET /api/v1/portfolios/:id/holdings'
    #   wkn and currency_code for that security.
    # - A position quoted below its cost reads its P&L and P&L % as a loss
    #   (`is-negative`); one quoted at its cost reads them flat
    #   (`is-flat`), as the read's zero.
    test "draws WKN, currency and the P&L columns with their signs", %{conn: conn} do
      today = Clock.today()
      world = base_world(name: "Spalten")
      deposit!(world, "5000", Date.add(today, -30))

      make = fn name, wkn ->
        {:ok, security} =
          Portfolixir.Catalog.create_security(Actor.owner_ui(), %{
            name: name,
            currency_code: "EUR",
            asset_class: "equity",
            wkn: wkn
          })

        security
      end

      loser = make.("Falling Test Works", "FTW001")
      flat = make.("Level Test Works", "LTW002")
      buy!(world, loser, quantity: "10", price: "100", date: Date.add(today, -20))
      buy!(world, flat, quantity: "10", price: "50", date: Date.add(today, -20))
      put_quotes!(loser, [{Date.add(today, -20), "100"}, {today, "80"}])
      put_quotes!(flat, [{Date.add(today, -20), "50"}, {today, "50"}])

      dashboard!([{"positions", "row"}])
      holdings = api("/api/v1/portfolios/#{world.portfolio.id}/holdings")
      {:ok, view, _html} = live(conn, "/")
      render_async(view)
      view |> element("#dashboard-positions-column-toggle") |> render_click()

      view
      |> form("#dashboard-positions-column-form", %{
        "columns" => ~w(security wkn currency unrealized_pnl_abs unrealized_pnl_pct)
      })
      |> render_change()

      doc = view |> render() |> Floki.parse_document!()

      cell = fn security, column ->
        doc
        |> Floki.find(
          "#dashboard-positions table [data-role='holdings-position'][data-security-id='#{security.id}'] [data-column='#{column}']"
        )
      end

      for security <- [loser, flat] do
        holding = Enum.find(holdings, &(&1["security_id"] == security.id))
        assert text(cell.(security, "wkn")) == holding["wkn"]
        assert text(cell.(security, "currency")) == holding["currency_code"]
      end

      for column <- ~w(unrealized_pnl_abs unrealized_pnl_pct) do
        assert ["num is-negative"] == Floki.attribute(cell.(loser, column), "class"), column
        assert ["num is-flat"] == Floki.attribute(cell.(flat, column), "class"), column
      end
    end
  end

  describe "Beitrag je Position (contribution) at L, on a view and over an empty period" do
    # User story (Sprint 32 closing act, PR 2, coverage):
    # As the operator who reads the contributions of one view,
    # I want the short list to show a loss as a loss, the table to name
    # the view, and a period nothing was held in to say so,
    # so that an empty list is never read as a failed one.
    #
    # Acceptance criteria:
    # - On a dashboard scoped to a view, at L each row's figure is GET
    #   /api/v1/performance/contribution?period=1y&view_id='s for that
    #   security, a loss signed and coloured as one; at „Zeile“ the table
    #   names the view.
    # - Over year:1999, before the first booking, the read lists no
    #   position, and the L list says „No position contributed in this
    #   period.“
    test "lists the view's contributions, a loss as one, and an empty period as empty",
         %{conn: conn} do
      %{home: home} = seed()
      today = Clock.today()
      loser = create_security!(name: "Sinking Test Linien")
      put_quotes!(loser, [{Date.add(today, -380), "50"}, {today, "40"}])
      buy!(home, loser, quantity: "5", price: "50", date: Date.add(today, -380))

      {:ok, scope} =
        Buckets.create_view(Actor.owner_ui(), %{name: "Alles drin", include_all: true})

      {:ok, _} =
        Dashboards.create_dashboard(Actor.owner_ui(), %{
          "name" => "Beitrag",
          "view_id" => scope.id,
          "layout" => [
            %{"kind" => "contribution", "size" => "L", "col" => 1, "row" => 1},
            %{"kind" => "contribution", "size" => "row", "col" => 1, "row" => 5}
          ]
        })

      read = api("/api/v1/performance/contribution?period=1y&view_id=#{scope.id}")
      doc = rendered(conn, "/")

      items =
        Floki.find(
          doc,
          "#dashboard-contribution [data-form='wide'] [data-role='contribution-item']"
        )

      assert length(items) == length(read["positions"])

      for item <- items do
        id = hd(Floki.attribute(item, "data-security-id"))
        position = Enum.find(read["positions"], &(to_string(&1["security_id"]) == id))
        figure = Floki.find(item, ".widget-row__figure span")
        assert text(figure) == Format.signed_decimal(Decimal.new(position["contribution"]), 2)

        if Decimal.negative?(Decimal.new(position["contribution"])),
          do: assert(Floki.attribute(figure, "class") == ["is-negative"])
      end

      assert Enum.any?(read["positions"], &Decimal.negative?(Decimal.new(&1["contribution"])))
      assert text(Floki.find(doc, "#dashboard-contribution-2")) =~ "Alles drin"

      assert api("/api/v1/performance/contribution?period=year:1999")["positions"] == []

      empty = rendered(conn, "/?period=year:1999")

      assert text(
               Floki.find(
                 empty,
                 "#dashboard-contribution [data-role='contribution-widget-empty']"
               )
             ) ==
               "No position contributed in this period."
    end
  end

  describe "Datenhinweise (data_notes)" do
    # User story:
    # As the operator who wants to know why a total may be off,
    # I want Wealth's data notes as a widget that stands only when a note
    # exists,
    # so that my dashboard says what Wealth says, and nothing when all is
    # well.
    #
    # Acceptance criteria:
    # - A held position without any price gives the note „no price at
    #   all“ naming it, as Wealth's section does, and its count equals GET
    #   /api/v1/valuation's unvalued_count.
    # - The exchange-rate remedy is not run from the dashboard: where it
    #   stands, it links to Wealth.
    # - Without a note the widget draws nothing; in the edit mode it says
    #   so in one quiet line.
    test "draws Wealth's notes when one exists, and nothing otherwise", %{conn: conn} do
      %{home: home} = seed()
      dashboard = dashboard!([{"data_notes", "row"}])

      clean = rendered(conn, "/")
      assert Floki.find(clean, "#dashboard-data-notes") == []

      unpriced = create_security!(name: "Ohne Kurs AG")
      deliver_untraded!(home, unpriced, "3", date: Date.add(Clock.today(), -30))
      valuation = api("/api/v1/valuation")
      assert valuation["unvalued_count"] == 1

      doc = rendered(conn, "/")
      note = Floki.find(doc, "#dashboard-data-notes [data-form='wide'] [data-role='dq-no-price']")
      assert text(note) =~ "Ohne Kurs AG"

      wealth = rendered(conn, "/portfolio")

      assert text(Floki.find(wealth, "#portfolio-data-quality [data-role='dq-no-price']")) ==
               text(note)

      {:ok, view, _html} = live(conn, "/dashboards/#{dashboard.id}")
      render_async(view)
      assert has_element?(view, "#dashboard-data-notes")
    end

    test "in the edit mode a widget without a note says so", %{conn: conn} do
      seed()
      dashboard = dashboard!([{"data_notes", "row"}])
      {:ok, view, _html} = live(conn, "/dashboards/#{dashboard.id}")
      render_async(view)
      refute has_element?(view, "#dashboard-data-notes")
      render_click(view, "edit_start", %{})
      render_async(view)
      assert has_element?(view, "#dashboard-data-notes [data-role='data-notes-none']")
    end
  end

  describe "Performance (performance at Zeile)" do
    # User story:
    # As the operator who keeps Wealth's performance chart on a dashboard,
    # I want the section „Performance“ as a Zeile with its series, its
    # level, its benchmark picker and „Daten als Tabelle“,
    # so that the chart reads on the dashboard's period as on Wealth.
    #
    # Acceptance criteria:
    # - The badge's TTWROR and result equal GET /api/v1/performance?period=1y
    #   and Wealth's badge on the same period; „Daten als Tabelle“ lists
    #   Wealth's rows.
    # - „Wert“ switches the widget's series, „Kategorien“ its level: the
    #   bands of GET /api/v1/performance/bands?level=category&period=1y are
    #   drawn; nothing is stored.
    # - The benchmark picker sends its GET form to the dashboard's own
    #   address, so the remembered selection is Wealth's.
    test "draws Wealth's chart, badge and table, and switches series and level",
         %{conn: conn} do
      seed()
      dashboard = dashboard!([{"performance", "row"}])
      perf = api("/api/v1/performance?period=1y")
      bands = api("/api/v1/performance/bands?period=1y&level=category")

      {:ok, view, _html} = live(conn, "/dashboards/#{dashboard.id}")
      render_async(view)
      doc = view |> render() |> Floki.parse_document!()
      widget = "#dashboard-performance-section [data-form='wide']"
      badge = text(Floki.find(doc, widget <> " [data-role='period-badge']"))

      assert badge =~ Format.signed_percent(Decimal.new(perf["ttwror"])) <> "%"

      result =
        perf["end_value"]
        |> Decimal.new()
        |> Decimal.sub(Decimal.new(perf["start_value"]))
        |> Decimal.sub(Decimal.new(perf["net_external_flows"]))

      assert badge =~ Format.signed_decimal(result, 2)

      wealth = rendered(conn, "/portfolio")
      assert text(Floki.find(wealth, "[data-role='period-badge']")) == badge

      rows = fn doc, scope ->
        doc
        |> Floki.find(scope <> " [data-role='perf-summary-table'] tbody tr")
        |> Enum.map(&text/1)
      end

      assert rows.(doc, widget) != []
      assert rows.(doc, widget) == rows.(wealth, "#portfolio-performance")

      assert [action] =
               doc
               |> Floki.find("#dashboard-performance-section [data-role='benchmark-form']")
               |> Floki.attribute("action")

      assert action == "/dashboards/#{dashboard.id}"

      view
      |> element(
        "#dashboard-performance-section [data-role='chart-series'] button[phx-value-mode='value']"
      )
      |> render_click()

      render_async(view)
      assert has_element?(view, widget <> " figure[data-chart-mode='value']")

      view
      |> element(
        "#dashboard-performance-section [data-role='performance-level'] button[phx-value-level='category']"
      )
      |> render_click()

      render_async(view)
      html = view |> element(widget) |> render()

      # One drawn band per band the route answers, the stack of its level.
      assert html =~ ~s(data-level="category")
      assert length(Regex.scan(~r/class="stack-band /, html)) == length(bands["bands"])

      # Nothing stored: the series and the level are the page's.
      assert Portfolixir.Repo.reload!(dashboard).lock_version == dashboard.lock_version
    end
  end

  describe "Performance (performance at Zeile), its lines, its securities and its benchmarks" do
    # User story (Sprint 32 closing act, PR 2, coverage):
    # As the operator who compares the parts of my book on a dashboard,
    # I want „Kategorien“ and „Wertpapiere“ in the % series to draw one
    # line per band the route answers, and a benchmark in the address to be
    # drawn and named in the widget,
    # so that the dashboard's chart reads as Wealth's at every level.
    #
    # Acceptance criteria:
    # - In the % series, „Kategorien“ draws the view's line and one line
    #   per band of GET
    #   /api/v1/performance/bands?period=1y&level=category&scale=ttwror,
    #   „Wertpapiere“ those of level=security, each under its band's key.
    # - A security benchmark and a fixed rate in the dashboard's address
    #   are named as the picker's active chips and drawn as two overlays
    #   on the TTWROR chart, whose accessible name names both.
    # - Nothing is stored.
    test "draws a line per band at each level and the benchmarks of the address",
         %{conn: conn} do
      %{security: security} = seed()
      today = Clock.today()
      owner = Actor.owner_ui()
      {:ok, tree} = Portfolixir.Classifications.create_classification(owner, %{name: "Strategy"})

      {:ok, growth} =
        Portfolixir.Classifications.create_category(owner, %{
          classification_id: tree.id,
          name: "Growth"
        })

      {:ok, _} =
        Portfolixir.Classifications.assign_security(owner, security.id, tree.id, growth.id)

      bench = create_security!(name: "Bench Test Index", ticker: "BTI")
      put_quotes!(bench, [{Date.add(today, -390), "50"}, {today, "60"}])
      dashboard = dashboard!([{"performance", "row"}])
      widget = "#dashboard-performance-section [data-form='wide']"

      address =
        "/dashboards/#{dashboard.id}?benchmark[]=security:#{bench.id}&benchmark_rate=2"

      {:ok, view, _html} = live(conn, address)
      render_async(view)

      active = view |> render() |> Floki.parse_document!()

      assert active
             |> Floki.find("#dashboard-performance-section [data-role='benchmark-chip']")
             |> Enum.map(&text/1) == ["Bench Test Index", "2.00 % p.a."]

      chart = view |> element(widget <> " figure") |> render()
      assert chart =~ ~s(class="chart-benchmark-1")
      assert chart =~ ~s(class="chart-benchmark-2")

      assert [label] =
               active
               |> Floki.find(widget <> " figure svg[aria-label]")
               |> Floki.attribute("aria-label")
               |> Enum.filter(&(&1 =~ "benchmarks"))

      assert label =~ "Bench Test Index"
      assert label =~ "2.00 % p.a."

      for level <- ~w(category security) do
        view
        |> element(
          "#dashboard-performance-section [data-role='performance-level'] button[phx-value-level='#{level}']"
        )
        |> render_click()

        render_async(view)
        read = api("/api/v1/performance/bands?period=1y&level=#{level}&scale=ttwror")
        assert read["bands"] != [], level

        drawn =
          view
          |> render()
          |> Floki.parse_document!()
          |> Floki.find(widget <> " figure[data-level='#{level}'] g.stack-line")
          |> Enum.map(&hd(Floki.attribute(&1, "data-band")))

        expected = [read["parent"]["key"] | Enum.map(read["bands"], & &1["key"])]
        assert Enum.sort(drawn) == Enum.sort(Enum.map(expected, &to_string/1)), level
      end

      assert Portfolixir.Repo.reload!(dashboard).lock_version == dashboard.lock_version
    end
  end

  describe "Wealth's polish list #1366 (Sprint 32 W5)" do
    # User story (#1366 line 7):
    # As the operator reading the positions,
    # I want a coupon such as „4,00 %“ kept on one line in the name column,
    # so that a name never breaks between the figure and its percent sign.
    #
    # Acceptance criteria:
    # - On Wealth's table and in the widget „Positionen“, the name „Larkspur
    #   Rail AG 4,00 % Anleihe 2031“ binds „4,00“ to „%“ with a no-break
    #   space; the stored name is unchanged.
    test "a percent in a security's name never breaks from its figure", %{conn: conn} do
      %{home: home} = seed()
      today = Clock.today()
      bond = create_security!(name: "Larkspur Rail AG 4,00 % Anleihe 2031")
      put_quotes!(bond, [{Date.add(today, -10), "100"}, {today, "101"}])
      buy!(home, bond, quantity: "10", price: "100", date: Date.add(today, -10))
      dashboard!([{"positions", "row"}])

      bound = "Larkspur Rail AG 4,00\u00A0% Anleihe 2031"

      for {path, selector} <- [
            {"/portfolio", "#holdings-positions-table"},
            {"/", "#dashboard-positions table"}
          ] do
        cells =
          conn
          |> rendered(path)
          |> Floki.find(selector <> " td[data-column='security']")
          |> Enum.map(&Floki.text/1)

        assert Enum.any?(cells, &String.contains?(&1, bound)), "#{path}: #{inspect(cells)}"
      end

      assert Portfolixir.Repo.reload!(bond).name == "Larkspur Rail AG 4,00 % Anleihe 2031"
    end

    # User story (#1366 line 8, #1320's remainder):
    # As the operator reading a data note on Wealth or on a dashboard,
    # I want two securities of the same name told apart in it,
    # so that I know which of the two the total leaves out.
    #
    # Acceptance criteria:
    # - Two held securities named alike, neither priced: the note „no price
    #   at all“ names each with what tells it apart (its ISIN), as the
    #   Overview's note does since Sprint 31 D3; on Wealth and in the
    #   widget „Datenhinweise“ alike.
    test "a data note tells twin securities apart", %{conn: conn} do
      %{home: home} = seed()
      today = Clock.today()

      for isin <- ~w(DE000TWIN001 DE000TWIN002) do
        twin = create_security!(name: "Zwilling Werke", isin: isin, ticker: nil)
        deliver_untraded!(home, twin, "2", date: Date.add(today, -20))
      end

      dashboard!([{"data_notes", "row"}])

      for {path, selector} <- [
            {"/portfolio", "#portfolio-data-quality [data-role='dq-no-price']"},
            {"/", "#dashboard-data-notes [data-form='wide'] [data-role='dq-no-price']"}
          ] do
        note = conn |> rendered(path) |> Floki.find(selector) |> text()
        assert note =~ "Zwilling Werke · ISIN DE000TWIN001", "#{path}: #{note}"
        assert note =~ "Zwilling Werke · ISIN DE000TWIN002", "#{path}: #{note}"
      end
    end
  end
end
