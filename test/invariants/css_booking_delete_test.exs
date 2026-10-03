defmodule Portfolixir.Invariants.CssBookingDeleteTest do
  use ExUnit.Case, async: true

  # Sprint 18 U1 (#912), the closing act's repairs to the delete dialog
  # (board ux-review-2026-10-03/02-delete-dialog-repairs). The rules are CSS
  # only, so the stylesheet is what these tests read; the board measures
  # them in a browser.

  @css File.read!("priv/static/app.css")

  # User story (U1, #912; the closing act, R8):
  # As the operator on a phone deleting a booking of a security, depot or
  # account with a long name that has no space,
  # I want the name to wrap inside the dialog,
  # so that the sentence and the box stay on the sheet and the danger button
  # is not pushed sideways.
  #
  # Acceptance criteria:
  # - The dialog's hints and the box's subject line (its one inner span, the
  #   flex item of `.phone-row__ids`) break anywhere and may shrink:
  #   `overflow-wrap: anywhere; min-width: 0`.
  test "a long name wraps inside the delete dialog" do
    [_, rule] =
      Regex.run(
        ~r/\n\.booking-delete-dialog \.hint,\s*\.booking-delete__subject \.phone-row__ids > span \{([^}]*)\}/,
        @css
      ) || flunk("no wrapping rule for the delete dialog's names")

    assert rule =~ ~r/overflow-wrap:\s*anywhere;/
    assert rule =~ ~r/min-width:\s*0;/
  end
end
