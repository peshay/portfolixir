defmodule Portfolixir.Invariants.CssSharedComponentsTest do
  use ExUnit.Case, async: true

  # Sprint 21 γ8, board ux-design-2026-10-09/08-shared-copy: the shared
  # components every page renders — a dialog's footer, the inline result's
  # slot and its dismiss. The rules are CSS, so the stylesheet is what these
  # tests read; the rendered structure each rule selects is pinned in
  # `test/portfolixir_web/components/inline_result_test.exs` and
  # `test/portfolixir_web/live/shared_components_live_test.exs`.

  @css File.read!("priv/static/app.css")

  # User story (#1138, Sprint 21 γ8; board 08, "#1138"):
  # As the operator closing the Manage-logo dialog with the keyboard,
  # I want its last button to stand inside the dialog's padding,
  # so that "Logo entfernen" does not touch the dialog's edge and its focus
  # ring is not cut by the dialog's overflow.
  #
  # Acceptance criteria:
  # - A footer that is the dialog's own child takes the body's 18 px padding
  #   (`.modal > .modal-footer:not(.modal-footer--band)`, `0 18px 18px`).
  # - A band footer keeps its own padding (`12px 18px`).
  # - The blocked-delete dialogs' scoped rule, which this one makes a
  #   duplicate, is gone: one rule for every dialog.
  test "a dialog's own footer takes the body's padding" do
    assert block(".modal > .modal-footer:not(.modal-footer--band)") =~
             ~r/padding:\s*0 18px 18px;/

    assert block(".modal-footer.modal-footer--band") =~ ~r/padding:\s*12px 18px;/

    refute @css =~ ~r/\n\.confirm-delete-blocked \.modal-footer \{/
  end

  # User story (#1160, Sprint 21 γ8; board 08, "#1160"):
  # As the operator reading Accounts, Securities and Snapshots before any
  # action,
  # I want an empty result slot to take no room,
  # so that the page looks as it does until an action answers — no 8 px band,
  # and on Accounts no second 16 px grid gap.
  #
  # Acceptance criteria:
  # - The component's region takes its 8 px margins only when it holds a
  #   result (`:has(> *)`): its regions always hold whitespace, so the old
  #   `:not(:empty)` always matched and is gone.
  # - In a section's grid every empty inline result leaves the flow, not only
  #   a page slot (`.workspace-section > .inline-result:not(…)`), so the grid
  #   adds no gap for it.
  # - A page slot keeps its own footprint: no margin at rest, 12 px above a
  #   result.
  test "an empty inline result takes no room at rest" do
    assert block(".inline-result__region:has(> *)") =~ ~r/margin:\s*8px 0;/
    refute @css =~ ~r/\.inline-result__region:not\(:empty\)/

    assert block(".workspace-section > .inline-result:not(:has(.inline-result__region > *))") =~
             ~r/position:\s*absolute;/

    assert block(".inline-result.inline-result--page > .inline-result__region") =~
             ~r/margin:\s*0;/

    assert block(".inline-result.inline-result--page > .inline-result__region:has(> *)") =~
             ~r/margin:\s*12px 0 0;/
  end

  # User story (#1166, Sprint 21 γ8; board 08, N13 = A, rules ① and ②):
  # As the operator moving through a result with the keyboard,
  # I want the dismiss and the heading the focus falls back to to draw the
  # house's 2 px accent ring,
  # so that neither shows the browser's own `auto 1px` ring, and a heading
  # brought into view stops below the sticky top bar.
  #
  # Acceptance criteria:
  # - ① `.inline-result__dismiss:focus-visible`: 2px solid accent, 2px offset
  #   (the button family's rule, issue 1062).
  # - ② `.result-focus-fallback`: a scroll margin below the sticky top bar;
  #   its `:focus-visible` the house ring with `{rounded.sm}` corners.
  test "the dismiss and its fallback heading draw the house ring" do
    dismiss = block(".inline-result__dismiss:focus-visible")
    assert dismiss =~ ~r/outline:\s*2px solid var\(--color-accent\);/
    assert dismiss =~ ~r/outline-offset:\s*2px;/

    assert block(".result-focus-fallback") =~
             ~r/scroll-margin-top:\s*calc\(var\(--topbar-height\) \+ var\(--space-3\)\);/

    heading = block(".result-focus-fallback:focus-visible")
    assert heading =~ ~r/outline:\s*2px solid var\(--color-accent\);/
    assert heading =~ ~r/outline-offset:\s*2px;/
    assert heading =~ ~r/border-radius:\s*var\(--radius-sm\);/
  end

  # User story (#1166, Sprint 21 γ8; the γ closing act's accessibility pass,
  # A-F2):
  # As the keyboard operator whose correction answer takes the focus on the
  # import preview,
  # I want the Imports correction's result slot to draw the house ring and
  # stop below the sticky top bar,
  # so that it reads as the securities' and the classifications' slots do,
  # not with the browser's `auto 1px` ring half under the bar.
  #
  # Acceptance criteria:
  # - `#import-correction-result` (a `focusable` slot and the corrections'
  #   `data-focus-fallback`) carries the top bar's scroll margin, and its
  #   `:focus-visible` the 2 px accent ring at a 2 px offset with
  #   `{rounded.md}` corners, as `#securities-action-result` and
  #   `#classifications-result` do.
  test "the Imports correction's result slot draws the house ring below the top bar" do
    for slot <- ~w(#securities-action-result #classifications-result #import-correction-result) do
      assert block(slot) =~
               ~r/scroll-margin-top:\s*calc\(var\(--topbar-height\) \+ var\(--space-3\)\);/,
             slot

      ring = block("#{slot}:focus-visible")
      assert ring =~ ~r/outline:\s*2px solid var\(--color-accent\);/, slot
      assert ring =~ ~r/outline-offset:\s*2px;/, slot
      assert ring =~ ~r/border-radius:\s*var\(--radius-md\);/, slot
    end
  end

  # User story (#1166 accessibility pass, Sprint 21 γ8; the γ closing act,
  # A-F3):
  # As the keyboard operator replacing a security's logo,
  # I want "Choose image…" to show the house ring when its file input has
  # the focus,
  # so that I can see where Tab took me.
  #
  # Acceptance criteria:
  # - The chooser is a label beside the visually hidden file input, its
  #   sibling, not its parent, so `:focus-within` never matched: the ring
  #   rides `.logo-override__choose:has(+ input:focus-visible)`, 2 px accent
  #   at a 2 px offset, the radio cards' `:has(input:focus-visible)` pattern.
  test "the logo dialog's chooser rings when its file input has the keyboard focus" do
    ring = block(".logo-override__choose:has(+ input:focus-visible)")
    assert ring =~ ~r/outline:\s*2px solid var\(--color-accent\);/
    assert ring =~ ~r/outline-offset:\s*2px;/

    refute @css =~ ~r/\n\.logo-override__choose:focus-within \{/
  end

  # User story (#1166 accessibility pass, Sprint 21 γ8; the γ closing act,
  # A-F6):
  # As the keyboard operator,
  # I want every link-button, every link inside a data note and the search
  # fields to draw the house's 2 px accent ring,
  # so that "Anders zuordnen…", "Anderes Wertpapier suchen…", the archived
  # note's "Aktivieren", the bond links in the two-scales notes and the
  # picker's searchbox show the focus as every other control does, not the
  # browser's `auto 1px` ring or none at all.
  #
  # Acceptance criteria:
  # - One top-level rule names `.link-button:focus-visible`,
  #   `.data-note a:focus-visible` and `.search-field:focus-within` (the
  #   stacked chart's drill links and breadcrumb between them since the
  #   Sprint 27 closing act, D5, and the version link since Sprint 28's,
  #   D4) and draws the 2 px accent outline at a 2 px
  #   offset.
  # - The search field's input keeps `outline: none`: the field, which holds
  #   the glyph and the input, draws the ring around both.
  test "link-buttons, links in a note and the search fields draw the house ring" do
    [_, body] =
      Regex.run(
        ~r/\n\.link-button:focus-visible,\n\.data-note a:focus-visible,\n(?:(?:\.stack-|a\.sidebar-version__)[^{}\n]+,\n)*\.search-field:focus-within \{([^}]*)\}/,
        @css
      ) || flunk("no shared focus rule for link-buttons, note links and search fields")

    assert body =~ ~r/outline:\s*2px solid var\(--color-accent\);/
    assert body =~ ~r/outline-offset:\s*2px;/
    assert block(".search-field input") =~ ~r/outline:\s*none;/
  end

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{inspect(selector)}")
    end
  end
end
