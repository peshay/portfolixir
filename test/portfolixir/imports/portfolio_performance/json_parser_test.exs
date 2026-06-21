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
      assert buy.security.isin == "US0378331005"
      assert buy.security.wkn == "865985"
      assert buy.security.ticker == "AAPL"
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

    test "reports invalid JSON" do
      assert {:error, {:invalid_json, _}} = JsonParser.parse("{not-json")
    end

    # User story:
    # As a local portfolio maintainer with a date typo in my PP export
    # (a real export contained "0217-12-05" instead of 2017-12-05),
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
              date: "0217-12-05",
              currency: "EUR",
              amount: 1346.47
            }
          ]
        })

      assert {:ok, %Preview{entries: [], errors: [%{row: 1, message: message}]}} =
               JsonParser.parse(body)

      assert message =~ "implausible date 0217-12-05"
      assert message =~ "re-import"
    end
  end

  test "an entry struct exposes the expected fields" do
    {:ok, %Preview{entries: [first | _]}} = JsonParser.parse(read!("sample.json"))
    assert %Entry{kind: "buy", source_row: 1} = first
  end
end
