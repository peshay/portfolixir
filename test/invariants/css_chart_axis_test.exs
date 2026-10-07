defmodule Portfolixir.Invariants.CssChartAxisTest do
  use ExUnit.Case, async: true

  # Sprint 19 PR γ U3 (issue 1088; board ux-design-2026-10-04/05-dates-charts,
  # pick J5 A, rules ② and ③). The label size is a stylesheet rule fed by
  # one number the chart hook measures, and whether the values move inside
  # the plot is a flag the same hook sets, so the stylesheet and the hook's
  # source are what these tests read; the board measures the label at 9 px
  # in real 390 px frames, and the story's own check measures it on the
  # built page.

  @css File.read!("priv/static/app.css")
  @layout File.read!("lib/portfolixir_web/layout_view.ex")

  # User story (J5 A, rule ②):
  # As a portfolio maintainer reading a chart on a phone,
  # I want its axis labels at the size the spec names, 9 px,
  # so that they are not 3 px tall because the chart scaled down to the
  # screen.
  #
  # Acceptance criteria:
  # - The labels' font size is 9 CSS px multiplied by `--chart-upx`, the
  #   viewBox units per CSS pixel, declared 1 on the frame — without script
  #   the label is the 9 units of before.
  # - The `ChartCrosshair` hook writes `--chart-upx` on the frame, measured
  #   on the svg as the larger of the two ratios (the `meet` viewBox scales
  #   by the narrower fit), kept current by a ResizeObserver, put back after
  #   every patch (`updated`), and stops observing when the chart goes.
  test "the axis label is 9 CSS px at every chart width" do
    assert block(".security-chart .chart-axis-labels text") =~
             ~r/font-size:\s*calc\(9px \* var\(--chart-upx, 1\)\);/

    assert block(".chart-frame") =~ ~r/--chart-upx:\s*1;/

    hook = hook_source("ChartCrosshair")
    assert hook =~ ~s(setProperty("--chart-upx")
    assert hook =~ "Math.max(view.width / rect.width, view.height / rect.height)"
    assert hook =~ "ResizeObserver"
    assert hook =~ ".disconnect()"

    [_, updated] =
      Regex.run(~r/updated: function \(\) \{(.*?)\n              \},/s, hook) ||
        flunk("no updated callback")

    assert updated =~ "this.writeScale();"
  end

  # User story (J5 A, rule ③, and the U3 review's finding 2):
  # As a portfolio maintainer reading a narrow chart, or a wide one whose
  # values are too long for the gutter ("1.544.042", "+1.234,5%"),
  # I want the axis values inside the plot, each on its grid line, over a
  # halo that keeps it legible on the line and the fill,
  # so that a 9 px value is never squeezed into, or cut off at, a gutter
  # too narrow for it.
  #
  # Acceptance criteria:
  # - The hook decides: it flags the frame `data-axis-inside` when the
  #   chart is at most 760 px wide or the widest value is wider than the
  #   gutter (the value's x, in viewBox units, over `--chart-upx`), and
  #   removes the flag otherwise. Without the hook there is no flag, and
  #   the values stay in the gutter, as before.
  # - Under the flag the values are start-anchored inside the plot, 3 px
  #   above their line, with a 3 px halo in the colour the frame is painted,
  #   `--color-bg` (amended 2026-10-07 by the closing act: it was the chart
  #   surface colour, a visible rim on the frame); the top value is centred
  #   on its line.
  # - No container query moves them: the flag is the one switch.
  test "the hook moves the values inside the plot when the chart is narrow or a value too wide" do
    hook = hook_source("ChartCrosshair")
    assert hook =~ ~s|setAttribute("data-axis-inside", "")|
    assert hook =~ ~s|removeAttribute("data-axis-inside")|
    assert hook =~ "rect.width <= 760"
    assert hook =~ ~r/widest > gutter/

    refute @css =~ ~r/@container[^{]*\{\s*\.security-chart/
    refute block(".chart-frame") =~ "container-type"

    y = block(".chart-frame[data-axis-inside] .security-chart .chart-axis-y")
    assert y =~ ~r/text-anchor:\s*start;/
    assert y =~ ~r/dominant-baseline:\s*alphabetic;/

    assert y =~
             ~r/transform:\s*translate\(calc\(6px \+ 4px \* var\(--chart-upx, 1\)\), calc\(-3px \* var\(--chart-upx, 1\)\)\);/

    assert y =~ ~r/paint-order:\s*stroke;/
    assert y =~ ~r/stroke:\s*var\(--color-bg\);/
    assert y =~ ~r/stroke-width:\s*calc\(3px \* var\(--chart-upx, 1\)\);/
    assert y =~ ~r/stroke-linejoin:\s*round;/

    top = block(".chart-frame[data-axis-inside] .security-chart .chart-axis-y.is-top")
    assert top =~ ~r/dominant-baseline:\s*central;/
    assert top =~ ~r/transform:\s*translate\(calc\(6px \+ 4px \* var\(--chart-upx, 1\)\), 0\);/
  end

  # User story (the closing act's design critic, judgement (b); amends board
  # 05, frame A, which drew the halo in the chart surface colour):
  # As a portfolio maintainer reading a chart,
  # I want a label's and a marker's halo in the colour they sit on,
  # so that the halo separates them from the line without drawing a rim of
  # its own around them.
  #
  # Acceptance criteria:
  # - The frame is painted `--color-bg`, and nothing paints the plot another
  #   colour: the axis values' halo and the buy/sell markers' halo are the
  #   frame's own colour, `--color-bg`, in both themes (the token is themed).
  test "a halo is the colour it sits on" do
    [_, frame_bg] =
      Regex.run(~r/background:\s*(var\(--color-[a-z-]+\));/, block(".chart-frame")) ||
        flunk("the chart frame names no background token")

    assert frame_bg == "var(--color-bg)"

    halo = ~r/stroke:\s*(var\(--color-[a-z-]+\));/

    for selector <- [
          ".chart-frame[data-axis-inside] .security-chart .chart-axis-y",
          ".security-chart .tx-marker"
        ] do
      [_, stroke] = Regex.run(halo, block(selector)) || flunk("#{selector} has no halo")
      assert stroke == frame_bg, "#{selector}'s halo is #{stroke} on a #{frame_bg} frame"
    end
  end

  # User story (the closing act's edge-case finding 5; J5 A, rule ②):
  # As a portfolio maintainer opening a security that has no quotes yet, on
  # a phone,
  # I want the chart's "No price history yet." at a readable size,
  # so that it is not 5 px tall because the empty chart scaled down too.
  #
  # Acceptance criteria:
  # - The sentence is 13 CSS px multiplied by `--chart-upx`; without script
  #   it is the 13 units of before.
  # - The hook writes the scale for an empty chart too: before it writes
  #   it, it returns only when there is no svg, and the scale does not read
  #   the series.
  test "the empty chart's sentence is 13 CSS px at every chart width" do
    assert block(".security-chart .no-quotes text") =~
             ~r/font-size:\s*calc\(13px \* var\(--chart-upx, 1\)\);/

    hook = hook_source("ChartCrosshair")

    [_, before_scale] =
      Regex.run(~r/mounted: function \(\) \{(.*?)this\.writeScale\(\);/s, hook) ||
        flunk("mounted never writes the scale")

    assert length(Regex.scan(~r/\breturn\b/, before_scale)) == 1
    assert before_scale =~ ~r/if \(!this\.svg\) \{\s*return;\s*\}/

    [_, write_scale] =
      Regex.run(~r/writeScale: function \(\) \{(.*?)\n              \},/s, hook) ||
        flunk("no writeScale")

    refute write_scale =~ "points"
  end

  # User story (the closing act's edge-case finding 1; J5 A, rule ③):
  # As a portfolio maintainer exporting a chart as SVG or PNG from a phone
  # or a tablet,
  # I want every axis value in the file where the screen shows it, legible
  # and sized for the file,
  # so that a chart whose values sit inside the plot does not lose them
  # under their own halo, or off the file's left edge, when it is exported.
  #
  # Acceptance criteria:
  # - Every property the two `[data-axis-inside]` rules declare is on
  #   `_CHART_EXPORT_PROPS`, the computed properties the exporter bakes into
  #   the file: `paint-order` (without it the halo paints over the glyphs),
  #   `text-anchor`, `dominant-baseline` and `transform` (without them a
  #   value falls back to end-anchoring in the gutter).
  # - Around the inlining, the frame's `--chart-upx` is the export's own
  #   scale, the viewBox units per pixel of the exported width and height
  #   (the larger of the two ratios, as the hook measures it), so the labels
  #   are sized for the file and not 24.7 units from a 390 px phone; the
  #   frame's own value is put back afterwards, even if the inlining throws.
  # - The file is painted the frame's colour, the ground the halos match,
  #   and it is set after the inlining, which rewrites the root's style.
  #   (Found while fixing: the body's background colour it named is
  #   transparent under the page's gradient and was overwritten anyway, so
  #   a dark-theme export drew its halos as black rims on a white viewer.)
  test "the export bakes in the inside rule, at the export's own scale" do
    props = export_props()

    for selector <- [
          ".chart-frame[data-axis-inside] .security-chart .chart-axis-y",
          ".chart-frame[data-axis-inside] .security-chart .chart-axis-y.is-top"
        ],
        property <- declared_properties(block(selector)) do
      assert property in props, "#{selector} sets #{property}, which the export drops"
    end

    for property <- ~w(paint-order text-anchor dominant-baseline transform) do
      assert property in props
    end

    export = export_source()

    sized = position(export, "var exportH = ")
    scale = position(export, "Math.max(view.width / exportW, view.height / exportH)")
    saved = position(export, ~s|var frameUpx = frame.style.getPropertyValue("--chart-upx");|)
    set = position(export, ~s|frame.style.setProperty("--chart-upx", exportUpx.toFixed(4));|)
    inlined = position(export, "window.Portfolixir._inlineStyles(svg, clone);")
    restored = position(export, ~s|frame.style.setProperty("--chart-upx", frameUpx);|)

    assert sized < scale and scale < set and saved < set and set < inlined and inlined < restored
    assert export =~ ~r/\} finally \{\s*if \(frameUpx\) \{/
    assert export =~ ~s|frame.style.removeProperty("--chart-upx");|

    refute export =~ "document.body"
    assert export =~ "var ground = window.getComputedStyle(frame).backgroundColor"
    assert inlined < position(export, ~s|clone.style.setProperty("background", ground);|)
    assert export =~ "ctx.fillStyle = ground;"
  end

  defp export_props do
    case Regex.run(~r/window\.Portfolixir\._CHART_EXPORT_PROPS = \[(.*?)\];/s, @layout) do
      [_, list] -> Regex.scan(~r/"([a-z-]+)"/, list) |> Enum.map(fn [_, name] -> name end)
      nil -> flunk("no _CHART_EXPORT_PROPS in the layout")
    end
  end

  defp export_source do
    case Regex.run(
           ~r/window\.Portfolixir\.exportChart = function \(button, format\) \{(.*?)\n            \};/s,
           @layout
         ) do
      [_, body] -> body
      nil -> flunk("no exportChart in the layout")
    end
  end

  # The property names a rule's body declares.
  defp declared_properties(body) do
    ~r/(?:^|;)\s*([a-z-]+)\s*:/
    |> Regex.scan(body)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp position(source, fragment) do
    case :binary.match(source, fragment) do
      {index, _} -> index
      :nomatch -> flunk("the export has no #{inspect(fragment)}")
    end
  end

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{selector}")
    end
  end

  defp hook_source(name) do
    case Regex.run(~r/Hooks\.#{name} = \{(.*?)\n            \};/s, @layout) do
      [_, body] -> body
      nil -> flunk("no hook #{name} in the layout")
    end
  end
end
