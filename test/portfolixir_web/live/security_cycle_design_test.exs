defmodule PortfolixirWeb.SecurityCycleDesignTest do
  # Sprint 29, the closing act's design lens on Lane H (board
  # ux-design-2026-11-12-sprint29/07, section ⑨, drawn before these fixes):
  # the basis sentence under the chart, the logarithmic scale on „Zyklus“
  # and a price axis that never goes below 0, the labels at the plot's
  # edges and in „Ausgerichtet“, the disabled „Jetzt lesen“, and „Bänder
  # und ihre Teile“ at 1200 px. The coin, its halvings and its closes are
  # synthetic (`Portfolixir.CycleFixtures`); the stored closes run from
  # 2013-01-10 to 2020-05-01.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.CycleFixtures
  import PortfolixirWeb.PreferenceCookieHelpers, only: [put_preference_cookie: 3]

  defp chart_path(security), do: "/securities/#{security.id}?tab=chart"

  defp open_max(conn, security) do
    {:ok, view, _html} = live(conn, chart_path(security))
    view |> element("button[phx-value-range='MAX']") |> render_click()
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
  defp num(node, name), do: node |> attr(name) |> Float.parse() |> elem(0)

  # The y of a marker's path, `M x,y …`.
  defp marker_y(node) do
    [_x, y] = Regex.run(~r/^M\s*([-\d.]+)[ ,]([-\d.]+)/, attr(node, "d"), capture: :all_but_first)
    y |> Float.parse() |> elem(0)
  end

  # User story (board 07 ④, ⑤, ⑨ item 1 and ⑩; DESIGN.md H7 item 3 and
  # I1):
  # As the operator reading the bands on the chart,
  # I want the basis under the chart while the bands are drawn, one
  # sentence ending „not a forecast“ with the method behind its ⓘ,
  # so that the sentence is there where the bands are, not in a closed
  # disclosure, and the screen shows its basis, not a paragraph of method.
  #
  # Acceptance criteria:
  # - With cycles on, on the time axis, a line under the chart names the
  #   basis in one visible sentence of at most 25 words ending „not a
  #   forecast.“; its ⓘ holds the gaps, the extremes and the band's rule
  #   („the hull of the parts, no average“), and on „Zyklus“ first the
  #   range's own sentence. None with cycles off or in „Aligned“, which has
  #   its own.
  # - The German line ends „keine Prognose.“, its ⓘ starts with „Bereich
  #   „Zyklus““.
  test "the basis sentence stands under the chart while the bands are drawn", %{conn: conn} do
    coin = synthetic_cycle_coin!()
    view = open_max(conn, coin)
    refute has_element?(view, "[data-role='cycle-basis']")

    cycles_on(view)
    {line, tip} = basis_line(view)
    assert line =~ ~r/^Basis: stored daily closes in USD, .* not a forecast\.$/
    assert words(line) <= 25
    assert tip =~ "the hull of the parts, no average."
    refute tip =~ "Range"

    view |> element("button[phx-value-range='CYCLE']") |> render_click()
    {line, tip} = basis_line(view)
    assert line =~ ~r/not a forecast\.$/
    assert tip =~ ~r/^Range „Cycle“: three months before the last confirmed halving/

    view |> element("#cycle-mode-aligned") |> render_click()
    refute has_element?(view, "[data-role='cycle-basis']")

    german = put_preference_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(german, chart_path(coin) <> "&cycles=1")
    {line, tip} = basis_line(view)
    assert line =~ ~r/keine Prognose\.$/
    assert words(line) <= 25
    assert tip =~ ~r/^Bereich „Zyklus“/
  end

  # The basis line's visible sentence (its text before the ⓘ) and the
  # method behind its ⓘ.
  defp basis_line(view) do
    [basis] = nodes(view, "[data-role='cycle-basis']")
    [tip] = nodes(view, "[data-role='cycle-basis'] details.metric-tooltip p")
    [line | _] = basis |> text() |> String.split("ⓘ")
    {String.trim(line), text(tip)}
  end

  # Words as L5's walk counts them (test/browser/control_bar.js).
  defp words(text),
    do: text |> String.split() |> Enum.count(&Regex.match?(~r/[\p{L}\p{N}]/u, &1))

  # User story (board 07 ⑤ and ⑨ item 2):
  # As the operator choosing „Zyklus“,
  # I want the logarithmic scale and a price axis that stays above 0,
  # so that a low band a tenth of the top's price is a band and not a
  # sliver under an axis of negative prices.
  #
  # Acceptance criteria:
  # - Choosing „Zyklus“ turns the logarithmic scale on; so does arriving
  #   with `cycles=1`.
  # - At „Max“ with cycles on and the linear scale, no price on the axis is
  #   below 0.
  test "„Zyklus“ turns the logarithmic scale on, and a price axis stays at 0 or above",
       %{conn: conn} do
    coin = synthetic_cycle_coin!()
    view = conn |> open_max(coin) |> cycles_on()
    assert has_element?(view, "#toggle-log[aria-pressed='false']")

    for tick <- nodes(view, ".security-chart text.chart-axis-y") do
      refute text(tick) =~ ~r/^[-−]/, "a price below 0 on the axis: #{text(tick)}"
    end

    view |> element("button[phx-value-range='CYCLE']") |> render_click()
    assert has_element?(view, "#toggle-log[aria-pressed='true']")

    {:ok, view, _html} = live(conn, chart_path(coin) <> "&cycles=1")
    assert has_element?(view, "#toggle-log[aria-pressed='true']")
  end

  # User story (board 07 ⑨ item 3):
  # As the operator reading a top or a low,
  # I want its label whole and off its marker,
  # so that a label at the plot's right edge or floor can be read.
  #
  # Acceptance criteria:
  # - At „Max“, the open window's low so far (05.2020, on the right edge)
  #   has its label anchored at its end, the first top (06.2013, near the
  #   left edge) at its start; a label in the middle is centred.
  # - The lowest low (09.2014, on the floor) has its label above its
  #   marker.
  # - In „Aligned“ no two labels cover each other.
  test "labels at the plot's edges stay whole and off their markers", %{conn: conn} do
    coin = synthetic_cycle_coin!()
    view = conn |> open_max(coin) |> cycles_on()

    [so_far] = nodes(view, "text.cycle-label--low[data-date='2020-05-01']")
    assert attr(so_far, "text-anchor") == "end"
    [first] = nodes(view, "text.cycle-label--top[data-date='2013-06-01']")
    assert attr(first, "text-anchor") == "start"
    [middle] = nodes(view, "text.cycle-label--top[data-date='2017-08-01']")
    assert attr(middle, "text-anchor") == "middle"

    [low_label] = nodes(view, "text.cycle-label--low[data-date='2014-09-01']")
    [low_mark] = nodes(view, "path.cycle-low[data-date='2014-09-01']")
    assert num(low_label, "y") < marker_y(low_mark) - 8

    view |> element("#cycle-mode-aligned") |> render_click()

    labels =
      for node <- nodes(view, "[data-role='cycle-aligned'] text.cycle-label"),
          do: {num(node, "x"), num(node, "y"), text(node)}

    for {a, i} <- Enum.with_index(labels), {b, j} <- Enum.with_index(labels), i < j do
      {ax, ay, at} = a
      {bx, by, bt} = b

      refute abs(ax - bx) < 90 and abs(ay - by) < 12,
             "„#{at}“ and „#{bt}“ cover each other"
    end
  end

  # User story (board 07 ⑨ item 5):
  # As the operator reading „Bands and their parts“,
  # I want a part that is absent to carry no badge,
  # so that „provisional“ never marks a figure that is not there.
  #
  # Acceptance criteria:
  # - Low → top waits (low_not_final): its row has no badge.
  test "a part that is absent carries no badge", %{conn: conn} do
    coin = synthetic_cycle_coin!()
    view = conn |> open_max(coin) |> cycles_on()

    assert has_element?(view, "tr.cycle-bands__part[data-relation='low_to_top']")
    refute has_element?(view, "tr.cycle-bands__part[data-relation='low_to_top'] .badge")
    assert has_element?(view, "tr.cycle-bands__part[data-relation='top_to_top'] .badge")
  end
end
