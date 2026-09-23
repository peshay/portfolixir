defmodule Portfolixir.Invariants.CssClosingActRepairsTest do
  use ExUnit.Case, async: true

  @css File.read!("priv/static/app.css")

  # User story (Sprint 15 closing act, design critic; board
  # ux-design-2026-09-23/07-closing-act-repairs):
  # As the operator reading the Risk tab and its dialogs on any device,
  # I want the controls Sprint 15 added to look as their boards drew them,
  # so that a rule's name reads as text, focus is always visible, and no
  # button sits against a dialog's edge.
  #
  # Acceptance criteria:
  # - F26: `.link-button` carries no button chrome — no shadow, no radius, no
  #   34 px floor — while a rule's name keeps its 44 px under a coarse pointer.
  # - F25: the position-targets toggle draws the 2 px accent focus outline.
  # - F27: the blocked-delete dialog's footer sits inside the body's padding.
  # - F29: below 480 px the rule dialog's footer wraps, "Retire rule" on a row
  #   of its own at the start, instead of setting every label on two lines.
  # - The open column-picker toggle carries the accent state board
  #   ux-design-2026-09-20/03 draws (`.ctl.on`): accent border and text, bold.
  test "the conformance repairs of board 07 are in the stylesheet" do
    link = block(".link-button")
    assert link =~ ~r/box-shadow:\s*none;/
    assert link =~ ~r/min-height:\s*0;/
    assert link =~ ~r/border-radius:\s*0;/
    assert @css =~ ~r/@media \(pointer: coarse\) \{\s*\.policy-rule__name \{\s*min-height: 44px;/

    focus = block(".soll-positions-toggle:focus-visible")
    assert focus =~ ~r/outline:\s*2px solid var\(--color-accent\);/
    assert focus =~ ~r/outline-offset:\s*2px;/

    assert block(".confirm-delete-blocked .modal-footer") =~ ~r/padding:\s*0 18px 18px;/

    phone =
      case Regex.run(
             ~r/@media \(max-width: 480px\) \{\s*\.policy-rule-dialog .modal-footer \{([^}]*)\}(.*?)\n\}/s,
             @css
           ) do
        [_, footer, rest] -> {footer, rest}
        nil -> flunk("no 480 px rule for the rule dialog's footer")
      end

    {footer, rest} = phone
    assert footer =~ ~r/flex-wrap:\s*wrap;/
    assert rest =~ ~r/> button \+ \.modal-footer__spacer \{[^}]*flex-basis:\s*100%;/
    assert rest =~ ~r/> button:first-child \{[^}]*margin-right:\s*auto;/

    open_toggle = block(".column-picker-toggle.is-active")
    assert open_toggle =~ ~r/border-color:\s*var\(--color-accent\);/
    assert open_toggle =~ ~r/color:\s*var\(--color-accent\);/
    assert open_toggle =~ ~r/font-weight:\s*700;/
  end

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{selector}")
    end
  end
end
