defmodule Portfolixir.Invariants.CssFloorSecondPassTest do
  use ExUnit.Case, async: true

  # Sprint 19 PR γ U5, board ux-design-2026-10-04/07-floor (Part 7 of the
  # design pass, picks J7 = A and J7.2 = A): the touch, focus and colour
  # floor, second pass. The rules are CSS, so the stylesheet is what these
  # tests read; the built screen was measured under a real coarse pointer
  # (touch emulation), which the board could only simulate.

  @css File.read!("priv/static/app.css")

  # User story (#1062; board 07, rules ① and ②):
  # As the operator on a tablet,
  # I want a row-menu item and a chart range button to be 44 px targets,
  # so that I hit "Löschen" and not the item beside it, and "1J" and not
  # "3J".
  #
  # Acceptance criteria:
  # - Under a coarse pointer a row-menu item takes a 44 px min-height — a
  #   real size, not H6's padding plus negative margin: the items stack,
  #   and boxes grown into their neighbours would overlap.
  # - Under a coarse pointer a range button is 44 × 44, again a real size:
  #   `.range-buttons` clips with `overflow: hidden`.
  # - The chart toggles beside them (found while drawing) take the same
  #   44 px floor.
  test "row-menu items, range buttons and chart toggles are 44 px targets on touch" do
    assert coarse(".row-context-menu__item") =~ ~r/min-height:\s*44px;/

    range = coarse(".range-button")
    assert range =~ ~r/min-height:\s*44px;/
    assert range =~ ~r/min-width:\s*44px;/

    assert coarse(".chart-toggle") =~ ~r/min-height:\s*44px;/

    refute coarse(".row-context-menu__item") =~ ~r/margin/
    refute range =~ ~r/margin/
  end

  # User story (#1062; the review of U5):
  # As the operator on a short, wide touch screen (a phone in landscape),
  # I want the row menu's last items within reach, and the menu never over
  # the kebab that opened it,
  # so that the taller touch items do not push "Löschen" off the screen.
  #
  # Acceptance criteria:
  # - The menu is at most the viewport less 16 px tall and scrolls inside,
  #   keeping its 4 px padding for the items' focus ring; its items do not
  #   shrink, so they stay 44 px and the menu scrolls.
  # - The positioning hook opens the menu below its kebab when it fits,
  #   above when it fits there, and otherwise on the roomier side with its
  #   height capped to that room: it no longer clamps to the viewport's top
  #   edge over its own kebab.
  test "the row menu scrolls within the viewport and never covers its kebab" do
    menu = block(".row-context-menu")
    assert menu =~ ~r/max-height:\s*calc\(100vh - 16px\);/
    assert menu =~ ~r/max-height:\s*calc\(100dvh - 16px\);/
    assert menu =~ ~r/overflow-y:\s*auto;/
    assert menu =~ ~r/padding:\s*var\(--space-1\);/
    # The menu is a flex column: capped, its items would shrink below 44 px
    # instead of scrolling.
    assert block(".row-context-menu__item") =~ ~r/flex-shrink:\s*0;/

    hook =
      "lib/portfolixir_web/layout_view.ex"
      |> File.read!()
      |> String.split("Hooks.PositionedMenu")
      |> Enum.at(1)
      |> String.split("Hooks.ChartCrosshair")
      |> hd()

    assert hook =~ "var below = window.innerHeight - rect.bottom - gap - pad;"
    assert hook =~ "var above = rect.top - gap - pad;"
    assert hook =~ ~s(this.el.style.maxHeight = "";)
    assert hook =~ ~s{this.el.style.maxHeight = room + "px";}
    refute hook =~ "if (top < pad) top = pad;"
  end

  # User story (the review of U5, items 3 and 4):
  # As the operator on a phone,
  # I want the chart toggles' words centred in their 44 px boxes, and the
  # range buttons in one row wherever eight 44 px buttons fit,
  # so that the toolbar reads as built, not as a stretched box with "Max"
  # alone on a second line.
  #
  # Acceptance criteria:
  # - `.chart-toggle` centres its content vertically.
  # - Under a coarse pointer a range button gives up its inline padding: the
  #   44 px minimum is its width, so "YTD" and "Max" are 44 px too and the
  #   group is 8 × 44 + 2 = 354 px — one row from a 376 px viewport up
  #   (the toolbar is the viewport less 22 px). Below that it wraps; the
  #   44 × 44 floor stays.
  test "the chart toggles centre their words and the range buttons are 44 px each" do
    assert block(".chart-toggle") =~ ~r/align-items:\s*center;/
    assert coarse(".range-button") =~ ~r/padding-inline:\s*0;/
  end

  # User story (#1085, J7.2 = A; the review of U5):
  # As the operator reading Accounts & depots on a desktop,
  # I want "letzte Buchung 22.09.2026" on one line, as the board draws it,
  # so that the longer words do not make every cash row 15 px taller.
  #
  # Acceptance criteria:
  # - From 1200 px the balance's date line does not wrap (German on the
  #   demo seed needs 1140 px; 1200 leaves room for longer names); below, the
  #   accounts table's own width (issue 1145) decides, and it wraps.
  test "the balance's date is one line on a wide screen" do
    [_, body] =
      Regex.run(
        ~r/@media \(min-width: 1200px\) \{\s*\.cash-balance__asof \{([^}]*)\}\s*\}/,
        @css
      ) || flunk("no wide-screen rule for the balance's date")

    assert body =~ ~r/white-space:\s*nowrap;/
    refute block(".cash-balance__asof") =~ ~r/white-space/
  end

  # User story (#1085, rules ⑦ and ⑧; the review of U5):
  # As the operator on a phone,
  # I want a tap on the role select to open the select, and the chip's ×
  # to fill the pill's end without a box of its own,
  # so that the ⓘ's touch ring does not steal the select's edge, and the
  # chip reads as one shape in the dark theme too.
  #
  # Acceptance criteria:
  # - Under a coarse pointer the role field keeps 12 px between its label,
  #   the ⓘ and the select: the ⓘ's ring reaches 8 px past its circle.
  # - The ×'s base button shadow is gone at every width, and under a coarse
  #   pointer its corners are the pill's end (0 on the left, full on the
  #   right).
  test "the role field keeps its ⓘ's ring off the select, and the × fills the pill's end" do
    assert coarse(".liquidity-role-field") =~ ~r/gap:\s*var\(--space-3\);/

    assert block(".bucket-chip__remove") =~ ~r/box-shadow:\s*none;/
    assert coarse(".bucket-chip__remove") =~ ~r/border-radius:\s*0 999px 999px 0;/
  end

  # User story (#1085, rule ⑦; the review of U5):
  # As the operator on a phone,
  # I want the role label visible at 640 px and below, and hidden only where
  # the column head states it,
  # so that no width shows the label twice or not at all.
  #
  # Acceptance criteria:
  # - The label is hidden only inside `@media (width > 640px)`, the exact
  #   complement of the card layout's `(max-width: 640px)`; at fractional
  #   widths between 640 and 641 px `min-width: 641px` left both off.
  # - Its own rule hides nothing, and no other rule names it.
  test "the role label is hidden only above 640 px, and visible at 640 and below" do
    base = block(".liquidity-role-field__label")
    assert base =~ ~r/display:\s*inline;/
    refute base =~ ~r/(position|clip|overflow|width|height):/

    named = Regex.scan(~r/[^{}]*\.liquidity-role-field__label[^{}]*\{/, @css)
    assert length(named) == 2, "the label's own rule and the one that hides it above 640 px"

    refute @css =~ "@media (min-width: 641px)"
  end

  # User story (the review of U5):
  # As the maintainer moving a rule in app.css,
  # I want a coarse override that only wins by coming later to fail its test
  # when it no longer does,
  # so that a floor is not lost to a reordering.
  #
  # Acceptance criteria:
  # - For `.range-button`, `.chart-toggle`, `.bucket-chip-add` and
  #   `.liquidity-role-field select`, the coarse rule's byte offset is
  #   greater than the base rule's, as U2's pill test pins its rule.
  test "each coarse override comes after the base rule it overrides" do
    for selector <- [".range-button", ".chart-toggle", ".bucket-chip-add"] do
      assert coarse_offset(selector) > base_offset(selector),
             "#{selector}: the coarse rule precedes its base rule"
    end

    assert coarse_offset(".liquidity-role-field select,") >
             base_offset(".liquidity-role-field select")
  end

  # User story (#1062; board 07, rule ③, and found while drawing):
  # As the operator moving through a dialog by keyboard,
  # I want "Abbrechen", "Transaktion löschen", "Plan speichern" and every
  # other button to show the house focus ring,
  # so that one dialog speaks one focus language, visible in the dark theme.
  #
  # Acceptance criteria:
  # - `.button`, `.button-primary`, `.button-ghost`, `.button-danger` and
  #   `.button-secondary` draw `outline: 2px solid` in the accent at a 2 px
  #   offset under `:focus-visible`, in one rule.
  # - The icon button draws the same ring (its focus rule changed colours
  #   only, so the browser's ring still drew).
  # - A range button draws it inset, because its group clips; a chart toggle
  #   draws it outside.
  test "the button family, the icon button and the chart toolbar draw the accent ring" do
    family =
      block(
        ":is(.button, .button-primary, .button-ghost, .button-danger, .button-secondary):focus-visible"
      )

    assert_ring(family, "2px")
    # The hover rule names the selector too (its colour change); the ring is
    # a rule of its own.
    assert_ring(blocks(".icon-button:focus-visible"), "2px")
    assert_ring(block(".range-button:focus-visible"), "-2px")
    assert_ring(block(".chart-toggle:focus-visible"), "2px")
  end

  # User story (#1085, rule ⑧; the PR γ closing act, design critic #6):
  # As the operator tabbing through a bucket cell,
  # I want the chip's × and + to show the house focus ring,
  # so that the two controls U5 raised to 44 px do not draw the browser's
  # thin black ring beside the accent ring of the "+N" chip next to them.
  #
  # Acceptance criteria:
  # - `.bucket-chip-add` draws the 2 px accent outline at a 2 px offset
  #   under `:focus-visible`, as the overflow chip does.
  # - `.bucket-chip__remove` draws it inset, at -2 px: the × fills the
  #   pill's end, so an outset ring would run over the pill's edge.
  test "the bucket chip's × and + draw the accent ring" do
    assert_ring(block(".bucket-chip-add:focus-visible"), "2px")
    assert_ring(block(".bucket-chip__remove:focus-visible"), "-2px")
  end

  # User story (#912's focus return; the PR γ closing act, design critic #7):
  # As the keyboard operator who just deleted a booking whose row is gone,
  # I want the history's heading, where the focus lands, to show the house
  # focus ring,
  # so that the page's one programmatic focus target does not draw the
  # browser's thin black ring where every control draws the accent.
  #
  # Acceptance criteria:
  # - `#transaction-history-heading` draws the 2 px accent outline at a 2 px
  #   offset under `:focus-visible`, the ring the securities page's result
  #   slot draws when it takes the focus the same way.
  test "the history heading draws the accent ring when it takes the focus" do
    assert_ring(block("#transaction-history-heading:focus-visible"), "2px")
    assert_ring(block("#securities-action-result:focus-visible"), "2px")
  end

  # User story (Part 4, "found while drawing" 3, handed to U5):
  # As the operator on a phone,
  # I want every ⓘ to be a 44 px target,
  # so that a thumb opens the definition without hunting for a 28 px dot.
  #
  # Acceptance criteria:
  # - Under a coarse pointer the ⓘ keeps its 28 px picture (1.75rem), and a
  #   transparent ring around it (`::before`, `inset: -9px`, placed from the
  #   26 px padding box inside the 1 px border) makes its target 44 px: no
  #   rendered difference, and the floor is an effective target (UX-DR6).
  #   Measured under touch emulation: 44 × 44 (42.5 with `-8px`).
  # - The ring is drawn in no colour.
  test "the coarse ⓘ is a 44 px target with its 28 px picture" do
    assert coarse(".metric-tooltip summary") =~ ~r/width:\s*1\.75rem;/
    assert coarse(".metric-tooltip summary") =~ ~r/position:\s*relative;/

    ring = coarse(".metric-tooltip summary::before")
    assert ring =~ ~r/content:\s*"";/
    assert ring =~ ~r/position:\s*absolute;/
    assert ring =~ ~r/inset:\s*-9px;/
    refute ring =~ ~r/(background|border|color)/

    # A table clips its cells, so a head cell holding an ⓘ keeps the ring
    # inside it.
    assert coarse(".drift-table th:has(.metric-tooltip)") =~ ~r/padding-block:\s*9px;/
  end

  # User story (issue 1164; the closing act of PR γ, the design critic's #3):
  # As the operator on a phone or a tablet,
  # I want the view switcher's quiet controls — "Ansichten", the active
  # view's ⓘ and Wealth's "Als Standard festlegen" — to be 44 px targets
  # that draw the house focus ring,
  # so that the switcher U7 put on the classification screen meets the floor
  # its chips already meet, and the keyboard sees one ring in it.
  #
  # Acceptance criteria:
  # - Under a coarse pointer "Ansichten" is a 44 px tall box (it was
  #   85 × 19) and the default button takes 44 px (it was the base
  #   button's 34): real sizes, in a row the chips already make 44 px tall.
  # - The ⓘ keeps its glyph in the 26 px box the coarse ⓘ ring is placed
  #   from (it was 14 × 20) and is named in the ring's rule, so its target
  #   is 44 × 44; 12 px between the switcher's items keep the ring off the
  #   link (8 px would let it reach 1 px into it).
  # - Each coarse override comes after the base rule it overrides.
  # - All three draw the 2 px accent ring at a 2 px offset, in the button
  #   family's rule, instead of the browser's `auto 1px` ring.
  # - The component's markup is unchanged: this is CSS.
  test "the view switcher's quiet controls take the floor and the accent ring" do
    assert coarse(".view-switcher__manage") =~ ~r/min-height:\s*44px;/
    assert coarse(".view-switcher__manage") =~ ~r/display:\s*inline-flex;/
    assert coarse(".view-switcher .button-mini") =~ ~r/min-height:\s*44px;/

    summary = coarse(".view-switcher__help summary")
    assert summary =~ ~r/position:\s*relative;/
    assert summary =~ ~r/min-width:\s*26px;/
    assert summary =~ ~r/min-height:\s*26px;/

    # The ⓘ ring's rule names the switcher's summary as well.
    [_, ring_selectors] =
      Regex.run(~r/\n  ((?:[^{}\n]+,\n  )*\.metric-tooltip summary::before) \{/, @css) ||
        flunk("no coarse ⓘ ring rule")

    assert ring_selectors =~ ".view-switcher__help summary::before,"
    assert coarse(".metric-tooltip summary::before") =~ ~r/inset:\s*-9px;/

    assert coarse(".view-switcher") =~ ~r/column-gap:\s*var\(--space-3\);/

    for selector <- [".view-switcher", ".view-switcher__manage", ".view-switcher__help summary"] do
      assert coarse_offset(selector) > base_offset(selector),
             "#{selector}: the coarse rule precedes its base rule"
    end

    [_, ring_list] =
      Regex.run(
        ~r/\n((?:[^{}\n]+,\n)*):is\(\.button, \.button-primary, \.button-ghost, \.button-danger, \.button-secondary\):focus-visible \{/,
        @css
      ) || flunk("no button-family ring rule")

    for selector <- [
          ".view-switcher__manage:focus-visible",
          ".view-switcher__help summary:focus-visible",
          ".view-switcher .button-mini:focus-visible"
        ] do
      assert ring_list =~ selector <> ",", "#{selector} draws no accent ring"
    end

    switcher = File.read!("lib/portfolixir_web/components/view_switcher.ex")
    assert switcher =~ ~s(class="view-switcher__manage")
    assert switcher =~ ~s|<summary aria-label={gettext("About views")}>ⓘ</summary>|
  end

  # User story (#1069 and #1071; board 07.3, rules ⑤ and ⑥):
  # As the operator reading the allocation tree,
  # I want its head row on the wrapper's top border and the Drift ⓘ's
  # sentence set as a sentence,
  # so that the table looks like every other table, and the explanation
  # reads from its left edge.
  #
  # Acceptance criteria:
  # - `.drift-table, .cash-table` carry no top margin: every call site sits
  #   in a bordered wrapper, so the margin was a 17 px band inside it.
  # - `.metric-tooltip p` sets `text-align: start` on the class, so a
  #   tooltip in a `th.num` no longer inherits the right alignment.
  test "the drift and cash tables are flush, and a tooltip reads from its start" do
    tables = block(".drift-table,\n.cash-table")
    refute tables =~ ~r/margin/

    assert block(".metric-tooltip p") =~ ~r/text-align:\s*start;/
  end

  # User story (#1085; board 07.4, rules ⑦, ⑧ and ⑨, and found while
  # drawing):
  # As the operator on a phone reading a cash account's card,
  # I want its role select to carry its label, every control of the card to
  # be a 44 px target, and the merge arrow to be readable,
  # so that "Verfügbares Cash" is not a value without a name, and the chips
  # are not 24 px dots.
  #
  # Acceptance criteria:
  # - The role label is visually hidden only above 640 px, where the column
  #   head states it.
  # - Under a coarse pointer the chip's + and × are 44 × 44 — the two
  #   sub-floor values UX-DR6's amendment 2 rejects are gone — and a chip
  #   holding a × gives up its block and right padding, so the × fills its
  #   end.
  # - On the desktop the + is the 22 × 22 it declares: the base button's
  #   34 px floor no longer wins its height (the H6.2 class).
  # - Under a coarse pointer the role select and "Saldo setzen" take 44 px.
  # - The merge record's arrow takes text-muted: it carries the direction,
  #   and text-subtle is barred from content.
  test "the accounts card: the label, the 44 px controls and the arrow" do
    [_, hidden] =
      Regex.run(
        ~r/@media \(width > 640px\) \{\s*\.accounts-table \.liquidity-role-field__label \{([^}]*)\}\s*\}/,
        @css
      ) || flunk("the role label is not hidden above 640 px")

    assert hidden =~ ~r/position:\s*absolute;/
    assert hidden =~ ~r/clip:\s*rect\(0 0 0 0\);/

    add = coarse(".bucket-chip-add")
    assert add =~ ~r/width:\s*44px;/
    assert add =~ ~r/\n\s*height:\s*44px;/

    remove = coarse(".bucket-chip__remove")
    assert remove =~ ~r/min-width:\s*44px;/
    assert remove =~ ~r/min-height:\s*44px;/

    chip = coarse(".bucket-chip:has(> .bucket-chip__remove)")
    assert chip =~ ~r/padding-block:\s*0;/
    assert chip =~ ~r/padding-right:\s*0;/

    refute @css =~ ~r/min-width:\s*24px;\s*min-height:\s*24px;/,
           "the 24 px × is gone"

    refute @css =~ ~r/\.bucket-chip-add \{\s*width:\s*32px;\s*height:\s*32px;/,
           "the 32 px + is gone"

    assert block(".bucket-chip-add") =~ ~r/min-height:\s*0;/

    controls = coarse(".liquidity-role-field select,\n  .cash-balance__action")
    assert controls =~ ~r/min-height:\s*44px;/

    assert block(".merge-record__arrow") =~ ~r/color:\s*var\(--color-text-muted\);/
  end

  # User story (#1064, J7 = A; board 07, J7):
  # As the operator whose page answers an action at its top,
  # I want the answer to keep the gutter the old alert had,
  # so that the note does not touch the screen's edge.
  #
  # Acceptance criteria:
  # - A page's result slot (`.inline-result--page`) that is a direct child of
  #   a workspace page takes the band's own side gutter, the one
  #   `.workspace-page > .alert-*` took, and 12 px above a result.
  # - At rest it takes no room: its regions keep no margin until they hold a
  #   result (`:has(> *)`; they always hold whitespace, so `:empty` never
  #   matched), and in a section's grid the empty slot leaves the flow, so
  #   the grid adds no gap for it.
  # - The history's result is a scroll target below the sticky top bar, as
  #   its alert was: the note that a closing dialog brings into view.
  test "a page's result slot keeps the alert's footprint and scroll margin" do
    assert block(".workspace-page > .inline-result--page") =~
             ~r/margin-inline:\s*clamp\(16px, 2\.4vw, 28px\);/

    assert block(".inline-result.inline-result--page > .inline-result__region") =~
             ~r/margin:\s*0;/

    assert block(".inline-result.inline-result--page > .inline-result__region:has(> *)") =~
             ~r/margin:\s*12px 0 0;/

    assert block(
             ".workspace-section > .inline-result--page:not(:has(.inline-result__region > *))"
           ) =~ ~r/position:\s*absolute;/

    assert @css =~
             ~r/#transactions-result \.data-note,\s*#transaction-history-heading,\s*#transaction-list \.row-actions__kebab,\s*#transaction-phone-rows \.row-actions__kebab \{\s*scroll-margin-top: calc\(var\(--topbar-height\) \+ var\(--space-3\)\);/
  end

  defp assert_ring(body, offset) do
    assert body =~ ~r/outline:\s*2px solid var\(--color-accent\);/
    assert body =~ ~r/outline-offset:\s*#{Regex.escape(offset)};/
  end

  # The body of a rule written inside a `@media (pointer: coarse)` block,
  # wherever in the stylesheet the block stands.
  defp coarse(selector) do
    blocks =
      Regex.scan(~r/@media \(pointer: coarse\) \{(.*?)\n\}/s, @css, capture: :all_but_first)

    found =
      Enum.find_value(blocks, fn [inner] ->
        case Regex.run(~r/(?:^|\n|,)\s*#{Regex.escape(selector)} \{([^}]*)\}/, inner) do
          [_, body] -> body
          nil -> nil
        end
      end)

    found || flunk("no coarse rule for #{inspect(selector)}")
  end

  # The byte offset of the first top-level rule for `selector`.
  defp base_offset(selector) do
    case :binary.match(@css, "\n#{selector} {") do
      {offset, _length} -> offset
      :nomatch -> flunk("no top-level rule for #{inspect(selector)}")
    end
  end

  # The byte offset of `selector` (a rule's selector, or the first line of a
  # selector list) inside a `@media (pointer: coarse)` block.
  defp coarse_offset(selector) do
    selector = if String.ends_with?(selector, ","), do: selector, else: selector <> " {"

    ~r/@media \(pointer: coarse\) \{(.*?)\n\}/s
    |> Regex.scan(@css, return: :index, capture: :all_but_first)
    |> Enum.find_value(fn [{start, length}] ->
      inner = binary_part(@css, start, length)

      case :binary.match(inner, "\n  #{selector}") do
        {offset, _length} -> start + offset
        :nomatch -> nil
      end
    end) || flunk("no coarse rule for #{inspect(selector)}")
  end

  # Every top-level rule whose selector list ends with `selector`, joined.
  defp blocks(selector) do
    case Regex.scan(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css, capture: :all_but_first) do
      [] -> flunk("no top-level rule for #{inspect(selector)}")
      bodies -> bodies |> List.flatten() |> Enum.join("\n")
    end
  end

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{inspect(selector)}")
    end
  end
end
