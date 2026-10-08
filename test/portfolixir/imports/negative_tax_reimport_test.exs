defmodule Portfolixir.Imports.NegativeTaxReimportTest do
  # ADR-0053 A3, A4 and K11 (the amendment of 2026-10-07; risk-tier: import
  # idempotency, ADR-0036). An instance that imported a Portfolio
  # Performance JSON export while the importer booked a row's whole `amount`
  # beside its split-off refund, and priced a trade from the positive taxes
  # alone, must book nothing when the same history is dropped again under
  # the amendment's reading (ADR-0050 §2, "a file already applied is a
  # no-op"), nor when a re-export of it drifted.
  #
  # The old reading is rebuilt from the entries the parser gives today: each
  # row's cash set to its hash amount (the `amount`, or a converter row's
  # Betrag) and a trade's price to its hash price (the price derived the old
  # way), which is what the importer booked before the amendment; the
  # split-off refund is booked as it was. Every name and amount is
  # synthetic.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  # sale_with_negative_tax.json: a deposit, a purchase, and a sale that
  # splits one refund off; sample_with_negative_tax.json: a dividend that
  # splits one refund off.
  @files [{"sale_with_negative_tax.json", 4}, {"sample_with_negative_tax.json", 2}]

  # The sale history as the converter prompt writes it, its refund riding the
  # sale as a negative Steuern.
  @converter_csv """
  Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
  2024-03-01;Einlage;;;;1.100,00;;;;Test-Cash;;;
  2024-03-04 10:01:00;Kauf;Arbolia Inc.;10;10,00;100,00;;;;Test-Depot;Test-Cash;;
  2024-06-14 15:30:00;Verkauf;Arbolia Inc.;10;10,00;120,00;5,00;-25,00;;Test-Depot;Test-Cash;;
  """

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Negative tax target",
        base_currency_code: "EUR"
      })

    %{portfolio: portfolio}
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp parse!(body, filename) do
    {:ok, preview} = PortfolioPerformance.parse(body, filename: filename)
    assert preview.errors == []
    preview
  end

  # What the importer booked before the amendment: every row's cash cell
  # whole, a trade priced the old way; the refunds as they are.
  defp old_reading(%Preview{entries: entries} = preview) do
    %{
      preview
      | entries:
          Enum.map(entries, fn %Entry{} = entry ->
            %{entry | gross_amount: entry.hash_amount, price: entry.hash_price || entry.price}
          end)
    }
  end

  # A re-export whose every time of day moved by a minute, a row without one
  # given one: no row keeps its content hash, and no booked field changes.
  defp drifted(json) do
    json
    |> then(
      &Regex.replace(~r/"time": "(\d\d):(\d\d)"/, &1, fn _all, hour, minute ->
        ~s("time": "#{hour}:#{minute |> String.to_integer() |> Kernel.+(1) |> pad()}")
      end)
    )
    |> then(
      &Regex.replace(
        ~r/("date": "\d{4}-\d\d-\d\d",)(\n\s+)("currency")/,
        &1,
        "\\1\\2\"time\": \"00:01\",\\2\\3"
      )
    )
  end

  defp pad(minute), do: minute |> Integer.to_string() |> String.pad_leading(2, "0")

  defp apply!(%Preview{} = preview, portfolio) do
    assert {:ok, %Result{} = result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    result
  end

  defp counts do
    %{
      cash: Portfolios.count_cash_accounts(),
      depots: length(Portfolios.list_securities_accounts()),
      securities: Catalog.count_securities(),
      transactions: Ledger.count_transactions()
    }
  end

  defp balances(portfolio), do: Ledger.cash_balances(portfolio_id: portfolio.id)

  defp sale(portfolio) do
    portfolio.id
    |> Ledger.list_transactions_for_portfolio()
    |> Enum.find(&(&1.type == "sell"))
  end

  # User story (ADR-0053 A3, K11):
  # As the operator whose instance imported a Portfolio Performance JSON
  # export before a negative tax unit was booked once,
  # I want dropping the same export again to book nothing,
  # so that the reading's change never books a row of mine twice.
  #
  # Acceptance criteria:
  # - Each file applied under the old reading (the sale at 120.0 and 12.5,
  #   as the importer booked it then), then dropped as Portfolio Performance
  #   wrote it, inserts no transaction and creates no cash account, depot or
  #   security; every entry, the split-off refund included, is a hash hit.
  # - The preview counts every entry as already imported by its hash.
  # - No balance moves.
  test "a JSON file applied under the old reading and dropped again books nothing", %{
    portfolio: portfolio
  } do
    for {name, entries} <- @files do
      first = apply!(old_reading(parse!(fixture(name), name)), portfolio)
      assert first.created_transactions == entries, name

      before = counts()
      cash = balances(portfolio)

      counted = Imports.reimport_counts(parse!(fixture(name), name), portfolio_id: portfolio.id)
      assert counted.total.hash == entries, name
      assert counted.total.new == 0, name

      again = apply!(parse!(fixture(name), name), portfolio)

      assert again.created_transactions == 0, name
      assert again.created_cash_accounts == 0, name
      assert again.created_securities_accounts == 0, name
      assert again.created_securities == 0, name
      assert again.already_imported == %{hash: entries, retired: 0, economics: 0}, name
      assert counts() == before, name
      assert balances(portfolio) == cash, name
    end

    old_sale = sale(portfolio)
    assert Decimal.equal?(old_sale.gross_amount, Decimal.new("120.00"))
    assert Decimal.equal?(old_sale.price, Decimal.new("12.50"))
  end

  # User story (ADR-0053 A4, K11):
  # As the operator whose fresh Portfolio Performance export moved a time of
  # day since the first import,
  # I want the rows booked under the old reading recognised by their
  # booking, though their content hash, their cash and their price moved,
  # so that a drifted re-export books nothing twice either.
  #
  # Acceptance criteria:
  # - Each file's re-export with every time of day moved, so no content hash
  #   matches, is skipped as equal economic bookings, entry for entry: the
  #   sale through the key read with its old cash and its old price, the
  #   dividend through its old cash, the refunds through their own key.
  # - The preview counts every entry under `economics`, none as new.
  # - Nothing is inserted or created, and no balance moves.
  test "a drifted re-export of a file applied under the old reading books nothing", %{
    portfolio: portfolio
  } do
    for {name, entries} <- @files do
      first = apply!(old_reading(parse!(fixture(name), name)), portfolio)
      assert first.created_transactions == entries, name

      before = counts()
      cash = balances(portfolio)
      export = drifted(fixture(name))
      refute export == fixture(name)

      counted = Imports.reimport_counts(parse!(export, name), portfolio_id: portfolio.id)
      assert counted.total.economics == entries, name
      assert counted.total.new == 0, name

      again = apply!(parse!(export, name), portfolio)

      assert again.created_transactions == 0, name
      assert again.already_imported == %{hash: 0, retired: 0, economics: entries}, name
      assert Enum.all?(again.duplicate_entries, &(&1.layer == :economics)), name
      assert counts() == before, name
      assert balances(portfolio) == cash, name
    end
  end

  # User story (ADR-0053 A4):
  # As the operator who imported a Portfolio Performance JSON export under
  # the amendment's reading,
  # I want a drifted re-export of it recognised by the bookings it made,
  # so that a moved time of day never books a row of mine twice.
  #
  # Acceptance criteria:
  # - The sale history applied as written, then dropped again with every
  #   time of day moved, is counted and skipped as `economics` for every
  #   entry, through the key read with the booked cash and price.
  test "a drifted re-export of a file imported under the new reading books nothing", %{
    portfolio: portfolio
  } do
    {name, entries} = hd(@files)

    first = apply!(parse!(fixture(name), name), portfolio)
    assert first.created_transactions == entries

    before = counts()
    cash = balances(portfolio)
    export = drifted(fixture(name))

    counted = Imports.reimport_counts(parse!(export, name), portfolio_id: portfolio.id)
    assert counted.total.economics == entries
    assert counted.total.new == 0

    again = apply!(parse!(export, name), portfolio)

    assert again.created_transactions == 0
    assert again.already_imported == %{hash: 0, retired: 0, economics: entries}
    assert counts() == before
    assert balances(portfolio) == cash
  end

  # User story (ADR-0053 A1, A4; K13):
  # As the operator who imported a converter-written CSV whose sale carried
  # a negative Steuern before the refund was taken out of its Betrag,
  # I want the same file, and a re-export of it with its times moved, to
  # book nothing,
  # so that the refund's new reading never books my sale twice.
  #
  # Acceptance criteria:
  # - Applied under the old reading (the sale's whole Betrag), the file
  #   dropped again is all hash hits, and with every time of day moved it is
  #   all economic duplicates, the sale through the key read with its
  #   Betrag; nothing is inserted.
  test "a converter file applied under the old reading books nothing, drifted or not", %{
    portfolio: portfolio
  } do
    first = apply!(old_reading(parse!(@converter_csv, "converter.csv")), portfolio)
    assert first.created_transactions == 4
    assert Decimal.equal?(sale(portfolio).gross_amount, Decimal.new("120.00"))

    before = counts()
    cash = balances(portfolio)

    again = apply!(parse!(@converter_csv, "converter.csv"), portfolio)
    assert again.already_imported == %{hash: 4, retired: 0, economics: 0}

    export = String.replace(@converter_csv, ":00;", ":01;")
    refute export == @converter_csv

    # The deposit carries no time of day, so it keeps its hash; the purchase,
    # the sale and its refund drift.
    drifted = apply!(parse!(export, "converter.csv"), portfolio)
    assert drifted.created_transactions == 0
    assert drifted.already_imported == %{hash: 1, retired: 0, economics: 3}
    assert counts() == before
    assert balances(portfolio) == cash
  end

  # -- A5's refused credit row, already imported (#1118, #1193) ---------------

  # #1118's figures in JSON: a worthless position sold at a nominal price, its
  # loss refunding tax. The sale's `amount` 20.10 less the refund 25.00 is
  # -4.90, so A5 refuses the row.
  @nominal_sale_json """
  {
    "version": 1,
    "transactions": [
      {"type": "DEPOSIT", "account": "Test-Cash", "date": "2024-03-01",
       "currency": "EUR", "amount": 1100.0},
      {"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot",
       "date": "2024-03-04", "time": "10:01", "currency": "EUR",
       "amount": 100.0, "shares": 10.0,
       "security": {"name": "Arbolia Inc.", "isin": "USEXMPL10014", "currency": "EUR"}},
      {"type": "SALE", "account": "Test-Cash", "portfolio": "Test-Depot",
       "date": "2024-06-14", "time": "15:30", "currency": "EUR",
       "amount": 20.10, "shares": 10.0,
       "security": {"name": "Arbolia Inc.", "isin": "USEXMPL10014", "currency": "EUR"},
       "units": [{"type": "FEE", "amount": 5.0}, {"type": "TAX", "amount": -25.0}]}
    ]
  }
  """

  # The same history as a Portfolio Performance CSV: Betrag 1,00, Gebühren
  # 5,90, Steuern -25,00, Gesamtpreis 20,10.
  @nominal_sale_csv """
  Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
  2024-01-02 00:00:00;Einlage;;;;1.000,00;;;1.000,00;Test-Cash;;;
  2024-01-15 10:01:00;Kauf;Arbolia Inc.;100;2,00;200,00;5,90;;205,90;Test-Depot;Test-Cash;;
  2024-06-14 15:30:00;Verkauf;Arbolia Inc.;100;0,01;1,00;5,90;-25,00;20,10;Test-Depot;Test-Cash;;
  """

  # The JSON sale as the parser of 12117072 (before the amendment of
  # 2026-10-07) built it, and the importer booked it: the whole `amount` as
  # the cash, the price derived from the positive taxes alone
  # ((20.10 + 5.0 + 0) / 10 = 2.51), and the refund split off beside it.
  defp nominal_sale_as_booked_before(%Entry{security: security}) do
    refund = %Entry{
      source_row: "3.tax_refund.1",
      kind: "tax_refund",
      date: ~D[2024-06-14],
      time: ~T[15:30:00],
      currency_code: "EUR",
      gross_amount: Decimal.new("25.0"),
      hash_amount: Decimal.new("25.0"),
      fees: Decimal.new(0),
      taxes: Decimal.new(0),
      security: security,
      pp_portfolio_name: "Test-Depot",
      pp_account_name: "Test-Cash",
      note: "Auto-split tax refund from row 3"
    }

    %Entry{
      source_row: 3,
      kind: "sell",
      date: ~D[2024-06-14],
      time: ~T[15:30:00],
      currency_code: "EUR",
      gross_amount: Decimal.new("20.10"),
      hash_amount: Decimal.new("20.10"),
      fees: Decimal.new("5.0"),
      taxes: Decimal.new(0),
      quantity: Decimal.new("10.0"),
      price: Decimal.new("2.51"),
      security: security,
      pp_portfolio_name: "Test-Depot",
      pp_account_name: "Test-Cash",
      companion_entries: [refund]
    }
  end

  defp refused!(body, filename) do
    {:ok, %Preview{errors: [_refused]} = preview} =
      PortfolioPerformance.parse(body, filename: filename)

    preview
  end

  # User story (#1118, #1193; found by the α closing act):
  # As the operator whose instance imported a nominal sale with a tax
  # refund before A5 refused such a row,
  # I want a re-drop of the export to say that the row is already imported
  # and cannot be corrected here,
  # so that I do not follow the refusal's remedy and book the sale twice.
  #
  # Acceptance criteria:
  # - #1118's JSON sale booked as the parser of 12117072 booked it (cash
  #   20.10, price 2.51, the refund 25.00 beside it; Test-Cash 1,045.10):
  #   the row's message in that portfolio says it is already imported, that
  #   it cannot be corrected here as its cash would be 0 or less, not to
  #   enter it again, and where the handbook explains it; it no longer asks
  #   for the booking by hand.
  # - In a portfolio that never imported it, the refusal keeps its remedy.
  # - The correction lists nothing for it (its correction is #1193), the
  #   apply books nothing twice, and no balance moves.
  # - The same holds for the PP CSV of it booked under the Betrag reading.
  test "a credit row A5 refuses whose booking is stored says it is already imported", %{
    portfolio: portfolio
  } do
    preview = refused!(@nominal_sale_json, "nominal.json")
    [deposit, purchase] = preview.entries

    old = %{preview | entries: [deposit, purchase, nominal_sale_as_booked_before(purchase)]}
    assert apply!(old, portfolio).created_transactions == 4
    assert [booked] = Map.values(balances(portfolio))
    assert Decimal.equal?(booked, Decimal.new("1045.10"))

    remedy =
      "amount 20.10 less the tax refund 25.0 leaves -4.90 to credit — enter this booking " <>
        "by hand, and the refund as a tax refund of its own — row not imported"

    assert preview.errors == [%{row: 3, message: remedy}]

    assert Imports.row_errors(preview, portfolio_id: portfolio.id) == [
             %{
               row: 3,
               message:
                 "amount 20.10 less the tax refund 25.0 leaves -4.90 to credit — already " <>
                   "imported, and it cannot be corrected here, as its cash would be 0 or " <>
                   "less — do not enter it again; see “A negative tax inside a row” in the " <>
                   "product documentation"
             }
           ]

    {:ok, fresh} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Never imported",
        base_currency_code: "EUR"
      })

    assert Imports.row_errors(preview, portfolio_id: fresh.id) == [%{row: 3, message: remedy}]

    assert Imports.cash_corrections(preview, portfolio_id: portfolio.id) == []
    before = counts()
    cash = balances(portfolio)
    assert apply!(preview, portfolio).created_transactions == 0
    assert counts() == before
    assert balances(portfolio) == cash

    csv = refused!(@nominal_sale_csv, "nominal.csv")
    [%{entry: refused_sale}] = csv.refused_credits

    old_csv = %{
      csv
      | entries: csv.entries ++ [%{refused_sale | gross_amount: refused_sale.hash_amount}]
    }

    {:ok, csv_portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Betrag reading",
        base_currency_code: "EUR"
      })

    assert apply!(old_csv, csv_portfolio).created_transactions == 4

    assert [%{row: 4, message: message}] = Imports.row_errors(csv, portfolio_id: csv_portfolio.id)

    assert message ==
             "Gesamtpreis 20,10 less the tax refund 25,00 leaves -4,90 to credit — already " <>
               "imported, and it cannot be corrected here, as its cash would be 0 or less — " <>
               "do not enter it again; see “A negative tax inside a row” in the product " <>
               "documentation"
  end
end
