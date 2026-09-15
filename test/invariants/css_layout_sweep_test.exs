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

  test "a labelled tooltip summary grows with its label" do
    assert block(".metric-tooltip--labelled summary") =~ ~r/width:\s*auto/
  end

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{selector}")
    end
  end

  # User story (#799 UX-DR27; DESIGN.md → Amendment 2026-09-12 →
  # Two-line phone rows and Components → Phone lists):
  # As a local portfolio maintainer on a 390 px phone,
  # I want the entity tables to give way to two-line rows under 560 px, and
  # the rows to stay out of the desktop layout above it,
  # so that the phone composition is a rule of the stylesheet, not a
  # coincidence of the viewport.
  test "under 560 px the entity tables give way to the two-line rows" do
    assert phone_block() =~ ~r/\.phone-rows \{\s*display: block;/

    assert phone_block() =~
             ~r/#securities-table,\s*#transaction-table-wrapper \{\s*display: none;/
  end

  test "the phone rows stay out of the desktop layout" do
    assert block(".phone-rows") =~ ~r/display:\s*none/
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
