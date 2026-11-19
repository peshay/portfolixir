defmodule PortfolixirWeb.Components.SecurityChartAxisBreakTest do
  # I43 (Sprint 30 W1; board `ux-design-2026-11-15-sprint30/01-axis-start`,
  # answer C; plan D-6): the shared line chart says where its axis starts.
  # Wherever an axis that reads an amount does not start at 0 its foot
  # carries the axis-break mark (≈) and its accessible name says so in
  # words; an axis that starts at 0 or below, the logarithmic scale and a
  # series already in percent carry none. `axis_start: :zero` („ab 0“)
  # draws the line on the stacked chart's axis: from 0 to the highest value
  # plus 5 %, in its round steps.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.Components.SecurityChart
  alias PortfolixirWeb.PrivacyMode

  defp series(closes) do
    closes
    |> Enum.with_index()
    |> Enum.map(fn {close, i} ->
      %{date: Date.add(~D[2026-03-02], i), close: Decimal.new(close)}
    end)
  end

  defp chart(closes, opts \\ []) do
    assigns =
      Map.merge(
        %{
          quotes: series(closes),
          transactions: [],
          show_transactions?: false,
          currency_code: "EUR"
        },
        Map.new(opts)
      )

    render_component(&SecurityChart.chart/1, assigns)
  end

  defp doc(html), do: Floki.parse_fragment!(html)

  defp marks(html), do: html |> doc() |> Floki.find("svg g.chart-axis-break")

  defp aria(html), do: html |> doc() |> Floki.attribute("svg", "aria-label") |> List.first()

  defp y_labels(html) do
    html
    |> doc()
    |> Floki.find("g.chart-axis-labels text.chart-axis-y")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end

  defp grid_ys(html) do
    html
    |> doc()
    |> Floki.find("g.chart-axes line")
    |> Enum.map(fn line -> line |> Floki.attribute("y1") |> hd() |> String.to_float() end)
  end

  # User story (I43; board 01 ② and ④, answer C):
  # As the operator reading a price or a value line whose axis is cut,
  # I want a mark at the axis' foot wherever it does not start at 0,
  # so that a dent does not read as a crash.
  #
  # Acceptance criteria:
  # - A price axis above 0 (closes 100 to 120, the axis from 99) draws one
  #   mark, at the plot's lower left corner, decorative (`aria-hidden`);
  #   the chart's name says it in words: „Price chart · axis from 99.00,
  #   not from 0“. The lowest value label stays.
  # - A value line above 0 (Wealth's Total) draws it too.
  # - A price axis that reaches 0 (its pad stops at 0) draws none, nor does
  #   an axis below 0, the logarithmic scale (it has no 0) or a series in
  #   percent (TTWROR, its zero line).
  test "the mark is drawn exactly where an amount axis does not start at 0" do
    priced = chart(["100", "110", "120"], price_axis?: true)

    assert [mark] = marks(priced)
    assert Floki.attribute(mark, "aria-hidden") == ["true"]
    assert Floki.attribute(mark, "transform") == ["translate(56 292)"]
    assert aria(priced) == "Price chart · axis from 99.00, not from 0"
    assert hd(y_labels(priced)) == "99.00"

    value = chart(["76618", "80000", "88307"], aria_label: "Value over time")
    assert [_mark] = marks(value)
    assert aria(value) == "Value over time · axis from 76,034, not from 0"

    assert marks(chart(["0", "5", "10"], price_axis?: true)) == []
    assert aria(chart(["0", "5", "10"], price_axis?: true)) == "Price chart"
    assert marks(chart(["-50", "100"])) == []
    assert marks(chart(["100", "110", "120"], log_scale?: true)) == []

    assert marks(chart(["5", "8", "10"], value_mode: :percent_values, zero_line?: true)) ==
             []
  end

  # User story (I43; board 01 ⑥):
  # As the operator showing a value chart in the privacy mode,
  # I want its percent axis to carry the mark too,
  # so that it says the amount axis does not start at 0 without a figure.
  #
  # Acceptance criteria:
  # - In the privacy mode a value line above 0 reads in percent of its
  #   first value and carries the mark: its floor, −0,8 % of the first
  #   value, is above −100 %, an amount of 0. Its name says so in percent.
  # - A security's own percent view does the same.
  # - Where the percent axis reaches −100 % (a price of 0) it carries none.
  test "a percent axis of an amount carries the mark while its floor is above -100 %" do
    PrivacyMode.put(true)
    on_exit(fn -> PrivacyMode.put(false) end)

    masked = chart(["100", "110", "120"])
    assert [_mark] = marks(masked)
    assert aria(masked) == "Price chart · axis from -1.0%, not from 0"
    refute aria(masked) =~ "99"

    assert marks(chart(["0", "5000", "6000"], price_axis?: true)) == []

    PrivacyMode.put(false)
    assert [_mark] = marks(chart(["100", "110", "120"], percent_mode?: true))
  end

  # User story (I43; board 01 ③ and ④, „ab 0“):
  # As the operator comparing Total with the stack at Kategorien,
  # I want the line drawn from 0 on the stack's axis,
  # so that it reads like the stack's top edge.
  #
  # Acceptance criteria:
  # - `axis_start: :zero` spans the axis from 0 to the highest value plus
  #   5 % (88,307 → 92,722.35) and labels the stack's round steps: 0,
  #   20,000, 40,000, 60,000, 80,000, each on its grid line; no mark, the
  #   chart's own name.
  # - The highest value lies at 1/1.05 of the plot's height above its foot.
  # - In the privacy mode, on a series in percent and on the logarithmic
  #   scale „ab 0“ does not apply: the chart is the one without it.
  test "axis_start :zero draws the line on the stack's axis" do
    zero = chart(["76618", "80000", "88307"], axis_start: :zero, aria_label: "Value over time")

    assert y_labels(zero) == ["0", "20,000", "40,000", "60,000", "80,000"]
    assert marks(zero) == []
    assert aria(zero) == "Value over time"

    plot_h = 292.0 - 16.0
    span = 88_307 * 1.05
    expected = Enum.map([0, 20_000, 40_000, 60_000, 80_000], &(292.0 - plot_h * &1 / span))

    for {got, want} <- Enum.zip(grid_ys(zero), expected),
        do: assert(abs(got - want) < 0.01, inspect({got, want}))

    [_, top_y] =
      zero
      |> doc()
      |> Floki.attribute("polyline.quote-line", "points")
      |> hd()
      |> String.split()
      |> List.last()
      |> String.split(",")

    assert abs(String.to_float(top_y) - (292.0 - plot_h / 1.05)) < 0.01

    for opts <- [[value_mode: :percent_values], [log_scale?: true]] do
      assert strip(chart(["5", "8", "10"], opts ++ [axis_start: :zero])) ==
               strip(chart(["5", "8", "10"], opts))
    end

    PrivacyMode.put(true)
    on_exit(fn -> PrivacyMode.put(false) end)

    assert strip(chart(["100", "110", "120"], axis_start: :zero)) ==
             strip(chart(["100", "110", "120"]))
  end

  defp strip(html), do: String.replace(html, ~r/chart-[0-9a-f]{12}/, "chart-ID")
end
