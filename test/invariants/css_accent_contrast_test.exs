defmodule Portfolixir.Invariants.CssAccentContrastTest do
  use ExUnit.Case, async: true

  # User story (#908; Sprint 18 pick H5, board
  # ux-design-2026-10-02/05-light-contrast, "after"; DESIGN.md → Colors,
  # the contrast commitments and the computed contrast table):
  # As the operator who picked the coral accent, reading in light mode,
  # I want every link and every accent-coloured word at body size to clear
  # the 4.5:1 bar on whatever surface it sits on,
  # so that a remedy link in a note, a rule's name, a date link and a
  # success message stay readable whichever of the three accents I chose.
  #
  # Acceptance criteria:
  # - Computed from the token values in app.css with the WCAG 2.x relative
  #   luminance, every accent as text clears 4.5:1 in light mode on the
  #   canvas, the panels, the muted wells, its own tint, the attention note's
  #   tint and the problem note's tint, and the white label on its fill
  #   clears it too — in `:root` and in `[data-theme="light"]` alike.
  # - In dark mode every accent clears 4.5:1 on the three dark surfaces and
  #   on its own translucent tint composited over the panel colour; the dark
  #   values are not touched by this repair.
  # - Translucent tints are composited in sRGB over the surface they sit on,
  #   as the board and DESIGN.md's table compute them.

  @css File.read!("priv/static/app.css")
  @bar 4.5
  @accents ~w(violet teal coral)

  test "every accent clears 4.5:1 as body text on every light surface" do
    for {block_name, tokens} <- [{":root", root()}, {~s([data-theme="light"]), light()}],
        accent <- @accents do
      ink = color(tokens, "color-accent-#{accent}")

      surfaces = [
        {"bg", color(tokens, "color-bg")},
        {"bg-elevated", color(tokens, "color-bg-elevated")},
        {"bg-muted", color(tokens, "color-bg-muted")},
        {"accent-#{accent}-soft", color(tokens, "color-accent-#{accent}-soft")},
        {"warning-soft", color(tokens, "color-warning-soft")},
        {"danger-soft", color(tokens, "color-danger-soft")}
      ]

      for {surface, ground} <- surfaces do
        ratio = contrast(ink, flatten(ground, color(tokens, "color-bg-elevated")))

        assert ratio >= @bar,
               "#{block_name}: accent-#{accent} on #{surface} measures " <>
                 "#{Float.round(ratio, 2)}:1, below #{@bar}:1"
      end

      label = contrast(color(tokens, "color-on-accent"), ink)

      assert label >= @bar,
             "#{block_name}: on-accent on accent-#{accent} measures #{Float.round(label, 2)}:1"
    end
  end

  test "every accent clears 4.5:1 as body text on every dark surface" do
    for {block_name, tokens} <- [
          {"prefers-color-scheme: dark", dark_media()},
          {~s([data-theme="dark"]), dark()}
        ],
        accent <- @accents do
      ink = color(tokens, "color-accent-#{accent}")
      panel = color(tokens, "color-bg-elevated")

      surfaces = [
        {"bg", color(tokens, "color-bg")},
        {"bg-elevated", panel},
        {"bg-muted", color(tokens, "color-bg-muted")},
        {"accent-#{accent}-soft over bg-elevated", color(tokens, "color-accent-#{accent}-soft")}
      ]

      for {surface, ground} <- surfaces do
        ratio = contrast(ink, flatten(ground, panel))

        assert ratio >= @bar,
               "#{block_name}: accent-#{accent} on #{surface} measures " <>
                 "#{Float.round(ratio, 2)}:1, below #{@bar}:1"
      end
    end
  end

  # The computation reproduces DESIGN.md's archived figures, so the bar above
  # is the table's bar and not a second method's.
  test "the computation reproduces the recorded ratios" do
    assert_in_delta contrast({124, 58, 237, 1.0}, {246, 247, 250, 1.0}), 5.32, 0.005
    assert_in_delta contrast({225, 29, 72, 1.0}, {246, 247, 250, 1.0}), 4.38, 0.005
    assert_in_delta contrast({185, 28, 28, 1.0}, {255, 228, 230, 1.0}), 5.39, 0.005
  end

  # User story (#1170):
  # As the designer reading the chart's rows of DESIGN.md's contrast table,
  # I want them measured against the colour the chart frame paints,
  # so that a marker or an axis value the table passes does pass on the
  # screen.
  #
  # Acceptance criteria:
  # - Every chart row is measured against `--color-bg`, which `.chart-frame`
  #   paints in both themes (css_chart_axis_test.exs holds the frame to
  #   it): the tx-buy and tx-sell token rows, the markers as the build
  #   paints them (`--color-positive`, `--color-danger`) and the axis text
  #   (`--color-text-muted`), in light and dark, each figure the one
  #   computed here from app.css to two decimals.
  # - No chart row is measured against chart-surface any more.
  test "the table's chart rows are measured against the chart frame" do
    rows =
      "_bmad-output/planning-artifacts/design-language/DESIGN.md"
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "| "))

    {light, night} = {root(), dark_media()}
    frame = color(light, "color-bg")
    night_frame = color(night, "color-bg")
    buy = parse("#10b981")
    sell = parse("#ef4444")

    expected = [
      {"tx-buy #10b981 / bg #f6f7fa (the chart frame)", buy, frame},
      {"tx-sell #ef4444 / bg (the chart frame)", sell, frame},
      {"buy marker as built, positive #047857 / bg (the chart frame)",
       color(light, "color-positive"), frame},
      {"sell marker as built, danger #b91c1c / bg (the chart frame)",
       color(light, "color-danger"), frame},
      {"chart axis, text-muted #5a6577 / bg (the chart frame)", color(light, "color-text-muted"),
       frame},
      {"tx-buy #10b981 / bg-dark #0b0f14 (the chart frame)", buy, night_frame},
      {"tx-sell #ef4444 / bg-dark (the chart frame)", sell, night_frame},
      {"buy marker as built, positive-dark #34d399 / bg-dark (the chart frame)",
       color(night, "color-positive"), night_frame},
      {"sell marker as built, danger-dark #fb7185 / bg-dark (the chart frame)",
       color(night, "color-danger"), night_frame},
      {"chart axis, text-muted-dark #8b97a8 / bg-dark (the chart frame)",
       color(night, "color-text-muted"), night_frame}
    ]

    for {pair, ink, ground} <- expected do
      figure = :erlang.float_to_binary(contrast(ink, ground), decimals: 2)
      row = Enum.find(rows, &String.starts_with?(&1, "| #{pair} |")) || flunk("no row: #{pair}")
      [_pair, ratio | _] = row |> String.split("|", trim: true) |> Enum.map(&String.trim/1)

      assert String.trim(ratio, "*") == figure,
             "#{pair}: the table says #{ratio}, app.css #{figure}"
    end

    refute Enum.any?(rows, &(&1 =~ ~r/^\| (tx-buy|tx-sell)[^|]*chart-surface/)),
           "a marker row is still measured against chart-surface"
  end

  # --- tokens ----------------------------------------------------------------

  defp root, do: tokens(~r/\A:root \{(.*?)\n\}/s)
  defp light, do: tokens(~r/\n\[data-theme="light"\] \{(.*?)\n\}/s)
  defp dark, do: tokens(~r/\n\[data-theme="dark"\] \{(.*?)\n\}/s)
  defp dark_media, do: tokens(~r/@media \(prefers-color-scheme: dark\) \{\s*:root \{(.*?)\n  \}/s)

  defp tokens(regex) do
    [body] = Regex.run(regex, @css, capture: :all_but_first)

    ~r/--([\w-]+)\s*:\s*([^;]+);/
    |> Regex.scan(body, capture: :all_but_first)
    |> Map.new(fn [name, value] -> {name, String.trim(value)} end)
  end

  # A theme block re-keys only what changes; anything it leaves out falls
  # back to `:root`.
  defp color(tokens, name) do
    value = Map.get(tokens, name) || Map.fetch!(root(), name)
    parse(value)
  end

  defp parse("#" <> hex) when byte_size(hex) == 6 do
    <<r::binary-2, g::binary-2, b::binary-2>> = hex
    {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16), 1.0}
  end

  defp parse("rgb(" <> rest) do
    [r, g, b, a] =
      Regex.run(~r/^(\d+) (\d+) (\d+) \/ ([\d.]+)\)$/, rest, capture: :all_but_first)

    {String.to_integer(r), String.to_integer(g), String.to_integer(b), parse_alpha(a)}
  end

  defp parse_alpha(a) do
    {alpha, ""} = Float.parse(a)
    alpha
  end

  # --- WCAG 2.x ----------------------------------------------------------------

  defp flatten({r, g, b, a}, {br, bg, bb, _}) do
    {round(a * r + (1 - a) * br), round(a * g + (1 - a) * bg), round(a * b + (1 - a) * bb), 1.0}
  end

  defp contrast(fg, bg) do
    {l1, l2} = {luminance(fg), luminance(bg)}
    (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
  end

  defp luminance({r, g, b, _}) do
    0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
  end

  defp channel(value) do
    c = value / 255
    if c <= 0.03928, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
  end
end
