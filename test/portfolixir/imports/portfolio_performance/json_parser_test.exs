defmodule Portfolixir.Imports.PortfolioPerformance.JsonParserTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance.JsonParser
  alias Portfolixir.Imports.Preview

  @fixtures Path.expand("../../../support/fixtures/portfolio_performance", __DIR__)

  defp read!(name), do: File.read!(Path.join(@fixtures, name))

  # User story:
  # As a local portfolio maintainer importing the JSON variant of my
  # Portfolio Performance "All Transactions" export,
  # I want each PP transaction type to map to the matching Portfolixir
  # ledger `kind` with monetary values preserved as `Decimal`,
  # so that the preview tells me exactly what the importer would create.

  describe "parse/2 happy path on the synthetic sample" do
    setup do
      {:ok, preview} = JsonParser.parse(read!("sample.json"), filename: "sample.json")
      {:ok, preview: preview}
    end

    test "produces a Preview tagged as :json with no errors", %{preview: preview} do
      assert %Preview{format: :json, errors: []} = preview
      assert length(preview.entries) == 13
    end

    test "maps PP transaction types to the 13 Portfolixir kinds", %{preview: preview} do
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

    # User story:
    # As a maintainer importing deliveries and security transfers (which move
    # shares but settle no cash), I want those entries to carry no gross_amount,
    # so a PP export that records them with amount 0 does not trip the
    # "gross_amount must be greater than 0" ledger validation (#482).
    test "delivery and transfer kinds carry no gross_amount", %{preview: preview} do
      for kind <- ["inbound_delivery", "outbound_delivery", "security_transfer"] do
        entry = Enum.find(preview.entries, &(&1.kind == kind))
        assert entry, "expected a #{kind} entry in the sample"
        assert entry.gross_amount == nil, "#{kind} should have nil gross_amount"
      end
    end

    # User story (ADR-0053 §3):
    # As the operator re-importing a JSON export,
    # I want the content hash to read the same amount it always read,
    # so that nothing imported before books twice.
    #
    # Acceptance criteria:
    # - Every entry's hash amount is its booked cash, the `amount` (nil
    #   where the kind settles no cash), so no JSON hash moves.
    test "the hash amount of every entry is the amount it books", %{preview: preview} do
      for entry <- preview.entries do
        assert entry.hash_amount == entry.gross_amount, "row #{entry.source_row}"
      end

      buy = Enum.find(preview.entries, &(&1.kind == "buy"))
      assert Decimal.equal?(buy.hash_amount, Decimal.new("1502.50"))
    end

    test "carries PP portfolio + account names through unchanged", %{preview: preview} do
      buy = Enum.find(preview.entries, &(&1.kind == "buy"))
      assert buy.pp_portfolio_name == "Test-Depot"
      assert buy.pp_account_name == "Test-Cash"

      transfer = Enum.find(preview.entries, &(&1.kind == "cash_transfer"))
      assert transfer.pp_account_name == "Test-Cash"
      assert transfer.pp_counter_account_name == "Test-Cash-2"

      sec_transfer = Enum.find(preview.entries, &(&1.kind == "security_transfer"))
      assert sec_transfer.pp_portfolio_name == "Test-Depot"
      assert sec_transfer.pp_counter_portfolio_name == "Test-Depot-2"
    end

    test "parses ISIN/WKN/ticker on the security ref", %{preview: preview} do
      buy = Enum.find(preview.entries, &(&1.kind == "buy"))
      assert buy.security.isin == "USEXMPL10014"
      assert buy.security.wkn == "ARBOL1"
      assert buy.security.ticker == "ARBL"
    end

    test "stores monetary values as Decimal and never as float", %{preview: preview} do
      buy = Enum.find(preview.entries, &(&1.kind == "buy"))
      assert %Decimal{} = buy.gross_amount
      assert Decimal.equal?(buy.gross_amount, Decimal.new("1502.50"))
      assert Decimal.equal?(buy.quantity, Decimal.new("10"))
      assert Decimal.equal?(buy.fees, Decimal.new("2.50"))
      assert is_nil(buy.taxes) or Decimal.equal?(buy.taxes, Decimal.new("0"))
    end

    test "derives a per-share price for buys (net of fees+taxes)", %{preview: preview} do
      buy = Enum.find(preview.entries, &(&1.kind == "buy"))
      # (1502.50 - 2.50) / 10 = 150.00
      assert Decimal.equal?(buy.price, Decimal.new("150.00"))
    end

    test "derives a per-share price for sells (gross of fees+taxes)", %{preview: preview} do
      sale = Enum.find(preview.entries, &(&1.kind == "sell"))
      # (1800.00 + 2.50 + 12.00) / 10 = 181.45
      assert Decimal.equal?(sale.price, Decimal.new("181.45"))
    end

    test "leaves price nil for non-trade kinds", %{preview: preview} do
      for kind <- ~w(dividend interest deposit removal fee tax tax_refund cash_transfer
                     inbound_delivery outbound_delivery security_transfer) do
        entry = Enum.find(preview.entries, &(&1.kind == kind))
        assert is_nil(entry.price), "#{kind} should have nil price"
      end
    end

    test "sums fee and tax units separately", %{preview: preview} do
      sale = Enum.find(preview.entries, &(&1.kind == "sell"))
      assert Decimal.equal?(sale.fees, Decimal.new("2.50"))
      assert Decimal.equal?(sale.taxes, Decimal.new("12.00"))

      dividend = Enum.find(preview.entries, &(&1.kind == "dividend"))
      assert Decimal.equal?(dividend.taxes, Decimal.new("2.41"))
    end

    test "carries the optional time when present, nil otherwise", %{preview: preview} do
      buy = Enum.find(preview.entries, &(&1.kind == "buy"))
      assert buy.time == ~T[10:01:00]

      deposit = Enum.find(preview.entries, &(&1.kind == "deposit"))
      assert is_nil(deposit.time)
    end
  end

  describe "parse/2 negative TAX units" do
    setup do
      {:ok, preview} =
        JsonParser.parse(read!("sample_with_negative_tax.json"),
          filename: "sample_with_negative_tax.json"
        )

      {:ok, preview: preview}
    end

    test "the parent dividend keeps abs() of the positive taxes only", %{preview: preview} do
      [parent] = preview.entries
      assert parent.kind == "dividend"
      assert Decimal.equal?(parent.taxes, Decimal.new("27.00"))
      assert Decimal.compare(parent.taxes, 0) != :lt
    end

    test "a tax_refund companion is emitted for each negative TAX unit", %{preview: preview} do
      [parent] = preview.entries
      assert [%Entry{kind: "tax_refund"} = refund] = parent.companion_entries
      assert Decimal.equal?(refund.gross_amount, Decimal.new("0.01"))
      assert Decimal.equal?(refund.hash_amount, Decimal.new("0.01"))
      assert refund.security == parent.security
      assert refund.pp_account_name == parent.pp_account_name
      assert refund.date == parent.date
    end

    test "companion source_row is derived from the parent row for traceability", %{
      preview: preview
    } do
      [parent] = preview.entries
      [refund] = parent.companion_entries
      assert is_binary(refund.source_row)
      assert refund.source_row =~ ".tax_refund."
    end
  end

  describe "parse/2 error paths" do
    test "rejects an unsupported PP version" do
      body = read!("invalid_version.json")
      assert {:error, {:unsupported_version, 99}} = JsonParser.parse(body)
    end

    test "captures unknown PP types as row-level errors rather than crashing" do
      body = read!("unknown_kind.json")
      assert {:ok, %Preview{entries: [], errors: errors}} = JsonParser.parse(body)
      assert [%{row: 1, message: message}] = errors
      assert message =~ "MYSTERY_KIND"
    end

    # The parser-warning body is app-generated prose (not raw PP passthrough),
    # so it is routed through gettext and localized; the interpolated PP type
    # is kept verbatim as data.
    test "localizes the app-generated unknown-type warning while keeping the PP type" do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")

      body = read!("unknown_kind.json")
      assert {:ok, %Preview{errors: [%{message: message}]}} = JsonParser.parse(body)
      assert message =~ "Unbekannter PP-Transaktionstyp"
      assert message =~ "MYSTERY_KIND"
    end

    test "reports invalid JSON" do
      assert {:error, {:invalid_json, _}} = JsonParser.parse("{not-json")
    end

    # User story:
    # As a local portfolio maintainer with a date typo in my PP export
    # (e.g. "0219-03-07" instead of 2019-03-07),
    # I want the row rejected with a clear per-row error,
    # so that one bad booking cannot poison every derived metric and I can
    # fix the source and re-import idempotently.
    test "rejects bookings with implausible dates (before 1900) per row" do
      body =
        Jason.encode!(%{
          version: 1,
          transactions: [
            %{
              type: "REMOVAL",
              account: "Girokonto",
              date: "0219-03-07",
              currency: "EUR",
              amount: 250.0
            }
          ]
        })

      assert {:ok, %Preview{entries: [], errors: [%{row: 1, message: message}]}} =
               JsonParser.parse(body)

      assert message =~ "implausible date 0219-03-07"
      assert message =~ "re-import"
    end

    # E25 S4, F70: the ledger refuses a date past its bounded range, so the
    # parser names the row instead of letting the apply fail on it.
    test "rejects bookings dated past the ledger's range per row" do
      body =
        Jason.encode!(%{
          version: 1,
          transactions: [
            %{
              type: "REMOVAL",
              account: "Girokonto",
              date: "3019-03-07",
              currency: "EUR",
              amount: 250.0
            }
          ]
        })

      assert {:ok, %Preview{entries: [], errors: [%{row: 1, message: message}]}} =
               JsonParser.parse(body)

      assert message =~ "implausible date 3019-03-07"
      assert message =~ "re-import"
    end

    # Acceptance criteria (E25 S4, G24): a name or note the ledger cannot
    # store is the row's error, naming the field.
    test "names the row whose text the ledger cannot store" do
      deposit = fn overrides ->
        Map.merge(
          %{
            type: "DEPOSIT",
            account: "Girokonto",
            date: "2026-03-07",
            currency: "EUR",
            amount: 250.0
          },
          overrides
        )
      end

      body =
        Jason.encode!(%{
          version: 1,
          transactions: [
            deposit.(%{security: %{name: String.duplicate("a", 256), currency: "EUR"}}),
            deposit.(%{portfolio: "Depot\u0000A"}),
            deposit.(%{note: "broken\u0000note"}),
            deposit.(%{})
          ]
        })

      assert {:ok, %Preview{entries: [entry], errors: errors}} = JsonParser.parse(body)
      assert entry.source_row == 4

      assert [%{row: 1, message: first}, %{row: 2, message: second}, %{row: 3, message: third}] =
               errors

      assert first =~ "security name"
      assert second =~ "portfolio"
      assert third =~ "note"
    end
  end

  # User story (#948):
  # As an operator importing a Portfolio Performance JSON export whose
  # currency codes are not all ones Portfolixir knows,
  # I want each such row named in the preview and left out,
  # so that a stray code neither fails the whole file after I confirm nor
  # creates an account in a currency nobody can value.
  #
  # Acceptance criteria (board ux-design-2026-10-04/09-import-correction):
  # - A booking currency outside the catalog's list ("EURO", "XEU") is the row
  #   error "currency “EURO” is not supported — row not imported", the value
  #   quoted as the file wrote it, upper-cased; the rest of the file previews.
  # - A currency that is present but not a string is a row error naming the
  #   value as written. An absent currency keeps today's default.
  # - A security currency outside the list is the row error "security
  #   currency “XEU” is not supported — row not imported", on every row that
  #   names that security.
  # - A lower-case code is normalised and accepted, as today.
  # - The German messages read "Währung „EURO“ wird nicht unterstützt — Zeile
  #   nicht übernommen" and "Wertpapierwährung „XEU“ wird nicht unterstützt —
  #   Zeile nicht übernommen".
  describe "parse/2 currency codes (#948)" do
    defp deposit(overrides) do
      Map.merge(
        %{
          "type" => "DEPOSIT",
          "account" => "Girokonto",
          "date" => "2026-03-07",
          "currency" => "EUR",
          "amount" => "250.00"
        },
        overrides
      )
    end

    defp purchase(security) do
      %{
        "type" => "PURCHASE",
        "account" => "Girokonto",
        "portfolio" => "Depot",
        "date" => "2026-03-09",
        "currency" => "EUR",
        "amount" => "100.00",
        "shares" => "2",
        "security" => Map.merge(%{"name" => "Example Fund", "isin" => nil}, security)
      }
    end

    defp parse_rows(rows) do
      JsonParser.parse(Jason.encode!(%{"version" => 1, "transactions" => rows}))
    end

    test "a booking currency the catalog does not list is a row error; the rest previews" do
      assert {:ok, %Preview{entries: [entry], errors: errors}} =
               parse_rows([
                 deposit(%{"currency" => "EURO"}),
                 deposit(%{}),
                 deposit(%{"currency" => " xeu "})
               ])

      assert entry.source_row == 2

      assert errors == [
               %{row: 1, message: "currency “EURO” is not supported — row not imported"},
               %{row: 3, message: "currency “XEU” is not supported — row not imported"}
             ]
    end

    test "a currency that is present but not a string is a row error naming the value" do
      assert {:ok, %Preview{entries: [_sound], errors: errors}} =
               parse_rows([
                 deposit(%{"currency" => 42}),
                 deposit(%{}),
                 deposit(%{"currency" => true})
               ])

      assert errors == [
               %{row: 1, message: "currency “42” is not supported — row not imported"},
               %{row: 3, message: "currency “true” is not supported — row not imported"}
             ]
    end

    test "an absent currency keeps today's default, and a lower-case code is accepted" do
      assert {:ok, %Preview{errors: [], entries: [absent, null, lower]}} =
               parse_rows([
                 Map.delete(deposit(%{}), "currency"),
                 deposit(%{"currency" => nil}),
                 deposit(%{"currency" => "usd"})
               ])

      assert absent.currency_code == nil
      assert null.currency_code == nil
      assert lower.currency_code == "USD"
    end

    test "a security currency the catalog does not list fails every row naming that security" do
      assert {:ok, %Preview{entries: entries, errors: errors}} =
               parse_rows([
                 purchase(%{"currency" => "XEU"}),
                 deposit(%{}),
                 purchase(%{"currency" => "XEU"}),
                 purchase(%{"name" => "Other Fund", "currency" => "usd"}),
                 purchase(%{"name" => "Third Fund", "currency" => 7})
               ])

      assert Enum.map(entries, & &1.source_row) == [2, 4]
      assert Enum.at(entries, 1).security.currency == "USD"

      assert errors == [
               %{row: 1, message: "security currency “XEU” is not supported — row not imported"},
               %{row: 3, message: "security currency “XEU” is not supported — row not imported"},
               %{row: 5, message: "security currency “7” is not supported — row not imported"}
             ]
    end

    # A blank currency, the booking's or the security's, reads as absent, as
    # the matching's normal form reads it and as the handbook says.
    test "an absent or blank currency keeps today's default" do
      assert {:ok, %Preview{errors: [], entries: [absent, blank, blank_booking]}} =
               parse_rows([
                 purchase(%{}),
                 purchase(%{"currency" => "  "}),
                 deposit(%{"currency" => "  "})
               ])

      assert absent.security.currency == nil
      assert blank.security.currency == nil
      assert blank_booking.currency_code == nil
    end

    # The value is named as the file wrote it, on one line and at most 40
    # characters long: a cut is marked, a character the operator cannot see or
    # that would break the line is spelled out, a number keeps its digits (in
    # scientific notation when its exponent alone would outrun the cap) and a
    # nested value reads as compact JSON, its numbers with their digits too.
    test "names an unsupported currency as written, spelled out and capped" do
      long = String.duplicate("X", 45)
      digits = String.duplicate("9", 1000)

      body = """
      {"version": 1, "transactions": [
        #{raw_deposit(~s("1.50"))},
        #{raw_deposit("1.50")},
        #{raw_deposit(~s("EU\\nR"))},
        #{raw_deposit(~s("EU\\u200bR"))},
        #{raw_deposit(~s("#{long}"))},
        #{raw_deposit(digits)},
        #{raw_deposit(~s({"code": [1, "EUR"]}))},
        #{raw_deposit("1.5e100")},
        #{raw_deposit("[1.50]")}
      ]}
      """

      assert {:ok, %Preview{entries: [], errors: errors}} = JsonParser.parse(body)

      shown =
        Enum.map(errors, fn %{message: message} ->
          [_, value] =
            Regex.run(~r/^currency “(.*)” is not supported — row not imported$/, message)

          value
        end)

      assert shown == [
               "1.50",
               "1.50",
               "EU[U+000A]R",
               "EU[U+200B]R",
               String.duplicate("X", 40) <> "…",
               String.duplicate("9", 40) <> "…",
               ~s({"code":[1,"EUR"]}),
               "1.5E+100",
               "[1.50]"
             ]
    end

    defp raw_deposit(currency) do
      ~s({"type": "DEPOSIT", "account": "Girokonto", "date": "2026-03-07", ) <>
        ~s("amount": "250.00", "currency": #{currency}})
    end

    test "names both currency refusals in German" do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")

      assert {:ok, %Preview{errors: [booking, security]}} =
               parse_rows([deposit(%{"currency" => "EURO"}), purchase(%{"currency" => "XEU"})])

      assert booking.message == "Währung „EURO“ wird nicht unterstützt — Zeile nicht übernommen"

      assert security.message ==
               "Wertpapierwährung „XEU“ wird nicht unterstützt — Zeile nicht übernommen"
    end
  end

  # User story (#1044, the JSON side):
  # As an operator importing a Portfolio Performance JSON export that holds a
  # transfer without its other side,
  # I want that row named in the preview and left out,
  # so that one incomplete row never fails the whole file after I confirm.
  #
  # Acceptance criteria:
  # - A CASH_TRANSFER without `otherAccount`, and a SECURITY_TRANSFER without
  #   `otherPortfolio`, blank or absent, is the row error "transfer without a
  #   counter account — row not imported"; the rest of the file previews.
  test "a transfer without its counter account or depot is a row error" do
    transfer = fn type, overrides ->
      Map.merge(
        %{
          "type" => type,
          "date" => "2026-03-07",
          "currency" => "EUR",
          "amount" => "100.00"
        },
        overrides
      )
    end

    body =
      Jason.encode!(%{
        "version" => 1,
        "transactions" => [
          transfer.("CASH_TRANSFER", %{"account" => "Giro"}),
          transfer.("CASH_TRANSFER", %{"account" => "Giro", "otherAccount" => "  "}),
          transfer.("SECURITY_TRANSFER", %{
            "portfolio" => "Depot-A",
            "shares" => "2",
            "security" => %{"name" => "Example Fund", "currency" => "EUR"}
          }),
          transfer.("CASH_TRANSFER", %{"account" => "Giro", "otherAccount" => "Tagesgeld"})
        ]
      })

    assert {:ok, %Preview{entries: [entry], errors: errors}} = JsonParser.parse(body)
    assert entry.source_row == 4

    assert Enum.map(errors, &{&1.row, &1.message}) == [
             {1, "transfer without a counter account — row not imported"},
             {2, "transfer without a counter account — row not imported"},
             {3, "transfer without a counter account — row not imported"}
           ]
  end

  test "an entry struct exposes the expected fields" do
    {:ok, %Preview{entries: [first | _]}} = JsonParser.parse(read!("sample.json"))
    assert %Entry{kind: "buy", source_row: 1} = first
  end
end
