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
end
