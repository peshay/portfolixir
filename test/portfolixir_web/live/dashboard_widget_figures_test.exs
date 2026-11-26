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
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30):
  # the compact forms of the larger sizes are read on a stored dashboard.
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Widgets
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

  # A stored dashboard of `items` ({kind, size}), one under the other, which
  # „/“ then opens: the compact forms of the larger sizes, whose rows the
  # S's figure and line do not draw (the S32 closing act).
  defp loaded_at(conn, items) do
    {layout, _row} =
      Enum.map_reduce(items, 1, fn {kind, size}, row ->
        {:ok, {_w, h}} = Widgets.dimensions(size)
        {%{"kind" => kind, "size" => size, "col" => 1, "row" => row}, row + h}
      end)

    {:ok, _dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Größer",
        "layout" => layout
      })

    loaded(conn)
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
  # - Compact: the total and its change over the item's period (1J), the
  #   1Y TTWROR of ?period=1y; since the S32 closing act no strip of four
  #   rows under them (the compact forms at S, below).
  # - The strip at M: dashboard_d4_widgets_test.exs.
  test "„Gesamtwert“ draws GET /api/v1/valuation and the performance read", %{conn: conn} do
    seed()
    doc = loaded(conn)
    valuation = api("/api/v1/valuation?include_positions=false")
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

    assert text(Floki.find(compact, ".widget-total__sub")) ==
             percent(one_year["ttwror"]) <> " TTWROR · 1Y"

    assert Floki.find(compact, ".widget-row") == []
  end

  # User story (the S32 closing act, PR 2's design critic; board 06, board
  # 07 ② 2 and 7; crop u393):
  # As the operator reading „Überblick“ on a phone, where two S stand side
  # by side,
  # I want each S in its compact form as the anatomy draws it — its
  # figure and one line under it —,
  # so that the two tiles are not 700 px tall and nothing in them is cut.
  #
  # Acceptance criteria:
  # - „Gesamtwert“: the total of GET /api/v1/valuation and one line, the
  #   item's period's TTWROR (1J) of GET /api/v1/performance?period=1y;
  #   Sprint 31's strip of four rows (TTWROR, Cashquote, Letzte Buchung,
  #   Kurse) is gone, as Sprint 32 E4 removed it from the wide form.
  # - „Datenqualität“ at S: how many findings there are as the figure,
  #   the most severe one's short line under it (its link the list's).
  # - „Fällig“ (S only): the next date of GET /api/v1/events/upcoming as
  #   the figure, its security and kind as the line, the rest behind
  #   „+n more“.
  # - No list row (`.widget-row`) in any of the three.
  test "the compact forms at S are a figure and one line", %{conn: conn} do
    world = seed()

    for {security, days} <- [{world.fresh, 3}, {world.stale, 12}, {world.fresh, 20}] do
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
    valuation = api("/api/v1/valuation?include_positions=false")
    one_year = api("/api/v1/performance?period=1y")
    [next | rest] = api("/api/v1/events/upcoming?days=30")["events"]

    total = compact(doc, "dashboard-wealth")
    assert text(Floki.find(total, ".widget-total__figure")) =~ money(valuation["total_with_cash"])

    assert text(Floki.find(total, ".widget-total__sub")) ==
             percent(one_year["ttwror"]) <> " TTWROR · 1Y"

    for role <- ~w(kpi-ttwror kpi-cash-quote kpi-last-booking kpi-freshness) do
      assert Floki.find(total, "[data-compact-role='#{role}']") == []
    end

    quality = compact(doc, "dashboard-data-quality")
    shown = doc |> wide("dashboard-data-quality") |> Floki.find(".widget-findings__item")
    more = doc |> wide("dashboard-data-quality") |> Floki.find("[data-role='data-quality-more']")

    more =
      if more == [],
        do: 0,
        else: more |> text() |> String.replace(~r/\D/, "") |> String.to_integer()

    count = length(shown) + more

    assert quality
           |> Floki.find("[data-compact-role='data-quality-count'] .widget-figure__value")
           |> text() ==
             ngettext_open_points(count)

    assert text(Floki.find(quality, "[data-compact-role='data-quality-first']")) ==
             text(hd(shown))

    due = compact(doc, "dashboard-upcoming")

    assert text(Floki.find(due, "[data-compact-role='upcoming-next'] .widget-figure__value")) ==
             Format.date(Date.from_iso8601!(next["date"]))

    assert text(Floki.find(due, "[data-compact-role='upcoming-next'] .widget-figure__sub")) =~
             "Fresh Co"

    assert text(Floki.find(due, "[data-compact-role='upcoming-more'] summary")) ==
             "+#{length(rest)} more"

    for widget <- ~w(dashboard-wealth dashboard-data-quality dashboard-upcoming) do
      assert Floki.find(compact(doc, widget), ".widget-row") == [], widget
    end
  end

  defp ngettext_open_points(1), do: "1 open point"
  defp ngettext_open_points(count), do: "#{count} open points"

  # User story:
  # As the operator reading „Datenqualität“,
  # I want each count to be the length of the list its link opens, as the
  # agent reads it,
  # so that a count never promises a list of another size.
  #
  # Acceptance criteria:
  # - Wide at S (the template's, Sprint 31 D4: one short counted line per
  #   finding) and compact at L (a row per finding; the S's compact form
  #   is its figure and one line since the S32 closing act): the
  #   stale-quote and the missing-logo counts equal the lengths of GET
  #   /api/v1/securities?data_quality=<set> over the held securities.
  test "„Datenqualität“ counts what GET /api/v1/securities lists", %{conn: conn} do
    seed()
    doc = loaded(conn)

    stale = length(api("/api/v1/securities?data_quality=stale_quote&holding_status=held"))
    logo = length(api("/api/v1/securities?data_quality=missing_logo&holding_status=held"))
    assert stale == 1
    assert logo == 2

    wide = wide(doc, "dashboard-data-quality")
    compact = conn |> loaded_at([{"data_quality", "L"}]) |> compact("dashboard-data-quality")

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
  #   with its date and its security; the compact form (an S, since the
  #   S32 closing act) the next one as its figure, the rest behind „+n
  #   more“.
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
      |> Floki.find("[data-role='upcoming-next-link'], [data-role='upcoming-event']")
      |> Enum.map(fn link ->
        date =
          if Floki.find(link, ".num") == [], do: text(link), else: text(Floki.find(link, ".num"))

        {hd(Floki.attribute(link, "href")), date}
      end)

    assert wide == expected
    assert compact == expected

    # At S (the template's) the wide form draws two dated lines and the
    # rest behind „+n more“, in the same order, and a short basis line
    # (Sprint 31 closing act, DS1's follow-up; board 02 ⑨).
    shown =
      doc
      |> wide("dashboard-upcoming")
      |> Floki.find(".widget-due--next > li [data-role='upcoming-event']")

    assert length(shown) == min(length(expected), 2)

    assert text(Floki.find(doc, "#dashboard-upcoming [data-role='upcoming-basis-short']")) ==
             "Whole catalogue · next 30 days"
  end

  # User story (Sprint 31 closing act, DS1's follow-up; board 02 ⑨):
  # As the operator reading „Fällig“ at S,
  # I want the next two dates on a line each and the rest one tap away,
  # so that the small widget fits its row and nothing due is lost.
  #
  # Acceptance criteria:
  # - Three upcoming dates: two on a line each (the date, the name), the
  #   third behind „+1 more“, a disclosure in the widget (no screen lists
  #   the upcoming dates as a page); each line the security's events.
  test "„Fällig“ at S shows two dates and the rest behind „+n more“", %{conn: conn} do
    world = seed()

    for {security, days} <- [{world.fresh, 3}, {world.stale, 12}, {world.fresh, 20}] do
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
    wide = wide(doc, "dashboard-upcoming")
    assert length(Floki.find(wide, ".widget-due--next > li [data-role='upcoming-event']")) == 2
    [more] = Floki.find(wide, "details[data-role='upcoming-more']")
    assert text(Floki.find(more, "summary")) == "+1 more"
    assert length(Floki.find(more, "[data-role='upcoming-event']")) == 1
  end

  # User story:
  # As the operator reading „Abseits des Ziels“,
  # I want each category's drift to be the allocation read's drift,
  # so that the widget shows the figure the agent reads.
  #
  # Acceptance criteria:
  # - Wide and compact at L (the S's compact form is its count since the
  #   S32 closing act): each listed category is one the allocation route
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
      conn
      |> loaded_at([{"off_target", "L"}])
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
    assert count |> Floki.find(".widget-figure__value") |> text() =~ ~r/^#{beyond} categor/

    # And the compact form at S: the same count as its figure.
    compact_count =
      doc
      |> compact("dashboard-attention")
      |> Floki.find("[data-compact-role='off-target-count']")

    assert compact_count |> Floki.find(".widget-figure__value") |> text() =~
             ~r/^#{beyond} categor/

    assert text(Floki.find(doc, "#dashboard-attention [data-role='off-target-beyond']")) =~
             "beyond ±5 pp"
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
