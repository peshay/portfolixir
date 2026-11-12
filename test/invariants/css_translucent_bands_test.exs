defmodule Portfolixir.Invariants.CssTranslucentBandsTest do
  use ExUnit.Case, async: true

  # Sprint 29 P2 (idea I33; board ux-design-2026-11-12-sprint29/05): the
  # stacked chart's bands slightly translucent. The rules are CSS only, so
  # the stylesheet is what these tests read; the board draws them in both
  # themes and the privacy mode.

  @css File.read!("priv/static/app.css")

  # Every rule of the stylesheet as {selector, body}, comments removed.
  defp rules do
    css = Regex.replace(~r{/\*.*?\*/}s, @css, "")

    ~r/([^{}]+)\{([^{}]*)\}/
    |> Regex.scan(css)
    |> Enum.map(fn [_, selector, body] -> {String.trim(selector), body} end)
  end

  defp rule!(selector) do
    case Enum.filter(rules(), fn {sel, _body} -> sel == selector end) do
      [] -> flunk("no rule for #{selector}")
      found -> Enum.map_join(found, "\n", fn {_sel, body} -> body end)
    end
  end

  # User story (I33, board 05):
  # As the operator reading the stacked value chart,
  # I want the bands slightly translucent, the legend's swatches with them,
  # so that the grid shows through and the chart reads lighter while every
  # band and its swatch still match.
  #
  # Acceptance criteria:
  # - `.stack-band` fills at `fill-opacity: 0.8`.
  # - `.stack-band--negative`, the part below zero (issue 1426), is set
  #   explicitly to 0.6: its `fill-opacity` replaces the base's on the same
  #   path, it does not multiply, so 0.75 would leave it almost as strong as
  #   the part above.
  # - The hover on a clickable band keeps `opacity: 0.85`, which multiplies
  #   with the fill (0.68).
  # - The bands' legend swatches sit at `opacity: 0.8`; the TTWROR lines'
  #   legend, whose lines are opaque strokes, keeps its swatches opaque.
  # - No other rule (a theme, the privacy mode) sets a band's or a swatch's
  #   opacity, so both themes and the privacy mode draw the same.
  test "the bands, their part below zero and their swatches are translucent" do
    assert rule!(".stack-band") =~ ~r/fill-opacity:\s*0\.8;/
    assert rule!(".stack-band--negative") =~ ~r/fill-opacity:\s*0\.6;/
    assert rule!(".stack-band[phx-click]:hover") =~ ~r/(?<!-)opacity:\s*0\.85;/
    assert rule!(".stack-legend:not(.lines-legend) .stack-swatch") =~ ~r/(?<!-)opacity:\s*0\.8;/

    setters =
      for {selector, body} <- rules(),
          String.contains?(selector, ".stack-band") or String.contains?(selector, "-swatch"),
          String.contains?(selector, "stack"),
          body =~ ~r/(^|[;\s])(fill-)?opacity\s*:/,
          do: selector

    assert Enum.sort(setters) ==
             Enum.sort([
               ".stack-band",
               ".stack-band--negative",
               ".stack-band[phx-click]:hover",
               ".stack-legend:not(.lines-legend) .stack-swatch"
             ])

    # The swatch rule reaches the bands' legend and not the lines': the
    # markup gives the bands' table `stack-legend` alone and the lines'
    # table `stack-legend lines-legend`.
    markup = File.read!("lib/portfolixir_web/live/portfolio/stacked_chart.ex")
    assert markup =~ ~r/id="stack-legend"\s+class="stack-legend"\s/
    assert markup =~ ~r/id="lines-legend"\s+class="stack-legend lines-legend"\s/
  end
end
