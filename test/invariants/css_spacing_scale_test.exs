defmodule Portfolixir.Invariants.CssSpacingScaleTest do
  use ExUnit.Case, async: true

  # User story (Steve UAT #450, UX-DR14):
  # As a maintainer keeping the design system coherent,
  # I want a 4px spacing scale and a heading ramp to exist as tokens and be
  # adopted on the primary surfaces,
  # so that spacing and headings stop being ad-hoc px values that drift.
  #
  # Acceptance criteria:
  # - A 4px-based spacing scale (--space-1 … --space-8) is defined in the
  #   stylesheet, with --space-1 == 4px and --space-8 == 48px.
  # - A heading ramp (--text-h1/h2/h3 size + weight) is defined.
  # - The spacing scale is actually adopted (var(--space-*) is used widely, not
  #   just defined).
  # - The locale-switcher pill text is at least 11px (UX-DR14 detail).

  @css_path "priv/static/app.css"

  setup do
    {:ok, css: File.read!(@css_path)}
  end

  test "a 4px spacing scale is defined as tokens", %{css: css} do
    assert css =~ ~r/--space-1:\s*4px;/
    assert css =~ ~r/--space-2:\s*8px;/
    assert css =~ ~r/--space-3:\s*12px;/
    assert css =~ ~r/--space-4:\s*16px;/
    assert css =~ ~r/--space-5:\s*20px;/
    assert css =~ ~r/--space-6:\s*24px;/
    assert css =~ ~r/--space-7:\s*32px;/
    assert css =~ ~r/--space-8:\s*48px;/
  end

  test "a heading ramp is defined as size and weight tokens", %{css: css} do
    for token <- [
          "--text-h1-size:",
          "--text-h1-weight:",
          "--text-h2-size:",
          "--text-h2-weight:",
          "--text-h3-size:",
          "--text-h3-weight:"
        ] do
      assert css =~ token, "expected heading-ramp token #{token} to be defined"
    end
  end

  test "the spacing scale is adopted across the stylesheet, not just defined", %{css: css} do
    uses = Regex.scan(~r/var\(--space-[1-8]\)/, css) |> length()
    assert uses >= 20, "expected the spacing scale to be adopted widely, saw #{uses} uses"
  end

  test "the heading ramp is adopted on the page and section headings", %{css: css} do
    assert css =~ "var(--text-h1-size)"
    assert css =~ "var(--text-h2-size)"
  end

  test "the locale-switcher pill text is at least 11px", %{css: css} do
    [_, size] = Regex.run(~r/\.locale-link\s*\{[^}]*font-size:\s*(\d+)px/s, css)
    assert String.to_integer(size) >= 11
  end
end
