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

  test "a labelled tooltip summary grows with its label" do
    assert block(".metric-tooltip--labelled summary") =~ ~r/width:\s*auto/
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

    assert phone_block() =~
             ~r/#securities-table,\s*#transaction-table-wrapper \{\s*display: none;/
  end

  test "under 560 px the chip row yields to the Filter control" do
    assert phone_block() =~ ~r/#securities-filter-chips \{\s*display: none;/
    assert phone_block() =~ ~r/\.filter-sheet-toggle \{\s*display: inline-flex;/
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
