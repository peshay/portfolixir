defmodule PortfolixirWeb.DesignConformanceCssTest do
  use ExUnit.Case, async: true

  @app_css "priv/static/app.css"

  # User story (#833, DESIGN.md → Components → data-table.cell; board
  # ux-design-2026-09-20/04-num-and-focus, "after"):
  # As a local portfolio maintainer reading any table in the app,
  # I want every numeric column right-aligned with tabular numerals,
  # so that I can compare figures down a column without the digits wandering.
  #
  # Acceptance criteria:
  # - One generic rule backs `class="num"` on a table cell: right-aligned and
  #   tabular numerals, whatever table it sits in.
  # - The header cell `th.num` wins over `.data-table thead th`'s
  #   `text-align: left`, so the header sits over its right-aligned figures.
  test "a numeric cell is right-aligned with tabular numerals in any table" do
    app_css = File.read!(@app_css)

    [generic] =
      Regex.run(~r/\nth\.num,\s*td\.num,\s*\.data-table thead th\.num \{[^}]*\}/s, app_css)

    assert generic =~ "text-align: right"
    assert generic =~ "font-variant-numeric: tabular-nums"

    # Several tables reset their cells to `text-align: left` at the same
    # specificity as `th.num` (`.perf-data-table th`, `.drift-table th`, …);
    # the generic rule must come after every one of them, or source order
    # hands the tie back to the left-aligned reset.
    {generic_at, _} = :binary.match(app_css, String.trim_leading(generic))

    left_aligned_cell_resets =
      ~r/\n([^{}\n]*\b(?:th|td)(?:,\s*[^{}]*)?) \{[^}]*text-align: left/s
      |> Regex.scan(app_css, return: :index)
      |> Enum.map(fn [{at, _} | _] -> at end)

    assert left_aligned_cell_resets != []
    assert Enum.all?(left_aligned_cell_resets, &(&1 < generic_at))
  end

  # User story (#834, DESIGN.md → Do's and Don'ts, EXPERIENCE.md → the
  # coarse-pointer table; board ux-design-2026-09-20/04-num-and-focus, "after"):
  # As a local portfolio maintainer working a table by keyboard or on a phone,
  # I want the row kebab and its menu items to show a real focus ring and the
  # kebab to be a thumb-sized target,
  # so that I can see where focus is and hit the row menu without zooming.
  #
  # Acceptance criteria:
  # - `.row-actions__kebab:focus-visible` and `.row-context-menu__item:focus-visible`
  #   carry the 2px accent outline with a 2px offset, as
  #   `.filter-sheet-toggle:focus-visible` does.
  # - No rule on either class substitutes `outline: none` for the ring.
  # - Under `@media (pointer: coarse)` the kebab is at least 44 x 44 px.
  test "the row kebab and its menu items carry the shared focus ring and a coarse floor" do
    app_css = File.read!(@app_css)

    for class <- ["row-actions__kebab", "row-context-menu__item"] do
      [ring] = Regex.run(~r/\n\.#{class}:focus-visible \{[^}]*\}/s, app_css)
      assert ring =~ "outline: 2px solid var(--color-accent)"
      assert ring =~ "outline-offset: 2px"

      for [rule] <- Regex.scan(~r/\.#{class}[^{}]*\{[^}]*\}/s, app_css) do
        refute rule =~ "outline: none", "#{class} still substitutes outline: none:\n#{rule}"
      end
    end

    assert app_css =~
             ~r/@media \(pointer: coarse\) \{\s*\.row-actions__kebab \{[^}]*min-width: 44px;[^}]*min-height: 44px/s
  end
end
