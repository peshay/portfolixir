defmodule Portfolixir.LocalizationFoundationTest do
  use ExUnit.Case, async: true

  @core_messages [
    "Dashboard",
    "Securities",
    "Portfolios",
    "Transactions",
    "Create securities",
    "Create one portfolio",
    "Record manual buy and sell transactions",
    "Linked cash account is derived from the selected depot."
  ]

  # User story:
  # As a contributor adding visible Portfolixir behavior,
  # I want English-first interface text backed by gettext catalogs and German translations,
  # so that future languages can be added without rewriting features.
  #
  # Acceptance criteria:
  # - The English gettext template exists.
  # - The German gettext catalog exists.
  # - Core visible workflow messages have German translations.
  test "visible foundation messages have gettext template entries and German translations" do
    template = File.read!("priv/gettext/default.pot")
    german = File.read!("priv/gettext/de/LC_MESSAGES/default.po")

    for message <- @core_messages do
      assert template =~ ~s(msgid "#{message}")
      assert german =~ ~s(msgid "#{message}")
    end

    assert german =~ ~s(msgstr "Dashboard")
    assert german =~ ~s(msgstr "Wertpapiere")
    assert german =~ ~s(msgstr "Portfolios")
    assert german =~ ~s(msgstr "Transaktionen")
    assert german =~ ~s(msgstr "Wertpapiere anlegen")
  end
end
