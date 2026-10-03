defmodule Portfolixir.Invariants.SoftHyphenScopeTest do
  use ExUnit.Case, async: true

  # U+00AD SOFT HYPHEN, as its UTF-8 bytes: written out, it would be the
  # very character the repository's invisible-Unicode gate refuses.
  @soft_hyphen <<0xC2, 0xAD>>

  # User story (#909; board ux-design-2026-10-02/07-phone-390, H7.5, pick A):
  # As the maintainer keeping the invisible-Unicode gate meaningful,
  # I want the one soft hyphen the German catalog carries to stay where its
  # allowlist entry says it is,
  # so that the entry — which the gate can scope only to a file and a code
  # point — does not quietly admit a soft hyphen anywhere else in the
  # catalog.
  #
  # Acceptance criteria:
  # - `.unicode-allowlist.txt` pins U+00AD to the German catalog, with a
  #   written reason.
  # - The catalog carries U+00AD exactly once: in the msgstr of the import
  #   summary cards' "Cash accounts" (context "import summary"), at the
  #   compound joint "Verrechnungs|konten".
  test "the German catalog's one soft hyphen is the import cards' label" do
    assert File.read!(".unicode-allowlist.txt") =~
             ~r/^priv\/gettext\/de\/LC_MESSAGES\/default\.po U\+00AD # \S.+$/m

    po = File.read!("priv/gettext/de/LC_MESSAGES/default.po")

    assert length(String.split(po, @soft_hyphen)) == 2,
           "the German catalog carries U+00AD outside the import cards' label"

    assert po =~
             ~s(msgctxt "import summary"\nmsgid "Cash accounts"\nmsgstr "Verrechnungs#{@soft_hyphen}konten"\n)
  end
end
