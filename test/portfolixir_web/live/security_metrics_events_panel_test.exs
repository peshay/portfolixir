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

  # User story (#828, ADR-0048; design pick D2-B of 2026-09-19):
  # As a local portfolio maintainer,
  # I want a security's dated calendar facts on their own tab,
  # so that a reporting date I must not miss is where I read the security.
  #
  # Acceptance criteria:
  # - "Termine" is the ninth tab of the detail pane and lists the events in
  #   the research timeline's shape, with the timing qualifier and the source
  #   quality as words.
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

  test "a security with no events says so", %{conn: conn} do
    security = create_security!(name: "Quiet Co", ticker: "QTC")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=events")

    assert has_element?(view, "#detail-tab-panel-events .empty-state")
  end
end
