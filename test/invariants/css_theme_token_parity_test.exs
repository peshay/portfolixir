defmodule Portfolixir.Invariants.CssThemeTokenParityTest do
  use ExUnit.Case, async: true

  # User story:
  # As a maintainer holding the design-language spec (DESIGN.md) against the
  # stylesheet,
  # I want a meta-test that fails when a theme-dependent token is declared in
  # one theme block but not the others, when a rule references a token that is
  # never defined, or when a decided token value drifts,
  # so that the defect class behind issues 643 (light-only warning tint),
  # 650 (light-only small shadow), 642 (white-on-dark-accent contrast) and
  # 644 (selected colour stuck on violet) cannot silently reappear.
  #
  # Acceptance criteria:
  # - The three theme override blocks (`prefers-color-scheme: dark`,
  #   `[data-theme="dark"]`, `[data-theme="light"]`) declare the same token
  #   set, so a forced theme always overrides the system default.
  # - Every `var(--x)` reference in app.css resolves to a token defined in
  #   app.css or set inline by a template under `lib/portfolixir_web/`.
  # - The designer-decided values of 2026-08-05 are pinned: danger `#b91c1c`
  #   (light), `--color-warning-soft` and `--shadow-sm` dark values,
  #   theme-dependent `--color-on-accent`, and `--color-selected` as an alias
  #   of the active accent's soft variant.
  # - Accent-variant tokens are referenced only at their sanctioned call
  #   sites (accent-picker swatches, the ma-50/ma-200 series strokes).

  @css_path "priv/static/app.css"

  @token_decl ~r/--([\w-]+)\s*:\s*([^;]+);/

  defp css, do: File.read!(@css_path)

  defp block(regex) do
    case Regex.run(regex, css(), capture: :all_but_first) do
      [body] -> body
      nil -> flunk("theme block not found for #{inspect(regex.source)}")
    end
  end

  defp tokens(body) do
    @token_decl
    |> Regex.scan(body, capture: :all_but_first)
    |> Map.new(fn [name, value] -> {name, String.trim(value)} end)
  end

  defp dark_media,
    do: tokens(block(~r/@media \(prefers-color-scheme: dark\) \{\s*:root \{(.*?)\n  \}/s))

  defp data_dark, do: tokens(block(~r/\n\[data-theme="dark"\] \{(.*?)\n\}/s))
  defp data_light, do: tokens(block(~r/\n\[data-theme="light"\] \{(.*?)\n\}/s))
  defp root_block, do: tokens(block(~r/\A:root \{(.*?)\n\}/s))

  test "the three theme override blocks re-key the same token set" do
    media = dark_media() |> Map.keys() |> MapSet.new()
    dark = data_dark() |> Map.keys() |> MapSet.new()
    light = data_light() |> Map.keys() |> MapSet.new()

    assert MapSet.equal?(media, dark), """
    `@media (prefers-color-scheme: dark)` and `[data-theme="dark"]` declare
    different token sets.
    Only in media block: #{inspect(MapSet.difference(media, dark) |> Enum.sort())}
    Only in [data-theme="dark"]: #{inspect(MapSet.difference(dark, media) |> Enum.sort())}
    """

    assert MapSet.equal?(media, light), """
    A token re-keyed for dark mode must also be declared in
    `[data-theme="light"]`, or forcing light under a dark system preference
    keeps the dark value (the issue-643/650 defect class).
    Only in dark media block: #{inspect(MapSet.difference(media, light) |> Enum.sort())}
    Only in [data-theme="light"]: #{inspect(MapSet.difference(light, media) |> Enum.sort())}
    """
  end

  test "every var(--x) reference in app.css resolves to a defined token" do
    defined =
      @token_decl
      |> Regex.scan(css(), capture: :all_but_first)
      |> MapSet.new(fn [name, _] -> name end)

    template_defined =
      "lib/portfolixir_web/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        Regex.scan(~r/--([\w-]+)\s*:/, File.read!(path), capture: :all_but_first)
      end)
      |> MapSet.new(fn [name] -> name end)

    known = MapSet.union(defined, template_defined)

    undefined =
      css()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, lineno} ->
        ~r/var\(\s*--([\w-]+)/
        |> Regex.scan(line, capture: :all_but_first)
        |> Enum.reject(fn [name] -> MapSet.member?(known, name) end)
        |> Enum.map(fn [name] -> "#{@css_path}:#{lineno}: --#{name}" end)
      end)

    assert undefined == [], """
    app.css references tokens that are never defined (a fallback value hiding
    behind them is the issue-644 drift pattern):
    #{Enum.join(undefined, "\n")}
    """
  end

  test "designer-decided token values of 2026-08-05 are pinned" do
    root = root_block()
    light = data_light()
    dark = data_dark()
    media = dark_media()

    # Issue 648: danger darkened to clear 4.5:1 on the danger tint (5.39:1).
    assert root["color-danger"] == "#b91c1c"
    assert light["color-danger"] == "#b91c1c"

    # Issue 643: warning tint exists in dark, in the -soft-dark idiom.
    assert media["color-warning-soft"] == "rgb(251 191 36 / 0.16)"
    assert dark["color-warning-soft"] == "rgb(251 191 36 / 0.16)"

    # Issue 650: the small shadow deepens in dark like the other three levels.
    assert media["shadow-sm"] == "0 1px 3px rgb(0 0 0 / 0.5)"
    assert dark["shadow-sm"] == "0 1px 3px rgb(0 0 0 / 0.5)"

    # Issue 642: labels on an accent fill are ink in dark mode (7.06-10.32:1),
    # white only in light.
    assert root["color-on-accent"] == "#ffffff"
    assert light["color-on-accent"] == "#ffffff"
    assert media["color-on-accent"] == "#0b0f14"
    assert dark["color-on-accent"] == "#0b0f14"
  end

  test "--color-selected aliases the active accent's soft variant (issue 644)" do
    assert root_block()["color-selected"] == "var(--color-accent-soft)"

    literal_redefinitions =
      css()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} ->
        String.match?(line, ~r/--color-selected\s*:/) and
          not String.contains?(line, "var(--color-accent-soft)")
      end)
      |> Enum.map(fn {line, lineno} -> "#{@css_path}:#{lineno}: #{String.trim(line)}" end)

    assert literal_redefinitions == [], """
    --color-selected must stay an alias of --color-accent-soft everywhere it
    is declared; a literal value stops it re-keying with the accent:
    #{Enum.join(literal_redefinitions, "\n")}
    """
  end

  test "accent-variant tokens appear only at sanctioned call sites" do
    # Outside token-definition lines the named variants are allowed only in
    # the accent-picker swatches (one each) and the deliberately
    # variant-coloured ma-50/ma-200 series strokes (dash-distinguished, so
    # not hue-only). Everything else must resolve var(--color-accent).
    allowed = %{"violet" => 1, "teal" => 2, "coral" => 2}

    counts =
      css()
      |> String.split("\n")
      |> Enum.reject(&String.match?(&1, ~r/^\s*--[\w-]+\s*:/))
      |> Enum.flat_map(fn line ->
        Regex.scan(~r/var\(--color-accent-(violet|teal|coral)\)/, line,
          capture: :all_but_first
        )
      end)
      |> Enum.frequencies_by(fn [variant] -> variant end)

    for {variant, max} <- allowed do
      count = Map.get(counts, variant, 0)

      assert count <= max, """
      var(--color-accent-#{variant}) is referenced #{count}x outside token
      definitions (sanctioned: #{max}). A rule that is not the accent picker's
      own swatch or a dash-coded ma series must use var(--color-accent), or
      the surface stops re-keying with the accent.
      """
    end
  end
end
