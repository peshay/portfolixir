defmodule Portfolixir.LocalizationTest do
  use ExUnit.Case, async: true

  @core_messages [
    "Dashboard",
    "Securities",
    "Portfolios",
    "Transactions",
    "Theme",
    "Light",
    "Dark",
    "Accent color",
    "Violet",
    "Teal",
    "Coral",
    "Language",
    "German",
    "Create securities",
    "Create one portfolio",
    "Record manual buy and sell transactions",
    "Add costs"
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
  test "visible messages have gettext template entries and German translations" do
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

  # User story:
  # As a contributor adding gettext-wrapped strings to a LiveView,
  # I want the CI pipeline to reject a PR whose .pot is stale,
  # so that newly added gettext() calls always have DE translations
  # before they ship.
  #
  # Acceptance criteria:
  # - Every msgid in the .pot file has a corresponding msgid in the DE .po file.
  # - Strings known to be missing from the .pot (allocation, income, logo views)
  #   are now present in the template.
  # - All msgids in the DE .po that have an empty msgstr are flagged by this test.
  test "DE catalog covers every msgid in the .pot (no stale .pot entries)" do
    pot = File.read!("priv/gettext/default.pot")
    po = File.read!("priv/gettext/de/LC_MESSAGES/default.po")

    pot_ids = extract_msgids(pot)
    po_ids = extract_msgids(po)

    missing_from_po = MapSet.difference(pot_ids, po_ids)

    assert MapSet.size(missing_from_po) == 0,
           "The following msgids are in default.pot but missing from de/LC_MESSAGES/default.po " <>
             "(run `mix gettext.extract --merge` and translate in priv/gettext/de/):\n" <>
             Enum.map_join(missing_from_po, "\n", &"  #{inspect(&1)}")
  end

  test "critical portfolio and income view strings are present in the .pot" do
    template = File.read!("priv/gettext/default.pot")

    # Allocation view strings (portfolio_live.ex) previously missing from .pot
    assert template =~ ~s(msgid "Σ target top level:")
    assert template =~ ~s(msgid "subcategories:")
    assert template =~ ~s(msgid "of")

    # Income view strings (income_live.ex) previously missing from .pot
    assert template =~ ~s(msgid "Income")
    assert template =~ ~s(msgid "Received dividends and interest")
    assert template =~ ~s(msgid "Annual overview")
    assert template =~ ~s(msgid "No dividends or interest booked yet.")
    assert template =~ ~s(msgid "Net")
    assert template =~ ~s(msgid "Withheld tax")
    assert template =~ ~s(msgid "Payments")
    assert template =~ ~s(msgid "Last payment")
    assert template =~ ~s(msgid "Per position")
  end

  test "critical portfolio and income view strings have German translations" do
    german = File.read!("priv/gettext/de/LC_MESSAGES/default.po")

    assert german =~ ~s(msgstr "Σ Soll oberste Ebene:")
    assert german =~ ~s(msgstr "Unterkategorien:")
    assert german =~ ~s(msgstr "Erträge")
    assert german =~ ~s(msgstr "Erhaltene Dividenden und Zinsen")
    assert german =~ ~s(msgstr "Jahresübersicht")
    assert german =~ ~s(msgstr "Netto")
    assert german =~ ~s(msgstr "Einbehaltene Steuer")
    assert german =~ ~s(msgstr "Je Position")
  end

  # User story:
  # As a contributor who adds gettext-wrapped strings to a view file,
  # I want the CI pipeline to detect that the .pot is stale
  # (i.e., source files contain gettext() calls whose msgids are absent from
  # the .pot), so that missing extractions are caught before merge.
  #
  # Acceptance criteria:
  # - Every plain gettext("…") call in the flagged view files has a matching
  #   msgid entry in default.pot.
  # - The test fails with a human-readable list of missing msgids.
  #
  # Implementation note: this test statically parses source files for
  # gettext("literal string") patterns and cross-checks them against the .pot.
  # It does NOT replace running `mix gettext.extract`; rather it is a fast
  # cheap guard that catches the most common miss (adding a string to a view
  # without extracting). Interpolated strings (`gettext("foo %{x}", x: v)`)
  # are also covered because the msgid is always the literal template string.
  test "flagged view files have no gettext() calls missing from the .pot" do
    pot = File.read!("priv/gettext/default.pot")

    flagged_views = [
      "lib/portfolixir_web/live/portfolio_live.ex",
      "lib/portfolixir_web/live/income_live.ex",
      "lib/portfolixir_web/live/classifications_live.ex",
      "lib/portfolixir_web/live/securities_live.ex",
      "lib/portfolixir_web/live/securities/logo_override_dialog.ex"
    ]

    missing =
      for path <- flagged_views,
          content = File.read!(path),
          msgid <- extract_gettext_literals(content),
          not (pot =~ ~s(msgid "#{msgid}")),
          do: {path, msgid}

    assert missing == [],
           "The following gettext() calls are not extracted in default.pot — " <>
             "run `mix gettext.extract --merge` and translate in priv/gettext/de/:\n" <>
             Enum.map_join(missing, "\n", fn {path, id} -> "  #{path}: #{inspect(id)}" end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Extract all plain msgid values (single-line) from a .pot/.po file.
  # Skips the empty header msgid and plural msgids.
  defp extract_msgids(content) do
    content
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^msgid "(.+)"$/, line) do
        [_, id] -> [id]
        _ -> []
      end
    end)
    |> MapSet.new()
  end

  # Extract literal string arguments from gettext("…") calls in Elixir source.
  # Only matches the first (msgid) argument when it is a plain string literal.
  # Does not attempt to match multiline or interpolated strings.
  defp extract_gettext_literals(content) do
    Regex.scan(~r/gettext\("((?:[^"\\]|\\.)*)"\s*(?:,|\))/, content)
    |> Enum.map(fn [_full, msgid] -> msgid end)
    |> Enum.uniq()
  end
end
