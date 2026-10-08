defmodule Portfolixir.Imports.CashCorrectionTest do
  # ADR-0053 §6 and the amendment's A6, K7, K8 and K15 (risk-tier: money and
  # import idempotency, ADR-0036). A booking an import stored under an older
  # reading of its row keeps its content hash, so a re-drop of the same file
  # is all hash hits and books nothing (ADR-0050 §3). The correction finds
  # those bookings by that hash, lists each whose stored cash differs from
  # the cash the row books today, and rewrites them through a confirm of its
  # own.
  #
  # The old readings are rebuilt from the entries the parsers give today, as
  # `csv_gesamtpreis_reimport_test.exs` and `negative_tax_reimport_test.exs`
  # rebuild them: each row's cash set to its hash amount (a PP CSV row's
  # Betrag, a converter row's Betrag, a JSON row's `amount`) and a JSON
  # trade's price to its hash price, which is what the importer booked
  # before ADR-0053 and its amendment; a split-off refund is booked as it
  # was. Every name and amount is synthetic.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.Correction.Item
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Portfolios

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  # The sale history as the converter prompt writes it, its refund riding the
  # sale as a negative Steuern and no Gesamtpreis.
  @converter_csv """
  Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
  2024-03-01;Einlage;;;;1.100,00;;;;Test-Cash;;;
  2024-03-04 10:01:00;Kauf;Arbolia Inc.;10;10,00;100,00;;;;Test-Depot;Test-Cash;;
  2024-06-14 15:30:00;Verkauf;Arbolia Inc.;10;10,00;120,00;5,00;-25,00;;Test-Depot;Test-Cash;;
  """

  # A sale of a USD security through a EUR account, its refund a negative
  # tax unit: a cross-currency trade whose settlement legs follow its cash
  # (ADR-0015, ADR-0033).
  @cross_currency_json """
  {
    "version": 1,
    "transactions": [
      {"type": "DEPOSIT", "account": "FX-Cash", "date": "2026-01-02",
       "currency": "EUR", "amount": 1000.0},
      {"type": "PURCHASE", "account": "FX-Cash", "portfolio": "FX-Depot",
       "date": "2026-01-15", "time": "10:00", "currency": "EUR",
       "amount": 100.0, "shares": 10.0,
       "security": {"name": "Harborline Freight Inc", "currency": "USD"}},
      {"type": "SALE", "account": "FX-Cash", "portfolio": "FX-Depot",
       "date": "2026-03-16", "time": "15:30", "currency": "EUR",
       "amount": 120.0, "shares": 10.0,
       "security": {"name": "Harborline Freight Inc", "currency": "USD"},
       "units": [{"type": "FEE", "amount": 5.0}, {"type": "TAX", "amount": -25.0}]}
    ]
  }
  """

  defp portfolio!(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    portfolio
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp parse!(body, filename) do
    {:ok, preview} = PortfolioPerformance.parse(body, filename: filename)
    assert preview.errors == []
    preview
  end

  # What the importer booked before ADR-0053 and its amendment: every row's
  # cash cell whole, a JSON trade priced the old way; the refunds as they are.
  defp old_reading(%Preview{entries: entries} = preview) do
    %{
      preview
      | entries:
          Enum.map(entries, fn %Entry{} = entry ->
            %{entry | gross_amount: entry.hash_amount, price: entry.hash_price || entry.price}
          end)
    }
  end

  defp apply!(%Preview{} = preview, portfolio) do
    assert {:ok, %Result{} = result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    result
  end

  defp usd_rate! do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-01-01],
          rate: "1.25",
          source: "manual"
        }
      ])

    :ok
  end

  defp norm(nil), do: nil
  defp norm(%Decimal{} = value), do: value |> Decimal.normalize() |> Decimal.to_string(:normal)

  # Each listed booking as row, stored cash, the file's cash and their
  # difference, each the signed effect on the booking's own cash account.
  defp figures(items) do
    Enum.map(items, fn %Item{} = item ->
      {item.row, norm(item.booked), norm(item.stated), norm(item.difference)}
    end)
  end

  defp account_totals(items) do
    items
    |> Enum.flat_map(& &1.accounts)
    |> Enum.group_by(& &1.account.name, & &1.delta)
    |> Map.new(fn {name, deltas} -> {name, deltas |> Enum.reduce(&Decimal.add/2) |> norm()} end)
  end

  describe "the bookings a re-dropped file lists (ADR-0053 §6, A6)" do
    # User story (ADR-0053 §6):
    # As the operator whose instance imported a Portfolio Performance CSV
    # while the importer booked PP's gross Betrag as the cash,
    # I want a re-drop of that export to list every booking whose stored
    # cash differs from the Gesamtpreis the row books now,
    # so that I see which balances are off and by how much before anything
    # is written.
    #
    # Acceptance criteria:
    # - hash_pin.csv applied under the old reading lists exactly the five
    #   rows whose Gesamtpreis differs from their Betrag: the Kauf (row 2),
    #   the two Dividenden (rows 3 and 5, the second net of its split-off
    #   refund), the Verkauf (row 6) and the Zinsen (row 16).
    # - Each line is the booking's signed cash effect as stored, as the file
    #   states it and their difference, exact in Decimal.
    # - The refund split off row 5, the converter-shaped row 17 (no
    #   Gesamtpreis), the cashless rows and every row without units are not
    #   listed: their stored cash is what the row books.
    # - The account total is the sum of the differences: Pin-Cash -22.11.
    # - Detection writes nothing: a CSV row's price is never among the
    #   changes, and the changes are the cash alone.
    test "a PP CSV stored under the Betrag reading lists the rows its Gesamtpreis corrects" do
      portfolio = portfolio!("Gesamtpreis correction")
      csv = fixture("hash_pin.csv")
      apply!(old_reading(parse!(csv, "export.csv")), portfolio)

      items = Imports.cash_corrections(parse!(csv, "export.csv"), portfolio_id: portfolio.id)

      assert figures(items) == [
               {2, "-1500", "-1503.5", "-3.5"},
               {3, "11.54", "9.13", "-2.41"},
               {5, "10", "9.5", "-0.5"},
               {6, "725.8", "711.3", "-14.5"},
               {16, "5.75", "4.55", "-1.2"}
             ]

      assert account_totals(items) == %{"Pin-Cash" => "-22.11"}
      assert Enum.all?(items, &(Map.keys(&1.changes) == [:gross_amount]))
    end

    # User story (ADR-0053 A1, A6):
    # As the operator who imported a converter-written CSV whose sale carried
    # a negative Steuern while the importer booked the whole Betrag beside the
    # refund it split off,
    # I want a re-drop of that file to list the sale,
    # so that the refund counted twice can be taken out.
    #
    # Acceptance criteria:
    # - The sale is listed: stored +120.00, the file +95.00 (its Betrag less
    #   the refund of 25.00), difference -25.00; nothing else is.
    # - Its price is Kurs from the file and is not among the changes.
    test "a converter CSV stored with its refund counted twice lists the sale" do
      portfolio = portfolio!("Converter correction")
      apply!(old_reading(parse!(@converter_csv, "converter.csv")), portfolio)

      items =
        Imports.cash_corrections(parse!(@converter_csv, "converter.csv"),
          portfolio_id: portfolio.id
        )

      assert figures(items) == [{3, "120", "95", "-25"}]
      assert account_totals(items) == %{"Test-Cash" => "-25"}
      assert [%Item{changes: changes}] = items
      assert Map.keys(changes) == [:gross_amount]
    end

    # User story (ADR-0053 A2, A6):
    # As the operator who imported a Portfolio Performance JSON export
    # whose rows carry a negative tax unit,
    # I want a re-drop of it to list each booking whose cash counted the
    # refund twice, and for a sale the price derived from that cash,
    # so that I see what the correction rewrites.
    #
    # Acceptance criteria:
    # - sale_with_negative_tax.json lists the sale: +120.00 → +95.00
    #   (difference -25.00), its price 12.50 → 10.00.
    # - sample_with_negative_tax.json lists the dividend: +181.49 → +181.48
    #   (difference -0.01); a dividend has no price to rewrite.
    test "a JSON file stored under the old reading lists its cash and a trade's price" do
      sale_portfolio = portfolio!("JSON sale correction")
      sale_file = fixture("sale_with_negative_tax.json")
      apply!(old_reading(parse!(sale_file, "sale.json")), sale_portfolio)

      assert [%Item{} = sale] =
               Imports.cash_corrections(parse!(sale_file, "sale.json"),
                 portfolio_id: sale_portfolio.id
               )

      assert figures([sale]) == [{3, "120", "95", "-25"}]
      assert norm(sale.transaction.price) == "12.5"
      assert norm(sale.changes.price) == "10"
      assert Map.keys(sale.changes) |> Enum.sort() == [:gross_amount, :price]

      dividend_portfolio = portfolio!("JSON dividend correction")
      dividend_file = fixture("sample_with_negative_tax.json")
      apply!(old_reading(parse!(dividend_file, "dividend.json")), dividend_portfolio)

      assert [%Item{} = dividend] =
               Imports.cash_corrections(parse!(dividend_file, "dividend.json"),
                 portfolio_id: dividend_portfolio.id
               )

      assert figures([dividend]) == [{1, "181.49", "181.48", "-0.01"}]
      assert Map.keys(dividend.changes) == [:gross_amount]
    end

    # User story (ADR-0053 §6, ADR-0015):
    # As the operator whose corrected sale settled a USD security through a
    # EUR account,
    # I want its settlement legs listed before and after,
    # so that I see that the trade amount and its USD leg change with the
    # cash.
    #
    # Acceptance criteria:
    # - The sale is listed with its stored legs (125.00 EUR = 156.25 USD,
    #   read off the old cash 120.00 plus the fee 5.00) and the legs the
    #   file's cash gives (100.00 EUR = 125.00 USD at the stored hub rate
    #   1 EUR = 1.25 USD), the rate 0.80 either way.
    test "a cross-currency trade lists its settlement legs before and after" do
      usd_rate!()
      portfolio = portfolio!("Cross-currency correction")
      apply!(old_reading(parse!(@cross_currency_json, "fx.json")), portfolio)

      assert [%Item{} = sale] =
               Imports.cash_corrections(parse!(@cross_currency_json, "fx.json"),
                 portfolio_id: portfolio.id
               )

      assert figures([sale]) == [{3, "120", "95", "-25"}]

      assert {norm(sale.transaction.settlement_amount), norm(sale.transaction.security_amount),
              norm(sale.transaction.settlement_fx_rate)} == {"125", "156.25", "0.8"}

      assert {norm(sale.changes.settlement_amount), norm(sale.changes.security_amount),
              norm(sale.changes.settlement_fx_rate)} == {"100", "125", "0.8"}

      assert norm(sale.changes.price) == "10"
    end

    # User story (ADR-0053 §6, ADR-0033 requirement 4):
    # As the operator correcting a cross-currency trade whose hub rate is no
    # longer stored,
    # I want its legs carried at the rate the trade stores,
    # so that the correction neither guesses a rate nor leaves the legs
    # disagreeing with the cash.
    #
    # Acceptance criteria:
    # - With every stored rate gone, the sale's legs become 100.00 EUR =
    #   125.00 USD at its stored rate 0.80.
    test "a cross-currency trade without a stored hub rate keeps its stored rate" do
      usd_rate!()
      portfolio = portfolio!("Cross-currency without a rate")
      apply!(old_reading(parse!(@cross_currency_json, "fx.json")), portfolio)
      Repo.delete_all(Fx.ExchangeRate)

      assert [%Item{} = sale] =
               Imports.cash_corrections(parse!(@cross_currency_json, "fx.json"),
                 portfolio_id: portfolio.id
               )

      assert {norm(sale.changes.settlement_amount), norm(sale.changes.security_amount),
              norm(sale.changes.settlement_fx_rate)} == {"100", "125", "0.8"}
    end

    # User story (ADR-0053 §6, UX-DR2):
    # As the operator re-dropping a file whose bookings all agree with it,
    # I want nothing listed,
    # so that the preview shows no correction and no all-clear either.
    #
    # Acceptance criteria:
    # - Each file applied under today's reading and dropped again lists
    #   nothing; so does a file never imported, and a preview without a
    #   portfolio to import into.
    test "nothing is listed when every stored booking agrees with the file" do
      for {name, body} <- [
            {"export.csv", fixture("hash_pin.csv")},
            {"converter.csv", @converter_csv},
            {"sale.json", fixture("sale_with_negative_tax.json")},
            {"dividend.json", fixture("sample_with_negative_tax.json")}
          ] do
        portfolio = portfolio!("Agreeing #{name}")
        fresh = portfolio!("Untouched #{name}")
        apply!(parse!(body, name), portfolio)

        assert Imports.cash_corrections(parse!(body, name), portfolio_id: portfolio.id) == [],
               name

        assert Imports.cash_corrections(parse!(body, name), portfolio_id: fresh.id) == [], name
        assert Imports.cash_corrections(parse!(body, name), portfolio_id: nil) == [], name
      end
    end
  end
end
