defmodule Portfolixir.Invariants.CssTablesConformanceTest do
  use ExUnit.Case, async: true

  @css File.read!("priv/static/app.css")

  # User story (#1009; Sprint 18 pick H4, board
  # ux-design-2026-10-02/04-tables-conformance, ① "after"; DESIGN.md →
  # Amendment 2026-08-22, the subject column):
  # As the operator reading a table wider than its scroller — a Cash-flow
  # matrix, the drift tree, the positions worklist, the history's Balance —
  # I want the subject column to stand at the scroller's right edge while the
  # other columns scroll beneath it,
  # so that the figure the surface is about is on screen at every width.
  #
  # Acceptance criteria:
  # - A table inside UX-DR15's scroller is not a scroll container of its own:
  #   `.data-table-wrapper > table` sets `overflow: visible`, so the wrapper is
  #   the sticky container `.col-subject` pins against. A bare table outside a
  #   wrapper keeps the global fallback.
  # - ①b The seam rides the pinned cell as an inset shadow, not a border,
  #   because a collapsed table paints a cell's border itself and leaves it
  #   behind when the cell sticks.
  # - ①c The pinned head cell takes the head row's grey outside `.data-table`.
  # - ①d The pinned cell is opaque on a striped row and follows the hover, so
  #   the figures scrolling beneath it never show through.
  test "the subject column pins to its scroller's edge, opaque, with its seam" do
    assert block(".data-table-wrapper > table") =~ ~r/overflow:\s*visible;/

    subject = block(".col-subject")
    assert subject =~ ~r/position:\s*sticky;/
    assert subject =~ ~r/right:\s*0;/
    assert subject =~ ~r/background:\s*var\(--color-bg-elevated\);/
    assert subject =~ ~r/border-left:\s*0;/
    assert subject =~ ~r/box-shadow:\s*inset 1px 0 0 var\(--color-border\);/

    head = block("thead .col-subject")
    assert head =~ ~r/z-index:\s*2;/
    assert head =~ ~r/background:\s*var\(--color-bg-muted\);/

    assert block(".data-table tbody tr:nth-child(even) td.col-subject") =~
             ~r/background:\s*color-mix\(in srgb, var\(--color-bg-muted\) 24%, var\(--color-bg-elevated\)\);/

    assert block(".data-table tbody tr:hover td.col-subject") =~
             ~r/background:\s*var\(--color-hover\);/

    # Both carry the same specificity, so the hover must come later to win
    # on a hovered even row.
    assert position(".data-table tbody tr:hover td.col-subject") >
             position(".data-table tbody tr:nth-child(even) td.col-subject")
  end

  # User story (#1010; Sprint 18 pick H4, board
  # ux-design-2026-10-02/04-tables-conformance, ② "after"; DESIGN.md →
  # Colors, "semantic color applies wherever a sign exists, at every level
  # of a table"):
  # As the operator reading gains and losses in a table — a security's open
  # lots and closed trades, the drift of a position row —
  # I want every signed cell in its sign colour,
  # so that a loss in a row looks like the loss it is, not like body text.
  #
  # Acceptance criteria:
  # - `.data-table td.is-positive` / `.is-negative` outrank `.data-table tbody
  #   td { color }`, in every data table at once.
  # - A muted drift row keeps its negative drift red:
  #   `.drift-table tr.is-muted td.is-negative` outranks the row's grey.
  # - The table-scoped copies of the sign rule are gone, because the general
  #   rule makes them redundant: Sprint 17's `#realized-trades-table` copy
  #   (board 01 rule ⑥) and the security Trades tab's
  #   `#detail-closed-trades-table` copy (pick H1, rule ①).
  # - Their muted-dash lines went the same way (#1142, Sprint 20 board
  #   ux-design-2026-10-07/02-money-findings, rule ②): the open lots', the
  #   Holdings tab's and Wealth's cells carry the reason dash too, so one
  #   general `.data-table td.trade-pa--na` (0,2,1) outranks `.data-table
  #   tbody td { color }` (0,1,2) in every data table.
  test "a signed cell keeps its sign colour in every data table" do
    assert block(".data-table td.is-positive") =~ ~r/color:\s*var\(--color-positive\);/
    assert block(".data-table td.is-negative") =~ ~r/color:\s*var\(--color-danger\);/

    assert block(".drift-table tr.is-muted td.is-negative") =~
             ~r/color:\s*var\(--color-danger\);/

    assert block(".data-table td.trade-pa--na") =~ ~r/color:\s*var\(--color-text-muted\);/

    for table <- ["#realized-trades-table", "#detail-closed-trades-table"] do
      refute @css =~ "#{table} td.is-positive", "#{table} still carries its own sign rule"
      refute @css =~ "#{table} td.is-negative", "#{table} still carries its own sign rule"
      refute @css =~ "#{table} td.trade-pa--na", "#{table} still carries its own dash rule"
    end
  end

  # User story (#1011, and #911's basis line; Sprint 18 pick H4, board
  # ux-design-2026-10-02/04-tables-conformance ⑤ "after"; DESIGN.md → the
  # basis voice and {components.disclosure}, UX-DR19):
  # As the operator reading what a surface aggregates and opening its
  # secondary tables,
  # I want every basis line in the muted 12 px voice and every disclosure
  # summary in the control label the spec names,
  # so that a basis line does not read as body text and one disclosure does
  # not look heavier than the next.
  #
  # Acceptance criteria:
  # - ⑤a A context-free `.summary-basis` sets margin 0, 12 px and the muted
  #   colour. It precedes every scoped basis rule, so the later single-class
  #   rules with their own margin or layout (`.kpi-strip__basis`,
  #   `.tree-basis`) keep winning by source order.
  # - ⑤b `.disclosure-summary` is defined once, at {typography.control-label}
  #   (12 px, weight 500, 0.04em) in the muted colour; its second definition
  #   (0.85rem / 600), which won by source order, is gone, and the merge
  #   manifest's local 12 px / 500 with it.
  test "one basis voice and one disclosure summary" do
    basis = block(".summary-basis")
    assert basis =~ ~r/margin:\s*0;/
    assert basis =~ ~r/font-size:\s*12px;/
    assert basis =~ ~r/color:\s*var\(--color-text-muted\);/

    for scoped <- [
          ".transaction-summary .summary-basis",
          "#portfolio-positions .summary-basis",
          ".kpi-strip__basis",
          ".tree-basis",
          ".detail-tab-panel--overview .summary-basis"
        ] do
      assert position(".summary-basis") < position(scoped),
             "the context-free basis rule must precede #{scoped}"
    end

    for selector <- [
          ".disclosure-summary",
          ".disclosure-summary::-webkit-details-marker",
          ".disclosure-summary:focus-visible"
        ] do
      assert length(Regex.scan(~r/\n#{Regex.escape(selector)} \{/, @css)) == 1,
             "#{selector} is defined more than once"
    end

    summary = block(".disclosure-summary")
    assert summary =~ ~r/font-size:\s*12px;/
    assert summary =~ ~r/font-weight:\s*500;/
    assert summary =~ ~r/letter-spacing:\s*0\.04em;/
    assert summary =~ ~r/color:\s*var\(--color-text-muted\);/

    manifest = block(".merge-manifest > .disclosure-summary")
    refute manifest =~ "font-size"
    refute manifest =~ "font-weight"
  end

  # User story (the closing act's H4 ①d finding; board
  # ux-review-2026-10-03/03-gamma-surface-repairs, G5):
  # As the operator hovering a booking in the history filtered to one
  # account,
  # I want the row's hover wash to run through the pinned Balance,
  # so that the one figure the filter was chosen for reads as part of the
  # row I point at.
  #
  # Acceptance criteria:
  # - `#transaction-list` is not a `.data-table`; its hover is the global
  #   `tbody tr:hover` wash (42 % accent-soft over transparent, on the row).
  # - The pinned Balance takes the same 42 % accent-soft over
  #   {colors.bg-elevated}, so it follows the wash and stays opaque while
  #   the figures scroll beneath it.
  test "the history's hover wash reaches the pinned Balance" do
    assert block("tbody tr:hover") =~
             ~r/background:\s*color-mix\(in srgb, var\(--color-accent-soft\) 42%, transparent\);/

    assert block("#transaction-list tbody tr:hover td.col-subject") =~
             ~r/background:\s*color-mix\(in srgb, var\(--color-accent-soft\) 42%, var\(--color-bg-elevated\)\);/
  end

  # User story (the closing act's H4 ⑤b finding; board
  # ux-review-2026-10-03/03-gamma-surface-repairs, G4):
  # As the operator on Snapshots,
  # I want "Neuer Snapshot" to read as the quiet disclosure summary every
  # other disclosure is,
  # so that one summary on the page does not look like a link in the accent
  # colour and a heavier weight than "Daten als Tabelle" beside it.
  #
  # Acceptance criteria:
  # - No rule targets `.snapshot-create > summary`: the summary's
  #   `.disclosure-summary` (12 px / 500 / muted, its chevron, its hover and
  #   its 44 px coarse floor) is the whole of its anatomy. The local rule
  #   (0,1,1: accent, weight 600) outranked the class (0,1,0).
  test "the new-snapshot summary has no local override of the disclosure summary" do
    refute @css =~ ".snapshot-create > summary",
           "a rule still overrides the new-snapshot summary's .disclosure-summary"

    assert block(".snapshot-create") =~ ~r/margin:\s*var\(--space-3\) 0;/
  end

  # User story (#1053, the closing act's H4 ④c finding; board
  # ux-review-2026-10-03/03-gamma-surface-repairs, G2):
  # As the operator opening the allocation tree's Drift ⓘ on a 390 px phone,
  # I want its sentence to wrap inside its box,
  # so that I can read what drift means and against which portion it is
  # measured, instead of one line running out of the box and off the screen.
  #
  # Acceptance criteria:
  # - A tooltip's paragraph sets `white-space: normal` itself, so the phone
  #   block's `table { white-space: nowrap }` (or any table cell's `nowrap`)
  #   no longer reaches it by inheritance — at every width, on the class.
  # - The phone table rule itself is unchanged.
  test "a tooltip's sentence wraps inside its box inside a table at phone width" do
    assert block(".metric-tooltip p") =~ ~r/white-space:\s*normal;/

    assert @css =~
             ~r/@media \(max-width: 560px\) \{.*?\n  table \{\s*display: block;\s*overflow-x: auto;\s*white-space: nowrap;\s*\}/s
  end

  defp position(selector) do
    case :binary.match(@css, "\n" <> selector <> " {") do
      {at, _} -> at
      :nomatch -> flunk("no top-level rule for #{selector}")
    end
  end

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{selector}")
    end
  end
end
