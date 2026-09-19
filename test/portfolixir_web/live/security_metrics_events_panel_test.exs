defmodule PortfolixirWeb.SecurityMetricsEventsPanelTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Knowledge.Events

  defp seed_series!(security_id, count, last \\ nil) do
    last = last || Date.utc_today()
    first = Date.add(last, -(count - 1))

    rows =
      for i <- 0..(count - 1) do
        %{date: Date.add(first, i), close: Decimal.new("100"), source: "manual"}
      end

    {:ok, _} = Quotes.upsert_many(security_id, rows)
    :ok
  end

  # User story (#824, ADR-0047 §9; design pick D1-A of 2026-09-19):
  # As a local portfolio maintainer reading one security,
  # I want its derived metrics beside the price history they describe,
  # so that a moving average means its distance to the price and its crossing
  # with the other average, not a row of digits.
  #
  # Acceptance criteria:
  # - The chart tab carries a metric grid under the chart: the two moving
  #   averages with their distances, volatility, drawdown, momentum and the
  #   distance to the 52-week extremes.
  # - SMA-50 and SMA-200 are drawn on the chart as the second and third
  #   series — the toggles that draw them are on by default.
  # - Every cell names the window it was measured over and its observation
  #   count; a metric below its minimum says so instead of showing a number.
  test "the chart tab carries the metric grid under the chart", %{conn: conn} do
    security = create_security!(name: "Metric Co", ticker: "MTC")
    seed_series!(security.id, 400)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

    assert has_element?(view, "#detail-metrics")
    grid = view |> element("#detail-metrics") |> render()

    assert grid =~ "SMA 50"
    assert grid =~ "SMA 200"
    assert grid =~ "Volatility"
    assert grid =~ "Max drawdown"
    assert grid =~ "Momentum"
    assert grid =~ "52-week range"

    # Every cell names what it was measured over.
    assert has_element?(view, "#detail-metrics [data-role='metric-window']")

    # D1-A: the two averages are drawn, not only printed.
    assert view |> element("button[phx-value-window='50']") |> render() =~ ~s(aria-pressed="true")

    assert view |> element("button[phx-value-window='200']") |> render() =~
             ~s(aria-pressed="true")
  end

  test "a young security says a metric is not computable instead of showing a number",
       %{conn: conn} do
    security = create_security!(name: "Young Co", ticker: "YNG")
    seed_series!(security.id, 10)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

    grid = view |> element("#detail-metrics") |> render()
    assert grid =~ "not computable"
    assert has_element?(view, "#detail-metrics [data-role='metric-observations']")
  end

  # User story (found by the design critic in the Sprint 13 closing act):
  # As a local portfolio maintainer reading the price chart,
  # I want each overlay named where it is drawn,
  # so that "which dashed line is which" has an answer other than the tint
  # on a toggle pill — which is colour only, and gone under forced colours.
  #
  # Acceptance criteria:
  # - The chart carries a legend naming every active overlay, and the
  #   swatch is drawn with that series' own stroke class.
  # - Turning an overlay off removes its legend entry.
  test "the chart names the overlays it draws", %{conn: conn} do
    security = create_security!(name: "Legend Co", ticker: "LGD")
    seed_series!(security.id, 400)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

    legend = view |> element("[data-role='detail-chart-legend']") |> render()
    assert legend =~ "MA50"
    assert legend =~ "MA200"
    assert legend =~ "chart-ma-50"
    refute legend =~ "MA30"

    view
    |> element("button[phx-click='toggle_detail_ma'][phx-value-window='200']")
    |> render_click()

    legend = view |> element("[data-role='detail-chart-legend']") |> render()
    assert legend =~ "MA50"
    refute legend =~ "MA200"
  end

  # User story (DESIGN.md → security-metric-grid.period; found by the design
  # critic in the Sprint 13 closing act):
  # As a local portfolio maintainer who picked 6M on the chart,
  # I want the cell to say which window it actually measured,
  # so that the snap to the engine's fixed windows is disclosed in words
  # rather than left to be inferred from two ISO dates.
  #
  # Acceptance criteria:
  # - A windowed cell names its window ("90 days", "6 months") beside the
  #   measured span.
  # - 6M snaps the day windows to 90 days and keeps the 6-month momentum.
  # - A signed figure carries the sign class the same grid carries one tab
  #   over; the drawdown, which is always negative, does not.
  test "each windowed cell names the window it used", %{conn: conn} do
    security = create_security!(name: "Window Co", ticker: "WIN")
    seed_series!(security.id, 400)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

    # The range control is the one control (pick D1-A); the cells follow it.
    view
    |> element("button[phx-click='set_detail_range'][phx-value-range='6M']")
    |> render_click()

    names =
      view
      |> element("#detail-metrics")
      |> render()

    assert names =~ "90 days"
    assert names =~ "6 months"
    refute names =~ "365 days"

    assert has_element?(view, "#detail-metrics [data-role='metric-window-name']")
    refute view |> element("#detail-metrics") |> render() =~ ~s(class="is-negative">\n)
  end

  # User story (#828, ADR-0048; design pick D2-B of 2026-09-19):
  # As a local portfolio maintainer,
  # I want a security's dated calendar facts on their own tab,
  # so that a reporting date I must not miss is where I read the security.
  #
  # Acceptance criteria:
  # - "Dates" (de "Termine") is the ninth tab of the detail pane and lists
  #   the events in the research timeline's shape, with the timing qualifier
  #   and the source quality as words.
  # - The Research tab keeps exactly what it had.
  test "the detail pane carries a Termine tab with the security's events", %{conn: conn} do
    security = create_security!(name: "Event Co", ticker: "EVC")

    {:ok, _} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-11-04],
        timing: "estimated",
        source_quality: "secondary_multi",
        note: "expected from the IR calendar"
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=events")

    assert has_element?(view, "#detail-tab-events")
    panel = view |> element("#detail-tab-panel-events") |> render()

    assert panel =~ "Earnings report"
    assert panel =~ "2026-11-04"
    # The qualifier and the source quality read as words, never as slugs.
    assert panel =~ "Estimated"
    assert panel =~ "Several secondary sources"
    # The slug appears only as the badge's class hook, never as read text.
    refute panel =~ ">secondary_multi<"
    assert panel =~ "expected from the IR calendar"
  end

  # User story (#828, ADR-0048 §3 vs §5.3 — the closing-act walkthrough of
  # 2026-09-19 found this on the seeded review instance):
  # As a local portfolio maintainer reading the Termine tab,
  # I want "the date is set" and "it happened" to read as different things,
  # so that a shareholder meeting nobody has ticked off does not appear to be
  # ticked off.
  #
  # Acceptance criteria:
  # - `timing: exact` does not render a label containing the word the
  #   `confirmed` badge uses, in English or in German — the two fields are
  #   independent and the row must not say otherwise.
  # - An `exact` event that is not confirmed renders the timing badge and no
  #   confirmed badge; confirming it adds the second badge.
  test "an exact date and a confirmed event do not read as the same fact", %{conn: conn} do
    security = create_security!(name: "Label Co", ticker: "LBC")

    {:ok, unconfirmed} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: security.id,
        kind: "shareholder_meeting",
        date: ~D[2026-08-14],
        timing: "exact",
        source_quality: "primary"
      })

    for locale <- ~w(en de) do
      Gettext.put_locale(PortfolixirWeb.Gettext, locale)

      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=events&locale=#{locale}")
      panel = view |> element("#detail-tab-panel-events") |> render()

      timing = view |> element("[data-role='event-timing']") |> render()
      refute has_element?(view, "[data-role='event-confirmed']")

      # The collision the walkthrough caught: "Confirmed date" beside a
      # "Confirmed" badge. Whatever the two labels become, neither may
      # contain the other.
      confirmed_label =
        Gettext.with_locale(PortfolixirWeb.Gettext, locale, fn ->
          Gettext.gettext(PortfolixirWeb.Gettext, "Took place")
        end)

      refute String.contains?(String.downcase(timing), String.downcase(confirmed_label)),
             "#{locale}: the timing badge #{inspect(timing)} reads as the confirmed badge " <>
               "#{inspect(confirmed_label)}"

      refute panel =~ confirmed_label
    end

    Gettext.put_locale(PortfolixirWeb.Gettext, "en")

    {:ok, _} = Events.update_event(Actor.owner_ui(), unconfirmed, %{confirmed: true})
    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=events&locale=en")

    assert has_element?(view, "[data-role='event-confirmed']")
    assert view |> element("[data-role='event-confirmed']") |> render() =~ "Took place"
    assert view |> element("[data-role='event-timing']") |> render() =~ "Announced"
  end

  test "a security with no events says so", %{conn: conn} do
    security = create_security!(name: "Quiet Co", ticker: "QTC")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=events")

    assert has_element?(view, "#detail-tab-panel-events .empty-state")
  end
end
