defmodule PortfolixirWeb.DashboardCrashChartWidgetTest do
  # Sprint 32 S5 (I61; board ux-design-2026-11-25-sprint32/11 ①, ②, ③; the
  # owner's description of 2026-11-25): the widget „Crash-Chart“ — the
  # crash benchmark's closes over the period with every crash window
  # shaded and named, the running one stronger — and „Crashes im
  # Vergleich“ with the running fall first and „erholt nach“, and
  # „Erholer nach Crashes“, the rebounders of the last ended windows side
  # by side, each figure
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
  alias PortfolixirWeb.Dashboard.Widgets.Rebounders
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
  # running —, a held security falls with it through both, and one only in
  # the catalogue through the second.
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

    put_quotes!(held, [
      {day(-700), "50"},
      {day(-650), "30"},
      {day(-600), "35"},
      {day(-560), "45"},
      {day(-512), "48"},
      {day(-60), "60"},
      {day(-50), "52"},
      {day(-5), "58"}
    ])

    # Only in the catalogue, and only through the second window.
    outsider = create_security!(name: "Synthetic Outsider", ticker: "SOU")
    put_quotes!(outsider, [{day(-60), "12"}, {day(-50), "9"}, {day(-5), "11"}])

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
  #   back. A window that began before the period has no label in the
  #   chart; the line under it says „−X % vom Hoch am <Datum> · läuft“
  #   (board 11 ②; the S32 closing act).
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

      # Sprint 32 L2 (board 07 ① 1): the benchmark is the line under the
      # title, the head the kind's title alone.
      assert text(Floki.find(doc, "[data-role='crash-chart-benchmark']")) =~
               "Synthetic Crash Index"

      drawn = Floki.find(doc, "[data-role='crash-chart-window']")
      assert Enum.map(drawn, &hd(Floki.attribute(&1, "data-key"))) == expected_keys

      for node <- drawn do
        key = hd(Floki.attribute(node, "data-key"))
        window = Enum.find(listed, &(&1["key"] == key))
        label = text(Floki.find(doc, "[data-role='crash-chart-label'][data-key='#{key}']"))
        before = text(Floki.find(doc, "[data-role='crash-chart-before'][data-key='#{key}']"))

        if Date.compare(Date.from_iso8601!(window["start"]), read.from) == :lt do
          # The S32 closing act (board 11 ②): a window that began before
          # the period gets no label pinned to the chart's left edge; the
          # line under the chart names it, the running one as the board
          # words it.
          assert label == ""
          assert before =~ percent(window["decline"])
          assert before =~ de(fn -> Format.date(Date.from_iso8601!(window["start"])) end)
          if window["provisional"], do: assert(before =~ "vom Hoch am")
          if window["provisional"], do: assert(before =~ "· läuft")
        else
          assert before == ""
          assert label =~ percent(window["decline"])

          if window["provisional"],
            do: assert(label =~ "läuft"),
            else: assert(label =~ window["name"])
        end

        if window["provisional"] do
          assert Floki.find(node, "rect.is-running") != []
        else
          assert Floki.find(node, "rect.is-running") == []
        end
      end

      compact = Floki.find(doc, "[data-compact-role='crash-chart-window']")

      assert Enum.map(compact, &hd(Floki.attribute(&1, "data-key"))) ==
               Enum.reverse(expected_keys)
    end

    assert Date.diff(CrashChart.read("1m").from, day(0)) in -31..-28
  end

  # User story (board 11 ①, ②):
  # As the operator who marked falls of my own as manual windows,
  # I want them on the crash chart too, shaded from their start to their
  # low and named, one that began before the period named under the chart,
  # so that the chart shows every window the crash routes hold.
  #
  # Acceptance criteria:
  # - At 1M the chart's windows are those of GET /api/v1/crashes (detected
  #   and manual) that overlap the period, oldest first: a manual window
  #   inside the period is labelled by its name alone (it has no
  #   decline); one that began before the period has no label, and the
  #   line under the chart says „<Name> · seit <Datum>“.
  # - The compact form lists the manual windows with „—“ for the decline
  #   they do not have.
  test "„Crash-Chart“ shades the manual windows and names one begun before the period" do
    index = crash_world!()

    {:ok, _} =
      Portfolixir.Crashes.create_manual_window(Actor.owner_ui(), %{
        "name" => "Synthetic early fall",
        "start" => day(-40),
        "trough" => day(-20)
      })

    {:ok, _} =
      Portfolixir.Crashes.create_manual_window(Actor.owner_ui(), %{
        "name" => "Synthetic late fall",
        "start" => day(-12),
        "trough" => day(-8)
      })

    windows = api("/api/v1/crashes")
    [early, late] = Enum.sort_by(windows["manual"], & &1["start"])
    assert early["name"] == "Synthetic early fall"

    read = CrashChart.read("1m")
    doc = draw(&CrashChart.widget/1, item: item("crash_chart", "XL", "1m"), card: read)

    overlapping =
      (windows["detected"] ++ windows["manual"])
      |> Enum.filter(fn window ->
        # A detected window runs to its recovery (to today while it runs),
        # a manual one to its trough.
        finish =
          cond do
            window["provisional"] -> day(0)
            window["recovered_on"] -> Date.from_iso8601!(window["recovered_on"])
            true -> Date.from_iso8601!(window["trough"])
          end

        Date.compare(Date.from_iso8601!(window["start"]), read.to) != :gt and
          Date.compare(finish, read.from) != :lt
      end)
      |> Enum.sort_by(&Date.from_iso8601!(&1["start"]), Date)
      |> Enum.map(& &1["key"])

    drawn = Floki.find(doc, "[data-role='crash-chart-window']")
    assert Enum.map(drawn, &hd(Floki.attribute(&1, "data-key"))) == overlapping
    assert early["key"] in overlapping and late["key"] in overlapping
    assert "d:#{index.id}:#{day(-35)}" in overlapping

    label = fn key ->
      text(Floki.find(doc, "[data-role='crash-chart-label'][data-key='#{key}']"))
    end

    before = fn key ->
      text(Floki.find(doc, "[data-role='crash-chart-before'][data-key='#{key}']"))
    end

    assert label.(late["key"]) == "Synthetic late fall"
    assert before.(late["key"]) == ""

    assert label.(early["key"]) == ""

    assert before.(early["key"]) ==
             "Synthetic early fall · seit " <> de(fn -> Format.date(day(-40)) end)

    for window <- [early, late] do
      [row] =
        Floki.find(doc, "[data-compact-role='crash-chart-window'][data-key='#{window["key"]}']")

      assert text(row) =~ window["name"]
      assert text(row) =~ "—"
    end
  end

  # User story (board 11 ①):
  # As the operator whose crash chart reads a period with too few closes,
  # or one the page cannot resolve,
  # I want the chart to say so instead of drawing a line,
  # so that an empty or failed read never looks like a flat price.
  #
  # Acceptance criteria:
  # - Pinned to 1T on a day without a close, the read holds no two closes:
  #   „Zu wenige Schlusskurse der Crash-Benchmark …“, no chart drawn.
  # - A period that does not resolve today (a year not yet begun) reads
  #   :error: „Die Crash-Fenster konnten nicht geladen werden.“, no chart.
  test "„Crash-Chart“ says too few closes, and a period that does not resolve" do
    crash_world!()

    read = CrashChart.read("1d")
    assert %{state: :ok, points: points} = read
    assert length(points) < 2

    doc = draw(&CrashChart.widget/1, item: item("crash_chart", "L", "1d"), card: read)

    assert text(Floki.find(doc, "[data-role='crash-chart-empty']")) =~
             "Zu wenige Schlusskurse der Crash-Benchmark"

    assert Floki.find(doc, "[data-role='crash-chart']") == []

    assert CrashChart.read("year:#{day(0).year + 1}") == :error

    doc = draw(&CrashChart.widget/1, item: item("crash_chart", "L", "1y"), card: :error)

    assert text(Floki.find(doc, "[data-role='crash-chart-failed']")) ==
             "Die Crash-Fenster konnten nicht geladen werden."

    assert Floki.find(doc, "[data-role='crash-chart']") == []
  end

  # User story (board 11 ①):
  # As the operator looking at a year of daily closes on the crash chart,
  # I want the line thinned to what the tile can show, never losing the
  # period's lowest and highest close,
  # so that the chart stays light and still shows the extremes its line
  # under the chart names.
  #
  # Acceptance criteria:
  # - With 360 daily closes in 1J, the line holds at most 300 points (the
  #   read keeps all 360, the quotes route's).
  # - The highest close is drawn at the plot's top and the lowest at its
  #   foot, though each falls between the points kept by the step; the
  #   line under the chart names both as the route answers them.
  test "„Crash-Chart“ thins a long line and keeps its lowest and highest close" do
    world = base_world()
    index = create_security!(name: "Synthetic Daily Index", ticker: "SDI")

    # The highest and the lowest close at odd places of the series, which
    # thinning by every second point would skip.
    closes =
      for offset <- -359..0 do
        close =
          cond do
            offset == -100 -> "150"
            offset == -200 -> "50"
            true -> to_string(100 + rem(offset, 7))
          end

        {day(offset), close}
      end

    put_quotes!(index, closes)
    deposit!(world, "100", day(-360))
    {:ok, _} = Settings.set_crash_benchmark(Actor.owner_ui(), index.id)

    read = CrashChart.read("1y")

    quotes =
      api("/api/v1/securities/#{index.id}/quotes?from=#{read.from}&to=#{read.to}")

    assert length(read.points) == length(quotes)
    assert length(quotes) == 360

    doc = draw(&CrashChart.widget/1, item: item("crash_chart", "XL", "1y"), card: read)
    [svg] = Floki.find(doc, "[data-role='crash-chart-svg']")
    drawn = svg |> Floki.attribute("data-points") |> hd() |> String.to_integer()
    assert drawn <= 300

    path = doc |> Floki.find("path.crash-chart__line") |> Floki.attribute("d") |> hd()
    ys = for [_, y] <- Regex.scan(~r/[ML][-\d.]+,([-\d.]+)/, path), do: String.to_float(y)
    assert length(ys) == drawn
    # The plot's top (6) is the highest close, its foot (220 − 22) the lowest.
    assert Enum.min(ys) == 6.0
    assert Enum.max(ys) == 198.0

    assert text(Floki.find(doc, "[data-role='crash-chart-high']")) =~ money("150")
    assert text(Floki.find(doc, "[data-role='crash-chart-low']")) =~ money("50")
  end

  # User story (board 11 ③):
  # As the operator comparing the falls,
  # I want the running one first and, for each fall that recovered, after
  # how many days from its low,
  # so that I see how long the last ones took, from the windows' own
  # dates.
  #
  # Acceptance criteria:
  # - The running window is the first row, its dates ending „läuft“ as
  #   the crash chart says it; „erholt nach“ is „—“ for it and,
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

    # The running fall „läuft“, as the crash chart and board 11 ③ say it,
    # not „andauernd“ (the S32 closing act).
    assert text(first) =~ "läuft"
    refute text(doc) =~ "andauernd"

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

  # User story (board 11 ③):
  # As the operator who marked a fall by hand on the day a detected one
  # began,
  # I want „Crashes im Vergleich“ to order the windows as the Risk tab
  # does,
  # so that the two lists read the same.
  #
  # Acceptance criteria:
  # - The running window first; then newest first by start; on one start,
  #   the detected window before the manual one. The keys are those of
  #   GET /api/v1/crashes.
  test "„Crashes im Vergleich“ orders a manual window after the detected one of its day" do
    index = crash_world!()

    {:ok, _} =
      Portfolixir.Crashes.create_manual_window(Actor.owner_ui(), %{
        "name" => "Synthetic same-day fall",
        "start" => day(-60),
        "trough" => day(-45)
      })

    {:ok, _} =
      Portfolixir.Crashes.create_manual_window(Actor.owner_ui(), %{
        "name" => "Synthetic recent fall",
        "start" => day(-20),
        "trough" => day(-10)
      })

    windows = api("/api/v1/crashes")
    [manual, recent] = Enum.sort_by(windows["manual"], & &1["start"])
    running = Enum.find(windows["detected"], & &1["provisional"])

    doc =
      draw(&CrashesWidget.widget/1,
        item: item("crashes", "L", "1y"),
        universe: "held",
        card: CrashesWidget.read("held")
      )

    keys =
      doc
      |> Floki.find("[data-form='wide'] [data-role='crash-window']")
      |> Enum.map(&hd(Floki.attribute(&1, "data-key")))

    assert keys == [
             running["key"],
             recent["key"],
             "d:#{index.id}:#{day(-60)}",
             manual["key"],
             "d:#{index.id}:#{day(-700)}"
           ]
  end

  # User story (board 11 ⑤; D-15):
  # As the operator who wants to see what came back after the last
  # crashes,
  # I want the rebounders' lists of the last ended windows side by side,
  # over my holdings or the catalogue, a name in more than one list marked
  # by its name,
  # so that I see the repetition myself, with no score across crashes.
  #
  # Acceptance criteria:
  # - The lists are the ended windows (the running one left out), newest
  #   first, at most three; each list's names and rises equal GET
  #   /api/v1/crashes/:key/rankings?list=rebounders&universe=held&limit=5
  #   (L shows three, XL five).
  # - „Katalog“ reads universe=catalogue.
  # - A name in more than one list carries „mehrfach“; one in one list
  #   does not; no figure is drawn that no list holds.
  # - Its ⓘ names the span (three months from the trough) and
  #   survivorship.
  test "„Erholer nach Crashes“ shows the last ended windows' rebounders side by side" do
    crash_world!()
    windows = api("/api/v1/crashes")

    ended =
      (windows["detected"] ++ windows["manual"])
      |> Enum.reject(& &1["provisional"])
      |> Enum.sort_by(& &1["start"], :desc)
      |> Enum.take(3)
      |> Enum.map(& &1["key"])

    for {universe, size, shown} <- [{"held", "XL", 5}, {"catalogue", "L", 3}] do
      read = Rebounders.read(universe)

      doc =
        draw(&Rebounders.widget/1,
          item: item("rebounders", size, "1y"),
          universe: universe,
          card: read
        )

      lists = Floki.find(doc, "[data-role='rebounders-list']")
      assert Enum.map(lists, &hd(Floki.attribute(&1, "data-key"))) == ended

      names_per_list =
        for list <- lists do
          key = hd(Floki.attribute(list, "data-key"))

          ranking =
            api(
              "/api/v1/crashes/#{URI.encode_www_form(key)}/rankings?list=rebounders" <>
                "&universe=#{universe}&limit=5"
            )

          expected = Enum.take(ranking["entries"], shown)
          rows = Floki.find(list, "[data-role='rebounder']")
          assert length(rows) == length(expected)

          for {row, entry} <- Enum.zip(rows, expected) do
            assert text(Floki.find(row, "bdi")) == entry["security"]["name"]

            assert text(Floki.find(row, "[data-role='rebounder-return']")) ==
                     percent(entry["return"])
          end

          Enum.map(expected, & &1["security"]["name"])
        end

      counts = names_per_list |> List.flatten() |> Enum.frequencies()

      for row <- Floki.find(doc, "[data-role='rebounder']") do
        name = text(Floki.find(row, "bdi"))
        marked? = Floki.find(row, "[data-role='rebounder-repeated']") != []
        assert marked? == counts[name] > 1, name

        if marked?,
          do: assert(text(Floki.find(row, "[data-role='rebounder-repeated']")) == "mehrfach")
      end

      assert Enum.any?(counts, fn {_name, count} -> count > 1 end)

      info = doc |> Floki.find("[data-role='section-info']") |> text()
      assert info =~ "drei Kalendermonate"
      assert info =~ "Survivorship"
    end
  end

  # User story (board 11 ⑤):
  # As the operator reading the rebounders over the catalogue,
  # I want a security that fell further after its low, or did not move,
  # drawn so, with the rise the route answers,
  # so that a list of „Erholer“ never colours a loss as a rebound.
  #
  # Acceptance criteria:
  # - In the list of the window that began 60 days ago, a security whose
  #   last close stands below its low in the window shows the route's
  #   negative rise, drawn negative; one whose close is back at its low
  #   shows 0,0 %, drawn flat; each is
  #   GET /api/v1/crashes/:key/rankings?list=rebounders&universe=catalogue's.
  test "„Erholer nach Crashes“ draws a further fall negative and no move flat" do
    index = crash_world!()
    sinker = create_security!(name: "Synthetic Sinker", ticker: "SSK")
    put_quotes!(sinker, [{day(-60), "20"}, {day(-50), "10"}, {day(-5), "8"}])
    flat = create_security!(name: "Synthetic Flat", ticker: "SFL")
    put_quotes!(flat, [{day(-60), "20"}, {day(-50), "10"}, {day(-5), "10"}])

    key = "d:#{index.id}:#{day(-60)}"

    ranking =
      api(
        "/api/v1/crashes/#{URI.encode_www_form(key)}/rankings?list=rebounders" <>
          "&universe=catalogue&limit=5"
      )

    rise = fn security ->
      Enum.find(ranking["entries"], &(&1["security"]["id"] == security.id))["return"]
    end

    assert Decimal.lt?(Decimal.new(rise.(sinker)), 0)
    assert Decimal.eq?(Decimal.new(rise.(flat)), 0)

    doc =
      draw(&Rebounders.widget/1,
        item: item("rebounders", "XL", "1y"),
        universe: "catalogue",
        card: Rebounders.read("catalogue")
      )

    [list] = Floki.find(doc, "[data-role='rebounders-list'][data-key='#{key}']")

    for {security, class} <- [{sinker, "is-negative"}, {flat, "is-flat"}] do
      [row] = Floki.find(list, "[data-role='rebounder'][data-security-id='#{security.id}']")
      [figure] = Floki.find(row, "[data-role='rebounder-return']")
      assert text(figure) == percent(rise.(security))
      assert class in String.split(hd(Floki.attribute(figure, "class")))
    end
  end

  # User story (board 11 ⑤):
  # As the operator whose agent scopes a dashboard to a view, or whose
  # crash benchmark has not ended a fall yet, or whose read failed,
  # I want the rebounders read over the view's holdings, and an empty or
  # failed read said for what it is,
  # so that no list stands for one the routes do not answer.
  #
  # Acceptance criteria:
  # - „Im Depot“ on a dashboard scoped to a view reads universe
  #   `view:<id>`; its lists equal the rankings route's for that universe.
  # - A benchmark with no ended window: „Kein beendetes Crash-Fenster in
  #   den Schlusskursen der Benchmark.“, no list.
  # - A failed read: „Die Crash-Fenster konnten nicht geladen werden.“
  test "„Erholer nach Crashes“ reads a view's holdings, and says no ended window or a failed read" do
    crash_world!()

    {:ok, view} =
      Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "Alles", include_all: true})

    universe = Rebounders.universe("held", view.id)
    assert universe == "view:#{view.id}"
    assert Rebounders.universe("held", nil) == "held"

    read = Rebounders.read(universe)
    assert %{state: :ok, universe: ^universe, lists: [_ | _] = lists} = read
    assert Enum.any?(lists, &(&1.entries != []))

    for list <- lists do
      ranking =
        api(
          "/api/v1/crashes/#{URI.encode_www_form(list.key)}/rankings?list=rebounders" <>
            "&universe=#{universe}&limit=5"
        )

      assert Enum.map(list.entries, & &1.security_id) ==
               Enum.map(ranking["entries"], & &1["security"]["id"])
    end

    # A benchmark whose closes only rise has no window, ended or running.
    rising = create_security!(name: "Synthetic Riser", ticker: "SRS")
    put_quotes!(rising, [{day(-300), "10"}, {day(-100), "20"}, {day(-1), "30"}])
    {:ok, _} = Settings.set_crash_benchmark(Actor.owner_ui(), rising.id)
    assert %{state: :ok, lists: []} = empty = Rebounders.read("held")

    doc =
      draw(&Rebounders.widget/1,
        item: item("rebounders", "L", "1y"),
        universe: "held",
        card: empty
      )

    assert text(Floki.find(doc, "[data-role='rebounders-empty']")) ==
             "Kein beendetes Crash-Fenster in den Schlusskursen der Benchmark."

    assert Floki.find(doc, "[data-role='rebounders-list']") == []

    failed =
      draw(&Rebounders.widget/1,
        item: item("rebounders", "L", "1y"),
        universe: "held",
        card: :error
      )

    assert text(Floki.find(failed, "[data-role='rebounders-failed']")) ==
             "Die Crash-Fenster konnten nicht geladen werden."
  end
end
