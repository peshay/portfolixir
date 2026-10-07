defmodule PortfolixirWeb.Components.SecurityChartTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.Components.SecurityChart

  defp render_chart(assigns) do
    render_component(&SecurityChart.chart/1, assigns)
  end

  defp quote_fixture(date, close) do
    %{date: date, close: Decimal.new(close)}
  end

  defp default_assigns(overrides) do
    Map.merge(
      %{
        quotes: [],
        transactions: [],
        log_scale?: false,
        show_transactions?: true,
        currency_code: "USD"
      },
      Map.new(overrides)
    )
  end

  test "renders an empty-state SVG when no quotes are present" do
    html = render_chart(default_assigns(quotes: []))
    assert html =~ "no-quotes"
  end

  test "renders a polyline through the provided quotes in chronological order" do
    quotes = [
      quote_fixture(~D[2026-05-13], "100"),
      quote_fixture(~D[2026-05-14], "110"),
      quote_fixture(~D[2026-05-15], "120")
    ]

    html = render_chart(default_assigns(quotes: quotes))

    assert html =~ ~s(<polyline)
    assert html =~ "points="
  end

  test "renders an area-fill path under the line" do
    quotes = [
      quote_fixture(~D[2026-05-13], "100"),
      quote_fixture(~D[2026-05-14], "110"),
      quote_fixture(~D[2026-05-15], "120")
    ]

    html = render_chart(default_assigns(quotes: quotes))

    # quote-area path renders as <path class="quote-area" d="M..."> and the
    # area closes back to the X axis with `Z`.
    assert html =~ ~s(class="quote-area")
    assert html =~ "Z\""
  end

  test "applies an is-log class when log_scale? is true" do
    quotes = [
      quote_fixture(~D[2026-05-13], "100"),
      quote_fixture(~D[2026-05-15], "110")
    ]

    html = render_chart(default_assigns(quotes: quotes, log_scale?: true))
    assert html =~ "is-log"
  end

  test "draws a buy marker at the close on the transaction date" do
    quotes = [quote_fixture(~D[2026-05-15], "100")]

    transactions = [
      %{date: ~D[2026-05-15], type: "buy", quantity: Decimal.new("1"), price: Decimal.new("100")}
    ]

    html = render_chart(default_assigns(quotes: quotes, transactions: transactions))

    assert html =~ ~s(class="tx-marker tx-buy")
  end

  # User story:
  # As a local portfolio maintainer opening a security detail chart,
  # I want the chart renderer to tolerate legacy numeric values,
  # so that a stale or imported row cannot crash the page with
  # `Decimal.to_string/2`.
  #
  # Acceptance criteria:
  # - Numeric quote closes render without raising.
  # - Numeric transaction quantity and price render in the payload.
  # - No persisted financial value is converted to float by this test; this
  #   only guards the view boundary.
  test "renders legacy numeric quote and transaction values without crashing" do
    quotes = [
      %{date: ~D[2026-05-14], close: 99.5},
      %{date: ~D[2026-05-15], close: 100.25}
    ]

    transactions = [
      %{date: ~D[2026-05-15], type: "buy", quantity: 1, price: 100.25}
    ]

    html = render_chart(default_assigns(quotes: quotes, transactions: transactions))

    assert html =~ ~s(class="tx-marker tx-buy")
    assert html =~ "100.25"
  end

  # User story:
  # As a local portfolio maintainer with dividend history,
  # I want the price chart to ignore non-trade ledger entries,
  # so that opening the chart tab cannot crash on a transaction without a
  # unit price.
  #
  # Acceptance criteria:
  # - A dividend row with nil quantity and nil price does not raise.
  # - The chart still renders the price line.
  # - No dividend marker is emitted because only buy/sell markers belong in
  #   the price chart.
  test "ignores non-trade transactions without unit prices" do
    quotes = [quote_fixture(~D[2026-05-15], "100")]

    transactions = [
      %{date: ~D[2026-05-15], type: "dividend", quantity: nil, price: nil}
    ]

    html = render_chart(default_assigns(quotes: quotes, transactions: transactions))

    assert html =~ ~s(class="quote-line")
    refute html =~ "tx-dividend"
  end

  test "positions quote points by calendar date so markers stay aligned" do
    # User story:
    # As a local portfolio maintainer,
    # I want a transaction marker on day N to land on the price line on day N,
    # so weekends/holidays in the quote history don't make the chart lie.
    #
    # The chart used to space points by index, so Fri/Mon/Tue (span 4 days)
    # rendered Mon at 50% width while a Mon transaction marker landed at
    # 75%. Both should land at 75% now.
    quotes = [
      quote_fixture(~D[2026-05-08], "100"),
      quote_fixture(~D[2026-05-11], "104"),
      quote_fixture(~D[2026-05-12], "108")
    ]

    transactions = [
      %{date: ~D[2026-05-11], type: "buy", quantity: Decimal.new("1"), price: Decimal.new("104")}
    ]

    html = render_chart(default_assigns(quotes: quotes, transactions: transactions))

    # The marker path is apex-first, so the apex x is the anchor x.
    marker_cx = Regex.run(~r/tx-marker tx-buy"\s+d="M([0-9.]+),/, html) |> Enum.at(1)

    # Polyline points are space-separated "x,y" pairs. The Monday point is
    # the second one; its x must match the marker's cx.
    points_attr = Regex.run(~r/<polyline[^>]*points="([^"]+)"/, html) |> Enum.at(1)
    [_first, monday, _last] = String.split(points_attr, " ", trim: true)
    [monday_x, _y] = String.split(monday, ",")

    assert marker_cx == monday_x
  end

  test "draws a sell marker for sell transactions" do
    quotes = [quote_fixture(~D[2026-05-15], "100")]

    transactions = [
      %{date: ~D[2026-05-15], type: "sell", quantity: Decimal.new("1"), price: Decimal.new("100")}
    ]

    html = render_chart(default_assigns(quotes: quotes, transactions: transactions))
    assert html =~ ~s(class="tx-marker tx-sell")
  end

  # User story:
  # As a portfolio maintainer who cannot rely on hue,
  # I want buy and sell markers shape-coded as up and down triangles,
  # so that the transaction direction stays readable without the colour
  # channel (UX-DR7, issue 645 — the SVG carries role="img", so the <title>
  # fallback inside a marker is unreachable and shape is the only channel).
  #
  # Acceptance criteria:
  # - Markers render as <path> triangles, not circles.
  # - The buy triangle points up (apex above its base), the sell triangle
  #   points down.
  test "shape-codes buy and sell markers as up/down triangles" do
    quotes = [
      quote_fixture(~D[2026-05-14], "100"),
      quote_fixture(~D[2026-05-15], "100")
    ]

    transactions = [
      %{date: ~D[2026-05-14], type: "buy", quantity: Decimal.new("1"), price: Decimal.new("100")},
      %{date: ~D[2026-05-15], type: "sell", quantity: Decimal.new("1"), price: Decimal.new("100")}
    ]

    html = render_chart(default_assigns(quotes: quotes, transactions: transactions))

    refute html =~ ~s(<circle class="tx-marker)

    assert [_, buy_d] = Regex.run(~r/class="tx-marker tx-buy"\s+d="([^"]+)"/, html)
    assert [_, sell_d] = Regex.run(~r/class="tx-marker tx-sell"\s+d="([^"]+)"/, html)

    {buy_apex_y, buy_base_y} = triangle_ys(buy_d)
    assert buy_apex_y < buy_base_y, "buy triangle must point up: #{buy_d}"

    {sell_apex_y, sell_base_y} = triangle_ys(sell_d)
    assert sell_apex_y > sell_base_y, "sell triangle must point down: #{sell_d}"
  end

  # The marker path is apex-first: "M apex L base-corner L base-corner Z".
  defp triangle_ys(d) do
    [[_, _, apex_y], [_, _, base_y] | _] = Regex.scan(~r/([0-9.]+)[ ,]([0-9.]+)/, d)
    {elem(Float.parse(apex_y), 0), elem(Float.parse(base_y), 0)}
  end

  # User story:
  # As a German-locale maintainer opening a security without quotes,
  # I want the chart's empty state localized,
  # so that the German UI never shows the raw English string (issue 640 —
  # the literal bypassed gettext, so localization_test could not see it).
  #
  # Acceptance criteria:
  # - The empty state and the default aria-label go through gettext.
  test "localizes the empty state" do
    Gettext.put_locale(PortfolixirWeb.Gettext, "de")

    html = render_chart(default_assigns(quotes: []))

    assert html =~ "Noch keine Kurshistorie."
    refute html =~ "No price history yet."
  after
    Gettext.put_locale(PortfolixirWeb.Gettext, "en")
  end

  test "omits transaction markers when show_transactions? is false" do
    quotes = [quote_fixture(~D[2026-05-15], "100")]

    transactions = [
      %{date: ~D[2026-05-15], type: "buy", quantity: Decimal.new("1"), price: Decimal.new("100")}
    ]

    html =
      render_chart(
        default_assigns(quotes: quotes, transactions: transactions, show_transactions?: false)
      )

    refute html =~ "tx-marker"
  end

  describe "the axes (Sprint 19 PR γ U3, issue 1088; board 05, pick J5 A)" do
    defp in_locale(locale, fun) do
      previous = Gettext.get_locale(PortfolixirWeb.Gettext)
      Gettext.put_locale(PortfolixirWeb.Gettext, locale)

      try do
        fun.()
      after
        Gettext.put_locale(PortfolixirWeb.Gettext, previous)
      end
    end

    defp axis_labels(html, class) do
      html
      |> Floki.parse_fragment!()
      |> Floki.find("g.chart-axis-labels text.#{class}")
      |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
    end

    # 10 000 → 20 000, padded by 5 %: the five ticks are 9 500, 12 250,
    # 15 000, 17 750 and 20 500.
    defp value_chart do
      render_chart(
        default_assigns(
          quotes: [
            quote_fixture(~D[2025-10-04], "10000"),
            quote_fixture(~D[2026-10-04], "20000")
          ]
        )
      )
    end

    # A series that already is a percentage: 0 → 8, padded to -0,4 … 8,4.
    defp percent_chart(closes) do
      quotes =
        closes
        |> Enum.with_index()
        |> Enum.map(fn {close, i} -> quote_fixture(Date.add(~D[2025-10-04], i), close) end)

      render_chart(default_assigns(quotes: quotes, value_mode: :percent_values))
    end

    # User story:
    # As a German-speaking portfolio maintainer reading a chart,
    # I want its axis to print dates and figures the way the KPI band above
    # it does,
    # so that "2025-10-04", "12500" and "+10.4 %" stop standing under
    # "+8,9%" and "14.218,40 EUR".
    #
    # Acceptance criteria:
    # - The two dates read DD.MM.YYYY.
    # - A value axis groups its thousands ("12.250"), keeps two places from 1
    #   and none from 1 000, with the decimal comma.
    # - A percent axis reads the house signed percent, the sign glued on and
    #   no space before "%": "+8,4%", "-0,4%", and a tick that reads zero
    #   carries no sign ("0,0%").
    test "German axes print dates, values and percents in the page's language" do
      in_locale("de", fn ->
        html = value_chart()

        assert axis_labels(html, "chart-axis-x") == ["04.10.2025", "04.10.2026"]

        assert axis_labels(html, "chart-axis-y") ==
                 ["9.500", "12.250", "15.000", "17.750", "20.500"]

        cents =
          render_chart(
            default_assigns(
              quotes: [
                quote_fixture(~D[2026-09-01], "100"),
                quote_fixture(~D[2026-09-30], "120")
              ]
            )
          )

        assert axis_labels(cents, "chart-axis-y") ==
                 ["99,00", "104,50", "110,00", "115,50", "121,00"]

        assert axis_labels(percent_chart(["0", "8"]), "chart-axis-y") ==
                 ["-0,4%", "+1,8%", "+4,0%", "+6,2%", "+8,4%"]

        assert axis_labels(percent_chart(["-1", "1"]), "chart-axis-y") ==
                 ["-1,1%", "-0,6%", "0,0%", "+0,6%", "+1,1%"]
      end)
    end

    # Acceptance criteria (U3 review, finding 4):
    # - A value tick takes its places by its size, not its sign: a negative
    #   tick of thousands reads none ("-20.500"), not four.
    # - Below 1 a tick keeps four places ("0,5000").
    test "a tick's places follow its size, whatever its sign" do
      in_locale("de", fn ->
        negative =
          render_chart(
            default_assigns(
              quotes: [
                quote_fixture(~D[2025-10-04], "-20000"),
                quote_fixture(~D[2026-10-04], "-10000")
              ]
            )
          )

        assert axis_labels(negative, "chart-axis-y") ==
                 ["-20.500", "-17.750", "-15.000", "-12.250", "-9.500"]

        small =
          render_chart(
            default_assigns(
              quotes: [
                quote_fixture(~D[2025-10-04], "0.4"),
                quote_fixture(~D[2026-10-04], "0.6")
              ]
            )
          )

        assert axis_labels(small, "chart-axis-y") ==
                 ["0,3900", "0,4450", "0,5000", "0,5550", "0,6100"]
      end)
    end

    # Acceptance criteria:
    # - English keeps ISO dates and the decimal point, groups thousands with
    #   a comma, and glues the percent sign on too.
    test "English axes keep ISO dates and the decimal point" do
      in_locale("en", fn ->
        html = value_chart()

        assert axis_labels(html, "chart-axis-x") == ["2025-10-04", "2026-10-04"]

        assert axis_labels(html, "chart-axis-y") ==
                 ["9,500", "12,250", "15,000", "17,750", "20,500"]

        assert axis_labels(percent_chart(["0", "8"]), "chart-axis-y") ==
                 ["-0.4%", "+1.8%", "+4.0%", "+6.2%", "+8.4%"]
      end)
    end

    # User story (J5 A, rule ③):
    # As a portfolio maintainer reading a chart on a phone,
    # I want the axis values inside the plot where the gutter is too narrow,
    # each on its own grid line, legible over the line and the fill,
    # so that the axis keeps its five values at a size I can read.
    #
    # Acceptance criteria:
    # - The five values carry `chart-axis-y`, the top one also `is-top`; the
    #   two dates carry `chart-axis-x`.
    # - The label group comes after the area and the line in the markup, so
    #   a label's halo paints over the series.
    test "the labels carry their classes and follow the series" do
      html = value_chart()
      doc = Floki.parse_fragment!(html)

      assert length(Floki.find(doc, "g.chart-axis-labels text.chart-axis-y")) == 5
      assert [top] = Floki.find(doc, "g.chart-axis-labels text.chart-axis-y.is-top")
      assert Floki.text(top) |> String.trim() == "20,500"
      assert length(Floki.find(doc, "g.chart-axis-labels text.chart-axis-x")) == 2

      line = :binary.match(html, ~s(class="quote-line")) |> elem(0)
      area = :binary.match(html, ~s(class="quote-area")) |> elem(0)
      labels = :binary.match(html, ~s(class="chart-axis-labels")) |> elem(0)

      assert labels > line
      assert labels > area
    end

    # Acceptance criteria:
    # - A marker's title names its date in the page's language; only the
    #   date changes on that line.
    test "a marker's title carries the date in the page's language" do
      in_locale("de", fn ->
        html =
          render_chart(
            default_assigns(
              quotes: [quote_fixture(~D[2026-05-14], "100"), quote_fixture(~D[2026-05-15], "101")],
              transactions: [
                %{
                  date: ~D[2026-05-15],
                  type: "buy",
                  quantity: Decimal.new("1"),
                  price: Decimal.new("101")
                }
              ]
            )
          )

        assert html =~ "buy on 15.05.2026 at 101"
        refute html =~ "buy on 2026-05-15"
      end)
    end
  end
end
