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
end
