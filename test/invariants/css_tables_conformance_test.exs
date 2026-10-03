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
  #   `#detail-closed-trades-table` copy (pick H1, rule ①). Their muted-dash
  #   lines stay: a muted class in a cell is not a sign.
  test "a signed cell keeps its sign colour in every data table" do
    assert block(".data-table td.is-positive") =~ ~r/color:\s*var\(--color-positive\);/
    assert block(".data-table td.is-negative") =~ ~r/color:\s*var\(--color-danger\);/

    assert block(".drift-table tr.is-muted td.is-negative") =~
             ~r/color:\s*var\(--color-danger\);/

    for table <- ["#realized-trades-table", "#detail-closed-trades-table"] do
      refute @css =~ "#{table} td.is-positive", "#{table} still carries its own sign rule"
      refute @css =~ "#{table} td.is-negative", "#{table} still carries its own sign rule"
      assert block("#{table} td.trade-pa--na") =~ ~r/color:\s*var\(--color-text-muted\);/
    end
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
