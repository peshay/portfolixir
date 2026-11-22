defmodule PortfolixirWeb.DashboardLineTest do
  # Sprint 31 closing act, money lens MO5 (S3): the M size's value line
  # labels its axis with the period's lowest and highest value, every
  # day's, but drew its path through the thinned points only, so a day
  # between two kept points could stand on the axis and be missing from
  # the line. Synthetic values only.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.Dashboard.Widgets.Line
  alias PortfolixirWeb.Format

  # 400 days at 100, but for a high of 200 on the second day and a low of
  # 50 on the third: even thinning to 160 points keeps days 0, 3, 5, … and
  # neither extreme.
  defp points do
    start = ~D[2025-01-01]

    for i <- 0..399 do
      value =
        case i do
          1 -> "200"
          2 -> "50"
          _ -> "100"
        end

      %{date: Date.add(start, i), value: Decimal.new(value)}
    end
  end

  # The path's y coordinates, top of the plot 8, bottom 156.
  defp ys(html) do
    [d] = html |> Floki.parse_fragment!() |> Floki.find("path") |> Floki.attribute("d")

    ~r/[ML][\d.]+ ([\d.]+)/
    |> Regex.scan(d)
    |> Enum.map(fn [_, y] -> String.to_float(y) end)
  end

  # User story:
  # As the operator reading „Wertentwicklung“ at M,
  # I want the line to reach the highest and the lowest value its axis
  # names,
  # so that the axis and the line tell one story.
  #
  # Acceptance criteria:
  # - Thinning keeps the first, the last, the lowest and the highest
  #   point, beside the evenly spaced ones.
  # - The path's top is the axis's top label and its bottom the bottom
  #   label: the highest value's y is the plot's top, the lowest's its
  #   bottom.
  test "the thinned line keeps the extremes the axis names" do
    points = points()
    thinned = Line.thin(points)

    assert Enum.any?(thinned, &Decimal.equal?(&1.value, 200))
    assert Enum.any?(thinned, &Decimal.equal?(&1.value, 50))
    assert hd(thinned) == hd(points)
    assert List.last(thinned) == List.last(points)
    assert thinned == Enum.sort_by(thinned, & &1.date, Date)

    html = render_component(&Line.chart/1, points: points, currency: "EUR", id: "line-probe")
    ys = ys(html)
    assert Enum.min(ys) == 8.0
    assert Enum.max(ys) == 156.0

    doc = Floki.parse_fragment!(html)

    assert doc |> Floki.find("[data-role='line-high']") |> Floki.text() ==
             Format.money(Decimal.new("200"))

    assert doc |> Floki.find("[data-role='line-low']") |> Floki.text() ==
             Format.money(Decimal.new("50"))
  end
end
