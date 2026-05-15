defmodule PortfolixirWeb.Components.SecurityChartCrosshairTest do
  # User story:
  # As a local portfolio maintainer,
  # I want to hover or touch the price chart and see the exact date and close
  # price under my cursor, so I can read individual data points without an
  # external chart library.
  #
  # Acceptance criteria (structural, see live test for runtime behaviour):
  # - The chart wraps in a `.chart-frame` carrying `phx-hook="ChartCrosshair"`
  #   and a stable `data-chart-id` for the JS hook to scope to.
  # - A `<script type="application/json">` sibling carries the data the hook
  #   needs to render the crosshair + tooltip without a server round-trip:
  #   points (date, close, pixel x, pixel y), transactions (with quantity and
  #   price), and the SVG view box dimensions.
  # - The currency code is exposed for the tooltip suffix.
  # - When `show_transactions?` is false the payload omits transactions.
  # - The empty state still mounts the frame so the hook can no-op cleanly.
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

  defp extract_payload(html) do
    [_, json] =
      Regex.run(
        ~r/<script type="application\/json" data-chart-payload[^>]*>(.*?)<\/script>/s,
        html
      )

    Jason.decode!(json)
  end

  test "wraps the SVG in a chart-frame carrying the crosshair hook" do
    html = render_chart(default_assigns(quotes: [quote_fixture(~D[2026-05-15], "100")]))

    assert html =~ ~s(class="chart-frame")
    assert html =~ ~s(phx-hook="ChartCrosshair")
    assert html =~ ~r/data-chart-id="chart-[a-f0-9]+"/
  end

  test "emits a JSON payload sibling with points, transactions and view dimensions" do
    quotes = [
      quote_fixture(~D[2026-05-13], "100"),
      quote_fixture(~D[2026-05-14], "110"),
      quote_fixture(~D[2026-05-15], "120")
    ]

    txs = [
      %{date: ~D[2026-05-14], type: "buy", quantity: Decimal.new("2"), price: Decimal.new("105")}
    ]

    html = render_chart(default_assigns(quotes: quotes, transactions: txs))
    payload = extract_payload(html)

    assert is_list(payload["points"])
    assert length(payload["points"]) == 3
    assert [iso, close_str, x, y] = List.first(payload["points"])
    assert iso == "2026-05-13"
    assert close_str == "100"
    assert is_number(x)
    assert is_number(y)

    assert [tx] = payload["txs"]
    assert tx["date"] == "2026-05-14"
    assert tx["type"] == "buy"
    assert tx["quantity"] == "2"
    assert tx["price"] == "105"
    assert is_number(tx["x"])
    assert is_number(tx["y"])

    assert payload["view"]["width"] > 0
    assert payload["view"]["height"] > 0
    assert payload["currency"] == "USD"
  end

  test "omits transactions from the payload when show_transactions? is false" do
    quotes = [quote_fixture(~D[2026-05-15], "100")]

    txs = [
      %{date: ~D[2026-05-15], type: "buy", quantity: Decimal.new("1"), price: Decimal.new("100")}
    ]

    html =
      render_chart(default_assigns(quotes: quotes, transactions: txs, show_transactions?: false))

    payload = extract_payload(html)
    assert payload["txs"] == []
  end

  test "renders the chart-frame even in the empty state so the hook mounts cleanly" do
    html = render_chart(default_assigns(quotes: []))

    assert html =~ ~s(class="chart-frame")
    assert html =~ ~s(phx-hook="ChartCrosshair")

    payload = extract_payload(html)
    assert payload["points"] == []
    assert payload["txs"] == []
  end

  test "point x-coordinates line up with polyline point x-coordinates" do
    # The crosshair hook positions itself at the nearest point's pixel-x; that
    # value must equal the polyline's actual pixel-x or the crosshair will
    # drift off the curve.
    quotes = [
      quote_fixture(~D[2026-05-08], "100"),
      quote_fixture(~D[2026-05-11], "104"),
      quote_fixture(~D[2026-05-12], "108")
    ]

    html = render_chart(default_assigns(quotes: quotes))
    payload = extract_payload(html)

    payload_xs =
      payload["points"]
      |> Enum.map(fn [_iso, _close, x, _y] -> x end)

    [_attr, points_attr] = Regex.run(~r/<polyline[^>]*points="([^"]+)"/, html)

    polyline_xs =
      points_attr
      |> String.split(" ", trim: true)
      |> Enum.map(fn pair ->
        [x, _y] = String.split(pair, ",")
        {f, ""} = Float.parse(x)
        f
      end)

    assert length(payload_xs) == length(polyline_xs)

    Enum.zip(payload_xs, polyline_xs)
    |> Enum.each(fn {a, b} ->
      assert_in_delta a / 1, b, 0.05
    end)
  end
end
