defmodule Portfolixir.Imports.PortfolioPerformance.CsvParserTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Imports.PortfolioPerformance.CsvParser
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Input.Text

  @fixtures Path.expand("../../../support/fixtures/portfolio_performance", __DIR__)

  defp read!(name), do: File.read!(Path.join(@fixtures, name))

  # User story:
  # As a local portfolio maintainer importing the CSV variant of my
  # Portfolio Performance export,
  # I want the German-formatted CSV (semicolon-separated, "23.685,40"
  # numbers, German type names) to parse into the same normalised
  # `Entry` shape the JSON parser produces,
  # so that the importer can present a single preview regardless of
  # which source file I dragged in.

  describe "parse/2 happy path on the synthetic sample" do
    setup do
      {:ok, preview} = CsvParser.parse(read!("sample.csv"), filename: "sample.csv")
      {:ok, preview: preview}
    end

    test "produces a Preview tagged as :csv with no row errors", %{preview: preview} do
      assert %Preview{format: :csv, errors: []} = preview
      assert length(preview.entries) == 13
    end

    test "maps German PP type labels to Portfolixir kinds", %{preview: preview} do
      kinds = preview.entries |> Enum.map(& &1.kind) |> Enum.sort()

      assert kinds == [
               "buy",
               "cash_transfer",
               "deposit",
               "dividend",
               "fee",
               "inbound_delivery",
               "interest",
               "outbound_delivery",
               "removal",
               "security_transfer",
               "sell",
               "tax",
               "tax_refund"
             ]
    end

    test "parses German-formatted decimals exactly", %{preview: preview} do
      buy = Enum.find(preview.entries, &(&1.kind == "buy"))
      assert Decimal.equal?(buy.gross_amount, Decimal.new("1502.50"))
      assert Decimal.equal?(buy.quantity, Decimal.new("10"))
      assert Decimal.equal?(buy.price, Decimal.new("150.25"))
      assert Decimal.equal?(buy.fees, Decimal.new("2.50"))
    end

    test "respects thousands separator in the deposit row", %{preview: preview} do
      deposit = Enum.find(preview.entries, &(&1.kind == "deposit"))
      assert Decimal.equal?(deposit.gross_amount, Decimal.new("5000.00"))
    end

    test "emits a csv-without-isin warning whenever a security is referenced", %{preview: preview} do
      with_security = Enum.filter(preview.entries, & &1.security)
      assert Enum.all?(with_security, &(&1.warnings == ["csv-without-isin"]))
      assert Enum.all?(with_security, &is_nil(&1.security.isin))
    end

    test "maps Konto/Gegenkonto according to the kind", %{preview: preview} do
      buy = Enum.find(preview.entries, &(&1.kind == "buy"))
      assert buy.pp_portfolio_name == "Test-Depot"
      assert buy.pp_account_name == "Test-Cash"

      transfer = Enum.find(preview.entries, &(&1.kind == "cash_transfer"))
      assert transfer.pp_account_name == "Test-Cash"
      assert transfer.pp_counter_account_name == "Test-Cash-2"

      sec_transfer = Enum.find(preview.entries, &(&1.kind == "security_transfer"))
      assert sec_transfer.pp_portfolio_name == "Test-Depot"
      assert sec_transfer.pp_counter_portfolio_name == "Test-Depot-2"

      dividend = Enum.find(preview.entries, &(&1.kind == "dividend"))
      assert dividend.pp_account_name == "Test-Cash"
      assert is_nil(dividend.pp_portfolio_name)
    end

    test "treats 00:00:00 time as nil and keeps real intraday times", %{preview: preview} do
      buy = Enum.find(preview.entries, &(&1.kind == "buy"))
      assert buy.time == ~T[10:01:00]

      deposit = Enum.find(preview.entries, &(&1.kind == "deposit"))
      assert is_nil(deposit.time)
    end
  end

  describe "parse/2 error paths" do
    test "errors on missing required columns" do
      body = "Datum;Typ\n2024-01-01;Kauf\n"
      assert {:error, {:missing_columns, missing}} = CsvParser.parse(body)
      assert "Stück" in missing
    end

    test "returns an :empty_csv error instead of crashing on an empty body" do
      assert {:error, :empty_csv} = CsvParser.parse("")
    end

    test "returns a structured error for whitespace-only input rather than crashing" do
      # whitespace-only parses to a single one-cell row, which fails
      # column validation instead of pattern-matching to an empty list.
      assert {:error, {:missing_columns, _}} = CsvParser.parse("   \n  \n")
    end

    test "captures unknown German type labels as row-level errors" do
      body = """
      Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
      2024-01-01 00:00:00;Mystery;;;;1,00;;;1,00;Test-Cash;;;
      """

      assert {:ok, %Preview{entries: [], errors: errors}} = CsvParser.parse(body)
      assert [%{row: 1, message: message}] = errors
      assert message =~ "Mystery"
    end

    # Mirrors the JSON parser: a date typo like 0219-03-07 must surface as a
    # per-row error instead of poisoning every derived metric after import.
    test "rejects bookings with implausible dates (before 1900) per row" do
      body = """
      Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
      0219-03-07 00:00:00;Entnahme;;;;250,00;;;250,00;Girokonto;;;
      """

      assert {:ok, %Preview{entries: [], errors: errors}} = CsvParser.parse(body)
      assert [%{row: 1, message: message}] = errors
      assert message =~ "implausible date 0219-03-07"
      assert message =~ "re-import"
    end

    # E25 S4, F70: the ledger refuses a date past its bounded range, so the
    # parser names the row instead of letting the apply fail on it.
    test "rejects bookings dated past the ledger's range per row" do
      body = """
      Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
      3019-03-07 00:00:00;Entnahme;;;;250,00;;;250,00;Girokonto;;;
      """

      assert {:ok, %Preview{entries: [], errors: errors}} = CsvParser.parse(body)
      assert [%{row: 1, message: message}] = errors
      assert message =~ "implausible date 3019-03-07"
      assert message =~ "re-import"
    end

    # User story:
    # As an operator importing a file whose names the ledger cannot store,
    # I want the preview to name the row and the field,
    # so that I fix the source instead of meeting a failed apply.
    #
    # Acceptance criteria (E25 S4, G24):
    # - A security or account name carrying a control character, or longer
    #   than 255 characters, and a note carrying a NUL are row errors naming
    #   the field; the other rows still preview.
    test "names the row whose text the ledger cannot store" do
      long = String.duplicate("a", 256)

      body =
        "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle\n" <>
          "2026-03-07 00:00:00;Einlage;;;;250,00;;;250,00;Giro\u0007konto;;;\n" <>
          "2026-03-08 00:00:00;Einlage;;;;250,00;;;250,00;#{long};;;\n" <>
          "2026-03-09 00:00:00;Einlage;;;;250,00;;;250,00;Girokonto;;broken\u0000note;\n" <>
          "2026-03-10 00:00:00;Einlage;;;;250,00;;;250,00;Girokonto;;;\n"

      assert {:ok, %Preview{entries: [entry], errors: errors}} = CsvParser.parse(body)
      assert entry.source_row == 4

      assert [%{row: 1, message: first}, %{row: 2, message: second}, %{row: 3, message: third}] =
               errors

      assert first =~ "account"
      assert second =~ "account"
      assert third =~ "note"
    end

    # User story (E25 S7, G20):
    # As an operator importing a file whose text carries characters I cannot
    # see,
    # I want the preview to name the row, the field and the characters,
    # so that nothing hidden reaches the ledger an agent reads, and I know what
    # to fix in the source.
    #
    # Acceptance criteria:
    # - A note or an account name carrying an invisible character (a
    #   zero-width space, a bidirectional control) is a row error naming the
    #   field and the character by code point; the other rows still preview.
    # - A security name's format characters are dropped as the catalog drops
    #   them (E25 S5, G23), so a zero-width space there is no error; a run of
    #   variation selectors, which that does not drop, is.
    test "names the row whose text carries invisible characters" do
      zwsp = <<0x200B::utf8>>
      rlo = <<0x202E::utf8>>
      selectors = <<0xFE00::utf8, 0xFE01::utf8>>

      header =
        "Datum;Typ;Wertpapier;ISIN;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle\n"

      body =
        header <>
          "2026-03-07 00:00:00;Einlage;;;;;250,00;;;250,00;Girokonto;;hidden#{zwsp}note;\n" <>
          "2026-03-08 00:00:00;Einlage;;;;;250,00;;;250,00;Giro#{rlo}konto;;;\n" <>
          "2026-03-09 00:00:00;Kauf;Nordic#{zwsp} Timber;;1;10,00;10,00;;;10,00;Girokonto;;;\n" <>
          "2026-03-10 00:00:00;Kauf;Helios#{selectors} Solar;;1;10,00;10,00;;;10,00;Girokonto;;;\n" <>
          "2026-03-11 00:00:00;Einlage;;;;;250,00;;;250,00;Girokonto;;;\n"

      assert {:ok, %Preview{entries: entries, errors: errors}} = CsvParser.parse(body)
      assert Enum.map(entries, & &1.source_row) == [3, 5]

      assert [%{row: 1, message: note}, %{row: 2, message: account}, %{row: 4, message: security}] =
               errors

      assert note =~ "note" and note =~ "invisible" and note =~ "U+200B"
      assert account =~ "account" and account =~ "U+202E"
      assert security =~ "security name" and security =~ "U+FE00, U+FE01"
    end

    # Acceptance criteria (E25 S6, G02):
    # - A note longer than the ledger's free-text cap is a row error naming
    #   the note and the cap; a note at the cap previews.
    test "names the row whose note is longer than the free-text cap" do
      max = Text.free_text_max()

      body =
        "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle\n" <>
          "2026-03-09 00:00:00;Einlage;;;;250,00;;;250,00;Girokonto;;#{String.duplicate("n", max + 1)};\n" <>
          "2026-03-10 00:00:00;Einlage;;;;250,00;;;250,00;Girokonto;;#{String.duplicate("n", max)};\n"

      assert {:ok, %Preview{entries: [entry], errors: [%{row: 1, message: message}]}} =
               CsvParser.parse(body)

      assert entry.source_row == 2
      assert message =~ "note"
      assert message =~ Integer.to_string(max)
    end
  end
end
