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

    marker_cx = Regex.run(~r/tx-marker tx-buy"\s+cx="([0-9.]+)"/, html) |> Enum.at(1)

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
