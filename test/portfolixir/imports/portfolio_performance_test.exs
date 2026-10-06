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
end
