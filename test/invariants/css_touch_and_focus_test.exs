defmodule Portfolixir.Invariants.CssTouchAndFocusTest do
  use ExUnit.Case, async: true

  # Sprint 18 plan U4, pick H6 (board
  # ux-design-2026-10-02/06-touch-focus): the touch targets UX-DR6 asks for
  # under a coarse pointer, and the 2 px accent focus ring DESIGN.md → Colors
  # gives every control. The rules are CSS only, so the stylesheet is what
  # these tests read.

  @css File.read!("priv/static/app.css")

  # User story (#1033; board 06, H6.2 and H6.2b, rule ②):
  # As the operator on a phone or a tablet,
  # I want every icon button — each dialog's close button and each toolbar
  # icon — to be a 44 px target, and on the desktop the 30 px square it is
  # drawn as,
  # so that I can hit "close" with a thumb, and a close button beside a long
  # title does not shrink to a sliver.
  #
  # Acceptance criteria:
  # - `.icon-button` is the 30 × 30 it declares: `min-height: 0` beats the
  #   base `button { min-height: 34px }`, which made every <button> of the
  #   class 30 × 34 while an <a> of the class stayed 30 × 30.
  # - It never shrinks beside a title that wraps (`flex: none`).
  # - Under a coarse pointer the class takes a 44 px minimum width and
  #   height — on the class, not per dialog: UX-DR6's call-site table lists
  #   the class itself as uncovered.
  # - The dialog heads keep a gap between the title and the close button.
  # - The release dialog's three rules, which the class rule subsumes, are
  #   gone, and so is the detail head's ID rule for its two icon buttons.
  test "an icon button is 30 × 30 on the desktop and a 44 px target on touch" do
    icon = block(".icon-button")

    assert icon =~ ~r/width:\s*30px;/
    assert icon =~ ~r/\n\s*height:\s*30px;/
    assert icon =~ ~r/min-height:\s*0;/
    assert icon =~ ~r/flex:\s*none;/

    assert @css =~
             ~r/@media \(pointer: coarse\) \{\s*\.icon-button \{\s*min-width: 44px;\s*min-height: 44px;\s*\}\s*\}/

    assert block(".modal-head") =~ ~r/gap:\s*var\(--space-2\);/
    assert block(".filter-sheet__head") =~ ~r/gap:\s*var\(--space-2\);/

    refute @css =~ ".quote-release-dialog .modal-head",
           "the release dialog's head rules are subsumed by the class rule"

    refute @css =~ "#detail-pane-fullscreen-toggle",
           "the detail head's two icon buttons take the floor from the class"
  end

  # User story (#1013; board 06, H6.1, pick A, rule ①):
  # As the operator on a phone reading a data note,
  # I want its remedy ("Freigeben…", "Neue Abrechnung erfassen", "Kurse
  # aktualisieren") to be a 44 px target where it stands in the sentence,
  # so that I can tap it with a thumb, and the note does not reflow to make
  # room for it.
  #
  # Acceptance criteria:
  # - Under a coarse pointer a `.link-button` inside a note's body gains
  #   13 px of block padding — (44 − 18) / 2, the note's 12 px × 1.5 line —
  #   and gives the same 13 px back as a negative block margin, so its line
  #   stays 18 px and no note changes height (the `.positions-toggle`
  #   technique).
  # - The box grows only in the block direction, so beside the inline
  #   result's dismiss (H6.4), the other 44 px target in the release result,
  #   the two never overlap.
  # - On the desktop nothing changes: `.link-button` keeps no padding and no
  #   floor (F26).
  test "a remedy inside a data note is a 44 px target on touch, and its line stays" do
    {_selectors, rule} = remedy_rule()

    assert rule =~ ~r/padding-block:\s*13px;/
    assert rule =~ ~r/margin-block:\s*-13px;/
    refute rule =~ ~r/(padding|margin)(-inline|-left|-right)?:/
    refute rule =~ ~r/min-height/

    link = block(".link-button")
    assert link =~ ~r/padding:\s*0;/
    assert link =~ ~r/min-height:\s*0;/
  end

  # User story (#330, closing act on U7, finding 5; board
  # ux-review-2026-10-03/04-bond-repairs, B4):
  # As the operator on a phone reading a bond whose master data is not
  # entered,
  # I want its remedy "Anleihedaten erfassen…" to be a 44 px target where it
  # stands in the sentence,
  # so that I can open the dialog with a thumb, and the sentence does not
  # reflow to make room for it.
  #
  # Acceptance criteria:
  # - The bond block's empty-state remedy is one more selector of the H6.1
  #   rule, scoped to that remedy: its sentence (`.detail-tab-empty`, 13 px
  #   on the 1.4 line) is 18 px high, as a note's line is, so the rule's
  #   13 px fit it unchanged.
  # - No other `.link-button` outside a note is reached: the rule names the
  #   note's remedy and the bond block's, nothing broader.
  test "the bond block's empty-state remedy is a 44 px target on touch" do
    {selectors, rule} = remedy_rule()

    assert selectors == [
             ".data-note__body .link-button",
             ".bond-strip .detail-tab-empty .link-button"
           ]

    assert rule =~ ~r/padding-block:\s*13px;/
    assert rule =~ ~r/margin-block:\s*-13px;/
  end

  # User story (#1033; board 06, H6.3, rule ③):
  # As the operator moving through the Overview by keyboard,
  # I want a row of "Abgeschlossene Trades", "Ziel-Abweichungen" or "Fällig"
  # to show the same 2 px accent ring as the KPI strip above it,
  # so that one page speaks one focus language, and the ring stays visible
  # in the dark theme.
  #
  # Acceptance criteria:
  # - `.attention-item:focus-visible` draws `outline: 2px solid` in the
  #   accent with a 2 px offset and the small radius — the form
  #   `.stat--link`, `.filter-chip` and `.row-actions__kebab` carry.
  # - One rule for all three cards: they share the class.
  test "an attention row draws the 2 px accent focus ring" do
    ring = block(".attention-item:focus-visible")

    assert ring =~ ~r/outline:\s*2px solid var\(--color-accent\);/
    assert ring =~ ~r/outline-offset:\s*2px;/
    assert ring =~ ~r/border-radius:\s*var\(--radius-sm\);/
  end

  # User story (#1033; board 06, H6.4, rule ④):
  # As the operator reading a one-line result ("Kurse aktualisiert."),
  # I want its × to sit on the sentence's line,
  # so that the note is one line high and the severity word stands beside
  # its sentence instead of 8 px above it — and the × stays a 44 px target
  # on touch.
  #
  # Acceptance criteria:
  # - On the desktop the dismiss drops the base button's 34 px floor
  #   (`min-height: 0`, the cause, not the 1.4rem) and is 1rem high, so it
  #   fits the 18 px line; its width, margin and hover stay.
  # - Under a coarse pointer it is 44 × 44 with 14 px of block padding given
  #   back as a negative block margin, so the touch target is 44 px and the
  #   line stays 18 px. Without this half, dropping the floor would shrink
  #   the touch target from 34 to 16 px.
  test "the inline result's dismiss fits its line and keeps a 44 px touch target" do
    dismiss = block(".inline-result__dismiss")

    assert dismiss =~ ~r/min-height:\s*0;/
    assert dismiss =~ ~r/\n\s*height:\s*1rem;/
    assert dismiss =~ ~r/width:\s*1\.4rem;/

    touch =
      case Regex.run(
             ~r/@media \(pointer: coarse\) \{\s*\.inline-result__dismiss \{([^}]*)\}\s*\}/,
             @css
           ) do
        [_, body] -> body
        nil -> flunk("no coarse rule for the inline result's dismiss")
      end

    assert touch =~ ~r/width:\s*44px;/
    assert touch =~ ~r/\n\s*height:\s*44px;/
    assert touch =~ ~r/padding-block:\s*14px;/
    assert touch =~ ~r/margin-block:\s*-14px;/
  end

  # H6.1's coarse-pointer rule: its selector list and its declarations.
  defp remedy_rule do
    case Regex.run(
           ~r/@media \(pointer: coarse\) \{\s*(\.data-note__body \.link-button[^{]*)\{([^}]*)\}\s*\}/,
           @css
         ) do
      [_, selectors, body] ->
        {selectors |> String.split(",") |> Enum.map(&String.trim/1), body}

      nil ->
        flunk("no coarse rule for a remedy inside a data note")
    end
  end

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{inspect(selector)}")
    end
  end
end
