defmodule Portfolixir.Invariants.CssLayoutSweepTest do
  use ExUnit.Case, async: true

  @css File.read!("priv/static/app.css")

  # User story (#790, the review's D8–D10 and the two lines after its table;
  # EXPERIENCE.md → Amendment 2026-09-12 → App shell; DESIGN.md → D6):
  # As a local portfolio maintainer,
  # I want the import button centred under its sentence, every control row
  # and section with a phone gutter of at least 16 px, the tab row with its
  # right-edge fade, and a labelled ⓘ that shows its whole label,
  # so that the layout reads as one composition.
  test "the import button is centred in the drop zone" do
    assert block(".import-drop-zone > .button-primary") =~ ~r/justify-self:\s*center/
  end

  test "sections and control rows keep a side gutter of at least 16 px" do
    assert block(".workspace-section") =~ ~r/padding:[^;]*clamp\(16px,/
    assert block(".workspace-section--controls") =~ ~r/padding-block:\s*0/
  end

  test "the area tab row carries a 40 px one-sided right-edge fade" do
    assert block(".area-tabs") =~
             ~r/mask-image:\s*linear-gradient\(to right, black calc\(100% - 40px\)/
  end

  # User story (#817; DESIGN.md → "Tab row overflow — the shipped form is the
  # specification (D6, UX-DR22)"; EXPERIENCE.md → UX-DR22, "answered here
  # once, for every tab row — Wealth, Transactions, detail panes"):
  # As a local portfolio maintainer reading a security on a 390 px phone,
  # I want the detail pane's tab row held to the same shipped form as the
  # area tabs,
  # so that the last tab stays reachable in a ~360 px panel instead of
  # coming to rest half-cut behind no affordance at all.
  #
  # Acceptance criteria:
  # - `.detail-pane-tabs` carries the five declarations of the D6 form:
  #   overflow-y hidden, x-proximity snapping, the one-sided right-edge fade,
  #   no scrollbar, and the baseline as an inset box-shadow.
  # - The `border-bottom` baseline is GONE, which is the clause the section
  #   calls non-obvious: with `overflow-x: auto` a border baseline either
  #   raises a vertical scrollbar or clips the active tab's underline to 1px.
  # - `.detail-pane-tab` keeps its intrinsic width and snaps to the start.
  test "the detail pane's tab row is held to the D6 shipped form" do
    row = block(".detail-pane-tabs")

    assert row =~ ~r/overflow-x:\s*auto/
    assert row =~ ~r/overflow-y:\s*hidden/
    assert row =~ ~r/scroll-snap-type:\s*x proximity/
    assert row =~ ~r/mask-image:\s*linear-gradient\(to right, black calc\(100% - 40px\)/
    assert row =~ ~r/scrollbar-width:\s*none/
    assert row =~ ~r/box-shadow:\s*inset 0 -1px 0 var\(--color-border\)/

    refute row =~ ~r/border-bottom:/,
           "D6's non-obvious clause: the baseline is an inset box-shadow, never a border-bottom"

    assert @css =~ ~r/\.detail-pane-tabs::-webkit-scrollbar \{\s*display: none;/

    tab = block(".detail-pane-tab")
    assert tab =~ ~r/flex:\s*none/
    assert tab =~ ~r/scroll-snap-align:\s*start/
    assert tab =~ ~r/white-space:\s*nowrap/
  end

  # User story (#1033; board ux-design-2026-10-02/07-phone-390, H7.2, rule
  # ②; DESIGN.md → D6, "the active tab is in view on arrival"):
  # As the operator arriving on a security's tab on a phone,
  # I want the detail tab row's fades to follow its edges, as the area tab
  # row's do,
  # so that the selected tab, now scrolled into view, does not rest under a
  # fixed right fade, and a left fade says there are tabs before it.
  #
  # Acceptance criteria:
  # - `.detail-pane-tabs` joins the three `.area-tabs` edge rules: a 24 px
  #   left fade away from the start, no right fade at the end, no mask on a
  #   row that rests on both edges.
  # - The row carries a trailing inset from `--detail-tabs-tail`, zero
  #   without script; the one-sided right fade stays its scriptless form.
  test "the detail tab row's fades follow its edges, and its end is a tab boundary" do
    row = block(".detail-pane-tabs")
    assert row =~ ~r/--detail-tabs-tail:\s*0px;/
    assert row =~ ~r/padding-inline-end:\s*var\(--detail-tabs-tail\);/

    assert @css =~
             ~r/\n\.detail-pane-tabs:not\(\[data-scroll-start\]\),\n\.area-tabs:not\(\[data-scroll-start\]\) \{\s*mask-image: linear-gradient\(\s*to right,\s*transparent 0,\s*black 24px,/

    assert @css =~
             ~r/\n\.detail-pane-tabs\[data-scroll-end\],\n\.area-tabs\[data-scroll-end\] \{\s*mask-image: linear-gradient\(to right, transparent 0, black 24px\);/

    assert @css =~
             ~r/\n\.detail-pane-tabs\[data-scroll-start\]\[data-scroll-end\],\n\.area-tabs\[data-scroll-start\]\[data-scroll-end\] \{\s*mask-image: none;/
  end

  # User story (#873; board ux-design-2026-09-24/08-classification-detail, ①
  # and pick G8 = A; DESIGN.md → Layout & Spacing and Classification tree
  # rows; EXPERIENCE.md → App shell, "nothing is flush with the screen edge"):
  # As the operator reading a classification on a 390 px phone,
  # I want the page's heading, controls, form and tree to keep the gutter
  # every other page keeps, and a category row to keep its name,
  # so that nothing starts at the screen's edge and "Growth" is not cut to
  # "Gr…" by the gutter that fixes the edge.
  #
  # Acceptance criteria:
  # - Every direct block of `.classifications-detail` that is not a band takes
  #   the band's inline gutter (16 px floor), the heading the band's top
  #   padding and the last block its bottom padding — no new value. A
  #   modal dialog is no block: it keeps its own centring (Sprint 26
  #   closing act, V4; test/browser/closing_act_layout_test.exs measures it).
  # - Under 560 px a category row lies on two lines of the same grid: marker,
  #   swatch, name (which may wrap) and its "+N without holdings" first, the
  #   actions at the end; value and result under their column heads second.
  #   The swatch never shrinks.
  test "the classification detail's own blocks keep the band gutter" do
    assert block(".classifications-detail > :not(.workspace-section):not(dialog)") =~
             ~r/margin-inline:\s*clamp\(16px, 2\.4vw, 28px\)/

    assert block(".classifications-detail > .detail-head") =~
             ~r/margin-top:\s*clamp\(18px, 2\.4vw, 28px\)/

    assert block(".classifications-detail > :last-child:not(dialog)") =~
             ~r/margin-bottom:\s*clamp\(18px, 2\.4vw, 28px\)/
  end

  #
  # Amended by #1165 (Sprint 21 γ6, board 06 ①, pick N17 A): between 561 and
  # 720 px the one-line row left the name 33 / 4 px at 600 px, so the two
  # lines, and the dropped "Positions" and "Cost", hold up to 720 px. They
  # are a container query on the page (`container: classifications /
  # inline-size`), selected by the room the tree has, so the band the open
  # sidebar makes (901 to about 940 px of viewport) lies on two lines too.
  # No tree rule is left at the viewport's 560 px.
  test "up to 720 px of the page a category row wraps to two lines and keeps its name" do
    assert block(".classifications-detail") =~ ~r/container:\s*classifications \/ inline-size;/

    columns =
      case Regex.run(
             ~r/@container classifications \(max-width: 720px\) \{\n  \/\* The phone keeps the name[^\n]*\n(.*?)\n\}\n/s,
             @css
           ) do
        [_, body] -> body
        nil -> flunk("no 720 px container block for the tree's columns")
      end

    assert columns =~
             ~r/\.cat-summary \{[^}]*grid-template-columns: 0\.7rem minmax\(0, 1fr\) 6rem 6rem 2\.6rem;/

    assert columns =~
             ~r/\.tree-head \{[^}]*grid-template-columns: minmax\(0, 1fr\) 6rem 6rem 2\.6rem;/

    assert columns =~ ~r/\.cat-positions,\s*\.cat-invested,[^{]*\{\s*display: none;/

    rows =
      case Regex.run(
             ~r/@container classifications \(max-width: 720px\) \{\n  \/\* category rows on two lines[^\n]*\n(.*?)\n\}\n/s,
             @css
           ) do
        [_, body] -> body
        nil -> flunk("no 720 px container block for the two-line category row")
      end

    refute @css =~
             ~r/@media \(max-width: 560px\) \{\n  \/\* (The phone keeps the name|category rows on two lines)/

    assert rows =~ ~r/\.cat-summary \.cat-name \{[^}]*grid-column: 2 \/ 5;[^}]*grid-row: 1;/
    assert rows =~ ~r/\.cat-summary \.cat-name \{[^}]*flex-wrap: wrap;/
    assert rows =~ ~r/\.cat-summary \.cat-name__text \{[^}]*white-space: normal;/
    assert rows =~ ~r/\.cat-summary \.cat-swatch \{[^}]*flex: none;/
    assert rows =~ ~r/\.cat-summary \.cat-actions \{[^}]*grid-column: 5;[^}]*grid-row: 1;/
    assert rows =~ ~r/\.cat-summary \.cat-value \{[^}]*grid-column: 3;[^}]*grid-row: 2;/
    assert rows =~ ~r/\.cat-summary \.cat-result \{[^}]*grid-column: 4;[^}]*grid-row: 2;/
  end

  # User story (#875, ①; board ux-design-2026-09-24/09-allocation-positions;
  # ADR-0023's hint anatomy):
  # As the operator reading the rebalancing hints on a German page,
  # I want "Verkauf" to fit its column,
  # so that the verb never runs into the "≈" and the "≈" stays on one vertical
  # line across the rows.
  #
  # Acceptance criteria:
  # - The verb track is `max-content`; the ≈, quantity and unit tracks keep
  #   their widths and the grid still packs to the end.
  test "the rebalancing hint's verb column is as wide as its word" do
    hint = block(".rebalance-hint")

    assert hint =~
             ~r/grid-template-columns:\s*max-content 0\.9em minmax\(4\.2em, max-content\) max-content;/

    assert hint =~ ~r/justify-content:\s*end;/
  end

  # User story (#909; board ux-design-2026-10-02/07-phone-390, H7.5, pick A,
  # rule ③):
  # As the operator reading the import's summary cards in any language,
  # I want a label that is one long word to break inside its card,
  # so that it never runs past the card's edge — the soft hyphen in the
  # German "Verrechnungskonten" decides where that word breaks, and this rule
  # is the floor for any other long word in any locale.
  #
  # Acceptance criteria:
  # - `.import-stat-card .label` may shrink below its content (`min-width:
  #   0`, it is a grid item) and break anywhere (`overflow-wrap: anywhere`).
  test "an import card's label breaks inside its card" do
    label = block(".import-stat-card .label")
    assert label =~ ~r/min-width:\s*0;/
    assert label =~ ~r/overflow-wrap:\s*anywhere;/
  end

  test "a labelled tooltip summary grows with its label" do
    assert block(".metric-tooltip--labelled summary") =~ ~r/width:\s*auto/
  end

  # User story (#1211, Sprint 21 γ6; board 06 ②, pick N18 A; the γ closing
  # act, DC1):
  # As the operator editing a category on a phone or a desktop,
  # I want the "Parent" select capped at the board's width,
  # so that a 31-level chain's option neither runs the select 589 px past a
  # 390 px screen nor wraps the edit form to three lines at 1200 px.
  #
  # Acceptance criteria:
  # - The cap outranks the page's own "controls shrink to the column" rule
  #   (`.classifications-detail :is(.inline-form, .cat-edit-form) :is(select,
  #   input)`, specificity 0-2-1, later in the file), which reset it to
  #   `max-width: 100%`: the select's rule is scoped to the page as well
  #   (0-3-1), so it wins wherever it sits.
  # - The cap is `min(16rem, 100%)`: the board's 16 rem, never wider than
  #   the column on a phone.
  test "the category edit form's parent select keeps its 16 rem cap over the page's shrink rule" do
    select = block(".classifications-detail .cat-edit-form .recolor-label select")
    assert select =~ ~r/max-width:\s*min\(16rem, 100%\);/
    assert select =~ ~r/min-width:\s*0;/

    refute @css =~ ~r/\n\.cat-edit-form \.recolor-label select \{/,
           "the unscoped 0-2-1 rule loses to the page's later shrink rule"
  end

  # User story (#1155, Sprint 21 γ8; board 08, N14 = A; the γ closing act,
  # DD-S4):
  # As the operator reading Wealth's allocation tree on a 390 px phone,
  # I want a position row's name to wrap, as the flat positions' names do,
  # so that a twin's identifier after the name is not hidden under the
  # pinned Drift column.
  #
  # Acceptance criteria:
  # - Under 560 px the tree's position rows (`.drift-table tr.is-position`)
  #   join the flat positions' name rule: the first cell takes the 9 rem
  #   share and wraps (`white-space: normal`, `overflow-wrap: break-word`),
  #   overriding the phone block's `table { white-space: nowrap }`.
  test "under 560 px the allocation tree's position names wrap as the flat positions' do" do
    [_, selectors, body] =
      Regex.run(
        ~r/@media \(max-width: 560px\) \{\n((?:  [^{\n]+,\n)*  \.drift-table\[data-role="flat-positions"\] td:first-child(?:,\n  [^{\n]+)*) \{([^}]*)\}/,
        @css
      ) || flunk("no phone rule for the flat positions' names")

    assert selectors =~ ".drift-table tr.is-position td:first-child"
    assert body =~ ~r/white-space:\s*normal;/
    assert body =~ ~r/overflow-wrap:\s*break-word;/
    assert body =~ ~r/min-width:\s*9rem;/
  end

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{selector}")
    end
  end

  # User story (#799 UX-DR27, #800 C4-B; DESIGN.md → Amendment 2026-09-12 →
  # Two-line phone rows and Components → Phone lists):
  # As a local portfolio maintainer on a 390 px phone,
  # I want the entity tables to give way to two-line rows and the chip row
  # to the Filter control under 560 px, and both to stay out of the desktop
  # layout above it,
  # so that the phone composition is a rule of the stylesheet, not a
  # coincidence of the viewport.
  test "under 560 px the entity tables give way to the two-line rows" do
    assert phone_block() =~ ~r/\.phone-rows \{\s*display: block;/

    # #984 (pick G1-A, board rule 3): the Trades facet's table is the third
    # list surface to give way to its rows; #1029 (pick H1, board rule ④):
    # the security's closed trades are the fourth; FR-41 (ADR-0051 §12,
    # board pick A): the contribution table under the Wealth performance
    # chart is the fifth; #1012 (pick H7.1 = A, board
    # ux-design-2026-10-02/07-phone-390 rule ①): a security's quotes the sixth.
    # #1065 (pick J6 A, board ux-design-2026-10-04/06-phone-wealth rule ①):
    # Wealth's Positions table the seventh. #1366 line 2 (Sprint 24 P1,
    # board ux-design-2026-11-05-sprint24-p1): the contribution table left
    # the block for a container query on its own width, where its columns
    # stop fitting (performance_contribution_live_test.exs pins it).
    assert phone_block() =~
             ~r/#securities-table,\s*#transaction-table-wrapper,\s*#realized-trades-table-wrapper,\s*#detail-closed-trades-table-wrap,\s*#quotes-table-wrapper,\s*#holdings-positions-wrapper \{\s*display: none;/
  end

  # User story (#1065; board ux-design-2026-10-04/06-phone-wealth, pick J6
  # A, rule ①; EXPERIENCE.md → UX-DR27, which names holdings):
  # As the operator reading my positions on a 390 px phone,
  # I want the Positions as two-line rows and no column toggle,
  # so that the quantity is on the screen and no control offers columns the
  # rows do not have.
  #
  # Acceptance criteria:
  # - The holdings phone row is the trades row's shape, two children: two
  #   tracks, `minmax(0, 1fr) auto`.
  # - Under 560 px the holdings column toggle joins the pickers that hide,
  #   and so does the picker's own panel: one opened on a wide window stays
  #   open across a resize, and its columns would do nothing to the rows
  #   (the review of PR γ U4).
  test "the holdings phone row has two tracks and its column picker hides on the phone" do
    assert block("#holdings-phone-rows .phone-row") =~
             ~r/grid-template-columns:\s*minmax\(0, 1fr\) auto;/

    assert phone_block() =~
             ~r/#toggle-column-popover,\s*\.column-picker-bar,\s*#holdings-column-toggle,\s*#holdings-column-picker \{\s*display: none;/
  end

  # User story (#1151, Sprint 21 γ2; board ux-design-2026-10-09/02-securities,
  # rule ⑤): As the operator who opened the securities list's column picker
  # on a wide window and then narrowed it below 560 px, I want the picker's
  # panel to hide with its toggle, so that no panel stays open over the rows
  # with nothing left to close it.
  #
  # Acceptance criteria:
  # - `#column-picker` joins the 560 px picker rule beside its toggle,
  #   `.column-picker-bar` and Wealth's toggle and panel.
  test "the securities list's column picker hides with its toggle on the phone" do
    assert phone_block() =~
             ~r/#column-picker,\s*#toggle-column-popover,\s*\.column-picker-bar,\s*#holdings-column-toggle,\s*#holdings-column-picker \{\s*display: none;/
  end

  # User story (#1139, Sprint 21 γ2; board ux-design-2026-10-09/02-securities,
  # rule ④): As the operator reading the securities list on a 390 px phone,
  # I want each row's monogram and row menu inset by the page gutter, so that
  # neither touches the viewport's edge.
  #
  # Acceptance criteria:
  # - The securities phone row carries a 16 px inline padding, the gutter
  #   the toolbar's search field keeps; the row's block padding is unchanged
  #   and its border still runs edge to edge.
  test "the securities phone row keeps the 16 px page gutter on both sides" do
    assert block("#securities-phone-rows .phone-row") =~ ~r/padding-inline:\s*16px;/
    assert block(".phone-row") =~ ~r/padding:\s*10px 0;/
  end

  # User story (#1057; board ux-design-2026-10-04/06-phone-wealth, pick J6.2
  # A, rule ②):
  # As the operator reading two securities of one name,
  # I want the identifier that tells them apart in the securities list's
  # identifier voice, quieter than the name,
  # so that it reads as a tag on the name and not as a second name.
  #
  # Acceptance criteria:
  # - `.twin-id` is about 6 px after the name, as the board draws it: the
  #   real word space before it and a 2 px margin (amended 2026-10-07, the
  #   PR γ closing act: a 6 px margin on top of the space measured 9.8 px on
  #   the desktop and 10.9 px on the phone, and an identifier wrapped alone
  #   hung 6 px in).
  # - It is muted, `--font-mono`, 12 px, weight 400, and never breaks inside
  #   itself.
  test "the twin identifier is muted mono after the name and never breaks" do
    twin = block(".twin-id")
    assert twin =~ ~r/margin-left:\s*2px;/
    assert twin =~ ~r/color:\s*var\(--color-text-muted\);/
    assert twin =~ ~r/font-family:\s*var\(--font-mono\);/
    assert twin =~ ~r/font-size:\s*12px;/
    assert twin =~ ~r/font-weight:\s*400;/
    assert twin =~ ~r/white-space:\s*nowrap;/
  end

  # User story (#1333; Sprint 22 board 03, rule ⑤):
  # As the operator reading two accounts of one name in two portfolios,
  # I want the portfolio's name after each in the twin tag's place, set as a
  # word,
  # so that it reads as the name it is and not as an identifier.
  #
  # Acceptance criteria:
  # - `.twin-id--portfolio` keeps the tag's colour, size and spacing and
  #   drops its monospace for the text's own font.
  test "the portfolio tag of a twin account drops the identifier's monospace" do
    assert block(".twin-id--portfolio") =~ ~r/font-family:\s*inherit;/
  end

  # User story (#1086; board ux-design-2026-10-04/06-phone-wealth, rule ④;
  # EXPERIENCE.md → Value slot: a value never wraps inside its slot):
  # As the operator reading the KPI band on a 390 px phone,
  # I want "182.450,30 EUR" on one line in its half-width card,
  # so that the currency does not drop under the digits.
  #
  # Acceptance criteria:
  # - Under 560 px a compact card of Wealth's KPI band takes 16 px for its
  #   value, the ramp's {typography.subsection-title} step; above it stays
  #   22 px.
  # - The step-down is Wealth's band only (`#portfolio-kpis`), as the board
  #   draws it: Risk's metric cards are `.stat--compact` too, and there a
  #   computed value would shrink to the 16 px of `.stat-empty`, the
  #   sentence a card shows when it has no value (the review of PR γ U4).
  test "under 560 px a compact card's value steps down to 16 px on Wealth only" do
    assert block(".stat--compact strong") =~ ~r/font-size:\s*22px;/

    refute @css =~ ~r/\n\s*\.stat--compact strong \{\s*font-size:\s*16px;/,
           "an unscoped 16 px compact value would reach Risk's metric cards"

    compact =
      case Regex.run(
             ~r/@media \(max-width: 560px\) \{\n  \/\* compact card value[^\n]*\n(.*?)\n\}\n/s,
             @css
           ) do
        [_, body] -> body
        nil -> flunk("no 560 px block for the compact card's value")
      end

    assert compact =~ ~r/#portfolio-kpis \.stat--compact strong \{\s*font-size: 16px;\s*\}/
  end

  # User story (#1063; board ux-design-2026-10-04/06-phone-wealth, rule ⑤;
  # EXPERIENCE.md → UX-DR15, no horizontal page scroll; DESIGN.md → D6):
  # As the operator reading a security's detail at 768 px,
  # I want the page to stay as wide as the window,
  # so that the tab row scrolls inside itself instead of the whole page
  # scrolling 17 px sideways.
  #
  # Acceptance criteria:
  # - The split workspace's one column has a zero floor, `minmax(0, 1fr)`:
  #   an implicit `auto` column took the detail pane's min-content (its nine
  #   `flex: none` tabs) as its floor.
  test "the split workspace's column has a zero floor" do
    assert block(".securities-workspace--split") =~
             ~r/grid-template-columns:\s*minmax\(0, 1fr\);/
  end

  # User story (#1063 on the chart tab; board
  # ux-design-2026-10-04/06b-chart-toggles-768, before / after; UX-DR15):
  # As the operator reading a security's chart with the detail pane open, in
  # German, at 768, 1024 or 1200 px,
  # I want the page to stay as wide as the window,
  # so that the chart's ten toggles do not push the page 239 px sideways.
  #
  # Acceptance criteria:
  # - The toggle row wraps at every width, not only inside the 720 px phone
  #   block: it is a flex item of the wrapping toolbar, so it takes a line
  #   of its own and its toggles break onto as many lines as they need.
  test "the chart tab's toggle row wraps at every width" do
    assert block(".chart-toggles") =~ ~r/flex-wrap:\s*wrap;/
  end

  # User story (issue 1063 in the detail head; the closing act's edge-case
  # finding 6; UX-DR15):
  # As the operator reading a security whose stored name has no break
  # opportunity (a 74-character run of letters), at 390, 768 or 1024 px,
  # I want the page to stay as wide as the window and the name to wrap,
  # so that the pane's Edit, Split, fullscreen and close buttons stay on the
  # screen instead of the page scrolling sideways.
  #
  # Acceptance criteria:
  # - The name breaks anywhere when nothing else fits (`overflow-wrap:
  #   anywhere`), which also lowers its min-content, the floor the title
  #   block took as a flex item; `break-word` would not lower it.
  # - The title block keeps its min-content floor (no `min-width: 0`): the
  #   ISIN line under the name still holds its column's width, and does not
  #   run past it toward the buttons.
  test "the detail head's name wraps instead of widening the page" do
    assert block(".detail-pane-head h2") =~ ~r/overflow-wrap:\s*anywhere;/
    refute block(".detail-pane-head__title") =~ ~r/min-width:\s*0;/
  end

  # User story (#1050; board ux-design-2026-10-02/03-bond-master-data, rule
  # ④, a conformance repair; DESIGN.md gives the grid "two per row under
  # 720px"):
  # As the operator reading a security's Overview on a 390 px phone,
  # I want its six figures in two columns,
  # so that "TAGESÄNDERUNG" does not run into "1Y" and "Durchschnittseinstand"
  # stays inside its cell.
  #
  # Acceptance criteria:
  # - Under 720 px `.overview-reading .overview-metrics` goes to two
  #   columns: the reading surface's three-column rule (issue 804) outranked
  #   the spec'd two-column rule by specificity, so the repair restates it
  #   at the same specificity inside the breakpoint.
  test "under 720 px the Overview's figures stand in two columns" do
    phone =
      case Regex.run(
             ~r/@media \(max-width: 720px\) \{\n  \/\* overview reading on a phone[^\n]*\n(.*?)\n\}\n/s,
             @css
           ) do
        [_, body] -> body
        nil -> flunk("no 720 px block for the overview reading's figures")
      end

    assert phone =~
             ~r/\.overview-reading \.overview-metrics \{\s*grid-template-columns: repeat\(2, minmax\(0, 1fr\)\);/
  end

  # User story (board ux-design-2026-10-02/07-phone-390, H7.6, rule ④;
  # UX-DR27 places the kebab at the row's end):
  # As the operator reading the transaction history on a 390 px phone,
  # I want each booking's kebab at the end of its row,
  # so that it does not drop under the date onto a line of its own, where
  # every booking grows by its height and the kebab reads as the next row's.
  #
  # Acceptance criteria:
  # - The history's phone row declares three tracks for its three children
  #   — the body, the figures, the kebab: `minmax(0, 1fr) auto auto`.
  test "the history's phone row has a track for its kebab" do
    assert block("#transaction-phone-rows .phone-row") =~
             ~r/grid-template-columns:\s*minmax\(0, 1fr\) auto auto;/
  end

  # User story (#1012; board ux-design-2026-10-02/07-phone-390, H7.1 pick A,
  # rule ①): a quote's phone row is the trades row's shape — two children,
  # the date over its source and the close on the right, no logo and no
  # kebab — so it needs its own two tracks, or the body would land in the
  # logo's `auto` column.
  test "the quote phone row has two tracks" do
    assert block("#quote-phone-rows .phone-row") =~
             ~r/grid-template-columns:\s*minmax\(0, 1fr\) auto;/
  end

  # The closing act's H7 finding (board
  # ux-review-2026-10-03/03-gamma-surface-repairs, G6) swapped the Quotes
  # tab's basis sentence per layout. Since I1 (Sprint 23, board
  # ux-design-2026-11-03-sprint23-i1 ①) the line says the price basis once
  # and both sentences — the table's Stored column, the rows' line under the
  # close — sit in its ⓘ, so no swap is left to pin
  # (securities_quote_phone_rows_test.exs).
  test "the quotes' basis line no longer swaps per layout" do
    refute @css =~ ".quotes-basis__"
  end

  test "under 560 px the chip row yields to the Filter control" do
    assert phone_block() =~ ~r/#securities-filter-chips,/
    assert phone_block() =~ ~r/\.filter-sheet-toggle \{\s*display: inline-flex;/
  end

  # #816: the same rule on the second list surface that has a chip row.
  test "under 560 px the history's chips and demoted conditions yield too" do
    assert phone_block() =~
             ~r/#securities-filter-chips,\s*#transaction-chips,\s*#transaction-more-filters \{\s*display: none;/
  end

  test "the phone rows and the Filter control stay out of the desktop layout" do
    assert block(".phone-rows") =~ ~r/display:\s*none/
    assert block(".filter-sheet-toggle") =~ ~r/display:\s*none/
  end

  # The one 560 px block that carries the phone list rules, found by its
  # marker comment.
  defp phone_block do
    case Regex.run(
           ~r/@media \(max-width: 560px\) \{\n  \/\* phone lists[^\n]*\n(.*?)\n\}\n/s,
           @css
         ) do
      [_, body] -> body
      nil -> flunk("no 560 px phone-lists block")
    end
  end

  # User story (#803 C6-C; DESIGN.md → Components → Booking drawer):
  # As a local portfolio maintainer recording a booking,
  # I want the drawer to sit beside the history on the desktop and to be a
  # bottom sheet on the phone,
  # so that the two placements are rules of the stylesheet, not accidents of
  # the dialog's user-agent styles.
  test "the booking drawer is a sticky side panel on the desktop and a sheet under 720 px" do
    assert block("dialog.booking-drawer") =~ ~r/position:\s*sticky/
    assert drawer_block() =~ ~r/dialog\.booking-drawer \{\s*position: fixed;/

    assert drawer_block() =~
             ~r/\.transactions-columns--drawer \{\s*grid-template-columns: minmax\(0, 1fr\);/
  end

  # User story (#1052, #1206, Sprint 21 α6; board 03, pick N12 A, and its
  # found while drawing 4):
  # As the operator booking a cash kind or correcting one on a phone,
  # I want the sheet's Save and Cancel to stay at the sheet's bottom edge
  # while the form scrolls above them, and a lone amount on its own row,
  # so that the primary action is never below the fold of a form taller
  # than the sheet (the edit state needs 934 px in a 743 px sheet).
  #
  # Acceptance criteria:
  # - Under 720 px the drawer's foot is sticky at the bottom of the sheet,
  #   on the sheet's own background.
  # - It sticks at the sheet's edge, not 16 px above it: its `bottom` takes
  #   back the sheet's bottom padding (16 px and the safe area), which the
  #   scroller's sticky edge otherwise keeps (the α closing act's design
  #   critic, 390 px), so nothing scrolls visibly under the buttons.
  # - A kind without taxes leaves the amount as the grid's fifth and last
  #   label; it takes the full row (the board's one proposal rule).
  test "the booking sheet keeps its foot at its edge and a lone amount takes the row" do
    assert drawer_block() =~
             ~r/\.booking-drawer__foot \{\s*position: sticky;\s*bottom: [^;]+;[^}]*background: var\(--color-bg-elevated\)/

    assert drawer_block() =~
             ~r/dialog\.booking-drawer \{[^}]*padding: 12px 16px calc\(16px \+ env\(safe-area-inset-bottom, 0px\)\);/

    assert drawer_block() =~
             ~r/\.booking-drawer__foot \{\s*position: sticky;\s*bottom: calc\(-16px - env\(safe-area-inset-bottom, 0px\)\);/

    assert block(".booking-drawer .form-grid > label:nth-child(5):last-child") =~
             ~r/grid-column:\s*1 \/ -1/
  end

  defp drawer_block do
    case Regex.run(
           ~r/@media \(max-width: 720px\) \{\n  \/\* booking drawer[^\n]*\n(.*?)\n\}\n/s,
           @css
         ) do
      [_, body] -> body
      nil -> flunk("no 720 px booking-drawer block")
    end
  end

  # User story (#801 C5-A; DESIGN.md → Components → Custom range popover):
  # As a local portfolio maintainer opening the custom range,
  # I want the from/to popover positioned on its trigger,
  # so that the section heading and the chart never move when it opens.
  test "the custom range popover is positioned on its trigger" do
    assert block(".period-disclosure") =~ ~r/position:\s*relative/
    assert block(".period-popover") =~ ~r/position:\s*absolute/
  end

  # Issue 796 (found at 390 px): an absolutely positioned descendant of a
  # scrolling table wrapper — the visually hidden "Actions" header label —
  # takes the page as its containing block unless the wrapper is positioned,
  # and then sits beyond the viewport and widens the document. The wrapper is
  # the containing block.
  test "the table scroller is the containing block of its hidden labels" do
    css = File.read!("priv/static/app.css")
    [rule] = Regex.run(~r/\n\.data-table-wrapper \{[^}]*\}/, css)
    assert rule =~ ~r/position:\s*relative/
    assert rule =~ ~r/overflow-x:\s*auto/
  end
end
