defmodule PortfolixirWeb.DashboardWidgetFiguresTest do
  # Sprint 31 D3 (FR-60; ADR-0062 §1, §12; plan D-1 exit criterion 1): a
  # widget carries no figure of its own. Per kind of the Overview, every
  # figure the widget shows — in its wide form and in its compact form — is
  # compared with its source route's answer for the same scope (the
  # template's: Everything here) and period, called through the conn with
  # the API's bearer token.
  #
  # Covered elsewhere for the wide form, with the same rule: „Tops und
  # Flops“ in dashboard_movers_test.exs (every row, figure and count
  # against GET /api/v1/movers), the cycle card in
  # security_cycle_range_test.exs (the bands against
  # GET /api/v1/securities/:id/cycles). Synthetic data only.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets
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

  defp loaded(conn) do
    {:ok, view, _html} = live(conn, "/")
    render_async(view)
    view |> render() |> Floki.parse_document!()
  end

  defp compact(doc, widget), do: Floki.find(doc, "##{widget} [data-form='compact']")
  defp wide(doc, widget), do: Floki.find(doc, "##{widget} [data-form='wide']")

  defp money(value), do: Format.money(Decimal.new(value))
  defp percent(value), do: Format.signed_percent(Decimal.new(value)) <> "%"

  # A held position priced today, one with a stale quote (16 days), a
  # closed trade, and cash.
  defp seed do
    world = base_world()
    today = Clock.today()
    fresh = create_security!(name: "Fresh Co", ticker: "FRS")
    stale = create_security!(name: "Stale Co", ticker: "STL")
    deposit!(world, "5000", Date.add(today, -400))
    buy!(world, fresh, quantity: "10", price: "100", date: Date.add(today, -380))
    buy!(world, stale, quantity: "4", price: "50", date: Date.add(today, -380))
    sell!(world, fresh, quantity: "2", price: "130", date: Date.add(today, -20))
    put_quotes!(fresh, [{Date.add(today, -1), "120"}, {today, "125"}])
    put_quote!(stale, Date.add(today, -16), "55")
    Map.merge(world, %{fresh: fresh, stale: stale, today: today})
  end

  # User story:
  # As the operator reading „Gesamtwert“,
  # I want its total, its cash quote, its returns and its quote date to be
  # the figures the agent reads for the same scope and period,
  # so that the widget and the API never disagree.
  #
  # Acceptance criteria:
  # - Wide at S (the template's, Sprint 31 D4): the total and its currency
  #   equal GET /api/v1/valuation; its change is the dashboard period's
  #   (1J) TTWROR of GET /api/v1/performance?period=1y.
  # - Compact: the total, the year-to-date TTWROR of ?period=ytd, the 1Y
  #   TTWROR, the cash quote and the quote date as the routes answer them.
  # - The strip at M: dashboard_d4_widgets_test.exs.
  test "„Gesamtwert“ draws GET /api/v1/valuation and the performance read", %{conn: conn} do
    seed()
    doc = loaded(conn)
    valuation = api("/api/v1/valuation?include_positions=false")
    ytd = api("/api/v1/performance?period=ytd")
    one_year = api("/api/v1/performance?period=1y")

    total = money(valuation["total_with_cash"])
    wide = wide(doc, "dashboard-wealth")
    assert text(Floki.find(wide, "[data-count-digits]")) == total
    assert text(Floki.find(wide, ".value-suffix")) == valuation["base_currency"]

    assert text(Floki.find(wide, "[data-role='card-period-change']")) ==
             percent(one_year["ttwror"]) <> " TTWROR · 1Y"

    assert Floki.find(wide, "svg[data-role='total-spark']") != []
    assert Floki.find(wide, "#dashboard-kpi-strip") == []

    compact = compact(doc, "dashboard-wealth")
    assert text(Floki.find(compact, ".widget-total__figure")) =~ total
    assert text(Floki.find(compact, ".widget-total__sub")) =~ percent(ytd["ttwror"])

    assert text(Floki.find(compact, "[data-compact-role='kpi-ttwror'] .widget-row__figure")) ==
             percent(one_year["ttwror"])

    assert text(Floki.find(compact, "[data-compact-role='kpi-cash-quote'] .widget-row__figure")) ==
             Format.percent(Decimal.new(valuation["cash_quote"])) <> "%"

    assert text(Floki.find(compact, "[data-compact-role='kpi-freshness'] .widget-row__figure")) ==
             Format.date(Date.from_iso8601!(valuation["newest_quote_date"]))
  end

  # User story:
  # As the operator reading „Datenqualität“,
  # I want each count to be the length of the list its link opens, as the
  # agent reads it,
  # so that a count never promises a list of another size.
  #
  # Acceptance criteria:
  # - Wide at S (the template's, Sprint 31 D4: one short counted line per
  #   finding) and compact: the stale-quote and the missing-logo counts
  #   equal the lengths of GET /api/v1/securities?data_quality=<set> over
  #   the held securities.
  test "„Datenqualität“ counts what GET /api/v1/securities lists", %{conn: conn} do
    seed()
    doc = loaded(conn)

    stale = length(api("/api/v1/securities?data_quality=stale_quote&holding_status=held"))
    logo = length(api("/api/v1/securities?data_quality=missing_logo&holding_status=held"))
    assert stale == 1
    assert logo == 2

    wide = wide(doc, "dashboard-data-quality")
    compact = compact(doc, "dashboard-data-quality")

    assert text(Floki.find(wide, "[data-role='dq-quotes']")) == "#{stale} quote older than 7 days"

    assert text(Floki.find(compact, "[data-compact-role='dq-quotes']")) ==
             "one held security without a quote in 7 days"

    assert text(Floki.find(wide, "[data-role='dq-logo']")) == "#{logo} securities without a logo"
    assert text(Floki.find(compact, "[data-compact-role='dq-logo']")) =~ "#{logo} without a logo"
  end

  # User story:
  # As the operator reading „Fällig“,
  # I want its rows to be GET /api/v1/events/upcoming's events for the
  # same 30 days,
  # so that the widget and the agent list the same dates.
  #
  # Acceptance criteria:
  # - Wide and compact: the rows are the route's events, in its order, each
  #   with its date and its security.
  test "„Fällig“ lists GET /api/v1/events/upcoming", %{conn: conn} do
    world = seed()

    for {security, days} <- [{world.fresh, 3}, {world.stale, 12}] do
      {:ok, _event} =
        Events.create_event(Actor.owner_ui(), %{
          security_id: security.id,
          kind: "earnings",
          timing: "exact",
          source_quality: "primary",
          date: Date.add(world.today, days)
        })
    end

    doc = loaded(conn)
    events = api("/api/v1/events/upcoming?days=30")["events"]
    assert length(events) == 2

    expected =
      Enum.map(events, fn event ->
        {"/securities/#{event["security_id"]}?tab=events",
         Format.date(Date.from_iso8601!(event["date"]))}
      end)

    wide =
      doc
      |> wide("dashboard-upcoming")
      |> Floki.find("[data-role='upcoming-event']")
      |> Enum.map(&{hd(Floki.attribute(&1, "href")), text(Floki.find(&1, ".num"))})

    compact =
      doc
      |> compact("dashboard-upcoming")
      |> Floki.find("[data-compact-role='upcoming-event']")
      |> Enum.map(&{hd(Floki.attribute(&1, "href")), text(Floki.find(&1, ".widget-row__figure"))})

    assert wide == expected
    assert compact == expected
  end

  # User story:
  # As the operator reading „Abseits des Ziels“,
  # I want each category's drift to be the allocation read's drift,
  # so that the widget shows the figure the agent reads.
  #
  # Acceptance criteria:
  # - Wide and compact: each listed category is one the allocation route
  #   answers beyond ±5 pp, its drift in points and in money equal to the
  #   route's drift_weight and drift_value.
  # - At S the wide form leads with how many categories that is.
  test "„Abseits des Ziels“ draws the allocation read's drift", %{conn: conn} do
    world = seed()

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Steering"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Core"
      })

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), world.fresh.id, tree.id, core.id)

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, tree.id, [
        %{"category_id" => core.id, "target_weight" => "0.3"}
      ])

    {:ok, _} = Portfolios.set_cash_target(Actor.owner_ui(), world.portfolio, Decimal.new("0.7"))

    doc = loaded(conn)

    answer =
      api("/api/v1/portfolios/#{world.portfolio.id}/allocation?classification_id=#{tree.id}")

    category = Enum.find(answer["categories"], &(&1["name"] == "Core"))
    drift = Decimal.new(category["drift_weight"])
    assert Decimal.compare(Decimal.abs(drift), Decimal.new("0.05")) == :gt

    [row] =
      doc
      |> wide("dashboard-attention")
      |> Floki.find("[data-role='drift-alert']")
      |> Enum.filter(&(text(Floki.find(&1, ".attention-name")) == "Core"))

    assert text(Floki.find(row, ".num")) =~ Format.percent(Decimal.abs(drift)) <> " pp"
    assert text(Floki.find(row, ".num")) =~ money(category["drift_value"])

    [compact] =
      doc
      |> compact("dashboard-attention")
      |> Floki.find("[data-compact-role='drift-alert']")
      |> Enum.filter(&(text(Floki.find(&1, ".widget-row__name")) =~ "Core"))

    sign = if Decimal.compare(drift, 0) == :lt, do: "−", else: "+"

    assert text(Floki.find(compact, ".widget-row__figure")) ==
             sign <> Format.percent(Decimal.abs(drift)) <> " pp"

    assert text(Floki.find(compact, ".widget-row__sub")) =~ money(category["drift_value"])

    # At S (the template's) the wide form leads with the count of the
    # categories the route answers beyond the rule (Sprint 31 closing act,
    # DS1; board ux-design-2026-11-21-sprint31/02 ①); at M only the list.
    # The categories and the cash row, as the rule counts them.
    beyond =
      Enum.count(
        answer["categories"] ++ List.wrap(answer["cash"]),
        &(&1["drift_weight"] &&
            Decimal.compare(Decimal.abs(Decimal.new(&1["drift_weight"])), Decimal.new("0.05")) !=
              :lt)
      )

    count = doc |> wide("dashboard-attention") |> Floki.find("[data-role='off-target-count']")
    assert text(Floki.find(count, ".widget-figure__value")) == "#{beyond}"
    assert text(count) =~ "beyond ±5 pp"
  end

  # User story:
  # As the operator reading „Tops und Flops“ on a phone,
  # I want its compact rows to be the movers read's rows,
  # so that the switch between the halves shows the agent's ranking.
  #
  # Acceptance criteria:
  # - The compact form's rows under each half are GET /api/v1/movers's rows
  #   for the same window, in order, each with its return or contribution:
  #   the dashboard's default period, 1J, which the widget reads as its
  #   window 1y (ADR-0062 §5; Sprint 31 D5).
  test "„Tops und Flops“ compact draws GET /api/v1/movers", %{conn: conn} do
    seed()
    doc = loaded(conn)
    answer = api("/api/v1/movers?window=1y")
    compact = compact(doc, "dashboard-movers")

    for half <- ~w(highest lowest) do
      rows =
        compact
        |> Floki.find("[data-half='#{half}'] [data-compact-role='movers-row']")
        |> Enum.map(
          &{hd(Floki.attribute(&1, "href")), text(Floki.find(&1, ".widget-row__figure"))}
        )

      price =
        Enum.map(
          answer["price_return"][half],
          &{"/securities/#{&1["security"]["id"]}", percent(&1["return"])}
        )

      contribution =
        Enum.map(
          answer["contribution"][half],
          &{"/securities/#{&1["security"]["id"]}",
           Format.signed_decimal(Decimal.new(&1["contribution"]), 2) <> " EUR"}
        )

      assert rows == price ++ contribution, half
    end
  end

  # User story:
  # As the operator reading „Verkaufsrückblick“,
  # I want its trades to be the realized-gains read's newest trades,
  # so that the widget and the agent show the same results.
  #
  # Acceptance criteria:
  # - Wide and compact: the rows are the first trades of
  #   GET /api/v1/realized_gains, newest close first, each with its
  #   realized_base in the report's currency.
  test "„Verkaufsrückblick“ draws GET /api/v1/realized_gains", %{conn: conn} do
    seed()
    doc = loaded(conn)
    report = api("/api/v1/realized_gains")
    assert [_ | _] = report["trades"]

    expected =
      report["trades"]
      |> Enum.take(5)
      |> Enum.map(fn trade ->
        {"/securities/#{trade["security_id"]}?tab=trades",
         Format.signed_decimal(Decimal.new(trade["realized_base"]), 2)}
      end)

    wide =
      doc
      |> wide("dashboard-trades")
      |> Floki.find("[data-role='closed-trade']")
      |> Enum.map(
        &{hd(Floki.attribute(&1, "href")), &1 |> Floki.find(".num > span:first-child") |> text()}
      )

    compact =
      doc
      |> compact("dashboard-trades")
      |> Floki.find("[data-compact-role='closed-trade']")
      |> Enum.map(
        &{hd(Floki.attribute(&1, "href")),
         &1 |> Floki.find(".widget-row__figure > span") |> text()}
      )

    assert wide == expected
    assert compact == expected

    assert text(Floki.find(compact(doc, "dashboard-trades"), ".widget-row__figure small")) =~
             report["base_currency"]
  end
end
