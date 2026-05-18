defmodule Portfolixir.Imports.PortfolioPerformance.CsvParserTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Imports.PortfolioPerformance.CsvParser
  alias Portfolixir.Imports.Preview

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

    test "captures unknown German type labels as row-level errors" do
      body = """
      Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
      2024-01-01 00:00:00;Mystery;;;;1,00;;;1,00;Test-Cash;;;
      """

      assert {:ok, %Preview{entries: [], errors: errors}} = CsvParser.parse(body)
      assert [%{row: 1, message: message}] = errors
      assert message =~ "Mystery"
    end
  end
end
