defmodule PortfolixirWeb.SecurityCycleRangeTest do
  # ADR-0060 §11 (Sprint 29 H8, FR-58; board ux-design-2026-11-12-sprint29/07
  # ⑤, ⑥; the idea board ux-design-2026-11-10-idea-i12/01, A's shortcut and
  # 02's zoom): the range „Zyklus“ on the security chart, which reaches past
  # today to four months after the later end of the next low's and the next
  # top's bands, the address `cycles=1` that opens the chart with cycles on
  # and that range, and the dashboard card „‹Name›-Zyklus“ that links there.
  #
  # The coin is the synthetic one of `Portfolixir.CycleFixtures`, its dates
  # moved so that its last close lies 30 days before today: its next low's
  # band then runs past today and its next top's band lies after it, as on
  # board 07 ⑤. Every date and price the screen shows is compared with the
  # API's answer for the same security (`GET /api/v1/securities/:id/cycles`).
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.CycleFixtures
  import Portfolixir.WorldFixtures, only: [create_security!: 1]
  import PortfolixirWeb.PreferenceCookieHelpers, only: [put_preference_cookie: 3]

  alias Portfolixir.Clock
  alias PortfolixirWeb.Format

  defp recent_coin!(opts \\ []) do
    synthetic_cycle_coin!(Keyword.put(opts, :shift_days, recent_shift(Clock.today())))
  end

  defp chart_path(security), do: "/securities/#{security.id}?tab=chart"

  defp nodes(view, selector) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.to_list()
  end

  defp attr(node, name), do: node |> LazyHTML.attribute(name) |> List.first()
  defp text(node), do: node |> LazyHTML.text() |> String.split() |> Enum.join(" ")

  defp axis_dates(view), do: view |> nodes("text.chart-axis-x") |> Enum.map(&text/1)

  defp chart_points(view) do
    [script] = nodes(view, "#detail-tab-panel-chart script[type='application/json']")
    script |> LazyHTML.text() |> Jason.decode!() |> Map.fetch!("points")
  end

  defp api_cycles(security) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get("/api/v1/securities/#{security.id}/cycles")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp iso(value), do: Date.from_iso8601!(value)
  defp dec(value), do: Decimal.new(value)

  # ADR-0060 §11: from three months before the last confirmed halving to
  # four months after the later end of the two bands, read from the API.
  defp cycle_range(api) do
    last_halving =
      api["halvings"] |> Enum.filter(& &1["confirmed"]) |> List.last() |> Map.fetch!("date")

    band_end =
      for(
        event <- ~w(next_low next_top),
        band = api["projection"][event]["band"],
        do: iso(band["window"]["to"])
      )
      |> Enum.max(Date)

    {Date.shift(iso(last_halving), month: -3), Date.shift(band_end, month: 4)}
  end

  # User story (ADR-0060 §11; board 07 ⑤; idea board 02's zoom):
  # As the operator with cycles on,
  # I want a range „Zyklus“ that runs from shortly before the last halving
  # to past the later of the two bands,
  # so that the bands, which lie mostly in the future, are large enough to
  # read, and the axis right of today holds only the halving window and the
  # bands.
  #
  # Acceptance criteria:
  # - „Zyklus“ sits beside 1M to Max only while cycles are on; a pushed
  #   „Zyklus“ with cycles off changes nothing.
  # - Chosen, the axis runs from three months before the last confirmed
  #   halving to four months after the later band end, both read from the
  #   API's answer; it reaches past today.
  # - Right of today: both bands at the API's dates, the next halving's
  #   window, a „today“ line; the price line ends at the last close.
  # - Cycles off while „Zyklus“ is chosen: the chip goes and the chart
  #   returns to the default range, which ends today.
  test "the range „Zyklus“ reaches past today to the later band's end", %{conn: conn} do
    coin = recent_coin!(next_window_days: 25)
    api = api_cycles(coin)
    today = Clock.today()
    {from, to} = cycle_range(api)
    assert Date.compare(to, today) == :gt

    {:ok, view, _html} = live(conn, chart_path(coin))
    refute has_element?(view, "button[phx-value-range='CYCLE']")

    default_axis = axis_dates(view)
    render_click(view, "set_detail_range", %{"range" => "CYCLE"})
    assert axis_dates(view) == default_axis
    refute has_element?(view, "button[phx-value-range='CYCLE'].is-active")

    view |> element("#toggle-cycles") |> render_click()
    assert has_element?(view, "button[phx-value-range='CYCLE']", "Cycle")

    view |> element("button[phx-value-range='CYCLE']") |> render_click()
    assert has_element?(view, "button[phx-value-range='CYCLE'].is-active")
    refute has_element?(view, "button[phx-value-range='1Y'].is-active")
    assert axis_dates(view) == [Format.date(from), Format.date(to)]

    for event <- ~w(next_low next_top) do
      window = api["projection"][event]["band"]["window"]
      assert [band] = nodes(view, "rect.cycle-band[data-event='#{event}']")
      assert attr(band, "data-from") == window["from"]
      assert attr(band, "data-to") == window["to"]
    end

    next = api["next_halving"]
    assert [estimate] = nodes(view, "line.cycle-halving.is-estimate")
    assert attr(estimate, "data-date") == next["date"]
    assert [window] = nodes(view, "rect.cycle-halving-window[data-date='#{next["date"]}']")
    assert attr(window, "data-to") == next["date_end"]

    assert [today_line] = nodes(view, "line.cycle-today")
    assert attr(today_line, "data-date") == Date.to_iso8601(today)
    assert has_element?(view, "text.cycle-label--today", "today")

    last_close = view |> chart_points() |> List.last() |> hd() |> iso()
    assert Date.compare(last_close, today) == :lt
    assert Date.diff(today, last_close) == 30

    view |> element("#toggle-cycles") |> render_click()
    refute has_element?(view, "button[phx-value-range='CYCLE']")
    assert has_element?(view, "button[phx-value-range='1Y'].is-active")
    assert axis_dates(view) |> List.last() == Format.date(last_close)
    refute has_element?(view, "line.cycle-today")
  end

  # User story (ADR-0060 §11; board 01's shortcut):
  # As the operator handed a link, or reloading the page,
  # I want the address to carry „Zyklen“,
  # so that the chart opens with cycles on, and a link from the dashboard
  # opens it on the range „Zyklus“ in one click.
  #
  # Acceptance criteria:
  # - `?tab=chart&cycles=1` opens with the toggle pressed and „Zyklus“
  #   chosen.
  # - Pressing the toggle puts `cycles=1` in the address, pressing it
  #   again takes it out; the range the operator chose stays.
  # - On a security without the view, `cycles=1` shows no toggle, no bar
  #   and the default range.
  test "the address carries „Zyklen“ and opens the range „Zyklus“", %{conn: conn} do
    coin = recent_coin!()
    {from, to} = coin |> api_cycles() |> cycle_range()

    {:ok, view, _html} = live(conn, chart_path(coin) <> "&cycles=1")
    assert has_element?(view, "#toggle-cycles[aria-pressed='true']")
    assert has_element?(view, "[data-role='cycle-bar']")
    assert has_element?(view, "button[phx-value-range='CYCLE'].is-active")
    assert axis_dates(view) == [Format.date(from), Format.date(to)]

    {:ok, view, _html} = live(conn, chart_path(coin))
    view |> element("button[phx-value-range='MAX']") |> render_click()
    view |> element("#toggle-cycles") |> render_click()
    assert_patch(view, "/securities/#{coin.id}?cycles=1&tab=chart")
    assert has_element?(view, "#toggle-cycles[aria-pressed='true']")
    assert has_element?(view, "button[phx-value-range='MAX'].is-active")

    view |> element("#toggle-cycles") |> render_click()
    assert_patch(view, "/securities/#{coin.id}?tab=chart")
    assert has_element?(view, "#toggle-cycles[aria-pressed='false']")
    assert has_element?(view, "button[phx-value-range='MAX'].is-active")

    plain = create_security!(name: "Plain Synthetic Fund")
    {:ok, view, _html} = live(conn, chart_path(plain) <> "&cycles=1")
    refute has_element?(view, "#toggle-cycles")
    refute has_element?(view, "[data-role='cycle-bar']")
    refute has_element?(view, "button[phx-value-range='CYCLE']")
    assert has_element?(view, "button[phx-value-range='1Y'].is-active")
  end

  # User story (ADR-0060 §11; idea board 01, A's shortcut):
  # As the operator landing on the dashboard,
  # I want a card „‹Name›-Zyklus“ for each security with the cycle view,
  # so that the next low's and the next top's windows, price ranges and
  # states are one look away, and the chart one click.
  #
  # Acceptance criteria:
  # - One card per security with the view, ordered by name; none for a
  #   bound security with fewer than two confirmed halvings, none for an
  #   unbound one.
  # - Each event's window, price range (two places, its currency), state
  #   and its parts' n equal the API's answer; the card says it is no
  #   forecast.
  # - Its link opens the security's chart with cycles on and „Zyklus“.
  # - The privacy mode hides the prices; the German page names the card
  #   „‹Name›-Zyklus“.
  test "the dashboard card shows the bands as the API answers them and opens the chart",
       %{conn: conn} do
    beta = recent_coin!(name: "Beta Cycle Coin")
    alpha = recent_coin!(name: "Alpha Cycle Coin")
    _one = synthetic_cycle_coin!(name: "One Halving Coin", halvings: 1)
    _plain = create_security!(name: "Plain Synthetic Fund")

    {:ok, view, _html} = live(conn, "/")

    assert view |> nodes("[data-role='cycle-card'] h2") |> Enum.map(&text/1) ==
             ["Alpha Cycle Coin cycle", "Beta Cycle Coin cycle"]

    api = api_cycles(alpha)
    card = "[data-role='cycle-card'][data-security-id='#{alpha.id}']"

    for event <- ~w(next_low next_top) do
      answer = api["projection"][event]
      band = answer["band"]
      row = "#{card} [data-event='#{event}']"

      assert has_element?(
               view,
               "#{row} [data-role='window']",
               "#{Format.date(iso(band["window"]["from"]))} – #{Format.date(iso(band["window"]["to"]))}"
             )

      assert has_element?(
               view,
               "#{row} [data-role='price']",
               "#{Format.decimal(dec(band["price"]["from"]), 2)} – #{Format.decimal(dec(band["price"]["to"]), 2)} USD"
             )

      for part <- answer["parts"], part["reason"] == nil do
        assert has_element?(view, "#{row} [data-role='parts']", "n = #{part["n_time"]}")
      end
    end

    assert has_element?(view, "#{card} [data-event='next_low'] [data-role='state']", "running")
    assert has_element?(view, "#{card} [data-event='next_top'] [data-role='state']", "open")
    assert has_element?(view, card, "not a forecast")

    [link] = nodes(view, "#{card} a[data-role='cycle-card-open']")
    href = attr(link, "href")
    assert href == "/securities/#{alpha.id}?tab=chart&cycles=1"

    {:ok, chart, _html} = live(conn, href)
    assert has_element?(chart, "#toggle-cycles[aria-pressed='true']")
    assert has_element?(chart, "button[phx-value-range='CYCLE'].is-active")
    assert has_element?(chart, "rect.cycle-band[data-event='next_top']")

    masked =
      conn
      |> put_preference_cookie("portfolixir_privacy", "on")
      |> put_preference_cookie("portfolixir_locale", "de")

    {:ok, view, _html} = live(masked, "/")
    assert has_element?(view, "[data-role='cycle-card'] h2", "Beta Cycle Coin-Zyklus")
    assert has_element?(view, "#{card} [data-event='next_low'] [data-role='state']", "läuft")
    assert has_element?(view, "#{card} [data-event='next_low'] [data-role='price'] .pf-mask")
    refute view |> nodes(card) |> hd() |> text() =~ "USD"
    _ = beta
  end
end
