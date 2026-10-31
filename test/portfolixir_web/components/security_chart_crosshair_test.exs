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
    # #1163 (Sprint 21 γ2, board 02 ⑥): the second slot is the display
    # close and a fifth slot the display date; the ISO date stays first.
    assert [iso, close_str, x, y, shown_date] = List.first(payload["points"])
    assert iso == "2026-05-13"
    assert close_str == "100.00"
    assert shown_date == "2026-05-13"
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
      |> Enum.map(fn [_iso, _close, x, _y, _shown_date] -> x end)

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

  defp in_german(fun) do
    previous = Gettext.get_locale(PortfolixirWeb.Gettext)
    Gettext.put_locale(PortfolixirWeb.Gettext, "de")

    try do
      fun.()
    after
      Gettext.put_locale(PortfolixirWeb.Gettext, previous)
    end
  end

  @layout File.read!("lib/portfolixir_web/layout_view.ex")

  defp hook_function(name) do
    [_, hook] = Regex.run(~r/Hooks\.ChartCrosshair = \{(.*?)\n            \};/s, @layout)

    [_, body] =
      Regex.run(~r/\n              #{name}: function \((.*?)\n              \},?\n/s, hook)

    body
  end

  # User story (#1163, Sprint 21 γ2; board 02, ⑥): As the operator reading a
  # security's chart in German, I want the crosshair tooltip and the trade
  # markers to read "15.05.2026", "41,40 USD" and "Kauf 12 zu 41,12 USD",
  # so that the last chart strings in ISO, raw decimals and English read in
  # the page's language like every other date and figure.
  #
  # Acceptance criteria:
  # - The server sends display strings beside the raw values: `points[i][1]`
  #   is the close through `Format.decimal(close, 2)`, `points[i][4]` the
  #   date through `Format.date`, `txs[i].label` the trade line ("%{kind}
  #   %{quantity} at %{price} %{currency}": the kind's label, the quantity as
  #   stored, the price by the history's stored-figure rule, the booking's
  #   currency).
  # - The ISO date stays at `points[i][0]` and the raw quantity and price
  #   stay on the trade, because the zoom sends the dates back.
  # - The marker's title reads "Kauf am 15.05.2026 zu 41,12 USD".
  test "the payload carries display strings in the page's language beside the raw values" do
    in_german(fn ->
      html =
        render_chart(
          default_assigns(
            quotes: [quote_fixture(~D[2026-05-14], "40.9"), quote_fixture(~D[2026-05-15], "41.4")],
            transactions: [
              %{
                date: ~D[2026-05-15],
                type: "buy",
                quantity: Decimal.new("12"),
                price: Decimal.new("41.12"),
                currency_code: "USD"
              }
            ]
          )
        )

      payload = extract_payload(html)

      assert [_first, ["2026-05-15", "41,40", _x, _y, "15.05.2026"]] = payload["points"]

      assert [tx] = payload["txs"]
      assert tx["label"] == "Kauf 12 zu 41,12 USD"
      assert tx["date"] == "2026-05-15"
      assert tx["quantity"] == "12"
      assert tx["price"] == "41.12"

      titles =
        html
        |> Floki.parse_fragment!()
        |> Floki.find("path.tx-marker title")
        |> Enum.map(&String.trim(Floki.text(&1)))

      assert titles == ["Kauf am 15.05.2026 zu 41,12 USD"]
    end)
  end

  # User story (#1163, Sprint 21 γ2; board 02, ⑥): As the operator reading
  # the chart in its percent view, I want the tooltip to print the axis's
  # signed percent, so that the hovered point reads "+10,0%" as its axis
  # does, not the raw close with a currency.
  #
  # Acceptance criteria:
  # - A percent-mode point's display slot is the signed percent against the
  #   first close, one decimal with the sign glued on.
  # - A quote's own `label` (Wealth's and the snapshots' charts) still wins,
  #   and those charts get the display date too (found while drawing 3).
  test "a percent-mode point reads the signed percent, and a label still wins" do
    in_german(fn ->
      percent =
        render_chart(
          default_assigns(
            percent_mode?: true,
            quotes: [quote_fixture(~D[2026-05-14], "100"), quote_fixture(~D[2026-05-15], "110")]
          )
        )
        |> extract_payload()

      assert [["2026-05-14", "0,0%", _, _, "14.05.2026"], ["2026-05-15", "+10,0%", _, _, _]] =
               percent["points"]

      labelled =
        render_chart(
          default_assigns(
            value_mode: :percent_values,
            quotes: [
              %{date: ~D[2026-05-15], close: Decimal.new("8"), label: "+8,0% · 1.080,00 EUR"}
            ]
          )
        )
        |> extract_payload()

      assert [["2026-05-15", "+8,0% · 1.080,00 EUR", _, _, "15.05.2026"]] = labelled["points"]
    end)
  end

  # User story (#1163, Sprint 21 γ2; board 02, ⑥): As the operator hovering
  # the chart, I want the hook to print the display strings the server sent,
  # so that the tooltip reads the page's language without the hook knowing
  # any locale.
  #
  # Acceptance criteria:
  # - `renderTooltip` prints the display date (`point[4]`) and the trade's
  #   `label`; the English "type quantity @ price" line is gone.
  # - A percent-mode point carries no currency suffix.
  # - Every value still goes in through `textContent` (#770).
  test "the crosshair hook prints the server's display strings through textContent" do
    move = hook_function("handleMove")
    assert move =~ "point[4]"

    tooltip = hook_function("renderTooltip")
    assert tooltip =~ "tx.label"
    refute tooltip =~ ~s(" @ ")
    assert tooltip =~ ~s("percent")
    assert tooltip =~ "textContent"
    refute tooltip =~ "innerHTML"
  end
end
