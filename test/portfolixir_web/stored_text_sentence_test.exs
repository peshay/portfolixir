defmodule PortfolixirWeb.StoredTextSentenceTest do
  # #1208 (Sprint 21 γ1; board 01 ⑥, before/after; DESIGN.md H8.8, "One body
  # sentence joined, for its punctuation"): one shared helper decides which
  # msgid a sentence that ends on stored names takes, so no name's last
  # character meets a full stop of the app's.
  use ExUnit.Case, async: true

  alias PortfolixirWeb.StoredText

  # User story (#1208, Sprint 21 γ1): As the operator reading a note that
  # ends on security names, I want a name that ends in a full stop
  # ("Larkspur Rail Corp.") to end the sentence once, so that the note never
  # reads "Corp..", in any language and wherever the sentence goes on.
  #
  # Acceptance criteria:
  # - A text whose last character is a full stop takes the sentence written
  #   without the stop (its own msgid); any other text takes the sentence
  #   with it.
  # - Each sentence is given the text, so the call site keeps both msgids
  #   literal for extraction, and the helper never rewrites a translation.
  test "a text that ends in a full stop takes the sentence without the stop" do
    with_stop = fn names -> "Left out: #{names}. Backfill below." end
    without_stop = fn names -> "Left out: #{names} Backfill below." end

    assert StoredText.ending_on("Larkspur Rail Corp.", with_stop, without_stop) ==
             "Left out: Larkspur Rail Corp. Backfill below."

    assert StoredText.ending_on("Arbolia Inc., Larkspur Rail Corp.", with_stop, without_stop) ==
             "Left out: Arbolia Inc., Larkspur Rail Corp. Backfill below."

    assert StoredText.ending_on("Larkspur Rail Corp", with_stop, without_stop) ==
             "Left out: Larkspur Rail Corp. Backfill below."

    # A full stop inside the text, not at its end, changes nothing.
    assert StoredText.ending_on("Arbolia Inc., Wrenfield Gardens AG", with_stop, without_stop) ==
             "Left out: Arbolia Inc., Wrenfield Gardens AG. Backfill below."
  end
end
