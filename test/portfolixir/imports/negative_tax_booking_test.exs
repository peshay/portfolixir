defmodule Portfolixir.Imports.NegativeTaxBookingTest do
  # ADR-0053, the amendment of 2026-10-07 (#1098; risk-tier: money and import
  # idempotency, ADR-0036). A negative tax unit inside a Portfolio
  # Performance row is split off as a `tax_refund` beside its booking. The
  # row's cash cell (a JSON row's `amount`, a PP CSV row's Gesamtpreis, a
  # converter row's Betrag) already holds the refund, so the parent books
  # that cell less the refund on a credit and plus it on a debit: parent and
  # refund net to the cell, and every account ends at Portfolio
  # Performance's balance.
  #
  # Every name and amount is synthetic. The JSON fixtures follow the shape
  # Portfolio Performance writes (JTransaction, JTransactionUnit); each CSV
  # below is the same history as PP writes it (Kurs and Betrag the gross
  # values, Gesamtpreis the cash) or as the converter prompt writes it
  # (Betrag the cash, Gesamtpreis empty).
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  # sale_with_negative_tax.json as Portfolio Performance's CSV export writes
  # it: the sale's Betrag is its gross value, 120,00 + 5,00 - 25,00 = 100,00,
  # Steuern the signed TAX unit, Gesamtpreis the cash.
  @sale_pp_csv """
  Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
  2024-03-01 00:00:00;Einlage;;;;1.100,00;;;1.100,00;Test-Cash;;;
  2024-03-04 10:01:00;Kauf;Arbolia Inc.;10;10,00;100,00;;;100,00;Test-Depot;Test-Cash;;
  2024-06-14 15:30:00;Verkauf;Arbolia Inc.;10;10,00;100,00;5,00;-25,00;120,00;Test-Depot;Test-Cash;;
  """

  # The same history as the converter prompt writes it: Betrag is the cash,
  # Gesamtpreis stays empty, and the refund rides the row as a negative
  # Steuern.
  @sale_converter_csv """
  Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
  2024-03-01;Einlage;;;;1.100,00;;;;Test-Cash;;;
  2024-03-04 10:01:00;Kauf;Arbolia Inc.;10;10,00;100,00;;;;Test-Depot;Test-Cash;;
  2024-06-14 15:30:00;Verkauf;Arbolia Inc.;10;10,00;120,00;5,00;-25,00;;Test-Depot;Test-Cash;;
  """

  # sample_with_negative_tax.json as PP's CSV export writes it: Steuern is
  # the TAX units' sum, 27,00 - 0,01 = 26,99, so nothing is split off, and
  # Betrag the gross value, 181,49 + 26,99 = 208,48.
  @dividend_pp_csv """
  Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
  2022-02-14 00:00:00;Dividende;Arbolia Inc.;400;;208,48;;26,99;181,49;Test-Cash;;;
  """

  defp target(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    portfolio
  end

  defp apply!(body, filename, portfolio) do
    {:ok, preview} = PortfolioPerformance.parse(body, filename: filename)
    assert preview.errors == []

    assert {:ok, %Result{} = result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    result
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp cash(portfolio, name) do
    account =
      portfolio.id
      |> Portfolios.list_cash_accounts_for_portfolio()
      |> Enum.find(&(&1.name == name))

    Ledger.cash_balances(portfolio_id: portfolio.id) |> Map.fetch!(account.id)
  end

  defp booked(portfolio, type) do
    portfolio.id
    |> Ledger.list_transactions_for_portfolio()
    |> Enum.filter(&(&1.type == type))
  end

  # User story (ADR-0053 A1, K9; risk-tier: money):
  # As the operator importing a Portfolio Performance history whose bookings
  # carry a negative tax unit,
  # I want every account to end at the balance Portfolio Performance shows,
  # whichever format I export,
  # so that a tax refund inside a booking is counted once, never twice.
  #
  # Acceptance criteria:
  # - sample_with_negative_tax.json (a dividend of 181.49 with tax units
  #   27.00 and -0.01) leaves Test-Cash at 181.49, PP's balance, as PP's CSV
  #   of the same dividend does (today 181.50).
  # - The synthetic sale (amount 120.0, 10 shares, FEE 5.0, TAX -25.0) into
  #   Test-Cash holding 1,000.00 leaves it at 1,120.00 (today 1,145.00): the
  #   sale books 95.00 and its refund 25.00.
  # - Its PP CSV (Betrag 100,00; Gebühren 5,00; Steuern -25,00; Gesamtpreis
  #   120,00) books the same, sale and refund alike.
  test "a negative tax unit books once: every account ends at PP's balance, JSON and CSV alike" do
    json = target("JSON dividend")
    apply!(fixture("sample_with_negative_tax.json"), "sample_with_negative_tax.json", json)
    assert Decimal.equal?(cash(json, "Test-Cash"), Decimal.new("181.49"))

    csv = target("CSV dividend")
    apply!(@dividend_pp_csv, "dividend.csv", csv)
    assert Decimal.equal?(cash(csv, "Test-Cash"), cash(json, "Test-Cash"))

    json_sale = target("JSON sale")
    apply!(fixture("sale_with_negative_tax.json"), "sale_with_negative_tax.json", json_sale)
    assert Decimal.equal?(cash(json_sale, "Test-Cash"), Decimal.new("1120.00"))

    csv_sale = target("CSV sale")
    apply!(@sale_pp_csv, "sale.csv", csv_sale)
    assert Decimal.equal?(cash(csv_sale, "Test-Cash"), Decimal.new("1120.00"))

    for portfolio <- [json_sale, csv_sale] do
      assert [sale] = booked(portfolio, "sell")
      assert Decimal.equal?(sale.gross_amount, Decimal.new("95.00"))

      assert [refund] = booked(portfolio, "tax_refund")
      assert Decimal.equal?(refund.gross_amount, Decimal.new("25.00"))
    end
  end

  # User story (ADR-0053 A1, K13; risk-tier: money):
  # As the operator dropping a converter-written CSV whose sale carries a
  # negative Steuern,
  # I want the sale and its refund to book together what Betrag says the
  # account received,
  # so that a refund written beside the cash is not counted twice.
  #
  # Acceptance criteria:
  # - The sale history as the converter writes it (the sale's Betrag 120,00,
  #   Gebühren 5,00, Steuern -25,00, no Gesamtpreis) leaves Test-Cash at
  #   1,120.00 (today 1,145.00): the sale books 95.00 and its refund 25.00,
  #   together its Betrag.
  test "a converter row with a negative Steuern books parent and refund to its Betrag" do
    portfolio = target("Converter sale")
    apply!(@sale_converter_csv, "converter.csv", portfolio)

    assert Decimal.equal?(cash(portfolio, "Test-Cash"), Decimal.new("1120.00"))
    assert [sale] = booked(portfolio, "sell")
    assert [refund] = booked(portfolio, "tax_refund")
    assert Decimal.equal?(sale.gross_amount, Decimal.new("95.00"))
    assert Decimal.equal?(refund.gross_amount, Decimal.new("25.00"))
  end

  # User story (ADR-0053 A2, K12; risk-tier: money):
  # As the operator whose Portfolio Performance sale carries a tax refund,
  # I want the sale priced from its gross value, as Portfolio Performance
  # prices it, and its realized result to leave the refund out,
  # so that the refund counts once, as income of its own, and never inside
  # the trade's result too.
  #
  # Acceptance criteria:
  # - The synthetic JSON sale is priced 10.00 (today 12.50): its gross value,
  #   120.0 + 5.0 - 25.0 = 100.0, over its 10 shares, PP's Kurs.
  # - Its closed trade's proceeds equal the sale's own cash, 95.00 (today
  #   120.00), and against the purchase's cost of 100.00 its realized result
  #   is -5.00 (today 20.00). The refund books 25.00 beside it.
  # - The PP CSV of the same history closes the same trade.
  test "a JSON sale is priced from its gross value, and its realized result leaves the refund out" do
    json = target("JSON trade")
    apply!(fixture("sale_with_negative_tax.json"), "sale_with_negative_tax.json", json)

    csv = target("CSV trade")
    apply!(@sale_pp_csv, "sale.csv", csv)

    assert [json_sale] = booked(json, "sell")
    assert [csv_sale] = booked(csv, "sell")

    # One security: the CSV's name finds the one the JSON's ISIN created, so
    # its trades are the two portfolios' sales, one closed trade each.
    assert json_sale.security_id == csv_sale.security_id

    assert %{closed_trades: [_, _] = trades, orphan_sells: []} =
             Ledger.list_trades_for_security(json_sale.security_id,
               latest_price: Decimal.new("10.00")
             )

    for trade <- trades do
      assert Decimal.equal?(trade.proceeds, Decimal.new("95.00"))
      assert Decimal.equal?(trade.basis, Decimal.new("100.00"))
      assert Decimal.equal?(trade.realized_pnl_abs, Decimal.new("-5.00"))
      assert Decimal.equal?(trade.avg_sell_price, Decimal.new("10.00"))
    end

    for sale <- [json_sale, csv_sale] do
      assert Decimal.equal?(sale.price, Decimal.new("10.00"))
      assert Decimal.equal?(sale.gross_amount, Decimal.new("95.00"))
    end
  end
end
