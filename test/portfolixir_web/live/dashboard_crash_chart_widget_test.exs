defmodule PortfolixirWeb.DashboardCrashChartWidgetTest do
  # Sprint 32 S5 (I61; board ux-design-2026-11-25-sprint32/11 ①, ②, ③; the
  # owner's description of 2026-11-25): the widget „Crash-Chart“ — the
  # crash benchmark's closes over the period with every crash window
  # shaded and named, the running one stronger — and „Crashes im
  # Vergleich“ with the running fall first and „erholt nach“, each figure
  # compared with the crash routes and the quotes route for the same
  # period. Every name and figure is synthetic.
  #
  # The widgets are drawn from their reads as the page draws them
  # (`render_component/2`): this module chooses the crash benchmark and
  # so runs in group :crash_benchmark, which a module storing a dashboard
  # cannot join; dashboard_theme_kinds_test.exs drives the page itself.
  use PortfolixirWeb.ConnCase, async: true, group: :crash_benchmark

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Settings
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Dashboard.Widgets.CrashChart
  alias PortfolixirWeb.Dashboard.Widgets.Crashes, as: CrashesWidget
  alias PortfolixirWeb.Format

  defp day(offset), do: Date.add(Portfolixir.Clock.today(), offset)

  defp api(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  # The widgets are drawn in German here, so the figures are written so.
  defp de(fun), do: Gettext.with_locale(PortfolixirWeb.Gettext, "de", fun)

  defp percent(nil), do: "—"
  defp percent(value), do: de(fn -> Format.signed_percent(Decimal.new(value)) <> "%" end)

  defp money(%Decimal{} = value), do: de(fn -> Format.money(value) end)
  defp money(value), do: money(Decimal.new(value))

  defp item(kind, size, period) do
    [item] =
      [%{"kind" => kind, "size" => size, "col" => 1, "row" => 1}]
      |> Widget.items(nil, [])
      |> Enum.map(&Widget.with_period(&1, period, true))

    item
  end

  defp draw(fun, assigns) do
    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn -> render_component(fun, assigns) end)
    |> Floki.parse_document!()
  end

  # The index falls three times — two windows recovered, the third
  # running — and a held security falls with it.
  defp crash_world! do
    world = base_world()
    index = create_security!(name: "Synthetic Crash Index", ticker: "SCI")

    put_quotes!(index, [
      {day(-700), "120"},
      {day(-600), "90"},
      {day(-500), "125"},
      {day(-60), "130"},
      {day(-45), "110"},
      {day(-35), "131"},
      {day(-5), "115"},
      {day(-1), "118"}
    ])

    held = create_security!(name: "Synthetic Holding", ticker: "SHD")
    put_quotes!(held, [{day(-700), "50"}, {day(-600), "35"}, {day(-60), "60"}, {day(-5), "50"}])
    deposit!(world, "10000", day(-720))
    buy!(world, held, quantity: "10", price: "45", date: day(-720))
    {:ok, _} = Settings.set_crash_benchmark(Actor.owner_ui(), index.id)

    {:ok, _} =
      Portfolixir.Crashes.name_window(Actor.owner_ui(), "d:#{index.id}:#{day(-60)}", %{
        "name" => "Synthetic dip"
      })

    index
  end

  # User story (board 11 ①, ②):
  # As the operator who looks at the last falls in their year,
  # I want the crash benchmark's closes over the period with every crash
  # window shaded and named, the running one stronger, and the same chart
  # pinned to 1M as the zoom,
  # so that I see the falls in their context without a figure of their own.
  #
  # Acceptance criteria:
  # - At 1J the chart names the benchmark; its first, last, lowest and
  #   highest close equal GET /api/v1/securities/:id/quotes over the
  #   period's from and to (adjusted_close); its windows are the windows
  #   of GET /api/v1/crashes that overlap the period, oldest first, each
  #   labelled with its name and decline, the running one marked running
  #   and drawn stronger.
  # - At 1M only the running window overlaps, and the line starts a month
  #   back.
  # - The compact form lists the same windows, newest first, with their
  #   declines.
  test "„Crash-Chart“ draws the benchmark's closes and the crash windows of the period" do
    index = crash_world!()
    windows = api("/api/v1/crashes")
    listed = windows["detected"] ++ windows["manual"]

    for {period, expected_keys} <- [
          {"1y", Enum.map([day(-60), day(-35)], &"d:#{index.id}:#{&1}")},
          {"1m", ["d:#{index.id}:#{day(-35)}"]}
        ] do
      read = CrashChart.read(period)
      doc = draw(&CrashChart.widget/1, item: item("crash_chart", "XL", period), card: read)

      quotes =
        api("/api/v1/securities/#{index.id}/quotes?from=#{read.from}&to=#{read.to}")

      closes = Enum.map(quotes, &Decimal.new(&1["adjusted_close"]))

      assert length(read.points) == length(closes)

      for {point, close} <- Enum.zip(read.points, closes) do
        assert Decimal.equal?(point.close, close)
      end

      [first | _] = quotes
      last = List.last(quotes)

      assert text(Floki.find(doc, "[data-role='crash-chart-first']")) =~
               money(first["adjusted_close"])

      assert text(Floki.find(doc, "[data-role='crash-chart-last']")) =~
               money(last["adjusted_close"])

      assert text(Floki.find(doc, "[data-role='crash-chart-low']")) =~
               money(Enum.min(closes, Decimal))

      assert text(Floki.find(doc, "[data-role='crash-chart-high']")) =~
               money(Enum.max(closes, Decimal))

      assert text(Floki.find(doc, "h2")) =~ "Synthetic Crash Index"

      drawn = Floki.find(doc, "[data-role='crash-chart-window']")
      assert Enum.map(drawn, &hd(Floki.attribute(&1, "data-key"))) == expected_keys

      for node <- drawn do
        key = hd(Floki.attribute(node, "data-key"))
        window = Enum.find(listed, &(&1["key"] == key))
        label = text(Floki.find(node, "[data-role='crash-chart-label']"))
        assert label =~ percent(window["decline"])

        if window["provisional"] do
          assert label =~ "läuft"
          assert Floki.find(node, "rect.is-running") != []
        else
          assert label =~ window["name"]
          assert Floki.find(node, "rect.is-running") == []
        end
      end

      compact = Floki.find(doc, "[data-compact-role='crash-chart-window']")

      assert Enum.map(compact, &hd(Floki.attribute(&1, "data-key"))) ==
               Enum.reverse(expected_keys)
    end

    assert Date.diff(CrashChart.read("1m").from, day(0)) in -31..-28
  end

  # User story (board 11 ③):
  # As the operator comparing the falls,
  # I want the running one first and, for each fall that recovered, after
  # how many days from its low,
  # so that I see how long the last ones took, from the windows' own
  # dates.
  #
  # Acceptance criteria:
  # - The running window is the first row; „erholt nach“ is „—“ for it and,
  #   for each recovered window, the calendar days from its trough to its
  #   recovered_on as GET /api/v1/crashes answers them, „nach N Tagen“.
  test "„Crashes im Vergleich“ shows the running fall first and „erholt nach“" do
    crash_world!()
    windows = api("/api/v1/crashes")
    read = CrashesWidget.read("held")

    doc =
      draw(&CrashesWidget.widget/1,
        item: item("crashes", "L", "1y"),
        universe: "held",
        card: read
      )

    rows = Floki.find(doc, "[data-form='wide'] [data-role='crash-window']")
    [first | rest] = rows
    running = Enum.find(windows["detected"], & &1["provisional"])
    assert hd(Floki.attribute(first, "data-key")) == running["key"]
    assert text(Floki.find(first, "[data-role='crash-recovered']")) == "—"

    for row <- rest do
      key = hd(Floki.attribute(row, "data-key"))
      window = Enum.find(windows["detected"] ++ windows["manual"], &(&1["key"] == key))

      expected =
        case window do
          %{"recovered_on" => recovered, "trough" => trough} when is_binary(recovered) ->
            "nach #{Date.diff(Date.from_iso8601!(recovered), Date.from_iso8601!(trough))} Tagen"

          _manual ->
            "—"
        end

      assert text(Floki.find(row, "[data-role='crash-recovered']")) == expected
    end
  end
end
