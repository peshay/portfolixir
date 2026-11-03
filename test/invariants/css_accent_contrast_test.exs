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
      {"tx-buy-dark #10b981 / bg #f6f7fa (the chart frame)", buy, frame},
      {"tx-sell #ef4444 / bg (the chart frame)", sell, frame},
      {"buy marker as built, positive #0f766e / bg (the chart frame)",
       color(light, "color-positive"), frame},
      {"sell marker as built, danger #ce1b42 / bg (the chart frame)",
       color(light, "color-danger"), frame},
      {"chart axis, text-muted #5a6577 / bg (the chart frame)", color(light, "color-text-muted"),
       frame},
      {"tx-buy-dark #10b981 / bg-dark #0b0f14 (the chart frame)", buy, night_frame},
      {"tx-sell #ef4444 / bg-dark (the chart frame)", sell, night_frame},
      {"buy marker as built, positive-dark #2dd4bf / bg-dark (the chart frame)",
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

  # User story (#1149/#1210, Sprint 21 γ4; the γ closing act, DB2):
  # As the operator reading the Cash-flow matrices,
  # I want the quiet dash of a month that sums to zero to clear the text
  # floor,
  # so that "nothing this month" is readable content, not a disabled-looking
  # mark at 2.64:1.
  #
  # Acceptance criteria:
  # - The colour `.matrix-zero` takes is a token that clears 4.5:1 on the
  #   panel the matrices sit on (`--color-bg-elevated`) and on the canvas
  #   (`--color-bg`), in `:root`, `[data-theme="light"]`, the dark media
  #   block and `[data-theme="dark"]`: text-muted (5.89 / 5.91 on the panel,
  #   the computed contrast table's rows), never text-subtle (2.64 / 3.03).
  test "the matrices' quiet dash clears the text floor in both themes" do
    [_, token] =
      Regex.run(~r/\n\.matrix-zero \{[^}]*?\n  color: var\(--([a-z-]+)\);/, @css) ||
        flunk("no colour on .matrix-zero")

    for {block_name, tokens} <- [
          {":root", root()},
          {~s([data-theme="light"]), light()},
          {"prefers-color-scheme: dark", dark_media()},
          {~s([data-theme="dark"]), dark()}
        ],
        ground <- ~w(color-bg-elevated color-bg) do
      ratio = contrast(color(tokens, token), color(tokens, ground))

      assert ratio >= @bar,
             "#{block_name}: .matrix-zero's #{token} on #{ground} measures " <>
               "#{Float.round(ratio, 2)}:1, below #{@bar}:1"
    end
  end

  # User story (#1180 correction's pending cue; the γ closing act's
  # accessibility pass, A-F7):
  # As the operator reading the import correction's "comparing by date and
  # figures" while the dry run runs,
  # I want the pending cue inside the attention note to clear the text
  # floor in dark mode,
  # so that the one word that says the list is not final is readable: the
  # muted cue measured 4.22:1 on the note's dark tint.
  #
  # Acceptance criteria:
  # - Inside a data note the cue inherits the note's ink
  #   (`.data-note .recomputing-cue { color: inherit; }`): the attention
  #   note's warning on its tint, the note-severity note's muted ink on its
  #   well (unchanged).
  # - The attention ink clears 4.5:1 on its tint composited over the canvas
  #   and over the panel, in all four token blocks.
  # - DESIGN.md's computed contrast table carries the cue's rows, light and
  #   dark, each figure the one computed here from app.css.
  test "the pending cue inside an attention note clears the text floor" do
    assert @css =~ ~r/\n\.data-note \.recomputing-cue \{\s*color: inherit;\s*\}/

    assert @css =~
             ~r/\n\.data-note--attention \{[^}]*background: var\(--color-warning-soft\);[^}]*color: var\(--color-warning\);/

    for {block_name, tokens} <- [
          {":root", root()},
          {~s([data-theme="light"]), light()},
          {"prefers-color-scheme: dark", dark_media()},
          {~s([data-theme="dark"]), dark()}
        ],
        base <- ~w(color-bg-elevated color-bg) do
      tint = flatten(color(tokens, "color-warning-soft"), color(tokens, base))
      ratio = contrast(color(tokens, "color-warning"), tint)

      assert ratio >= @bar,
             "#{block_name}: the cue's warning on warning-soft over #{base} measures " <>
               "#{Float.round(ratio, 2)}:1"
    end

    rows =
      "_bmad-output/planning-artifacts/design-language/DESIGN.md"
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "| "))

    {light, night} = {root(), dark_media()}

    expected = [
      {"recomputing-cue in an attention note, warning #b45309 / warning-soft over bg-elevated",
       color(light, "color-warning"),
       flatten(color(light, "color-warning-soft"), color(light, "color-bg-elevated"))},
      {"recomputing-cue in an attention note, warning-dark #fbbf24 / warning-soft-dark over bg-elevated-dark",
       color(night, "color-warning"),
       flatten(color(night, "color-warning-soft"), color(night, "color-bg-elevated"))}
    ]

    for {pair, ink, ground} <- expected do
      figure = :erlang.float_to_binary(contrast(ink, ground), decimals: 2)
      row = Enum.find(rows, &String.starts_with?(&1, "| #{pair} |")) || flunk("no row: #{pair}")
      [_pair, ratio | _] = row |> String.split("|", trim: true) |> Enum.map(&String.trim/1)

      assert String.trim(ratio, "*") == figure,
             "#{pair}: the table says #{ratio}, app.css #{figure}"
    end
  end

  # User story (Sprint 23 C2; plan D-11; board
  # ux-design-2026-11-02-sprint23/04-number-colours, pick Q7 C, its
  # contrast table):
  # As the operator reading a gain or a loss in any theme,
  # I want the brand teal and the brand coral the gain and loss colours now
  # alias to clear the text floor wherever a signed figure or a problem note
  # sits,
  # so that one green and one red cost no readability.
  #
  # Acceptance criteria:
  # - `--color-positive` and `--color-danger` measure, light and dark, on the
  #   canvas, the panels and the problem tint (composited over the panel), the
  #   board's figures to two decimals: teal 5.11 / 5.47 / 4.56 and coral
  #   5.08 / 5.44 / 4.53 light; teal 10.32 / 9.40 / 8.51 and coral
  #   7.14 / 6.50 / 5.89 dark — every one ≥ 4.5:1, in all four token blocks.
  test "the gain and loss colours clear the text floor on the canvas, the panels and the problem tint" do
    expected = %{
      light: %{
        "color-positive" => ["5.11", "5.47", "4.56"],
        "color-danger" => ["5.08", "5.44", "4.53"]
      },
      dark: %{
        "color-positive" => ["10.32", "9.40", "8.51"],
        "color-danger" => ["7.14", "6.50", "5.89"]
      }
    }

    for {block_name, tokens, mode} <- [
          {":root", root(), :light},
          {~s([data-theme="light"]), light(), :light},
          {"prefers-color-scheme: dark", dark_media(), :dark},
          {~s([data-theme="dark"]), dark(), :dark}
        ],
        {token, figures} <- expected[mode] do
      panel = color(tokens, "color-bg-elevated")

      grounds = [
        color(tokens, "color-bg"),
        panel,
        flatten(color(tokens, "color-danger-soft"), panel)
      ]

      measured =
        Enum.map(grounds, fn ground ->
          ratio = contrast(color(tokens, token), ground)

          assert ratio >= @bar,
                 "#{block_name}: #{token} measures #{Float.round(ratio, 2)}:1, below #{@bar}:1"

          :erlang.float_to_binary(ratio, decimals: 2)
        end)

      assert measured == figures,
             "#{block_name}: #{token} on bg / bg-elevated / danger-soft measures " <>
               "#{inspect(measured)}, the board says #{inspect(figures)}"
    end
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
  # An alias (`var(--x)`) resolves in the block that declares it, as the
  # browser computes it on the root element.
  defp color(tokens, name) do
    case Map.get(tokens, name) || Map.fetch!(root(), name) do
      "var(--" <> rest -> color(tokens, String.trim_trailing(rest, ")"))
      value -> parse(value)
    end
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
