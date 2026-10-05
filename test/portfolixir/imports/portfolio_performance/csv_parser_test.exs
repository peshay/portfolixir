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
      assert Decimal.equal?(buy.hash_amount, Decimal.new("1500.00"))
      assert Decimal.equal?(buy.quantity, Decimal.new("10"))
      assert Decimal.equal?(buy.price, Decimal.new("150.00"))
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

  # User story (ADR-0053 §1, §5; risk-tier: money):
  # As the operator dropping the CSV Portfolio Performance exports,
  # I want each row to book the cash PP writes in its Gesamtpreis, where
  # Betrag is only the gross value before fees and taxes,
  # so that my cash balances match Portfolio Performance's to the cent.
  #
  # Acceptance criteria:
  # - A Kauf books its Gesamtpreis (Betrag plus Gebühren and Steuern); a
  #   Verkauf, a Dividende and Zinsen book theirs (Betrag minus them).
  # - A row with an empty Gesamtpreis (a converter-written file) books its
  #   Betrag, as before; so does every row of a file without the column.
  # - A row with a Gesamtpreis and no Betrag books the Gesamtpreis.
  # - A kind without cash (a delivery, a security transfer) books none,
  #   whatever its money cells say.
  # - A negative Steuern split off as a refund leaves the row's bookings
  #   summing to its Gesamtpreis: on a credit row the parent books the
  #   Gesamtpreis minus the refund, on a debit row the parent's debit is the
  #   Gesamtpreis plus the refund, and the refund is booked beside it.
  describe "parse/2 the cash a row books" do
    @header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle\n"

    defp booked(rows, header \\ @header) do
      assert {:ok, %Preview{errors: [], entries: entries}} = CsvParser.parse(header <> rows)
      entries
    end

    defp cash(%{gross_amount: nil}), do: nil
    defp cash(%{gross_amount: amount}), do: Decimal.to_string(amount, :normal)

    test "a Portfolio Performance row books its Gesamtpreis" do
      entries =
        booked("""
        2024-01-15 10:01:00;Kauf;Synthetic AG;10;150,00;1.500,00;2,50;1,00;1.503,50;Depot;Cash;;
        2024-04-22 12:25:00;Verkauf;Synthetic AG;10;181,45;1.814,50;2,50;12,00;1.800,00;Depot;Cash;;
        2024-02-15 00:00:00;Dividende;Synthetic AG;50;;11,54;;2,41;9,13;Cash;;;
        2024-12-30 00:00:00;Zinsen;;;;5,75;;1,20;4,55;Cash;;;
        2024-01-02 00:00:00;Einlage;;;;5.000,00;;;5.000,00;Cash;;;
        """)

      assert Enum.map(entries, &cash/1) == ["1503.50", "1800.00", "9.13", "4.55", "5000.00"]

      assert Enum.map(entries, &Decimal.to_string(&1.hash_amount, :normal)) ==
               ["1500.00", "1814.50", "11.54", "5.75", "5000.00"]

      [buy, sell | _] = entries
      assert Decimal.equal?(buy.price, Decimal.new("150.00"))
      assert Decimal.equal?(buy.fees, Decimal.new("2.50"))
      assert Decimal.equal?(buy.taxes, Decimal.new("1.00"))
      assert Decimal.equal?(sell.taxes, Decimal.new("12.00"))
    end

    test "a row with an empty Gesamtpreis books its Betrag, as a converter writes it" do
      entries =
        booked("""
        2025-01-06 10:15:00;Kauf;Synthetic AG;40;80,50;3.221,00;1,00;;;Depot;Cash;;
        2025-06-16 00:00:00;Dividende;Synthetic AG;10;;7,36;;2,64;;Cash;;;
        2025-09-01 14:00:00;Verkauf;Synthetic AG;10;62,00;612,50;1,50;6,00;;Depot;Cash;;
        """)

      assert Enum.map(entries, &cash/1) == ["3221.00", "7.36", "612.50"]
    end

    test "a file without a Gesamtpreis column books every row's Betrag" do
      header = "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Konto;Gegenkonto\n"

      entries =
        booked(
          """
          2025-01-06 10:15:00;Kauf;Synthetic AG;40;80,50;3.221,00;1,00;;Depot;Cash
          2025-06-16 00:00:00;Dividende;Synthetic AG;10;;7,36;;2,64;Cash;
          """,
          header
        )

      assert Enum.map(entries, &cash/1) == ["3221.00", "7.36"]
    end

    test "a row with a Gesamtpreis and no Betrag books the Gesamtpreis" do
      assert [deposit] = booked("2024-01-02 00:00:00;Einlage;;;;;;;250,00;Cash;;;\n")
      assert cash(deposit) == "250.00"
      assert deposit.hash_amount == nil
    end

    test "a kind without cash books none, whatever its money cells say" do
      entries =
        booked("""
        2024-09-04 00:00:00;Einlieferung;Synthetic Fund;5;20,00;100,00;1,00;;101,00;Depot;;;
        2024-10-01 00:00:00;Auslieferung;Synthetic Fund;2;40,00;80,00;;;999,00;Depot;;;
        2024-11-15 21:00:00;Umbuchung (Ausgang);Synthetic Fund;3;66,67;200,00;;;200,00;Depot;Depot-2;;
        2024-11-20 00:00:00;Einlieferung;Synthetic Fund;1;20,00;20,00;;;abc;Depot;;;
        """)

      assert Enum.map(entries, &cash/1) == [nil, nil, nil, nil]
    end

    test "a refund split off a credit row leaves the row summing to its Gesamtpreis" do
      # Betrag 10,00; Gebühren 0,50 and Steuern -1,00 make U = -0,50, so the
      # credit's Gesamtpreis is 10,00 - (-0,50) = 10,50.
      assert [dividend] =
               booked(
                 "2024-03-15 00:00:00;Dividende;Synthetic AG;10;;10,00;0,50;-1,00;10,50;Cash;;;\n"
               )

      assert [refund] = dividend.companion_entries
      assert cash(dividend) == "9.50"
      assert cash(refund) == "1.00"

      assert Decimal.equal?(
               Decimal.add(dividend.gross_amount, refund.gross_amount),
               Decimal.new("10.50")
             )

      assert Decimal.equal?(dividend.taxes, Decimal.new("0"))
    end

    test "a refund split off a debit row leaves the row's net cash at its Gesamtpreis" do
      # Betrag 1.000,00; Gebühren 2,50 and Steuern -1,00 make U = 1,50, so the
      # debit's Gesamtpreis is 1.000,00 + 1,50 = 1.001,50.
      assert [buy] =
               booked(
                 "2024-01-15 10:01:00;Kauf;Synthetic AG;10;100,00;1.000,00;2,50;-1,00;1.001,50;Depot;Cash;;\n"
               )

      assert [refund] = buy.companion_entries
      assert cash(buy) == "1002.50"
      assert cash(refund) == "1.00"

      assert Decimal.equal?(
               Decimal.sub(buy.gross_amount, refund.gross_amount),
               Decimal.new("1001.50")
             )
    end

    test "a refund split off a converter row books as before" do
      assert [dividend] =
               booked("2024-03-15 00:00:00;Dividende;Synthetic AG;10;;9,00;;-1,00;;Cash;;;\n")

      assert [refund] = dividend.companion_entries
      assert cash(dividend) == "9.00"
      assert cash(refund) == "1.00"
    end
  end

  # User story (ADR-0053 §2, K5; risk-tier: money):
  # As the operator dropping a CSV whose Gesamtpreis contradicts its Betrag,
  # Gebühren and Steuern,
  # I want that row named with the cells as the file wrote them and left out,
  # while the rest of the file previews,
  # so that the import never guesses which cell is wrong.
  #
  # Acceptance criteria:
  # - With U = Gebühren as booked (its magnitude) + Steuern as written (a
  #   negative Steuern with its sign), a debit kind (Kauf, Entnahme, Gebühren, Steuern, Umbuchung
  #   (Ausgang)) needs Gesamtpreis = Betrag + U and a credit kind (Verkauf,
  #   Dividende, Zinsen, Einlage, Steuerrückerstattung, Umbuchung (Eingang))
  #   Gesamtpreis = Betrag − U, exactly.
  # - A row that fails is a row error naming the Gesamtpreis, the Betrag and
  #   the units the row carries, as written, in one of four forms; in German
  #   it reads "… passt nicht zu … — Zeile nicht übernommen".
  # - A row without a Gesamtpreis, or without a Betrag, is not checked; nor
  #   is a kind without cash.
  describe "parse/2 a Gesamtpreis that contradicts its Betrag" do
    @header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle\n"

    defp checked(rows), do: CsvParser.parse(@header <> rows)

    test "names the row with the cells as written, and the other rows preview" do
      assert {:ok, %Preview{entries: [entry], errors: [%{row: 1, message: message}]}} =
               checked("""
               2024-04-22 12:25:00;Verkauf;Synthetic AG;10;150,25;1.502,50;2,50;;1.505,00;Depot;Cash;;
               2024-01-02 00:00:00;Einlage;;;;5.000,00;;;5.000,00;Cash;;;
               """)

      assert entry.source_row == 2

      assert message ==
               "Gesamtpreis 1.505,00 does not match Betrag 1.502,50 and Gebühren 2,50 — row not imported"
    end

    test "names the units the row carries in each of four forms" do
      assert {:ok, %Preview{entries: [], errors: errors}} =
               checked("""
               2024-01-02 00:00:00;Einlage;;;;250,00;;;251,00;Cash;;;
               2024-01-15 10:01:00;Kauf;Synthetic AG;10;150,25;1.502,50;2,50;;1.502,50;Depot;Cash;;
               2024-02-15 00:00:00;Dividende;Synthetic AG;10;;11,54;;2,41;9,31;Cash;;;
               2024-01-15 10:01:00;Kauf;Synthetic AG;10;150,00;1.500,00;2,50;1,00;1.502,50;Depot;Cash;;
               """)

      assert Enum.map(errors, & &1.message) == [
               "Gesamtpreis 251,00 does not match Betrag 250,00 — row not imported",
               "Gesamtpreis 1.502,50 does not match Betrag 1.502,50 and Gebühren 2,50 — row not imported",
               "Gesamtpreis 9,31 does not match Betrag 11,54 and Steuern 2,41 — row not imported",
               "Gesamtpreis 1.502,50 does not match Betrag 1.500,00, Gebühren 2,50 and Steuern 1,00 — row not imported"
             ]
    end

    test "says it in German" do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")

      assert {:ok, %Preview{entries: [], errors: errors}} =
               checked("""
               2024-01-02 00:00:00;Einlage;;;;250,00;;;251,00;Cash;;;
               2024-04-22 12:25:00;Verkauf;Synthetic AG;10;150,25;1.502,50;2,50;;1.505,00;Depot;Cash;;
               2024-02-15 00:00:00;Dividende;Synthetic AG;10;;11,54;;2,41;9,31;Cash;;;
               2024-01-15 10:01:00;Kauf;Synthetic AG;10;150,00;1.500,00;2,50;1,00;1.502,50;Depot;Cash;;
               """)

      assert Enum.map(errors, & &1.message) == [
               "Gesamtpreis 251,00 passt nicht zu Betrag 250,00 — Zeile nicht übernommen",
               "Gesamtpreis 1.505,00 passt nicht zu Betrag 1.502,50 und Gebühren 2,50 — Zeile nicht übernommen",
               "Gesamtpreis 9,31 passt nicht zu Betrag 11,54 und Steuern 2,41 — Zeile nicht übernommen",
               "Gesamtpreis 1.502,50 passt nicht zu Betrag 1.500,00, Gebühren 2,50 und Steuern 1,00 — Zeile nicht übernommen"
             ]
    end

    test "reads every cash kind in its direction, a negative Steuern with its sign" do
      # Betrag 100,00 with Gebühren 2,00 and Steuern -0,50: U = 1,50, so a
      # debit's Gesamtpreis is 101,50 and a credit's 98,50.
      for {label, debit?} <- [
            {"Kauf", true},
            {"Entnahme", true},
            {"Gebühren", true},
            {"Steuern", true},
            {"Umbuchung (Ausgang)", true},
            {"Verkauf", false},
            {"Dividende", false},
            {"Zinsen", false},
            {"Einlage", false},
            {"Steuerrückerstattung", false},
            {"Umbuchung (Eingang)", false}
          ] do
        {right, wrong} = if debit?, do: {"101,50", "98,50"}, else: {"98,50", "101,50"}
        security = if label in ["Kauf", "Verkauf", "Dividende"], do: "Synthetic AG", else: ""

        row =
          &"2024-03-01 00:00:00;#{label};#{security};1;100,00;100,00;2,00;-0,50;#{&1};Cash;Cash-2;;\n"

        assert {:ok, %Preview{errors: [], entries: [_]}} = checked(row.(right)), label

        assert {:ok, %Preview{entries: [], errors: [%{message: message}]}} = checked(row.(wrong)),
               label

        assert message ==
                 "Gesamtpreis #{wrong} does not match Betrag 100,00, Gebühren 2,00 and Steuern -0,50 — row not imported",
               label
      end
    end

    # ADR-0053 §2: "to the cent". Both sides are compared rounded to two
    # places, so a cell written with more places than PP prints is not
    # refused for a fraction of a cent.
    test "compares the two readings to the cent" do
      assert {:ok, %Preview{errors: [], entries: [buy]}} =
               checked(
                 "2024-01-15 10:01:00;Kauf;Synthetic AG;10;150,00;1.500,004;2,50;;1.502,50;Depot;Cash;;\n"
               )

      assert Decimal.equal?(buy.gross_amount, Decimal.new("1502.50"))
    end

    # The booking stores Gebühren as a magnitude, so U counts it as booked;
    # only Steuern keeps its sign (a negative one is a split-off refund).
    test "counts a negative Gebühren as the fee it books" do
      assert {:ok, %Preview{entries: [], errors: [%{message: message}]}} =
               checked(
                 "2024-01-15 10:01:00;Kauf;Synthetic AG;10;100,00;1.000,00;-2,50;;997,50;Depot;Cash;;\n"
               )

      assert message ==
               "Gesamtpreis 997,50 does not match Betrag 1.000,00 and Gebühren -2,50 — row not imported"

      assert {:ok, %Preview{errors: [], entries: [buy]}} =
               checked(
                 "2024-01-15 10:01:00;Kauf;Synthetic AG;10;100,00;1.000,00;-2,50;;1.002,50;Depot;Cash;;\n"
               )

      assert Decimal.equal?(buy.fees, Decimal.new("2.50"))
      assert Decimal.equal?(buy.gross_amount, Decimal.new("1002.50"))
    end

    test "checks nothing on a row missing a reading or on a kind without cash" do
      assert {:ok, %Preview{errors: [], entries: [_, _, _, _]}} =
               checked("""
               2025-01-06 10:15:00;Kauf;Synthetic AG;40;80,50;3.221,00;1,00;;;Depot;Cash;;
               2024-01-02 00:00:00;Einlage;;;;;1,00;;250,00;Cash;;;
               2024-09-04 00:00:00;Einlieferung;Synthetic Fund;5;20,00;100,00;1,00;;999,00;Depot;;;
               2024-11-15 21:00:00;Umbuchung (Ausgang);Synthetic Fund;3;66,67;200,00;;;1,00;Depot;Depot-2;;
               """)
    end
  end

  # User story (ADR-0053 §3, K2; risk-tier: idempotency):
  # As the operator who imported a Portfolio Performance CSV before,
  # I want each row to carry the file's Betrag as the content hash's amount,
  # apart from the cash the row books,
  # so that every hash stored for the file stays valid and a re-drop books
  # nothing twice.
  #
  # Acceptance criteria:
  # - A cash row's hash amount is its Betrag as parsed, with or without a
  #   Gesamtpreis beside it; a split-off refund's is the refund it books.
  # - A kind that settles no cash (a delivery, a security transfer) carries
  #   none, as its hash read none before.
  describe "parse/2 the content hash's amount input" do
    test "carries each cash row's Betrag, and nothing for a kind without cash" do
      body = """
      Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
      2024-01-15 10:01:00;Kauf;Synthetic AG;10;150,00;1.500,00;2,50;;1.502,50;Depot;Cash;;
      2024-02-15 00:00:00;Dividende;Synthetic AG;10;;10,00;0,50;-1,00;10,50;Cash;;;
      2024-03-01 10:15:00;Kauf;Synthetic AG;2;80,50;162,00;1,00;;;Depot;Cash;;
      2024-09-04 00:00:00;Einlieferung;Synthetic AG;5;100,00;500,00;;;500,00;Depot;;;
      2024-11-15 21:00:00;Umbuchung (Ausgang);Synthetic AG;2;100,00;200,00;;;200,00;Depot;Depot-2;;
      """

      assert {:ok, %Preview{errors: [], entries: [buy, dividend, converted, delivery, transfer]}} =
               CsvParser.parse(body)

      assert Decimal.equal?(buy.hash_amount, Decimal.new("1500.00"))
      assert Decimal.equal?(dividend.hash_amount, Decimal.new("10.00"))
      assert Decimal.equal?(converted.hash_amount, Decimal.new("162.00"))
      assert delivery.hash_amount == nil
      assert transfer.hash_amount == nil

      assert [refund] = dividend.companion_entries
      assert Decimal.equal?(refund.hash_amount, Decimal.new("1.00"))
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

  # User story:
  # As a maintainer importing a Portfolio Performance CSV that moves money or
  # shares between two of my accounts or depots,
  # I want every transfer booked exactly once, in the direction it moved,
  # whichever of PP's export shapes the file has,
  # so that both cash balances and both depot positions come out right.
  #
  # Acceptance criteria (#1023, Sprint 18 C1; established from Portfolio
  # Performance's source at commit bcae360b, 2026-10-02):
  # - PP's "All transactions" export writes ONE row per transfer, the sending
  #   side: "Umbuchung (Ausgang)", `Konto` the sender, `Gegenkonto` the
  #   receiver (`Client.getAllTransactions/0` leaves out every TRANSFER_IN).
  #   It is booked as it reads.
  # - A depot-to-depot transfer in that export is also "Umbuchung (Ausgang)",
  #   carrying the security (PP labels a portfolio TRANSFER_OUT the same way):
  #   a row naming a security is a security transfer, never a cash transfer.
  # - An account's or a security's own transaction list in PP exports the
  #   receiving side too: "Umbuchung (Eingang)", `Konto` the receiver,
  #   `Gegenkonto` the sender. It is booked from `Gegenkonto` to `Konto`.
  # - A file carrying both sides of one transfer books it once, from the
  #   sending row; the receiving row is named in the parser warnings with the
  #   row it was booked from. Sides pair only on equal date, time, security,
  #   shares, amount and accounts, so two different transfers never merge.
  describe "parse/2 transfers in every Portfolio Performance export shape" do
    @header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle\n"

    defp transfers(rows) do
      {:ok, preview} = CsvParser.parse(@header <> rows)
      preview
    end

    defp direction(entry) do
      {entry.kind, entry.pp_portfolio_name, entry.pp_account_name,
       entry.pp_counter_portfolio_name, entry.pp_counter_account_name}
    end

    test "books the sending side of a cash transfer from Konto to Gegenkonto" do
      preview =
        transfers(
          "2024-08-12 10:00:00;Umbuchung (Ausgang);;;;1.000,00;;;1.000,00;Cash-A;Cash-B;;\n"
        )

      assert %Preview{errors: [], entries: [entry]} = preview
      assert direction(entry) == {"cash_transfer", nil, "Cash-A", nil, "Cash-B"}
      assert Decimal.equal?(entry.gross_amount, Decimal.new("1000.00"))
    end

    test "books the receiving side of a cash transfer from Gegenkonto to Konto" do
      preview =
        transfers(
          "2024-08-12 10:00:00;Umbuchung (Eingang);;;;1.000,00;;;1.000,00;Cash-B;Cash-A;;\n"
        )

      assert %Preview{errors: [], entries: [entry]} = preview
      assert direction(entry) == {"cash_transfer", nil, "Cash-A", nil, "Cash-B"}
      assert Decimal.equal?(entry.gross_amount, Decimal.new("1000.00"))
    end

    test "books PP's sending-side depot transfer as a security transfer" do
      preview =
        transfers(
          "2024-11-15 21:00:00;Umbuchung (Ausgang);Example Fund;3;20,00;60,00;;;60,00;Depot-A;Depot-B;;\n"
        )

      assert %Preview{errors: [], entries: [entry]} = preview
      assert direction(entry) == {"security_transfer", "Depot-A", nil, "Depot-B", nil}
      assert Decimal.equal?(entry.quantity, Decimal.new("3"))
      assert entry.gross_amount == nil
      assert entry.security.name == "Example Fund"
    end

    test "books the receiving side of a depot transfer from Gegenkonto to Konto" do
      preview =
        transfers(
          "2024-11-15 21:00:00;Umbuchung (Eingang);Example Fund;3;20,00;60,00;;;60,00;Depot-B;Depot-A;;\n"
        )

      assert %Preview{errors: [], entries: [entry]} = preview
      assert direction(entry) == {"security_transfer", "Depot-A", nil, "Depot-B", nil}
    end

    test "keeps the security-transfer label Portfolixir's converter writes" do
      preview =
        transfers(
          "2024-11-15 21:00:00;Umbuchung (Wertpapier);Example Fund;3;;60,00;;;60,00;Depot-A;Depot-B;;\n"
        )

      assert %Preview{errors: [], entries: [entry]} = preview
      assert direction(entry) == {"security_transfer", "Depot-A", nil, "Depot-B", nil}
    end

    test "books both sides of one cash transfer once, from the sending row" do
      preview =
        transfers("""
        2024-08-12 10:00:00;Umbuchung (Eingang);;;;1.000,00;;;1.000,00;Cash-B;Cash-A;;
        2024-08-12 10:00:00;Umbuchung (Ausgang);;;;1.000,00;;;1.000,00;Cash-A;Cash-B;;
        """)

      assert %Preview{entries: [entry], errors: [%{row: 1, message: message}]} = preview
      assert entry.source_row == 2
      assert direction(entry) == {"cash_transfer", nil, "Cash-A", nil, "Cash-B"}
      assert message =~ "receiving side of the transfer in row 2"
    end

    test "books both sides of one depot transfer once, from the sending row" do
      preview =
        transfers("""
        2024-11-15 21:00:00;Umbuchung (Ausgang);Example Fund;3;20,00;60,00;;;60,00;Depot-A;Depot-B;;
        2024-11-15 21:00:00;Umbuchung (Eingang);Example Fund;3;20,00;60,00;;;60,00;Depot-B;Depot-A;;
        """)

      assert %Preview{entries: [entry], errors: [%{row: 2, message: message}]} = preview
      assert entry.source_row == 1
      assert direction(entry) == {"security_transfer", "Depot-A", nil, "Depot-B", nil}
      assert message =~ "row 1"
    end

    test "never pairs two different transfers between the same accounts" do
      preview =
        transfers("""
        2024-08-12 10:00:00;Umbuchung (Ausgang);;;;1.000,00;;;1.000,00;Cash-A;Cash-B;;
        2024-08-12 10:00:00;Umbuchung (Eingang);;;;250,00;;;250,00;Cash-B;Cash-A;;
        2024-08-13 10:00:00;Umbuchung (Eingang);;;;1.000,00;;;1.000,00;Cash-B;Cash-A;;
        2024-08-12 10:00:00;Umbuchung (Eingang);;;;1.000,00;;;1.000,00;Cash-A;Cash-B;;
        """)

      assert %Preview{errors: [], entries: entries} = preview
      assert Enum.map(entries, & &1.source_row) == [1, 2, 3, 4]

      assert Enum.map(entries, &direction/1) == [
               {"cash_transfer", nil, "Cash-A", nil, "Cash-B"},
               {"cash_transfer", nil, "Cash-A", nil, "Cash-B"},
               {"cash_transfer", nil, "Cash-A", nil, "Cash-B"},
               {"cash_transfer", nil, "Cash-B", nil, "Cash-A"}
             ]
    end

    test "pairs each receiving row with one sending row, never two" do
      preview =
        transfers("""
        2024-08-12 10:00:00;Umbuchung (Ausgang);;;;1.000,00;;;1.000,00;Cash-A;Cash-B;;
        2024-08-12 10:00:00;Umbuchung (Ausgang);;;;1.000,00;;;1.000,00;Cash-A;Cash-B;;
        2024-08-12 10:00:00;Umbuchung (Eingang);;;;1.000,00;;;1.000,00;Cash-B;Cash-A;;
        2024-08-12 10:00:00;Umbuchung (Eingang);;;;1.000,00;;;1.000,00;Cash-B;Cash-A;;
        2024-08-12 10:00:00;Umbuchung (Eingang);;;;1.000,00;;;1.000,00;Cash-B;Cash-A;;
        """)

      assert Enum.map(preview.entries, & &1.source_row) == [1, 2, 5]
      assert [%{row: 3, message: first}, %{row: 4, message: second}] = preview.errors
      assert first =~ "row 1"
      assert second =~ "row 2"
    end

    # The closing act's review round (Sprint 18 C1): a file assembled from
    # two lists may write the same amount in two ways, and the converter's
    # security-transfer label is a sending row like PP's own.
    test "pairs the two sides whatever way each row writes the amount" do
      preview =
        transfers("""
        2024-08-12 10:00:00;Umbuchung (Ausgang);;;;1.000,00;;;1.000,00;Cash-A;Cash-B;;
        2024-08-12 10:00:00;Umbuchung (Eingang);;;;1000;;;1000;Cash-B;Cash-A;;
        """)

      assert %Preview{entries: [entry], errors: [%{row: 2, message: message}]} = preview
      assert entry.source_row == 1
      assert message =~ "row 1"
    end

    # ADR-0053: each side books its own Gesamtpreis, Betrag + U on the
    # sending row and Betrag − U on the receiving row, so the two sides of
    # one transfer carrying units pair on the file's Betrag, as before.
    test "pairs both sides of one cash transfer that carry fees and taxes" do
      preview =
        transfers("""
        2024-08-12 10:00:00;Umbuchung (Ausgang);;;;1.000,00;2,00;0,50;1.002,50;Cash-A;Cash-B;;
        2024-08-12 10:00:00;Umbuchung (Eingang);;;;1.000,00;2,00;0,50;997,50;Cash-B;Cash-A;;
        """)

      assert %Preview{entries: [entry], errors: [%{row: 2, message: message}]} = preview
      assert entry.source_row == 1
      assert direction(entry) == {"cash_transfer", nil, "Cash-A", nil, "Cash-B"}
      assert Decimal.equal?(entry.gross_amount, Decimal.new("1002.50"))
      assert message =~ "row 1"
    end

    test "pairs a receiving row with the converter's security-transfer row" do
      preview =
        transfers("""
        2024-11-15 21:00:00;Umbuchung (Wertpapier);Example Fund;3;20,00;60,00;;;60,00;Depot-A;Depot-B;;
        2024-11-15 21:00:00;Umbuchung (Eingang);Example Fund;3;20,00;60,00;;;60,00;Depot-B;Depot-A;;
        """)

      assert %Preview{entries: [entry], errors: [%{row: 2, message: message}]} = preview
      assert entry.source_row == 1
      assert direction(entry) == {"security_transfer", "Depot-A", nil, "Depot-B", nil}
      assert message =~ "row 1"
    end
  end
end
