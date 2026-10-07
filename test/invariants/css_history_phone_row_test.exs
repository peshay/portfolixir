defmodule Portfolixir.Invariants.CssHistoryPhoneRowTest do
  use ExUnit.Case, async: true

  # Sprint 19 PR γ U1 (#1073, #1084; board ux-design-2026-10-04/03-history,
  # rule ①, and the story's review). The rules are CSS only, so the
  # stylesheet is what these tests read; the board measures the phone row in
  # a 390 px frame, and the review measured the table at 1200 px.

  @css File.read!("priv/static/app.css")

  # User story (#1073, the phone row):
  # As the operator reading the history on a phone,
  # I want a security, account or depot name with no break opportunity to
  # wrap inside its row,
  # so that it never runs over the amounts and out of the screen.
  #
  # Acceptance criteria:
  # - `.phone-row__ids` breaks anywhere: its text is the flex container's
  #   anonymous item, whose min-content width then shrinks to a glyph, so it
  #   can shrink and break (the delete dialog's R8 fix, moved onto the class).
  # - The delete dialog keeps its own rule for its hints and its box.
  test "a long name wraps inside the phone row's identifier line" do
    assert block(".phone-row__ids") =~ ~r/overflow-wrap:\s*anywhere;/

    assert @css =~
             ~r/\n\.booking-delete-dialog \.hint,\s*\.booking-delete__subject \.phone-row__ids > span \{/
  end

  # User story (U1 review, the table's width; #1084):
  # As the operator reading the history at 1200 px,
  # I want Preis and Betrag in view beside the default Konto column and a
  # long security name,
  # so that the amounts never sit beyond the scroller's edge with no cue.
  #
  # Acceptance criteria:
  # - The history is a reading table: it opts out of the scroller's
  #   `min-width: max-content` (the Risk tables' fit pattern), so it fits
  #   its wrapper; UX-DR15's scroller stays the fallback.
  # - The names (`.cell-name`, Wertpapier and Konto) wrap between words with
  #   a 12ch floor, hyphenated where the page language allows, never
  #   `anywhere` (the contribution table's name rule, R4).
  # - The date and the kind stay on one line, and the figures keep `.num`'s
  #   `nowrap`.
  test "the history fits its wrapper: the names wrap, the date, kind and figures do not" do
    fit = block(".data-table-wrapper > #transaction-list")
    assert fit =~ ~r/min-width:\s*0;/
    assert fit =~ ~r/width:\s*100%;/

    names = block("#transaction-list .cell-name")
    assert names =~ ~r/min-width:\s*12ch;/
    assert names =~ ~r/overflow-wrap:\s*break-word;/
    assert names =~ ~r/(?<!-)hyphens:\s*auto;/
    refute names =~ ~r/anywhere/

    assert @css =~
             ~r/\n#transaction-list \.cell-date,\s*#transaction-list \.cell-kind \{\s*white-space:\s*nowrap;\s*\}/

    assert @css =~
             ~r/\n#transaction-list th\.num,\s*#transaction-list td\.num \{[^}]*white-space:\s*nowrap;/
  end

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{selector}")
    end
  end
end
