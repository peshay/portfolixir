defmodule Portfolixir.Imports.PortfolioPerformanceTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  defp read!(name), do: File.read!(Path.join(@fixtures, name))

  # User story:
  # As the LiveView upload handler receiving an arbitrary
  # drag-and-drop file,
  # I want one entry point that figures out whether the bytes are
  # PP JSON v1 or PP CSV and routes to the right parser,
  # so that the user does not have to tell us the format.

  describe "parse/2 format detection" do
    test "routes JSON bodies to the JSON parser" do
      body = read!("sample.json")
      assert {:ok, %Preview{format: :json}} = PortfolioPerformance.parse(body)
    end

    test "routes CSV bodies to the CSV parser" do
      body = read!("sample.csv")
      assert {:ok, %Preview{format: :csv}} = PortfolioPerformance.parse(body)
    end

    test "uses the filename hint when content sniffing is ambiguous" do
      body = read!("sample.json")
      assert {:ok, %Preview{format: :json}} = PortfolioPerformance.parse(body, filename: "x.json")
    end

    test "errors on neither-json-nor-csv input" do
      assert {:error, :unknown_format} = PortfolioPerformance.parse("hello world")
    end
  end

  # User story (#948):
  # As an operator importing an export of either format,
  # I want one check to judge a row's currencies against the catalog's list,
  # so that the two parsers can never disagree about which codes book.
  #
  # Acceptance criteria:
  # - `row_error/1` refuses a booking currency and a security currency the
  #   catalog does not list (`Catalog.Currencies.supported?/1`), each with its
  #   own message (`currency_message/2`, which the JSON parser also gives a
  #   currency that is not a string).
  # - An absent currency, and a listed one, pass.
  describe "row_error/1 and the currency codes" do
    defp entry(currency, security_currency) do
      %Entry{
        source_row: 1,
        kind: "buy",
        currency_code: currency,
        security: %{
          name: "Example Fund",
          isin: nil,
          wkn: nil,
          ticker: nil,
          currency: security_currency
        }
      }
    end

    test "names a booking currency the catalog does not list" do
      assert PortfolioPerformance.row_error(entry("XEU", nil)) ==
               "currency “XEU” is not supported — row not imported"

      assert PortfolioPerformance.currency_message(:booking, 42) ==
               "currency “42” is not supported — row not imported"
    end

    test "names a security currency the catalog does not list" do
      assert PortfolioPerformance.row_error(entry("EUR", "XEU")) ==
               "security currency “XEU” is not supported — row not imported"

      assert PortfolioPerformance.currency_message(:security, %{"a" => 1}) ==
               ~s(security currency “{"a":1}” is not supported — row not imported)
    end

    test "passes an absent and a listed currency" do
      assert PortfolioPerformance.row_error(entry(nil, nil)) == nil
      assert PortfolioPerformance.row_error(entry("GBX", "USD")) == nil
    end

    test "a JSON row with an unlisted currency is a row error through the dispatcher" do
      body =
        Jason.encode!(%{
          "version" => 1,
          "transactions" => [
            %{
              "type" => "DEPOSIT",
              "account" => "Girokonto",
              "date" => "2026-03-07",
              "currency" => "EURO",
              "amount" => "250.00"
            }
          ]
        })

      assert {:ok, %Preview{entries: [], errors: [%{row: 1, message: message}]}} =
               PortfolioPerformance.parse(body, filename: "export.json")

      assert message == "currency “EURO” is not supported — row not imported"
    end
  end

  # User story (#1118, #1193; the α closing act, UAT persona and design
  # critic):
  # As the operator re-dropping an export whose refused credit row was
  # imported under an older reading,
  # I want its warning in the sentence of board
  # ux-design-2026-10-07/01-import-preview ③ for its kind, with or without a
  # refund, saying it is already imported,
  # so that no sale is asked for by hand a second time and no dividend is
  # called a sale.
  #
  # Acceptance criteria:
  # - A sale without a refund: "sell with Gesamtpreis -4,90: nothing would
  #   remain for the sale — already imported, …" / "Verkauf mit … Dem
  #   Verkauf bliebe nichts — bereits importiert …".
  # - Any other credit reads "booking"/"Buchung", with a refund and without.
  # - The fresh message keeps the remedy; a debit is never refused.
  describe "credit_refusal/3 and its message when already imported" do
    defp refused(kind, cell, cash, refund, rest) do
      entry = %Entry{source_row: 2, kind: kind, gross_amount: Decimal.new("-1")}
      written = %{cell: cell, cash: cash, refund: refund, rest: rest}
      PortfolioPerformance.credit_refusal(:credit, entry, written)
    end

    test "names a sale as a sale and any other credit as the booking" do
      assert {"sell with Gesamtpreis -4,90: nothing would remain for the sale — row not " <>
                "imported. Book the sale by hand.",
              %{
                message:
                  "sell with Gesamtpreis -4,90: nothing would remain for the sale — already " <>
                    "imported, and it cannot be corrected here. Do not book the sale again; " <>
                    "see “A negative tax inside a row” in the product documentation."
              }} = refused("sell", "Gesamtpreis", "-4,90", nil, nil)

      assert {_fresh,
              %{
                message:
                  "booking with Betrag 1,00 and a tax refund of 1,00: 0,00 would remain for " <>
                    "the booking — already imported, and it cannot be corrected here. Do not " <>
                    "enter the booking again; see “A negative tax inside a row” in the " <>
                    "product documentation."
              }} = refused("dividend", "Betrag", "1,00", "1,00", "0,00")

      assert {_fresh,
              %{
                message:
                  "booking with Gesamtpreis 0,00: nothing would remain for the booking — " <>
                    "already imported, and it cannot be corrected here. Do not enter the " <>
                    "booking again; see “A negative tax inside a row” in the product " <>
                    "documentation."
              }} = refused("deposit", "Gesamtpreis", "0,00", nil, nil)

      entry = %Entry{source_row: 2, kind: "tax", gross_amount: Decimal.new("-1")}
      assert PortfolioPerformance.credit_refusal(:debit, entry, %{}) == nil
    end

    test "says it in German" do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")

      assert {_fresh,
              %{
                message:
                  "Verkauf mit Gesamtpreis -4,90: Dem Verkauf bliebe nichts — bereits " <>
                    "importiert und hier nicht zu korrigieren. Den Verkauf nicht noch einmal " <>
                    "buchen; siehe „Eine negative Steuer in einer Zeile“ in der " <>
                    "Produktdokumentation."
              }} = refused("sell", "Gesamtpreis", "-4,90", nil, nil)

      assert {_fresh,
              %{
                message:
                  "Buchung mit Gesamtpreis 0,00: Der Buchung bliebe nichts — bereits " <>
                    "importiert und hier nicht zu korrigieren. Die Buchung nicht noch einmal " <>
                    "erfassen; siehe „Eine negative Steuer in einer Zeile“ in der " <>
                    "Produktdokumentation."
              }} = refused("interest", "Gesamtpreis", "0,00", nil, nil)
    end
  end
end
