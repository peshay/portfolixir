defmodule Portfolixir.Imports.PortfolioPerformance.JsonParserTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.ImportHash
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

    # ADR-0053 A1 (the amendment of 2026-10-07): PP's `amount` already
    # holds the refund, so the parent credits it less the refund, and the
    # two together book the `amount`, which the hash keeps reading.
    test "the parent dividend books its amount less the refund split off it", %{
      preview: preview
    } do
      [parent] = preview.entries
      [refund] = parent.companion_entries

      assert Decimal.equal?(parent.gross_amount, Decimal.new("181.48"))
      assert Decimal.equal?(parent.hash_amount, Decimal.new("181.49"))

      assert Decimal.equal?(
               Decimal.add(parent.gross_amount, refund.gross_amount),
               Decimal.new("181.49")
             )
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

  # User story (ADR-0053 A3, K10; risk-tier: idempotency):
  # As the operator who imported a Portfolio Performance JSON export whose
  # sale carries a negative tax unit,
  # I want that sale's content hash to keep reading the price it read when it
  # was imported,
  # so that dropping the export again finds it, whatever price it now books.
  #
  # Acceptance criteria:
  # - A purchase or sale with a negative TAX unit carries, as its hash price,
  #   the price derived from its `amount`, its fees and its positive taxes:
  #   the synthetic sale (amount 120.0, 10 shares, FEE 5.0, TAX -25.0) carries
  #   12.5, written as the hash wrote it before.
  # - A row without a negative TAX unit, and a kind without a price, carries
  #   none, so its hash reads its price as before.
  describe "parse/2 a trade with a negative TAX unit" do
    setup do
      {:ok, preview} =
        JsonParser.parse(read!("sale_with_negative_tax.json"),
          filename: "sale_with_negative_tax.json"
        )

      {:ok, preview: preview}
    end

    test "carries the price derived before the amendment as its hash price", %{
      preview: preview
    } do
      assert %Preview{errors: []} = preview
      [deposit, purchase, sale] = preview.entries

      assert %Decimal{} = sale.hash_price
      assert Decimal.to_string(sale.hash_price, :normal) == "12.5"
      assert purchase.hash_price == nil
      assert deposit.hash_price == nil
    end

    # ADR-0053 A1: a sale credits its `amount` less the refund, a purchase
    # debits its `amount` plus the refund, so each row's bookings net to its
    # `amount`, PP's cash; the hash keeps reading the `amount`.
    test "the parent books its amount less the refund on a sale, plus it on a purchase", %{
      preview: preview
    } do
      [_deposit, purchase, sale] = preview.entries

      assert [refund] = sale.companion_entries
      assert Decimal.equal?(sale.gross_amount, Decimal.new("95.00"))
      assert Decimal.equal?(refund.gross_amount, Decimal.new("25.00"))
      assert Decimal.equal?(sale.hash_amount, Decimal.new("120.00"))
      assert Decimal.equal?(purchase.gross_amount, Decimal.new("100.00"))

      body =
        Jason.encode!(%{
          version: 1,
          transactions: [
            %{
              type: "PURCHASE",
              account: "Test-Cash",
              portfolio: "Test-Depot",
              date: "2024-01-15",
              currency: "EUR",
              amount: Jason.Fragment.new("1001.5"),
              shares: Jason.Fragment.new("10.0"),
              security: %{name: "Synthetic AG", currency: "EUR"},
              units: [
                %{type: "FEE", amount: Jason.Fragment.new("2.5")},
                %{type: "TAX", amount: Jason.Fragment.new("-1.0")}
              ]
            }
          ]
        })

      assert {:ok, %Preview{errors: [], entries: [buy]}} = JsonParser.parse(body)
      assert [buy_refund] = buy.companion_entries
      assert Decimal.equal?(buy.gross_amount, Decimal.new("1002.50"))
      assert Decimal.equal?(buy_refund.gross_amount, Decimal.new("1.00"))
      assert Decimal.equal?(buy.hash_amount, Decimal.new("1001.50"))
    end

    # ADR-0053 A2: the price comes from the gross value, as Portfolio
    # Performance derives it (PortfolioTransaction.getGrossValueAmount):
    # a sale's (amount + fees + signed taxes) / shares, a purchase's
    # (amount - fees - signed taxes) / shares. The hash keeps the old one.
    test "prices a trade from its gross value, its negative tax with its sign", %{
      preview: preview
    } do
      [_deposit, purchase, sale] = preview.entries

      # (120.0 + 5.0 - 25.0) / 10.0; before the amendment (120.0 + 5.0) / 10.0.
      assert Decimal.equal?(sale.price, Decimal.new("10.00"))
      assert Decimal.equal?(sale.hash_price, Decimal.new("12.50"))
      assert Decimal.equal?(purchase.price, Decimal.new("10.00"))

      body =
        Jason.encode!(%{
          version: 1,
          transactions: [
            %{
              type: "PURCHASE",
              account: "Test-Cash",
              portfolio: "Test-Depot",
              date: "2024-01-15",
              currency: "EUR",
              amount: Jason.Fragment.new("1001.5"),
              shares: Jason.Fragment.new("10.0"),
              security: %{name: "Synthetic AG", currency: "EUR"},
              units: [
                %{type: "FEE", amount: Jason.Fragment.new("2.5")},
                %{type: "TAX", amount: Jason.Fragment.new("-1.0")}
              ]
            }
          ]
        })

      # (1001.5 - 2.5 - (-1.0)) / 10.0; before the amendment
      # (1001.5 - 2.5) / 10.0 = 99.9.
      assert {:ok, %Preview{errors: [], entries: [buy]}} = JsonParser.parse(body)
      assert Decimal.equal?(buy.price, Decimal.new("100.00"))
      assert Decimal.equal?(buy.hash_price, Decimal.new("99.90"))
    end
  end

  # User story (ADR-0053 A5, K14, #1118; risk-tier: money):
  # As the operator dropping a JSON export whose sale's own booking would
  # credit nothing or less, because the tax refund split off it is larger
  # than the cash it moved, or because the cash itself is nothing,
  # I want that row named in the preview with what to do instead, in the
  # page's notation, while the rest of the file previews,
  # so that the sale is never silently skipped at apply.
  #
  # Acceptance criteria (board ux-design-2026-10-07/01-import-preview ③;
  # the α closing act, UAT persona):
  # - A sale whose `amount` less its split-off refunds is 0 or less is a
  #   row error in the board's sentence, its `amount` named as the board
  #   names the cash, "Gesamtpreis", and every figure to the cent in the
  #   reader's notation: "sell with Gesamtpreis 20.10 and a tax refund of
  #   25.00: -4.90 would remain for the sale — row not imported. Book the
  #   sale by hand, and the refund as a tax refund of its own."
  # - Without a refund, a credit whose `amount` is 0 or less: "… nothing
  #   would remain for …"; a credit other than a sale is "the booking".
  # - In German the figures read "20,10", "25,00", "-4,90".
  # - The file's other rows preview, with the content hash each has without
  #   the refused row; a debit row is not refused.
  describe "parse/2 a credit row that nets to nothing (#1118)" do
    defp tx(fields) do
      Map.merge(
        %{
          type: "SALE",
          account: "Test-Cash",
          portfolio: "Test-Depot",
          date: "2024-06-14",
          currency: "EUR",
          shares: Jason.Fragment.new("100.0"),
          security: %{name: "Synthetic AG", currency: "EUR"}
        },
        fields
      )
    end

    defp deposit do
      %{
        type: "DEPOSIT",
        account: "Test-Cash",
        date: "2024-01-02",
        currency: "EUR",
        amount: Jason.Fragment.new("1000.0")
      }
    end

    defp unit(type, amount), do: %{type: type, amount: Jason.Fragment.new(amount)}

    defp nominal_sale do
      tx(%{
        amount: Jason.Fragment.new("20.1"),
        units: [unit("FEE", "5.9"), unit("TAX", "-25.0")]
      })
    end

    test "a sale whose refund exceeds its amount is named, and the rest previews" do
      body = Jason.encode!(%{version: 1, transactions: [deposit(), nominal_sale()]})

      assert {:ok, %Preview{entries: [kept], errors: [%{row: 2, message: message}]}} =
               JsonParser.parse(body)

      assert message ==
               "sell with Gesamtpreis 20.10 and a tax refund of 25.00: -4.90 would remain " <>
                 "for the sale — row not imported. Book the sale by hand, and the refund as " <>
                 "a tax refund of its own."

      {:ok, %Preview{entries: [alone]}} =
        JsonParser.parse(Jason.encode!(%{version: 1, transactions: [deposit()]}))

      assert ImportHash.compute(kept, 42) == ImportHash.compute(alone, 42)
    end

    test "a credit whose amount is nothing or less is named, a refund split off or not" do
      body =
        Jason.encode!(%{
          version: 1,
          transactions: [
            tx(%{type: "DIVIDEND", amount: Jason.Fragment.new("0.00")}),
            tx(%{amount: Jason.Fragment.new("25.0"), units: [unit("TAX", "-25.0")]}),
            tx(%{type: "TAX", amount: Jason.Fragment.new("1.0"), units: [unit("TAX", "-1.0")]}),
            tx(%{amount: Jason.Fragment.new("-1234.5")})
          ]
        })

      assert {:ok, %Preview{entries: [debit], errors: errors}} = JsonParser.parse(body)
      assert debit.kind == "tax"

      assert errors == [
               %{
                 row: 1,
                 message:
                   "booking with Gesamtpreis 0.00: nothing would remain for the booking — " <>
                     "row not imported. Enter the booking by hand."
               },
               %{
                 row: 2,
                 message:
                   "sell with Gesamtpreis 25.00 and a tax refund of 25.00: 0.00 would remain " <>
                     "for the sale — row not imported. Book the sale by hand, and the refund " <>
                     "as a tax refund of its own."
               },
               %{
                 row: 4,
                 message:
                   "sell with Gesamtpreis -1,234.50: nothing would remain for the sale — " <>
                     "row not imported. Book the sale by hand."
               }
             ]
    end

    test "says it in German, its figures in the German notation" do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")

      body =
        Jason.encode!(%{
          version: 1,
          transactions: [
            nominal_sale(),
            tx(%{type: "INTEREST", amount: Jason.Fragment.new("1.5"), units: [unit("TAX", "-2")]})
          ]
        })

      assert {:ok, %Preview{errors: errors}} = JsonParser.parse(body)

      assert Enum.map(errors, & &1.message) == [
               "Verkauf mit Gesamtpreis 20,10 und Steuererstattung 25,00: Dem Verkauf " <>
                 "blieben -4,90 — Zeile nicht übernommen. Den Verkauf von Hand buchen, die " <>
                 "Erstattung als eigene Steuererstattung.",
               "Buchung mit Gesamtpreis 1,50 und Steuererstattung 2,00: Der Buchung " <>
                 "blieben -0,50 — Zeile nicht übernommen. Die Buchung von Hand erfassen, " <>
                 "die Erstattung als eigene Steuererstattung."
             ]
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

  # User story (#1188, #1177; Sprint 21 α5; ADR-0053 A8 and A9, K16 to K18):
  # As the operator dropping a Portfolio Performance JSON export whose
  # delivery or transfer carries a tax refund, or whose booking carries a
  # negative fee unit,
  # I want that row named in the preview with its remedy, and the rest of
  # the file to preview,
  # so that one row the ledger cannot carry never rolls back the whole file,
  # books a refund on an account Portfolio Performance never moved, or
  # stores a fee refund as a fee.
  #
  # Acceptance criteria (board ux-design-2026-10-09/07-imports ③):
  # - K16: of a deposit, an inbound delivery with a TAX unit of -0.40 and a
  #   purchase, the delivery is the one row error, "inbound delivery with a
  #   tax refund of 0.40: an inbound delivery moves no cash, so the refund
  #   would have no account — row not imported. Book the inbound delivery
  #   by hand without it; if money did move, book that as a tax refund of
  #   its own."; the deposit and the purchase preview.
  # - An outbound delivery and a security transfer read the same, each in
  #   its own words.
  # - K17: a cash transfer with a TAX unit of -5.00 is the row error
  #   "transfer with a tax refund of 5.00: a transfer moves cash between two
  #   accounts, and a refund split off it would land on one side only — row
  #   not imported. …"; the deposit previews.
  # - K18: a purchase with FEE units 5.00 and -2.00 is the row error
  #   "booking with a negative fee (-2.00): the import does not book a fee
  #   refund yet — row not imported. Enter the booking by hand, with its
  #   fees less the refund (3.00)."; a sale reads "sell … Book the sale by
  #   hand …". It is named before A8's and A5's refusals.
  # - The preview keeps each refused row's would-be entry as it is built
  #   today, its split-off refund and its fees of 7.00 included, so its
  #   content hash does not move (K25).
  # - In German, with the figures in the German notation.
  describe "parse/2 a refund or a fee refund the row cannot carry (#1188, #1177)" do
    test "K16: a delivery with a negative tax unit is a row error, and the rest previews" do
      assert {:ok, %Preview{entries: [deposit, buy], errors: errors, refused_credits: refused}} =
               JsonParser.parse(read!("k16_delivery_negative_tax.json"))

      assert {deposit.source_row, deposit.kind, buy.source_row, buy.kind} ==
               {1, "deposit", 3, "buy"}

      assert errors == [
               %{
                 row: 2,
                 message:
                   "inbound delivery with a tax refund of 0.40: an inbound delivery moves no " <>
                     "cash, so the refund would have no account — row not imported. Book the " <>
                     "inbound delivery by hand without it; if money did move, book that as a " <>
                     "tax refund of its own."
               }
             ]

      assert [%{row: 2, entry: %Entry{kind: "inbound_delivery"} = delivery}] = refused
      assert [%Entry{kind: "tax_refund", gross_amount: refund}] = delivery.companion_entries
      assert Decimal.equal?(refund, Decimal.new("0.40"))
    end

    test "an outbound delivery and a security transfer are named in their own words" do
      body =
        Jason.encode!(%{
          version: 1,
          transactions: [
            delivery("OUTBOUND_DELIVERY", %{}),
            delivery("SECURITY_TRANSFER", %{otherPortfolio: "Test-Depot-2"})
          ]
        })

      assert {:ok, %Preview{entries: [], errors: errors, refused_credits: [_, _]}} =
               JsonParser.parse(body)

      assert Enum.map(errors, & &1.message) == [
               "outbound delivery with a tax refund of 0.40: an outbound delivery moves no " <>
                 "cash, so the refund would have no account — row not imported. Book the " <>
                 "outbound delivery by hand without it; if money did move, book that as a " <>
                 "tax refund of its own.",
               "security transfer with a tax refund of 0.40: a security transfer moves no " <>
                 "cash, so the refund would have no account — row not imported. Book the " <>
                 "security transfer by hand without it; if money did move, book that as a " <>
                 "tax refund of its own."
             ]
    end

    test "K17: a cash transfer with a negative tax unit is a row error, and the deposit previews" do
      assert {:ok, %Preview{entries: [deposit], errors: errors, refused_credits: refused}} =
               JsonParser.parse(read!("k17_transfer_negative_tax.json"))

      assert deposit.kind == "deposit"

      assert errors == [
               %{
                 row: 2,
                 message:
                   "transfer with a tax refund of 5.00: a transfer moves cash between two " <>
                     "accounts, and a refund split off it would land on one side only — row " <>
                     "not imported. Book the transfer by hand without it; if money did move, " <>
                     "book that as a tax refund of its own."
               }
             ]

      # The would-be entry as Sprint 20 booked it: the transfer at 105.00,
      # the refund 5.00 beside it (K20 reads it).
      assert [%{row: 2, entry: %Entry{kind: "cash_transfer"} = transfer}] = refused
      assert Decimal.equal?(transfer.gross_amount, Decimal.new("105.00"))
      assert [%Entry{kind: "tax_refund", gross_amount: refund}] = transfer.companion_entries
      assert Decimal.equal?(refund, Decimal.new("5.00"))
    end

    test "K18: a negative FEE unit is a row error, its would-be entry keeping the fees its hash reads" do
      assert {:ok, %Preview{entries: [deposit], errors: errors, refused_credits: refused}} =
               JsonParser.parse(read!("k18_negative_fee.json"))

      assert deposit.kind == "deposit"

      assert errors == [
               %{
                 row: 2,
                 message:
                   "booking with a negative fee (-2.00): the import does not book a fee " <>
                     "refund yet — row not imported. Enter the booking by hand, with its fees " <>
                     "less the refund (3.00)."
               }
             ]

      assert [%{row: 2, entry: %Entry{kind: "buy"} = buy}] = refused
      assert Decimal.equal?(buy.fees, Decimal.new("7.00"))
      assert Decimal.equal?(buy.price, Decimal.new("99.60"))
      assert Decimal.equal?(buy.gross_amount, Decimal.new("1003.00"))
    end

    test "a negative FEE unit is named first, before a refund the row cannot carry" do
      fee_refund = [unit("FEE", "4.90"), unit("FEE", "-1.90"), unit("TAX", "-25.0")]

      body =
        Jason.encode!(%{
          version: 1,
          transactions: [
            tx(%{amount: Jason.Fragment.new("20.1"), units: fee_refund}),
            delivery("INBOUND_DELIVERY", %{units: [unit("FEE", "-1.90"), unit("TAX", "-0.40")]})
          ]
        })

      assert {:ok, %Preview{entries: [], errors: errors}} = JsonParser.parse(body)

      assert Enum.map(errors, & &1.message) == [
               "sell with a negative fee (-1.90): the import does not book a fee refund " <>
                 "yet — row not imported. Book the sale by hand, with its fees less the " <>
                 "refund (3.00).",
               "booking with a negative fee (-1.90): the import does not book a fee refund " <>
                 "yet — row not imported. Enter the booking by hand without a fee."
             ]
    end

    # User story (#1177's negative FEE unit, Sprint 21 α5 review S1; ADR-0053
    # A9; #1188): As the operator whose row refunds more fee than it charges,
    # I want the remedy to name what to enter in the booking drawer,
    # so that I never try to book a negative fee, which the ledger refuses,
    # and the booking I enter moves the cash Portfolio Performance shows.
    #
    # Acceptance criteria:
    # - A purchase of 10 with FEE units 1.00 and -2.00 (net -1.00) and
    #   `amount` 1,003.00 (Portfolio Performance's price 100.40): the drawer
    #   books quantity × price without a fee, so the remedy names the price
    #   that books 1,003.00: "booking with a negative fee (-2.00): … — row
    #   not imported. Enter the booking by hand without a fee, at the price
    #   100.30 (Gesamtpreis 1,003.00 ÷ 10)."; a sale of 100 at 20.10 reads
    #   "Book the sale by hand without a fee, at the price 0.201 (Gesamtpreis
    #   20.10 ÷ 100)."
    # - A sale of a USD security through the EUR account (the drawer asks
    #   its settlement amount): "Book the sale by hand without a fee, with
    #   the settlement amount 20.10 (the Gesamtpreis Portfolio Performance
    #   shows)."
    # - A dividend (the drawer asks its cash) keeps "Enter the booking by
    #   hand at the cash Portfolio Performance shows, Gesamtpreis 20.10,
    #   without a fee."
    # - A row that moves no cash (a delivery) reads "… by hand without a
    #   fee."
    # - A net of zero or above keeps "with its fees less the refund (…)".
    # - In German: "… Die Buchung von Hand ohne Gebühr erfassen, zum Kurs
    #   100,30 (Gesamtpreis 1.003,00 ÷ 10)."
    test "a fee refund larger than the fees names what to enter, never a negative fee" do
      over = [unit("FEE", "1.00"), unit("FEE", "-2.00")]

      body =
        Jason.encode!(%{
          version: 1,
          transactions: [
            tx(%{
              type: "PURCHASE",
              amount: Jason.Fragment.new("1003.00"),
              shares: Jason.Fragment.new("10"),
              units: over
            }),
            tx(%{amount: Jason.Fragment.new("20.10"), units: over}),
            tx(%{
              amount: Jason.Fragment.new("20.10"),
              units: [unit("FEE", "2"), unit("FEE", "-2")]
            }),
            tx(%{
              amount: Jason.Fragment.new("20.10"),
              security: %{name: "Synthetic Corp", currency: "USD"},
              units: over
            }),
            tx(%{type: "DIVIDEND", amount: Jason.Fragment.new("20.10"), units: over})
          ]
        })

      assert {:ok, %Preview{entries: [], errors: errors}} = JsonParser.parse(body)

      assert Enum.map(errors, & &1.message) == [
               "booking with a negative fee (-2.00): the import does not book a fee refund " <>
                 "yet — row not imported. Enter the booking by hand without a fee, at the " <>
                 "price 100.30 (Gesamtpreis 1,003.00 ÷ 10).",
               "sell with a negative fee (-2.00): the import does not book a fee refund yet " <>
                 "— row not imported. Book the sale by hand without a fee, at the price " <>
                 "0.201 (Gesamtpreis 20.10 ÷ 100).",
               "sell with a negative fee (-2.00): the import does not book a fee refund yet " <>
                 "— row not imported. Book the sale by hand, with its fees less the refund " <>
                 "(0.00).",
               "sell with a negative fee (-2.00): the import does not book a fee refund yet " <>
                 "— row not imported. Book the sale by hand without a fee, with the " <>
                 "settlement amount 20.10 (the Gesamtpreis Portfolio Performance shows).",
               "booking with a negative fee (-2.00): the import does not book a fee refund " <>
                 "yet — row not imported. Enter the booking by hand at the cash Portfolio " <>
                 "Performance shows, Gesamtpreis 20.10, without a fee."
             ]

      Gettext.put_locale(PortfolixirWeb.Gettext, "de")
      assert {:ok, %Preview{errors: errors}} = JsonParser.parse(body)

      assert Enum.map(errors, & &1.message) |> Enum.take(4) == [
               "Buchung mit einer negativen Gebühr (-2,00): Eine Gebührenerstattung bucht der " <>
                 "Import noch nicht — Zeile nicht übernommen. Die Buchung von Hand ohne Gebühr " <>
                 "erfassen, zum Kurs 100,30 (Gesamtpreis 1.003,00 ÷ 10).",
               "Verkauf mit einer negativen Gebühr (-2,00): Eine Gebührenerstattung bucht der " <>
                 "Import noch nicht — Zeile nicht übernommen. Den Verkauf von Hand ohne Gebühr " <>
                 "buchen, zum Kurs 0,201 (Gesamtpreis 20,10 ÷ 100).",
               "Verkauf mit einer negativen Gebühr (-2,00): Eine Gebührenerstattung bucht der " <>
                 "Import noch nicht — Zeile nicht übernommen. Den Verkauf von Hand buchen, mit " <>
                 "den Gebühren abzüglich der Erstattung (0,00).",
               "Verkauf mit einer negativen Gebühr (-2,00): Eine Gebührenerstattung bucht der " <>
                 "Import noch nicht — Zeile nicht übernommen. Den Verkauf von Hand ohne Gebühr " <>
                 "buchen, mit dem Abrechnungsbetrag 20,10 (der Gesamtpreis, den Portfolio " <>
                 "Performance zeigt)."
             ]

      body =
        Jason.encode!(%{
          version: 1,
          transactions: [delivery("OUTBOUND_DELIVERY", %{units: over})]
        })

      assert {:ok, %Preview{errors: [%{message: message}]}} = JsonParser.parse(body)

      assert message ==
               "Buchung mit einer negativen Gebühr (-2,00): Eine Gebührenerstattung bucht der " <>
                 "Import noch nicht — Zeile nicht übernommen. Die Buchung ohne Gebühr von Hand " <>
                 "erfassen."
    end

    test "says it in German, its figures in the German notation" do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")

      body =
        Jason.encode!(%{
          version: 1,
          transactions: [
            delivery("INBOUND_DELIVERY", %{units: [unit("TAX", "-12.40")]}),
            delivery("OUTBOUND_DELIVERY", %{}),
            delivery("SECURITY_TRANSFER", %{otherPortfolio: "Test-Depot-2"}),
            %{
              type: "CASH_TRANSFER",
              account: "Test-Cash",
              otherAccount: "Test-Savings",
              date: "2026-02-10",
              currency: "EUR",
              amount: Jason.Fragment.new("100.00"),
              units: [unit("TAX", "-5.00")]
            },
            tx(%{
              amount: Jason.Fragment.new("120.0"),
              units: [unit("FEE", "4.90"), unit("FEE", "-1.90")]
            }),
            tx(%{
              type: "PURCHASE",
              amount: Jason.Fragment.new("1003.0"),
              units: [unit("FEE", "5"), unit("FEE", "-2")]
            })
          ]
        })

      assert {:ok, %Preview{errors: errors}} = JsonParser.parse(body)

      assert Enum.map(errors, & &1.message) == [
               "Einlieferung mit Steuererstattung 12,40: Eine Einlieferung bewegt kein Geld, " <>
                 "die Erstattung hätte kein Konto — Zeile nicht übernommen. Die Einlieferung " <>
                 "ohne sie von Hand buchen; ist Geld geflossen, das als eigene " <>
                 "Steuererstattung.",
               "Auslieferung mit Steuererstattung 0,40: Eine Auslieferung bewegt kein Geld, " <>
                 "die Erstattung hätte kein Konto — Zeile nicht übernommen. Die Auslieferung " <>
                 "ohne sie von Hand buchen; ist Geld geflossen, das als eigene " <>
                 "Steuererstattung.",
               "Wertpapierumbuchung mit Steuererstattung 0,40: Eine Wertpapierumbuchung " <>
                 "bewegt kein Geld, die Erstattung hätte kein Konto — Zeile nicht " <>
                 "übernommen. Die Wertpapierumbuchung ohne sie von Hand buchen; ist Geld " <>
                 "geflossen, das als eigene Steuererstattung.",
               "Umbuchung mit Steuererstattung 5,00: Eine Umbuchung bewegt Geld zwischen " <>
                 "zwei Konten, eine abgespaltene Erstattung landete nur auf einer Seite — " <>
                 "Zeile nicht übernommen. Die Umbuchung ohne sie von Hand buchen; ist Geld " <>
                 "geflossen, das als eigene Steuererstattung.",
               "Verkauf mit einer negativen Gebühr (-1,90): Eine Gebührenerstattung bucht " <>
                 "der Import noch nicht — Zeile nicht übernommen. Den Verkauf von Hand " <>
                 "buchen, mit den Gebühren abzüglich der Erstattung (3,00).",
               "Buchung mit einer negativen Gebühr (-2,00): Eine Gebührenerstattung bucht " <>
                 "der Import noch nicht — Zeile nicht übernommen. Die Buchung von Hand " <>
                 "erfassen, mit den Gebühren abzüglich der Erstattung (3,00)."
             ]
    end

    # A delivery or a security transfer of 10 Arbolia Inc. with a TAX unit
    # of -0.40, as Portfolio Performance writes one: a depot, no account.
    defp delivery(type, fields) do
      Map.merge(
        %{
          type: type,
          portfolio: "Test-Depot",
          date: "2026-02-03",
          currency: "EUR",
          amount: Jason.Fragment.new("999.60"),
          shares: Jason.Fragment.new("10"),
          security: %{name: "Arbolia Inc.", currency: "EUR"},
          units: [unit("TAX", "-0.40")]
        },
        fields
      )
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
