defmodule PortfolixirWeb.SecurityCycleChartTest do
  # ADR-0060 §11 and ADR-0059 §8 (Sprint 29 H7, FR-58; the idea boards
  # ux-design-2026-11-10-idea-i12/01 to 03 as adopted, and board
  # ux-design-2026-11-12-sprint29/07, D-6 Q3 to Q9): the security chart's
  # „Zyklen“ toggle, its cycle bar with „Zeitachse“ and „Ausgerichtet“, the
  # three line switches and the chain's health line, and on the time axis
  # the halvings, the tops and lows, the bands with „beide Wege“ and the
  # cones. The screen reads the context (`SecurityCycles.for_security/2`),
  # never the API; the figures it shows are compared with the API's answer
  # for the same security.
  #
  # The coin, its halvings and its closes are synthetic
  # (`Portfolixir.CycleFixtures`): the stored closes run from 2013-01-10 to
  # 2020-05-01, so the range „Max“ shows every window, the next low's band
  # (29.12.2019 to 31.12.2020) overlaps the axis and the next top's (from
  # 02.03.2021) lies right of it.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.CycleFixtures
  import Portfolixir.WorldFixtures, only: [create_security!: 1]
  import PortfolixirWeb.PreferenceCookieHelpers, only: [put_preference_cookie: 3]

  alias PortfolixirWeb.Format

  defp chart_path(security), do: "/securities/#{security.id}?tab=chart"

  # The chart tab at „Max“, so the whole stored history is on the axis.
  defp open_max(conn, security) do
    {:ok, view, _html} = live(conn, chart_path(security))

    view
    |> element("button[phx-click='set_detail_range'][phx-value-range='MAX']")
    |> render_click()

    view
  end

  defp cycles_on(view) do
    view |> element("#toggle-cycles") |> render_click()
    view
  end

  defp nodes(view, selector) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.to_list()
  end

  defp attr(node, name), do: node |> LazyHTML.attribute(name) |> List.first()
  defp text(node), do: node |> LazyHTML.text() |> String.split() |> Enum.join(" ")

  defp dates(view, selector), do: view |> nodes(selector) |> Enum.map(&attr(&1, "data-date"))

  defp classes(node), do: node |> attr("class") |> String.split()

  # User story (ADR-0060 §1, §11; board 07 ③, Q3 A):
  # As the operator reading a security's chart,
  # I want a „Zyklen“ toggle only where the security has the cycle view,
  # so that a toggle never opens an empty view.
  #
  # Acceptance criteria:
  # - A security bound to no chain has no toggle.
  # - A bound security with fewer than two confirmed halvings has none
  #   (Q3 A: the edit form says why, H8).
  # - A security with the view has the toggle, unpressed, and no cycle bar
  #   until it is pressed; pressing it shows the bar with „Timeline“
  #   pressed and „Top ↔ low“ on, „Top – top“ and „Low – low“ off.
  test "the toggle appears only where the view exists, and opens the cycle bar", %{conn: conn} do
    plain = create_security!(name: "Plain Synthetic Fund")
    {:ok, view, _html} = live(conn, chart_path(plain))
    refute has_element?(view, "#toggle-cycles")

    one = synthetic_cycle_coin!(name: "One Halving Coin", halvings: 1)
    {:ok, view, _html} = live(conn, chart_path(one))
    refute has_element?(view, "#toggle-cycles")

    coin = synthetic_cycle_coin!()
    view = open_max(conn, coin)
    assert has_element?(view, "#toggle-cycles[aria-pressed='false']", "Cycles")
    refute has_element?(view, "[data-role='cycle-bar']")
    refute has_element?(view, "g.cycle-layer")

    cycles_on(view)
    assert has_element?(view, "#toggle-cycles[aria-pressed='true']")
    assert has_element?(view, "[data-role='cycle-bar'] #cycle-mode-timeline[aria-pressed='true']")
    assert has_element?(view, "#cycle-mode-aligned[aria-pressed='false']", "Aligned")
    assert has_element?(view, "#cycle-line-top_low[aria-pressed='true']", "Top ↔ low")
    assert has_element?(view, "#cycle-line-top_top[aria-pressed='false']", "Top – top")
    assert has_element?(view, "#cycle-line-low_low[aria-pressed='false']", "Low – low")

    view |> element("#toggle-cycles") |> render_click()
    refute has_element?(view, "[data-role='cycle-bar']")
    refute has_element?(view, "g.cycle-layer")
  end

  # User story (ADR-0060 §11 „Zeitachse“, §5, §6; boards 01 and 03 as
  # adopted):
  # As the operator with cycles on,
  # I want the halvings as vertical lines, each window's top and low marked
  # with date and close, the next low's band with „beide Wege“ shaded, the
  # segments between tops and lows and the cone into the band,
  # so that I see the cycles and where the stored ones point, never a line.
  #
  # Acceptance criteria:
  # - One line per confirmed halving on the axis (four), none for the next
  #   one, which lies right of the axis.
  # - A top mark per window (the open one's anchored top provisional), a
  #   low mark per closed window, and the open window's low so far.
  # - The next low's band and its agree, at the band's own dates; the next
  #   top's band lies right of the axis and is not drawn.
  # - „Top ↔ low“ draws its six segments and the cone into top → low, so
  #   the next low's band is an outline; „Low – low“ adds its two segments
  #   and its cone; with no cone into it the band is filled again.
  # - „Top – top“ draws its three segments and its cone.
  test "the time axis draws halvings, tops, lows, the band and the cones", %{conn: conn} do
    coin = synthetic_cycle_coin!()
    view = conn |> open_max(coin) |> cycles_on()

    assert dates(view, "line.cycle-halving") ==
             ~w(2013-01-10 2015-01-10 2017-01-10 2019-01-10)

    refute has_element?(view, "line.cycle-halving.is-estimate")

    assert dates(view, "path.cycle-top") ==
             ~w(2013-06-01 2016-03-01 2017-08-01 2019-10-01)

    assert [provisional] = nodes(view, "path.cycle-top.is-provisional")
    assert attr(provisional, "data-date") == "2019-10-01"
    assert dates(view, "path.cycle-low:not(.is-so-far)") == ~w(2014-09-01 2016-09-01 2018-05-01)
    assert dates(view, "path.cycle-low.is-so-far") == ["2020-05-01"]

    assert has_element?(view, "text.cycle-label[data-date='2019-10-01']", "1,500 USD")

    assert [band] = nodes(view, "rect.cycle-band")
    assert attr(band, "data-event") == "next_low"
    assert attr(band, "data-from") == "2019-12-29"
    assert attr(band, "data-to") == "2020-12-31"
    assert "is-outline" in classes(band)
    assert [_agree] = nodes(view, "rect.cycle-band__agree[data-event='next_low']")

    assert has_element?(
             view,
             "text.cycle-label[data-event='next_low']",
             "Low band 300–383 USD"
           )

    assert has_element?(view, "text.cycle-label[data-event='next_low']", "both ways 333–374 USD")
    assert has_element?(view, "text.cycle-label[data-event='next_low']", "running")

    assert length(nodes(view, "line.cycle-segment[data-line='top_low']")) == 6
    assert [_cone] = nodes(view, "g.cycle-cone[data-line='top_low']")
    assert nodes(view, "g.cycle-cone[data-line='low_low']") == []

    view |> element("#cycle-line-low_low") |> render_click()
    assert has_element?(view, "#cycle-line-low_low[aria-pressed='true']")
    assert length(nodes(view, "line.cycle-segment[data-line='low_low']")) == 2
    assert [_cone] = nodes(view, "g.cycle-cone[data-line='low_low']")

    view |> element("#cycle-line-low_low") |> render_click()
    view |> element("#cycle-line-top_low") |> render_click()
    assert nodes(view, "line.cycle-segment") == []
    assert nodes(view, "g.cycle-cone") == []
    assert [band] = nodes(view, "rect.cycle-band")
    refute "is-outline" in classes(band)

    view |> element("#cycle-line-top_top") |> render_click()
    assert length(nodes(view, "line.cycle-segment[data-line='top_top']")) == 3
    assert [_cone] = nodes(view, "g.cycle-cone[data-line='top_top']")
  end

  # User story (ADR-0059 §8; board 07 ③, Q4 A):
  # As the operator with cycles on,
  # I want the chain source's health in the cycle bar,
  # so that a quiet chain and a dead or refused source look different.
  #
  # Acceptance criteria:
  # - A chain without a source says its halvings are entered by hand.
  # - Bitcoin's source: the host and the age of the last read; the fallback
  #   named as such; stale after 24 hours in ADR-0059 §8's sentence with
  #   the last host and time; a refused own URL with its host and reason in
  #   the line; never read yet.
  test "the cycle bar carries the chain source's health line", %{conn: conn} do
    litecoin = synthetic_cycle_coin!()
    view = conn |> open_max(litecoin) |> cycles_on()

    assert has_element?(
             view,
             "[data-role='cycle-health'][data-status='by_hand']",
             "Halvings entered by hand · no chain source for Litecoin"
           )

    bitcoin = synthetic_cycle_coin!(name: "Synthetic Chain Coin", chain: :bitcoin)
    view = conn |> open_max(bitcoin) |> cycles_on()
    assert has_element?(view, "[data-role='cycle-health'][data-status='never_read']")

    now = DateTime.truncate(DateTime.utc_now(), :second)
    two_hours_ago = DateTime.add(now, -2 * 3600)

    chain_state!(:bitcoin, %{
      source_host: "mempool.space",
      last_tried_at: two_hours_ago,
      last_ok_at: two_hours_ago
    })

    view = conn |> open_max(bitcoin) |> cycles_on()

    assert has_element?(
             view,
             "[data-role='cycle-health'][data-status='current']",
             "Chain source: mempool.space · read 2 h ago"
           )

    Portfolixir.Repo.delete_all(Portfolixir.Chains.ChainRead)

    chain_state!(:bitcoin, %{
      source_host: "blockstream.info",
      last_tried_at: two_hours_ago,
      last_ok_at: two_hours_ago
    })

    view = conn |> open_max(bitcoin) |> cycles_on()
    assert has_element?(view, "[data-role='cycle-health']", "blockstream.info (fallback)")

    Portfolixir.Repo.delete_all(Portfolixir.Chains.ChainRead)
    ok_at = DateTime.add(now, -31 * 3600)

    chain_state!(:bitcoin, %{
      source_host: "mempool.space",
      last_tried_at: DateTime.add(now, -600),
      last_ok_at: ok_at,
      last_error: "mempool.space: timeout; blockstream.info: http_503"
    })

    view = conn |> open_max(bitcoin) |> cycles_on()

    assert has_element?(
             view,
             "[data-role='cycle-health'][data-status='stale']",
             "Chain source without an answer for 31 h"
           )

    assert has_element?(view, "[data-role='cycle-health']", "last mempool.space")
    assert has_element?(view, "[data-role='cycle-health']", "halving estimate from then")

    Portfolixir.Repo.delete_all(Portfolixir.Chains.ChainRead)

    chain_state!(:bitcoin, %{
      last_tried_at: DateTime.add(now, -600),
      last_error: "node.example.invalid: url_not_allowed:private_address",
      inserted_at: DateTime.add(now, -3600)
    })

    view = conn |> open_max(bitcoin) |> cycles_on()

    assert has_element?(
             view,
             "[data-role='cycle-health'][data-status='refused']",
             "Chain source refused: node.example.invalid resolves to a private address"
           )

    # The closing act's security lens on Lane H (finding 4): an IPv6
    # literal's host has colons, and the health line read its refusal as a
    # plain failure.
    for host <- ["::1", "fd00::5"] do
      Portfolixir.Repo.delete_all(Portfolixir.Chains.ChainRead)

      chain_state!(:bitcoin, %{
        last_tried_at: DateTime.add(now, -600),
        last_error: "#{host}: url_not_allowed:private_address",
        inserted_at: DateTime.add(now, -3600)
      })

      view = conn |> open_max(bitcoin) |> cycles_on()

      assert has_element?(
               view,
               "[data-role='cycle-health'][data-status='refused']",
               "Chain source refused: #{host} resolves to a private address"
             )
    end
  end

  # User story (ADR-0060 §11, the privacy mode; plan row H7):
  # As the operator showing the chart to someone,
  # I want the cycles drawn without a price in the privacy mode,
  # so that a top's close or a band's price never reaches the screen,
  # while the percent axis, the dates and the counts stay.
  #
  # Acceptance criteria:
  # - The axis is in percent, as the chart is today.
  # - A top's label names its month, no close; the band's label names the
  #   band, its dates and its state, no price.
  # - The disclosure hides its prices as every amount; „Ausgerichtet“
  #   keeps its index axis, which is no amount.
  # - The German page says „Zyklen“, „Zeitachse“, „Top ↔ Tief“.
  test "the privacy mode draws the cycles without a price", %{conn: conn} do
    coin = synthetic_cycle_coin!()

    masked =
      conn
      |> put_preference_cookie("portfolixir_privacy", "on")
      |> put_preference_cookie("portfolixir_locale", "de")

    view = masked |> open_max(coin) |> cycles_on()

    assert has_element?(view, "#toggle-cycles", "Zyklen")
    assert has_element?(view, "#cycle-mode-timeline", "Zeitachse")
    assert has_element?(view, "#cycle-line-top_low", "Top ↔ Tief")
    assert view |> nodes(".chart-axis-y") |> Enum.all?(&(text(&1) =~ "%"))

    top = view |> nodes("text.cycle-label[data-date='2019-10-01']") |> hd() |> text()
    assert top =~ "10.2019"
    refute top =~ "1.500"

    band = view |> nodes("text.cycle-label[data-event='next_low']") |> hd() |> text()
    assert band =~ "Tief-Band"
    assert band =~ "29.12.2019"
    assert band =~ "läuft"
    refute band =~ "300"
    refute band =~ "383"
    refute band =~ "USD"

    assert has_element?(view, "tr[data-row='next_low'] td[data-role='price'] .pf-mask")
    assert has_element?(view, "tr[data-row='next_low'] td[data-role='agree']", "beide Wege")
    refute view |> nodes("details[data-role='cycle-bands']") |> hd() |> text() =~ "USD"

    view |> element("#cycle-mode-aligned") |> render_click()
    assert has_element?(view, "[data-role='cycle-aligned'] .chart-axis-y", "×1")
  end

  defp api_cycles(security) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get("/api/v1/securities/#{security.id}/cycles")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp cell(row, role),
    do: row |> LazyHTML.query("td[data-role='#{role}']") |> Enum.to_list() |> hd() |> text()

  defp iso(value), do: Date.from_iso8601!(value)
  defp dec(value), do: Decimal.new(value)

  # User story (ADR-0060 §11 „Ausgerichtet“; board 01, A):
  # As the operator with cycles on,
  # I want the windows laid over each other from their halving, indexed to
  # the halving day's close on a log scale, with the next low's band in
  # cycle days,
  # so that I see that the timing repeats and the size shrinks.
  #
  # Acceptance criteria:
  # - „Aligned“ replaces the price chart with one line per window (the
  #   open one marked), its tops and lows at their cycle days, and the next
  #   low's band from day 353 to day 721 of the open window.
  # - The line switches belong to the time axis and leave the bar.
  # - The axis is an index (×), so the privacy mode keeps it.
  test "„Aligned“ lays the windows over each other from their halving", %{conn: conn} do
    coin = synthetic_cycle_coin!()
    view = conn |> open_max(coin) |> cycles_on()
    view |> element("#cycle-mode-aligned") |> render_click()

    assert has_element?(view, "#cycle-mode-aligned[aria-pressed='true']")
    refute has_element?(view, "#cycle-line-top_low")
    assert has_element?(view, "[data-role='cycle-aligned'] svg")
    refute has_element?(view, "svg.security-chart polyline.quote-line")

    lines = nodes(view, "[data-role='cycle-aligned'] polyline.cycle-aligned__line")

    assert Enum.map(lines, &attr(&1, "data-start")) ==
             ~w(2013-01-10 2015-01-10 2017-01-10 2019-01-10)

    assert "is-open" in classes(List.last(lines))

    tops = nodes(view, "[data-role='cycle-aligned'] path.cycle-top")
    assert Enum.map(tops, &attr(&1, "data-days")) == ~w(142 416 203 264)

    assert [band] =
             nodes(view, "[data-role='cycle-aligned'] rect.cycle-band[data-event='next_low']")

    assert attr(band, "data-from-day") == "353"
    assert attr(band, "data-to-day") == "721"
    assert has_element?(view, "[data-role='cycle-aligned'] .chart-axis-y", "×1")

    view |> element("#cycle-mode-timeline") |> render_click()
    assert has_element?(view, "svg.security-chart g.cycle-layer")
  end

  # User story (ADR-0060 §3, §11, §12; board 07 ④, Q9):
  # As the operator with cycles on,
  # I want the intervals under the chart, each with its n, and the count of
  # complete, partial and open cycles,
  # so that every figure says how few cycles stand behind it.
  #
  # Acceptance criteria:
  # - The count line names the complete, partial and open cycles and the
  #   month of the first stored close.
  # - One row per relation, each with the n the API answers; a cell carries
  #   its days and its change or factor; „provisional“ marks an
  #   observation with an end that is not final, „Part“ one from the
  #   partial window, whose column head says „Part“ too.
  test "the interval table carries every row's n and the count", %{conn: conn} do
    coin = synthetic_cycle_coin!()
    api = api_cycles(coin)
    view = conn |> open_max(coin) |> cycles_on()

    assert has_element?(
             view,
             "[data-role='cycle-count']",
             "Cycles: 3 complete, 0 partial, 1 open · closes from 2013-01"
           )

    rows = nodes(view, "table[data-role='cycle-intervals'] tbody tr")

    assert Enum.map(rows, &attr(&1, "data-relation")) ==
             ~w(halving_to_top top_to_low low_to_top top_to_top low_to_low low_to_next_halving)

    for row <- rows do
      relation = attr(row, "data-relation")
      [n] = row |> LazyHTML.query("td[data-role='n']") |> Enum.map(&text/1)
      assert n == "n = #{api["intervals"][relation]["n"]}"
    end

    assert has_element?(
             view,
             "tr[data-relation='top_to_low'] td[data-window='2013-01-10']",
             "457 d · -87.5 %"
           )

    assert has_element?(
             view,
             "tr[data-relation='low_to_top'] td[data-window='2017-01-10'] .badge",
             "provisional"
           )

    partial = synthetic_cycle_coin!(name: "Late Close Coin", closes_from: ~D[2013-03-01])
    view = conn |> open_max(partial) |> cycles_on()

    assert has_element?(view, "[data-role='cycle-count']", "2 complete, 1 partial, 1 open")

    assert has_element?(
             view,
             "table[data-role='cycle-intervals'] th[data-window='2013-01-10'] .badge",
             "Part"
           )

    assert has_element?(
             view,
             "tr[data-relation='low_to_top'] td[data-window='2013-01-10'] .badge",
             "Part"
           )
  end

  # User story (ADR-0060 §4, §5, §7, §11; board 07 ⑤, Q6, Q8):
  # As the operator with cycles on,
  # I want a disclosure „Bands and their parts“ listing each band and each
  # part with its window, its price range, its n, where the ways agree and
  # its state,
  # so that the band can be traced to what made it, as the agent reads it.
  #
  # Acceptance criteria:
  # - Each event's row and each present part's row show the window and the
  #   price range the API answers for the same security, and each part its
  #   time n and price n (the borrowed price side named).
  # - The next low's row says „both ways“ with agree's range; the next
  #   top's says one price way; the states read running, missed, open.
  # - An absent part says why (low → top waits for a final low).
  # - The disclosure says the band is not a forecast.
  test "the disclosure lists the bands and their parts as the API answers them", %{conn: conn} do
    coin = synthetic_cycle_coin!()
    api = api_cycles(coin)
    view = conn |> open_max(coin) |> cycles_on()

    assert has_element?(view, "details[data-role='cycle-bands'] summary", "Bands and their parts")

    for event <- ~w(next_low next_top) do
      answer = api["projection"][event]
      band = answer["band"]
      [row] = nodes(view, "tr[data-row='#{event}']")

      assert cell(row, "window") ==
               "#{Format.date(iso(band["window"]["from"]))} – #{Format.date(iso(band["window"]["to"]))}"

      assert cell(row, "price") ==
               "#{Format.decimal(dec(band["price"]["from"]), 2)} – #{Format.decimal(dec(band["price"]["to"]), 2)} USD"

      for part <- answer["parts"], part["reason"] == nil do
        [prow] = nodes(view, "tr[data-row='#{event}'] ~ tr[data-relation='#{part["relation"]}']")
        origin = cell(prow, "origin")

        if part["price_from"] do
          assert origin =~ "time n = #{part["n_time"]}, price from Top → top"
        else
          assert origin =~ "time n = #{part["n_time"]}, price n = #{part["n_price"]}"
        end

        assert cell(prow, "price") ==
                 "#{Format.decimal(dec(part["price"]["from"]), 2)} – #{Format.decimal(dec(part["price"]["to"]), 2)} USD"

        assert cell(prow, "window") ==
                 "#{Format.date(iso(part["window"]["from"]))} – #{Format.date(iso(part["window"]["to"]))}"
      end
    end

    agree = api["projection"]["next_low"]["agree"]

    assert has_element?(
             view,
             "tr[data-row='next_low'] td[data-role='agree']",
             "both ways #{Format.decimal(dec(agree["from"]), 2)} – #{Format.decimal(dec(agree["to"]), 2)} USD"
           )

    assert has_element?(view, "tr[data-row='next_top'] td[data-role='agree']", "one price way")
    assert has_element?(view, "tr[data-row='next_low'] td[data-role='state']", "running")

    assert has_element?(
             view,
             "tr[data-relation='low_to_low'] td[data-role='state']",
             "missed · window over"
           )

    assert has_element?(view, "tr[data-row='next_top'] td[data-role='state']", "open")

    assert has_element?(
             view,
             "tr[data-relation='low_to_top'] td[data-role='origin']",
             "waits until the running cycle's low is final"
           )

    assert has_element?(view, "details[data-role='cycle-bands']", "not a forecast")
  end
end
