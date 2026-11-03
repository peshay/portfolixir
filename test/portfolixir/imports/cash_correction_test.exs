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
  alias Portfolixir.Derived
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Fx
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.Correction.Item
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Transaction
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

  # Each test here holds its own copy of one history in several portfolios
  # on purpose, so every apply includes the others' rows deliberately (ADR-0050
  # as amended on 2026-11-01, #1313: held back by default).
  defp every_portfolio, do: Enum.map(Portfolios.list_portfolios(), & &1.id)

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
    assert {:ok, %Result{} = result} =
             Imports.apply(preview, %{
               portfolio_id: portfolio.id,
               include_portfolios: every_portfolio()
             })

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

  # Every stored booking's persisted fields but its timestamps, by id: what
  # the correction may change, and must not change elsewhere.
  @fields Transaction.__schema__(:fields) -- [:inserted_at, :updated_at]

  defp snapshot do
    Transaction |> Repo.all() |> Map.new(&{&1.id, Map.take(&1, @fields)})
  end

  # The fields that changed, per booking that changed.
  defp changed_fields(before, after_) do
    for {id, row} <- after_,
        fields = for({field, value} <- row, Map.get(before[id], field) != value, do: field),
        fields != [],
        into: %{},
        do: {id, Enum.sort(fields)}
  end

  defp identities(snapshot), do: Map.new(snapshot, fn {id, row} -> {id, row.import_hash} end)

  defp correct!(%Preview{} = preview, portfolio) do
    assert {:ok, corrected} =
             Imports.correct_cash(Imports.correction_actor(), preview, portfolio_id: portfolio.id)

    corrected
  end

  # Each cash account's balance by name: the balances of two portfolios
  # compare by the names the same file gave their accounts.
  defp balances(portfolio) do
    names = Map.new(Portfolios.list_cash_accounts(), &{&1.id, &1.name})

    [portfolio_id: portfolio.id]
    |> Ledger.cash_balances()
    |> Map.new(fn {id, balance} -> {names[id], norm(balance)} end)
  end

  defp corrections_journal do
    Journal.list_entries(resource_type: "transaction", operation: :update)
  end

  defp booking(portfolio, kind) do
    portfolio.id
    |> Ledger.list_transactions_for_portfolio()
    |> Enum.find(&(&1.type == kind))
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
    #   rows whose Gesamtpreis differs from their Betrag: the Kauf (row 3),
    #   the two Dividenden (rows 4 and 6, the second net of its split-off
    #   refund), the Verkauf (row 7) and the Zinsen (row 17).
    # - Each line is the booking's signed cash effect as stored, as the file
    #   states it and their difference, exact in Decimal.
    # - The refund split off row 6, the converter-shaped row 18 (no
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
               {3, "-1500", "-1503.5", "-3.5"},
               {4, "11.54", "9.13", "-2.41"},
               {6, "10", "9.5", "-0.5"},
               {7, "725.8", "711.3", "-14.5"},
               {17, "5.75", "4.55", "-1.2"}
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

      assert figures(items) == [{4, "120", "95", "-25"}]
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

    # User story (ADR-0053 A1, A6; found by the α closing act, money lens):
    # As the operator whose JSON sale was stored under the old reading
    # beside its split-off refund, and who has since deleted that refund by
    # hand,
    # I want the correction not to list the sale,
    # so that confirming it alone never takes out a refund the account no
    # longer holds and leaves the cash below the stored state.
    #
    # Acceptance criteria:
    # - sale_with_negative_tax.json applied under the old reading (sale
    #   120.00, refund 25.00, Test-Cash 1,145.00), the refund deleted by
    #   hand (Test-Cash 1,120.00): a re-drop lists nothing, and its
    #   correction changes nothing and leaves Test-Cash at 1,120.00, never
    #   1,095.00.
    # - With the refund stored, the same sale is listed (the K15 case).
    test "a refund-carrying row whose refund is no longer stored is not listed" do
      portfolio = portfolio!("Refund deleted by hand")
      sale_file = fixture("sale_with_negative_tax.json")
      apply!(old_reading(parse!(sale_file, "sale.json")), portfolio)

      assert [%Item{row: 3}] =
               Imports.cash_corrections(parse!(sale_file, "sale.json"),
                 portfolio_id: portfolio.id
               )

      {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), booking(portfolio, "tax_refund"))
      assert balances(portfolio) == %{"Test-Cash" => "1120"}
      before = snapshot()

      assert Imports.cash_corrections(parse!(sale_file, "sale.json"), portfolio_id: portfolio.id) ==
               []

      assert correct!(parse!(sale_file, "sale.json"), portfolio) == []
      assert snapshot() == before
      assert balances(portfolio) == %{"Test-Cash" => "1120"}
    end

    # User story (ADR-0053 A2, A6, A11; the α closing act, coverage):
    # As the operator whose JSON sale's stored cash differs from the file
    # while its price agrees,
    # I want its correction to rewrite only what differs, and a cash I
    # changed by hand to stay as I made it,
    # so that a price that already agrees with the file is not written, and
    # no figure I made is rewritten.
    #
    # Acceptance criteria:
    # - sale_with_negative_tax.json applied as read today, the sale's cash
    #   set from 95.00 to 95.05 (its price stays 10.00; a cash stated alone
    #   must agree with the stored figures within 0.01 plus 10 × 0.005, the
    #   price's rounding, ADR-0053's amendment of 2026-11-02): the re-drop
    #   lists the sale with the cash alone among its changes.
    # - Set by hand (`owner_ui`), the line reads edited since its import,
    #   without a confirm (A11), and the confirm writes nothing.
    # - Set without a hand edit (the importer's own actor, a stand-in for a
    #   stored state no other actor touched, as K22's), the line carries a
    #   confirm, and the confirm writes the cash alone.
    test "a JSON sale whose price agrees lists its cash alone" do
      sale_file = fixture("sale_with_negative_tax.json")

      for {actor, state, written} <- [
            {Actor.owner_ui(), :edited, []},
            {Actor.import_session(), :confirm, [:gross_amount]}
          ] do
        portfolio = portfolio!("Sale set to 95.05 by #{actor.type}")
        apply!(parse!(sale_file, "sale.json"), portfolio)

        {:ok, _edited} =
          Ledger.update_transaction(actor, booking(portfolio, "sell"), %{gross_amount: "95.05"})

        assert [%Item{changes: changes} = sale] =
                 Imports.cash_corrections(parse!(sale_file, "sale.json"),
                   portfolio_id: portfolio.id
                 )

        assert figures([sale]) == [{3, "95.05", "95", "-0.05"}]
        assert Map.keys(changes) == [:gross_amount]
        assert sale.state == state

        before = snapshot()
        correct!(parse!(sale_file, "sale.json"), portfolio)

        assert Map.get(changed_fields(before, snapshot()), sale.transaction.id, []) == written
      end
    end

    # Acceptance criteria (Sprint 23's sprint PR closing act, coverage of
    # #1371's confirm): a sale whose stored cash is gone (cleared in the
    # database directly: no edit can clear a stored-cash trade's cash, so
    # the row stands for one stored before that rule) is listed with the
    # file's cash, and the confirm writes the cash alone, stating no stored
    # cash beside it.
    test "a sale stored without its cash is corrected to the file's cash" do
      sale_file = fixture("sale_with_negative_tax.json")
      portfolio = portfolio!("Sale without its cash")
      apply!(parse!(sale_file, "sale.json"), portfolio)

      sale = booking(portfolio, "sell")

      {:ok, {1, _}} =
        Repo.transaction(fn ->
          Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test', true)")
          Transaction |> where(id: ^sale.id) |> Repo.update_all(set: [gross_amount: nil])
        end)

      cleared = Repo.get!(Transaction, sale.id)

      assert is_nil(cleared.gross_amount)

      assert [%Item{changes: changes, state: :confirm}] =
               Imports.cash_corrections(parse!(sale_file, "sale.json"),
                 portfolio_id: portfolio.id
               )

      assert Map.keys(changes) == [:gross_amount]

      before = snapshot()
      correct!(parse!(sale_file, "sale.json"), portfolio)

      assert Map.get(changed_fields(before, snapshot()), cleared.id) == [:gross_amount]
      assert Decimal.equal?(booking(portfolio, "sell").gross_amount, Decimal.new("95.00"))
    end

    # User story (ADR-0053 §6; the α closing act, coverage):
    # As the operator dropping a file whose every row the preview refuses,
    # or confirming a correction before any portfolio exists,
    # I want nothing listed and nothing corrected,
    # so that an empty file or a fresh instance never errs.
    #
    # Acceptance criteria:
    # - A file of #1118's refused sale alone lists nothing in a portfolio.
    # - Without a portfolio record, the correction's confirm answers
    #   {:ok, []}.
    test "a file with no entries lists nothing, and no portfolio corrects nothing" do
      assert Imports.correct_cash(Imports.correction_actor(), parse!(@converter_csv, "c.csv")) ==
               {:ok, []}

      portfolio = portfolio!("Nothing to list")

      refused =
        """
        Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
        2024-06-14 15:30:00;Verkauf;Arbolia Inc.;100;0,01;1,00;5,90;-25,00;20,10;Test-Depot;Test-Cash;;
        """

      {:ok, %Preview{entries: [], errors: [_refusal]} = preview} =
        PortfolioPerformance.parse(refused, filename: "refused.csv")

      assert Imports.cash_corrections(preview, portfolio_id: portfolio.id) == []
    end

    # User story (ADR-0053 §6, ADR-0033 requirement 4; the α closing act,
    # coverage):
    # As the operator who gave an imported cross-currency sale a settlement
    # amount by hand, where no hub rate was ever stored,
    # I want its correction to move that settlement with the cash and guess
    # no rate,
    # so that the settlement guard holds without an invented native leg.
    #
    # Acceptance criteria:
    # - The USD sale imported without any stored rate carries no legs; given
    #   a settlement of 125.00 EUR by hand, its correction changes the
    #   settlement to 100.00 alone, beside the cash and the price.
    test "a hand-set settlement without a rate moves with the cash, and no rate is guessed" do
      portfolio = portfolio!("Settlement without a rate")
      apply!(old_reading(parse!(@cross_currency_json, "fx.json")), portfolio)
      sale = booking(portfolio, "sell")
      assert sale.settlement_amount == nil

      {:ok, _edited} =
        Ledger.update_transaction(Actor.owner_ui(), sale, %{settlement_amount: "125.00"})

      assert [%Item{changes: changes}] =
               Imports.cash_corrections(parse!(@cross_currency_json, "fx.json"),
                 portfolio_id: portfolio.id
               )

      assert Enum.sort(Map.keys(changes)) == [:gross_amount, :price, :settlement_amount]
      assert norm(changes.settlement_amount) == "100"
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

  describe "the correction's own confirm (ADR-0053 §6, A6; K7, K8, K15)" do
    # User story (ADR-0053 §6, K7):
    # As the operator whose instance imported a Portfolio Performance CSV
    # while the importer booked PP's gross Betrag as the cash,
    # I want to confirm the correction the re-dropped export lists,
    # so that every balance is what Portfolio Performance shows, with each
    # old amount kept in the journal.
    #
    # Acceptance criteria:
    # - Exactly the five listed bookings change, and in each only its cash.
    # - Every id and every content hash stays as it was.
    # - Each change is one journal update under the operator's actor,
    #   labelled an import correction, its before-image the stored cash and
    #   its after-image the file's.
    # - Every account's balance then equals the balance of the same export
    #   imported under today's reading: Pin-Cash 8,098.59 -> 8,076.48,
    #   Pin-Cash-2 700.00.
    # - The portfolio's derived values are invalidated (ADR-0039).
    # - A second drop lists nothing, and a second confirm changes and
    #   journals nothing.
    test "K7: a PP CSV's correction rewrites only the listed cash, keeps every hash, journals each change" do
      portfolio = portfolio!("Gesamtpreis correction")
      reference = portfolio!("Gesamtpreis reference")
      csv = fixture("hash_pin.csv")
      apply!(old_reading(parse!(csv, "export.csv")), portfolio)
      apply!(parse!(csv, "export.csv"), reference)

      assert balances(portfolio) == %{"Pin-Cash" => "8098.59", "Pin-Cash-2" => "700"}
      before = snapshot()
      version = Derived.current_version(DataVersion.portfolio_basis(portfolio.id))

      corrected = correct!(parse!(csv, "export.csv"), portfolio)

      assert Enum.map(corrected, & &1.row) == [3, 4, 6, 7, 17]
      after_ = snapshot()
      ids = Enum.map(corrected, & &1.transaction.id)

      assert changed_fields(before, after_) == Map.new(ids, &{&1, [:gross_amount]})
      assert identities(after_) == identities(before)

      journal = corrections_journal()
      assert length(journal) == 5
      assert Enum.all?(journal, &(&1.actor_type == :owner_ui))
      assert Enum.all?(journal, &(&1.actor_label == "import correction"))

      assert journal |> Enum.map(&String.to_integer(&1.resource_id)) |> Enum.sort() ==
               Enum.sort(ids)

      for entry <- journal do
        id = String.to_integer(entry.resource_id)
        assert Decimal.equal?(Decimal.new(entry.before["gross_amount"]), before[id].gross_amount)
        assert Decimal.equal?(Decimal.new(entry.after["gross_amount"]), after_[id].gross_amount)
        assert entry.before["import_hash"] == entry.after["import_hash"]
      end

      assert balances(portfolio) == %{"Pin-Cash" => "8076.48", "Pin-Cash-2" => "700"}
      assert balances(portfolio) == balances(reference)
      assert Derived.current_version(DataVersion.portfolio_basis(portfolio.id)) > version

      assert Imports.cash_corrections(parse!(csv, "export.csv"), portfolio_id: portfolio.id) ==
               []

      assert correct!(parse!(csv, "export.csv"), portfolio) == []
      assert snapshot() == after_
      assert length(corrections_journal()) == 5
    end

    # User story (ADR-0053 A1, A6, K15):
    # As the operator who imported a converter-written CSV whose sale's
    # negative Steuern was counted twice,
    # I want the correction to take the refund out of the sale's cash,
    # so that the account holds what the converter's file says.
    #
    # Acceptance criteria:
    # - Only the sale changes, and only its cash: +120.00 -> +95.00. Its
    #   price stays the file's Kurs, 10.00.
    # - Test-Cash 1,145.00 -> 1,120.00, the PP balance (K9).
    # - Hashes and ids stay; one journal update; a second drop lists
    #   nothing.
    test "K15: a converter CSV's correction takes the refund out of the sale's cash" do
      portfolio = portfolio!("Converter correction")
      apply!(old_reading(parse!(@converter_csv, "converter.csv")), portfolio)
      assert balances(portfolio) == %{"Test-Cash" => "1145"}
      before = snapshot()

      [item] = correct!(parse!(@converter_csv, "converter.csv"), portfolio)

      after_ = snapshot()
      assert changed_fields(before, after_) == %{item.transaction.id => [:gross_amount]}
      assert identities(after_) == identities(before)
      assert length(corrections_journal()) == 1

      sale = booking(portfolio, "sell")
      assert norm(sale.gross_amount) == "95"
      assert norm(sale.price) == "10"
      assert balances(portfolio) == %{"Test-Cash" => "1120"}

      assert Imports.cash_corrections(parse!(@converter_csv, "converter.csv"),
               portfolio_id: portfolio.id
             ) == []
    end

    # User story (ADR-0053 A2, A6, K15):
    # As the operator who imported a Portfolio Performance JSON export with
    # a negative tax unit before it was booked once,
    # I want the correction to rewrite the cash and a trade's price,
    # so that every balance is PP's and a sale's realized result leaves the
    # refund out.
    #
    # Acceptance criteria (K9's figures):
    # - sale_with_negative_tax.json: only the sale changes, its cash and its
    #   price: 120.00 -> 95.00 at 12.50 -> 10.00; Test-Cash 1,145.00 ->
    #   1,120.00; the refund stays 25.00.
    # - sample_with_negative_tax.json: only the dividend's cash changes,
    #   181.49 -> 181.48; Test-Cash 181.50 -> 181.49.
    # - Hashes and ids stay; each change is journaled with its price
    #   before and after; a second drop of each file lists nothing.
    test "K15: a JSON file's correction rewrites the cash and a trade's price" do
      sale_portfolio = portfolio!("JSON sale correction")
      sale_file = fixture("sale_with_negative_tax.json")
      apply!(old_reading(parse!(sale_file, "sale.json")), sale_portfolio)
      assert balances(sale_portfolio) == %{"Test-Cash" => "1145"}
      before = snapshot()

      [item] = correct!(parse!(sale_file, "sale.json"), sale_portfolio)

      after_ = snapshot()
      assert changed_fields(before, after_) == %{item.transaction.id => [:gross_amount, :price]}
      assert identities(after_) == identities(before)

      sale = booking(sale_portfolio, "sell")
      assert norm(sale.gross_amount) == "95"
      assert norm(sale.price) == "10"
      assert norm(booking(sale_portfolio, "tax_refund").gross_amount) == "25"
      assert balances(sale_portfolio) == %{"Test-Cash" => "1120"}

      assert [entry] = corrections_journal()
      assert {entry.before["price"], entry.after["price"]} == {"12.500000", "10.000000"}

      assert Imports.cash_corrections(parse!(sale_file, "sale.json"),
               portfolio_id: sale_portfolio.id
             ) == []

      dividend_portfolio = portfolio!("JSON dividend correction")
      dividend_file = fixture("sample_with_negative_tax.json")
      apply!(old_reading(parse!(dividend_file, "dividend.json")), dividend_portfolio)
      assert balances(dividend_portfolio) == %{"Test-Cash" => "181.5"}
      before = snapshot()

      [item] = correct!(parse!(dividend_file, "dividend.json"), dividend_portfolio)

      after_ = snapshot()
      assert changed_fields(before, after_) == %{item.transaction.id => [:gross_amount]}
      assert identities(after_) == identities(before)
      assert norm(booking(dividend_portfolio, "dividend").gross_amount) == "181.48"
      assert balances(dividend_portfolio) == %{"Test-Cash" => "181.49"}

      assert Imports.cash_corrections(parse!(dividend_file, "dividend.json"),
               portfolio_id: dividend_portfolio.id
             ) == []
    end

    # User story (ADR-0053 §6, ADR-0015, K15):
    # As the operator correcting a sale that settled a USD security through
    # a EUR account,
    # I want its settlement legs rewritten with its cash in the same write,
    # so that the settlement guard holds and the cost basis reads the
    # corrected trade.
    #
    # Acceptance criteria:
    # - The sale's cash, price, settlement amount and security amount
    #   change (95.00, 10.00, 100.00 EUR, 125.00 USD); its rate stays 0.80,
    #   the same stored hub rate on the same date; nothing else changes.
    # - No stored trade misses the settlement guard afterwards.
    test "K15: a cross-currency trade's settlement legs are rewritten with its cash" do
      usd_rate!()
      portfolio = portfolio!("Cross-currency correction")
      apply!(old_reading(parse!(@cross_currency_json, "fx.json")), portfolio)
      before = snapshot()

      [item] = correct!(parse!(@cross_currency_json, "fx.json"), portfolio)

      after_ = snapshot()

      assert changed_fields(before, after_) == %{
               item.transaction.id => [
                 :gross_amount,
                 :price,
                 :security_amount,
                 :settlement_amount
               ]
             }

      assert identities(after_) == identities(before)

      sale = after_[item.transaction.id]

      assert {norm(sale.gross_amount), norm(sale.price), norm(sale.settlement_amount),
              norm(sale.security_amount),
              norm(sale.settlement_fx_rate)} ==
               {"95", "10", "100", "125", "0.8"}

      assert SettlementGuard.violations() == []
      assert balances(portfolio) == %{"FX-Cash" => "1020"}
    end

    # User story (ADR-0053 §6, ADR-0050 §3, K8):
    # As the operator who confirms the import of a re-dropped file rather
    # than its correction,
    # I want the import to change no stored value,
    # so that a hash hit never rewrites a booking behind my back, whether or
    # not the preview listed a correction.
    #
    # Acceptance criteria:
    # - With the correction listed (a file stored under the old reading),
    #   the ordinary apply is all hash hits, inserts nothing and changes no
    #   stored value; the same bookings are still listed afterwards.
    # - Without one (a file stored as it reads today), the same holds and
    #   nothing is listed.
    test "K8: the ordinary apply of an all-hash-hit file changes no stored value" do
      for {name, body, listed} <- [
            {"export.csv", fixture("hash_pin.csv"), [3, 4, 6, 7, 17]},
            {"converter.csv", @converter_csv, [4]},
            {"sale.json", fixture("sale_with_negative_tax.json"), [3]}
          ] do
        portfolio = portfolio!("K8 #{name}")
        apply!(old_reading(parse!(body, name)), portfolio)

        listed_before = Imports.cash_corrections(parse!(body, name), portfolio_id: portfolio.id)
        assert Enum.map(listed_before, & &1.row) == listed, name
        before = snapshot()

        result = apply!(parse!(body, name), portfolio)

        assert result.created_transactions == 0, name
        assert result.already_imported.economics == 0, name
        assert snapshot() == before, name

        listed_after = Imports.cash_corrections(parse!(body, name), portfolio_id: portfolio.id)
        assert figures(listed_after) == figures(listed_before), name

        agreeing = portfolio!("K8 agreeing #{name}")
        apply!(parse!(body, name), agreeing)
        assert Imports.cash_corrections(parse!(body, name), portfolio_id: agreeing.id) == []
        before = snapshot()

        assert apply!(parse!(body, name), agreeing).created_transactions == 0, name
        assert snapshot() == before, name
      end

      assert corrections_journal() == []
    end
  end

  # ADR-0053's amendment of 2026-10-09, A10 to A12 (#1193, #1194, #1205;
  # Sprint 21 α7): the correction lists a stored booking whose row the
  # preview now refuses (A10), names a booking edited by hand since its
  # import instead of rewriting it (A11), and finds a drifted re-export's
  # row by its figures under A4's old-reading key (A12). Every figure is the
  # ADR's own, exact in Decimal; the names are its synthetic Test-Cash,
  # Test-Savings, Test-Depot and Arbolia Inc. (USEXMPL10014).
  describe "what the correction lists (ADR-0053 amendment of 2026-10-09, A10–A12)" do
    @arbolia %{"name" => "Arbolia Inc.", "isin" => "USEXMPL10014", "currency" => "EUR"}

    defp json(rows), do: Jason.encode!(%{"version" => 1, "transactions" => rows})

    defp deposit(date, amount),
      do: %{
        "type" => "DEPOSIT",
        "account" => "Test-Cash",
        "date" => date,
        "currency" => "EUR",
        "amount" => amount
      }

    defp purchase(date, shares, amount),
      do: %{
        "type" => "PURCHASE",
        "account" => "Test-Cash",
        "portfolio" => "Test-Depot",
        "date" => date,
        "time" => "10:00",
        "currency" => "EUR",
        "amount" => amount,
        "shares" => shares,
        "security" => @arbolia
      }

    # K9's shape: FEE 5.00 and TAX -25.00 beside the amount.
    defp sale(date, time, amount),
      do: %{
        "type" => "SALE",
        "account" => "Test-Cash",
        "portfolio" => "Test-Depot",
        "date" => date,
        "time" => time,
        "currency" => "EUR",
        "amount" => amount,
        "shares" => 10.0,
        "security" => @arbolia,
        "units" => [%{"type" => "FEE", "amount" => 5.0}, %{"type" => "TAX", "amount" => -25.0}]
      }

    defp dividend(date, amount),
      do: %{
        "type" => "DIVIDEND",
        "account" => "Test-Cash",
        "date" => date,
        "currency" => "EUR",
        "amount" => amount,
        "security" => @arbolia
      }

    defp parse_rows(rows) do
      {:ok, preview} = PortfolioPerformance.parse(json(rows), filename: "history.json")
      preview
    end

    # What an importer stored for a row A5, A8 or A9 now refuses before it
    # refused it: its would-be entry as the preview keeps it
    # (`refused_credits`), with the refund split off it beside it — the
    # reading of Sprint 20, which booked a JSON cash transfer's refund
    # (ADR-0053 K20).
    defp stored_as_refused(%Preview{entries: entries, refused_credits: refused} = preview) do
      refused_entries = Enum.map(refused, & &1.entry)

      %{
        preview
        | entries: Enum.sort_by(entries ++ refused_entries, & &1.source_row),
          refused_credits: [],
          errors: []
      }
    end

    # The same under the old reading, before A1.
    defp stored_with_refused(%Preview{} = preview), do: old_reading(stored_as_refused(preview))

    defp listed(preview, portfolio),
      do: Imports.cash_corrections(preview, portfolio_id: portfolio.id)

    defp states(items), do: Enum.map(items, &{&1.row, &1.state})

    # A refused line's cash accounts, each as stored, as the file states it,
    # and their difference.
    defp per_account(%Item{accounts: accounts}) do
      Map.new(accounts, fn %{account: account, booked: booked, stated: stated, delta: delta} ->
        {account.name, {norm(booked), norm(stated), norm(delta)}}
      end)
    end

    defp realized(portfolio) do
      sale = booking(portfolio, "sell")

      %{closed_trades: [trade]} =
        Ledger.list_trades_for_security(sale.security_id, latest_price: Decimal.new("10.00"))

      norm(trade.realized_pnl_abs)
    end

    # User story (#1193, Sprint 21 α7; ADR-0053 A10, K19):
    # As the operator who imported #1118's sale before A5 refused it,
    # I want the re-drop to list the stored sale per cash account, its
    # stored figure against the file's, without a confirm,
    # so that I see the 25.00 too much and replace the sale by hand, and no
    # write the ledger would refuse is ever offered.
    #
    # Acceptance criteria:
    # - Stored under the old reading (the sale at 20.10, priced 2.51, the
    #   refund 25.00 beside it), Test-Cash reads 945.10.
    # - The re-drop lists the sale, not correctable here: Test-Cash +45.10
    #   as stored, +20.10 as the file states, difference -25.00.
    # - Its row error still says the row is already imported, and points to
    #   the line: "… — already imported; listed under “Already imported,
    #   with a different amount”." (DE: „… — bereits importiert; aufgeführt
    #   unter „Bereits importiert, mit anderem Betrag“.“; board 07 ①).
    # - The confirm writes nothing: Test-Cash stays 945.10.
    test "K19: a stored sale the preview now refuses is listed without a confirm" do
      portfolio = portfolio!("K19")

      preview =
        parse_rows([
          deposit("2026-04-01", 1000.0),
          purchase("2026-04-02", 10.0, 100.0),
          sale("2026-04-15", "15:30", 20.10)
        ])

      assert [%{row: 3}] = preview.refused_credits
      apply!(stored_with_refused(preview), portfolio)
      assert balances(portfolio) == %{"Test-Cash" => "945.1"}
      assert norm(booking(portfolio, "sell").price) == "2.51"

      assert [%Item{row: 3, state: :refused} = line] = listed(preview, portfolio)
      assert per_account(line) == %{"Test-Cash" => {"45.1", "20.1", "-25"}}
      assert Map.get(line.refusal, :rule) == :a5

      assert [%{row: 3, message: message}] =
               Imports.row_errors(preview, portfolio_id: portfolio.id)

      assert message =~
               "— already imported; listed under “Already imported, with a different amount”."

      assert [%{row: 3, message: german}] =
               Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
                 [
                   deposit("2026-04-01", 1000.0),
                   purchase("2026-04-02", 10.0, 100.0),
                   sale("2026-04-15", "15:30", 20.10)
                 ]
                 |> parse_rows()
                 |> Imports.row_errors(portfolio_id: portfolio.id)
               end)

      assert german ==
               "Verkauf mit Gesamtpreis 20,10 und Steuererstattung 25,00: Dem Verkauf blieben " <>
                 "-4,90 — bereits importiert; aufgeführt unter „Bereits importiert, mit anderem " <>
                 "Betrag“."

      assert correct!(preview, portfolio) == []
      assert balances(portfolio) == %{"Test-Cash" => "945.1"}
      assert corrections_journal() == []
    end

    # User story (#1193, #1194, Sprint 21 α7; ADR-0053 A10, A11; board 07,
    # found while drawing 4):
    # As the operator who put a stored sale the preview now refuses right
    # by hand,
    # I want its line to read edited since its import, not refused,
    # so that I am not told again to replace a booking I already fixed.
    #
    # Acceptance criteria:
    # - K19's sale stored under the old reading (20.10, the refund 25.00
    #   beside it), then set to 0.10 by hand, its fees raised by 20.00 with
    #   it (a stated cash agrees with the figures, ADR-0053's amendment of
    #   2026-11-02): Test-Cash 925.10.
    # - The re-drop lists it as edited since its import (today), not
    #   refused: Test-Cash +25.10 as stored, +20.10 per the file; no
    #   confirm, and the confirm writes nothing.
    test "A10, A11: a refused booking edited by hand reads as edited" do
      portfolio = portfolio!("Refused, then edited")

      preview =
        parse_rows([
          deposit("2026-04-01", 1000.0),
          purchase("2026-04-02", 10.0, 100.0),
          sale("2026-04-15", "15:30", 20.10)
        ])

      apply!(stored_with_refused(preview), portfolio)

      sold = booking(portfolio, "sell")

      {:ok, _} =
        Ledger.update_transaction(Actor.owner_ui(), sold, %{
          gross_amount: "0.10",
          fees: Decimal.add(sold.fees || Decimal.new(0), Decimal.new("20.00"))
        })

      assert balances(portfolio) == %{"Test-Cash" => "925.1"}

      assert [%Item{row: 3, state: :edited} = line] = listed(preview, portfolio)
      assert line.edited_on == Date.utc_today()
      assert per_account(line) == %{"Test-Cash" => {"25.1", "20.1", "-5"}}

      assert correct!(preview, portfolio) == []
      assert balances(portfolio) == %{"Test-Cash" => "925.1"}
    end

    # User story (#1193, #1188, Sprint 21 α7; ADR-0053 A10, K20):
    # As the operator whose cash transfer with a tax refund was imported
    # before A8 refused it,
    # I want the re-drop to list the transfer on both its accounts, stored
    # against the file, without a confirm,
    # so that I see which account holds the refund PP never moved.
    #
    # Acceptance criteria:
    # - Stored under Sprint 20's reading (the transfer at 105.00, the
    #   refund 5.00 on Test-Cash): Test-Cash -100.00 as stored and as the
    #   file states; Test-Savings +105.00 as stored, +100.00 per the file.
    # - Stored under the old reading (the transfer at 100.00, the refund
    #   beside it): Test-Cash -95.00 against -100.00; Test-Savings +100.00
    #   on both sides.
    # - Nothing is written.
    test "K20: a stored transfer A8 now refuses is listed on both accounts without a confirm" do
      rows = [
        deposit("2026-02-09", 1000.0),
        %{
          "type" => "CASH_TRANSFER",
          "account" => "Test-Cash",
          "otherAccount" => "Test-Savings",
          "date" => "2026-02-10",
          "currency" => "EUR",
          "amount" => 100.0,
          "units" => [%{"type" => "TAX", "amount" => -5.0}]
        }
      ]

      refused = parse_rows(rows)
      assert [%{row: 2}] = refused.refused_credits

      sprint20 = portfolio!("K20 Sprint 20 reading")
      apply!(stored_as_refused(refused), sprint20)
      assert balances(sprint20) == %{"Test-Cash" => "900", "Test-Savings" => "105"}

      assert [%Item{row: 2, state: :refused} = line] = listed(refused, sprint20)

      assert per_account(line) == %{
               "Test-Cash" => {"-100", "-100", "0"},
               "Test-Savings" => {"105", "100", "-5"}
             }

      assert Map.get(line.refusal, :rule) == :a8

      assert correct!(refused, sprint20) == []
      assert balances(sprint20) == %{"Test-Cash" => "900", "Test-Savings" => "105"}

      old = portfolio!("K20 old reading")
      apply!(stored_with_refused(refused), old)
      assert [%Item{row: 2, state: :refused} = line] = listed(refused, old)

      assert per_account(line) == %{
               "Test-Cash" => {"-95", "-100", "-5"},
               "Test-Savings" => {"100", "100", "0"}
             }

      assert correct!(refused, old) == []
      assert corrections_journal() == []
    end

    # A JSON sale of 10 Arbolia Inc. with A9's fee units (FEE 5.00 and FEE
    # -2.00) beside `units`, after a deposit of 1,000.00 and a purchase of
    # 100.00.
    defp fee_refund_history(units) do
      [
        deposit("2026-04-01", 1000.0),
        purchase("2026-04-02", 10.0, 100.0),
        %{
          sale("2026-04-15", "15:30", 120.0)
          | "units" =>
              [%{"type" => "FEE", "amount" => 5.0}, %{"type" => "FEE", "amount" => -2.0}] ++ units
        }
      ]
    end

    # User story (#1193, #1177, Sprint 21 α7; ADR-0053 A9, A10):
    # As the operator who imported a JSON sale with a refunded fee before A9
    # refused it,
    # I want the re-drop to leave it out of the correction when no cash
    # account's stored figure differs,
    # so that no line asks me to change a sale whose cash is already right.
    #
    # Acceptance criteria:
    # - Stored as the file states it (the sale at 120.00, fees 7.00, no
    #   negative tax): Test-Cash 1,020.00, and nothing is listed.
    # - Its row error still says that the row is already imported and
    #   cannot be corrected here: it is listed nowhere to point to.
    test "A10: a stored A9 sale whose every account agrees is not listed" do
      portfolio = portfolio!("A9 agreeing")
      preview = parse_rows(fee_refund_history([]))

      assert [%{row: 3}] = preview.refused_credits
      apply!(stored_as_refused(preview), portfolio)
      assert balances(portfolio) == %{"Test-Cash" => "1020"}
      assert norm(booking(portfolio, "sell").fees) == "7"

      assert listed(preview, portfolio) == []

      assert [%{row: 3, message: message}] =
               Imports.row_errors(preview, portfolio_id: portfolio.id)

      assert message =~ "— already imported with fees of 7.00, and it cannot be corrected here."
    end

    # User story (#1193, #1177, Sprint 21 α7; ADR-0053 A9, A10):
    # As the operator whose JSON sale with a refunded fee and a tax refund
    # was imported under the old reading,
    # I want the line to carry the rule that refused its row, A9,
    # so that its remedy is A9's (its fees stay as stored) and not A5's.
    #
    # Acceptance criteria:
    # - Stored under the old reading (the sale at 120.00, the refund 25.00
    #   beside it): Test-Cash 1,045.00.
    # - Listed, not correctable here: Test-Cash +145.00 as stored, +120.00
    #   as the file states, difference -25.00; its refusal names A9, and the
    #   cash a hand correction sets, 95.00.
    # - Its row error names its fees as stored and points to the line, in
    #   English and in German.
    # - K19's sale carries A5, K20's transfer A8.
    test "A10: a stored A9 sale with a tax refund is listed under A9's rule" do
      portfolio = portfolio!("A9 with a tax refund")
      preview = parse_rows(fee_refund_history([%{"type" => "TAX", "amount" => -25.0}]))

      assert [%{row: 3}] = preview.refused_credits
      apply!(stored_with_refused(preview), portfolio)
      assert balances(portfolio) == %{"Test-Cash" => "1045"}

      assert [%Item{row: 3, state: :refused, refusal: refusal} = line] =
               listed(preview, portfolio)

      assert per_account(line) == %{"Test-Cash" => {"145", "120", "-25"}}
      assert Map.get(refusal, :rule) == :a9
      assert norm(refusal.rest) == "95"
      assert correct!(preview, portfolio) == []

      assert [%{row: 3, message: message}] =
               Imports.row_errors(preview, portfolio_id: portfolio.id)

      assert message ==
               "sell with a negative fee (-2.00): the import does not book a fee refund yet — " <>
                 "already imported with fees of 7.00; listed under “Already imported, with a " <>
                 "different amount”."

      german =
        Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
          preview = parse_rows(fee_refund_history([%{"type" => "TAX", "amount" => -25.0}]))
          Imports.row_errors(preview, portfolio_id: portfolio.id)
        end)

      assert [%{row: 3, message: message}] = german

      assert message ==
               "Verkauf mit einer negativen Gebühr (-2,00): Eine Gebührenerstattung bucht der " <>
                 "Import noch nicht — bereits importiert mit Gebühren von 7,00; aufgeführt " <>
                 "unter „Bereits importiert, mit anderem Betrag“."
    end

    # User story (#1194, Sprint 21 α7; ADR-0053 A11, K21, K26):
    # As the operator who set a dividend's amount by hand after importing it,
    # I want the re-drop to name it as edited since its import and leave it,
    # so that a correction never rewrites a figure I made, while the sale
    # stored under the old reading is still corrected.
    #
    # Acceptance criteria:
    # - Stored under the old reading: Test-Cash 1,154.13; the dividend set
    #   to 9.20 by hand: 1,154.20.
    # - The re-drop lists the sale with a confirm (120.00 → 95.00, price
    #   12.50 → 10.00) and the dividend as edited since its import (9.20
    #   stored, 9.13 per the file), without a confirm.
    # - After the confirm Test-Cash reads 1,129.20: PP's 1,129.13 plus the
    #   operator's 0.07, kept. The journal holds one update, under
    #   `owner_ui` labelled "import correction", with its before-image.
    # - A second drop lists the dividend alone, still edited, with no
    #   confirm.
    test "K21: a booking edited by hand since its import is named, not rewritten" do
      portfolio = portfolio!("K21")

      rows = [
        deposit("2026-03-02", 1100.0),
        purchase("2026-03-03", 10.0, 100.0),
        dividend("2026-05-15", 9.13),
        sale("2026-06-15", "15:30", 120.0)
      ]

      apply!(old_reading(parse_rows(rows)), portfolio)
      assert balances(portfolio) == %{"Test-Cash" => "1154.13"}

      {:ok, _} =
        Ledger.update_transaction(Actor.owner_ui(), booking(portfolio, "dividend"), %{
          gross_amount: "9.20"
        })

      assert balances(portfolio) == %{"Test-Cash" => "1154.2"}

      items = listed(parse_rows(rows), portfolio)
      assert states(items) == [{3, :edited}, {4, :confirm}]
      assert figures(items) == [{3, "9.2", "9.13", "-0.07"}, {4, "120", "95", "-25"}]
      [edited, sale_line] = items
      assert edited.edited_on == Date.utc_today()
      assert norm(sale_line.changes.price) == "10"

      [corrected] = correct!(parse_rows(rows), portfolio)
      assert corrected.row == 4
      assert balances(portfolio) == %{"Test-Cash" => "1129.2"}
      assert norm(booking(portfolio, "dividend").gross_amount) == "9.2"

      assert [entry] =
               corrections_journal() |> Enum.filter(&(&1.actor_label == "import correction"))

      assert entry.actor_type == :owner_ui
      assert entry.resource_id == to_string(corrected.transaction.id)
      assert entry.before["gross_amount"] == "120.000000"

      assert states(listed(parse_rows(rows), portfolio)) == [{3, :edited}]
    end

    # User story (#1194, Sprint 21 α7; ADR-0053 A11, K21's last sentence):
    # As the operator whose cross-currency sale got its settlement legs from
    # the backfill after its import,
    # I want that sale still corrected,
    # so that a system job's legs never count as a hand edit.
    #
    # Acceptance criteria:
    # - The sale's only update since its import is the backfill's
    #   (`system_job`, "settlement_backfill"); the re-drop lists it with a
    #   confirm, and the confirm corrects it.
    test "K21: a sale whose only update is the backfill's legs keeps its confirm" do
      portfolio = portfolio!("K21 backfill")
      apply!(old_reading(parse!(@cross_currency_json, "fx.json")), portfolio)
      assert booking(portfolio, "sell").security_amount == nil

      :ok = usd_rate!()

      assert {:ok, %{updated: updated}} =
               Ledger.SettlementBackfill.run(Actor.system_job("settlement_backfill"))

      assert updated >= 1
      assert %Decimal{} = booking(portfolio, "sell").security_amount

      assert [%Item{row: 3, state: :confirm}] =
               listed(parse!(@cross_currency_json, "fx.json"), portfolio)

      assert [%Item{row: 3}] = correct!(parse!(@cross_currency_json, "fx.json"), portfolio)
      assert norm(booking(portfolio, "sell").gross_amount) == "95"
    end

    # User story (#1194, Sprint 21 α7; ADR-0053 A11, K22):
    # As the operator whose JSON sale holds the file's cash but the old price,
    # I want it listed on its price with a confirm that writes the price
    # alone,
    # so that its realized result leaves the refund out.
    #
    # Acceptance criteria:
    # - Stored at the cash 95.00 and the price 12.50, its journal holding no
    #   other actor's edit: the realized result reads +20.00.
    # - The re-drop lists it with a confirm: 95.00 on both sides (0.00) and
    #   the price 12.50 → 10.00.
    # - The confirm writes the price alone; the realized result reads -5.00.
    test "K22: a JSON sale whose cash agrees is listed on its price" do
      portfolio = portfolio!("K22")

      rows = [
        deposit("2026-03-02", 1100.0),
        purchase("2026-03-03", 10.0, 100.0),
        sale("2026-06-15", "15:30", 120.0)
      ]

      apply!(parse_rows(rows), portfolio)

      store_old_price!(booking(portfolio, "sell"), "12.50")

      assert realized(portfolio) == "20"

      assert [%Item{row: 3, state: :confirm, changes: changes} = line] =
               listed(parse_rows(rows), portfolio)

      assert figures([line]) == [{3, "95", "95", "0"}]
      assert Map.keys(changes) == [:price]
      assert norm(changes.price) == "10"

      before = snapshot()
      correct!(parse_rows(rows), portfolio)
      assert changed_fields(before, snapshot()) == %{line.transaction.id => [:price]}
      assert realized(portfolio) == "-5"
    end

    # User story (#1205, Sprint 21 α7; ADR-0053 A12, K23, K26):
    # As the operator re-dropping a re-export whose sale's time moved by a
    # minute,
    # I want the sale stored under the old reading found by its figures and
    # offered for correction,
    # so that a drifted re-export does not leave it 25.00 too high without a
    # word.
    #
    # Acceptance criteria:
    # - Stored under the old reading: Test-Cash 1,145.00. The re-export
    #   (15:30 → 15:31) books nothing.
    # - It lists the sale as matched by its figures, with a confirm:
    #   120.00 → 95.00, price 12.50 → 10.00.
    # - After the confirm Test-Cash reads 1,120.00, PP's balance; a second
    #   drop lists nothing.
    test "K23: a drifted re-export's row is matched by its figures, with a confirm" do
      portfolio = portfolio!("K23")
      history = [deposit("2026-03-02", 1100.0), purchase("2026-03-03", 10.0, 100.0)]
      apply!(old_reading(parse_rows(history ++ [sale("2026-06-15", "15:30", 120.0)])), portfolio)
      assert balances(portfolio) == %{"Test-Cash" => "1145"}

      drifted = history ++ [sale("2026-06-15", "15:31", 120.0)]
      before = snapshot()
      assert apply!(parse_rows(drifted), portfolio).created_transactions == 0
      assert snapshot() == before

      assert [%Item{row: 3, state: :confirm, match: :figures, changes: changes} = line] =
               listed(parse_rows(drifted), portfolio)

      assert figures([line]) == [{3, "120", "95", "-25"}]
      assert norm(changes.price) == "10"

      assert [_corrected] = correct!(parse_rows(drifted), portfolio)
      assert balances(portfolio) == %{"Test-Cash" => "1120"}
      assert listed(parse_rows(drifted), portfolio) == []
    end

    # User story (#1205, #1194, Sprint 21 α7; ADR-0053 A11, A12; the
    # decision noted under A12 on 2026-10-31):
    # As the operator who booked a sale by hand, with the figures an old
    # import would have stored,
    # I want a drifted re-export's row that its figures match to name it as
    # made by hand, without a confirm,
    # so that a correction never rewrites a figure I made, whether I edited
    # an imported booking or entered it myself.
    #
    # Acceptance criteria:
    # - K23's history stored under the old reading, its sale then deleted
    #   and entered again by hand with the same figures (120.00, price
    #   12.50, no import hash): Test-Cash 1,145.00.
    # - The drifted re-export (15:30 → 15:31) lists the sale as matched by
    #   its figures, edited since its import (the date of its entry), with
    #   no confirm; the confirm writes nothing and Test-Cash stays 1,145.00.
    test "A12: a booking entered by hand that a drifted row's figures match is named, not rewritten" do
      portfolio = portfolio!("A12 by hand")
      history = [deposit("2026-03-02", 1100.0), purchase("2026-03-03", 10.0, 100.0)]
      apply!(old_reading(parse_rows(history ++ [sale("2026-06-15", "15:30", 120.0)])), portfolio)

      imported = booking(portfolio, "sell")
      {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), imported)

      {:ok, by_hand} =
        Ledger.create_transaction(
          Actor.owner_ui(),
          imported
          |> Map.take(@fields -- [:id, :import_hash])
          |> Map.reject(fn {_field, value} -> is_nil(value) end)
        )

      assert is_nil(by_hand.import_hash)
      assert balances(portfolio) == %{"Test-Cash" => "1145"}

      drifted = history ++ [sale("2026-06-15", "15:31", 120.0)]

      assert [%Item{row: 3, match: :figures} = line] = listed(parse_rows(drifted), portfolio)
      assert line.transaction.id == by_hand.id
      assert line.state == :edited
      assert line.edited_on == Date.utc_today()

      assert correct!(parse_rows(drifted), portfolio) == []
      assert balances(portfolio) == %{"Test-Cash" => "1145"}
      assert corrections_journal() == []
    end

    # The simulations the test process starts (each opens its read-only
    # transaction with this statement), counted while `fun` runs.
    defp simulations(fun) do
      test_pid = self()
      handler = "correction-simulations-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler,
          [:portfolixir, :repo, :query],
          fn _event, _measurements, metadata, _config ->
            if self() == test_pid and metadata[:query] == "SET TRANSACTION READ ONLY",
              do: send(test_pid, :simulation)
          end,
          nil
        )

      try do
        result = fun.()
        {result, count_simulations(0)}
      after
        :telemetry.detach(handler)
      end
    end

    defp count_simulations(n) do
      receive do
        :simulation -> count_simulations(n + 1)
      after
        0 -> n
      end
    end

    # User story (#1205, Sprint 21 α7; ADR-0053 A12, the follow-up on the
    # dry run's cost):
    # As the operator dropping a large file,
    # I want the correction to run the apply's simulation only when a row
    # could be matched by its figures,
    # so that a re-drop whose rows all hit their hashes, or a file no old
    # reading can match, is listed in the time the hash lookup takes.
    #
    # Acceptance criteria:
    # - K23's history stored under the old reading. Its own re-drop (every
    #   row a hash hit) lists the sale by its hash and runs no simulation.
    # - The same file with a new dividend (no hash hit, but its cash is what
    #   its hash reads, so no old reading differs) runs none either.
    # - The drifted re-export in a portfolio that holds no booking runs none
    #   and lists nothing.
    # - The drifted re-export in the stored portfolio runs one, and lists
    #   the sale by its figures.
    test "A12: the simulation runs only when a row without a hash hit has an old reading" do
      portfolio = portfolio!("A12 the run")
      history = [deposit("2026-03-02", 1100.0), purchase("2026-03-03", 10.0, 100.0)]
      stored = history ++ [sale("2026-06-15", "15:30", 120.0)]
      apply!(old_reading(parse_rows(stored)), portfolio)

      assert {[%Item{row: 3, match: :hash}], 0} =
               simulations(fn -> listed(parse_rows(stored), portfolio) end)

      with_dividend = stored ++ [dividend("2026-07-15", 9.13)]

      assert {[%Item{row: 3, match: :hash}], 0} =
               simulations(fn -> listed(parse_rows(with_dividend), portfolio) end)

      drifted = history ++ [sale("2026-06-15", "15:31", 120.0)]
      empty = portfolio!("A12 holds nothing")
      assert {[], 0} = simulations(fn -> listed(parse_rows(drifted), empty) end)

      assert {[%Item{row: 3, match: :figures}], 1} =
               simulations(fn -> listed(parse_rows(drifted), portfolio) end)
    end

    # User story (#1205, #1193, Sprint 21 α7; the plan's D-7 and the lock
    # table's row 10):
    # As the operator whose confirm locks many bookings of a portfolio,
    # I want it to lock them in id order,
    # so that two writers taking the same bookings never take them in
    # opposite orders.
    #
    # Acceptance criteria:
    # - In K23's drifted world, every statement the confirm sends that locks
    #   several bookings (`FOR NO KEY UPDATE` on `transactions`, not the
    #   journal's lock of one row by its id) orders them by id.
    test "the confirm takes the bookings' row locks in id order" do
      portfolio = portfolio!("Row locks by id")
      history = [deposit("2026-03-02", 1100.0), purchase("2026-03-03", 10.0, 100.0)]
      apply!(old_reading(parse_rows(history ++ [sale("2026-06-15", "15:30", 120.0)])), portfolio)
      drifted = parse_rows(history ++ [sale("2026-06-15", "15:31", 120.0)])

      test_pid = self()
      handler = "correction-row-locks-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler,
          [:portfolixir, :repo, :query],
          fn _event, _measurements, metadata, _config ->
            query = metadata[:query]

            if self() == test_pid and is_binary(query) and
                 String.starts_with?(query, ~s(SELECT)) and
                 query =~ ~s(FROM "transactions") and query =~ "FOR NO KEY UPDATE" and
                 not String.contains?(query, "\"id\" = $1)"),
               do: send(test_pid, {:row_lock, query})
          end,
          nil
        )

      try do
        assert [_corrected] = correct!(drifted, portfolio)
      after
        :telemetry.detach(handler)
      end

      locks = Stream.repeatedly(fn -> receive do: ({:row_lock, q} -> q), after: (0 -> nil) end)
      locks = Enum.take_while(locks, & &1)

      assert length(locks) >= 2
      assert Enum.all?(locks, &(&1 =~ ~r/ORDER BY \w+\."id"/)), Enum.join(locks, "\n")
    end

    # User story (#1205, Sprint 21 α7; ADR-0053 A12's twin rule, K24):
    # As the operator with two equal sales on one day,
    # I want a row matched by its figures corrected only when exactly one
    # stored booking holds them and no other row claims it,
    # so that the correction never corrects the wrong twin.
    #
    # Acceptance criteria:
    # - Stored under the old reading: Test-Cash 1,190.00 (PP: 1,140.00).
    # - (i) Both times moved: both sales are listed, two bookings matching
    #   each; nothing is confirmable and the confirm writes nothing.
    # - (ii) Only B's time moved: A is listed with a confirm (its hash
    #   hit), B without one (two bookings match). The confirm corrects A:
    #   1,165.00. A second drop lists B with a confirm (one booking
    #   matches now); its confirm brings Test-Cash to 1,140.00.
    test "K24: a row matched by its figures has a confirm only without a twin" do
      history = [deposit("2026-06-01", 1100.0), purchase("2026-06-02", 20.0, 200.0)]
      stored = history ++ [sale("2026-06-15", "15:30", 120.0), sale("2026-06-15", "16:10", 120.0)]

      both = portfolio!("K24 both moved")
      apply!(old_reading(parse_rows(stored)), both)
      assert balances(both) == %{"Test-Cash" => "1190"}

      both_moved =
        history ++ [sale("2026-06-15", "15:31", 120.0), sale("2026-06-15", "16:11", 120.0)]

      items = listed(parse_rows(both_moved), both)
      assert states(items) == [{3, :twin}, {4, :twin}]
      assert Enum.all?(items, &(&1.matches == 2))
      assert correct!(parse_rows(both_moved), both) == []
      assert balances(both) == %{"Test-Cash" => "1190"}

      one = portfolio!("K24 B moved")
      apply!(old_reading(parse_rows(stored)), one)

      b_moved =
        history ++ [sale("2026-06-15", "15:30", 120.0), sale("2026-06-15", "16:11", 120.0)]

      items = listed(parse_rows(b_moved), one)
      assert states(items) == [{3, :confirm}, {4, :twin}]
      assert Enum.map(items, & &1.match) == [:hash, :figures]

      assert [%Item{row: 3}] = correct!(parse_rows(b_moved), one)
      assert balances(one) == %{"Test-Cash" => "1165"}

      assert [%Item{row: 4, state: :confirm, match: :figures}] = listed(parse_rows(b_moved), one)
      assert [%Item{row: 4}] = correct!(parse_rows(b_moved), one)
      assert balances(one) == %{"Test-Cash" => "1140"}
    end

    # User story (#1205, #1193, Sprint 21 α7; ADR-0053 A1, A6 on A12's
    # figure path, the twin rule applied to split-off refunds):
    # As the operator with two sales on one day, each with an equal refund
    # split off it, who has since deleted one of those refunds by hand,
    # I want a drifted re-export to count one stored refund for one row
    # only,
    # so that a confirm never takes out a refund the account no longer
    # holds and leaves the cash below the file.
    #
    # Acceptance criteria:
    # - Stored under the old reading: sale A 120.00 and sale B 130.00, each
    #   with a 25.00 refund beside it; Test-Cash 1,200.00 (PP: 1,150.00).
    # - Both refunds stored, the drifted re-export (15:30 → 15:31, 16:10 →
    #   16:11) lists both sales by their figures with a confirm; the
    #   confirm brings Test-Cash to 1,150.00.
    # - B's refund deleted by hand (Test-Cash 1,175.00): the one stored
    #   refund cannot be told apart by its figures, so neither sale is
    #   listed, the confirm writes nothing, and Test-Cash stays 1,175.00,
    #   never 1,125.00.
    test "A12: one stored refund counts as the split-off refund of one row only" do
      history = [deposit("2026-06-01", 1100.0), purchase("2026-06-02", 20.0, 200.0)]
      stored = history ++ [sale("2026-06-15", "15:30", 120.0), sale("2026-06-15", "16:10", 130.0)]

      drifted =
        history ++ [sale("2026-06-15", "15:31", 120.0), sale("2026-06-15", "16:11", 130.0)]

      both = portfolio!("Both refunds stored")
      apply!(old_reading(parse_rows(stored)), both)
      assert balances(both) == %{"Test-Cash" => "1200"}

      items = listed(parse_rows(drifted), both)
      assert states(items) == [{3, :confirm}, {4, :confirm}]
      assert Enum.all?(items, &(&1.match == :figures))
      assert figures(items) == [{3, "120", "95", "-25"}, {4, "130", "105", "-25"}]
      assert [_a, _b] = correct!(parse_rows(drifted), both)
      assert balances(both) == %{"Test-Cash" => "1150"}

      one = portfolio!("B's refund deleted")
      apply!(old_reading(parse_rows(stored)), one)

      b_refund =
        one.id
        |> Ledger.list_transactions_for_portfolio()
        |> Enum.filter(&(&1.type == "tax_refund"))
        |> Enum.max_by(& &1.id)

      {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), b_refund)
      assert balances(one) == %{"Test-Cash" => "1175"}
      before = snapshot()

      assert listed(parse_rows(drifted), one) == []
      assert correct!(parse_rows(drifted), one) == []
      assert snapshot() == before
      assert balances(one) == %{"Test-Cash" => "1175"}
    end

    # User story (#1205, Sprint 21 α7; ADR-0053's note of 2026-10-31 under
    # A12, "the confirm writes what its dialog offered"):
    # As the operator who confirms the lines a dialog offered,
    # I want each line matched by its file row and its stored booking,
    # so that a booking offered for one row is never written with another
    # row's figures.
    #
    # Acceptance criteria:
    # - K23's drifted sale (row 3) offered as row 4 is not written: nothing
    #   corrected, row 3 answered as found since, Test-Cash stays 1,145.00.
    # - Offered as row 3, it is corrected: Test-Cash 1,120.00.
    test "the listed confirm writes a line only by its row and booking" do
      portfolio = portfolio!("Listed confirm")
      history = [deposit("2026-03-02", 1100.0), purchase("2026-03-03", 10.0, 100.0)]
      apply!(old_reading(parse_rows(history ++ [sale("2026-06-15", "15:30", 120.0)])), portfolio)
      drifted = parse_rows(history ++ [sale("2026-06-15", "15:31", 120.0)])
      [%Item{row: 3, transaction: %{id: id}}] = listed(drifted, portfolio)
      actor = Imports.correction_actor()

      assert {:ok, [], [%Item{row: 3}]} =
               Imports.correct_listed_cash(actor, drifted, [{4, id}], portfolio_id: portfolio.id)

      assert balances(portfolio) == %{"Test-Cash" => "1145"}

      assert {:ok, [%Item{row: 3}], []} =
               Imports.correct_listed_cash(actor, drifted, [{3, id}], portfolio_id: portfolio.id)

      assert balances(portfolio) == %{"Test-Cash" => "1120"}
    end

    # User story (Sprint 21 α7, the plan's round trip 3; ADR-0053 K19, K21
    # and K23 on one account, K26):
    # As the operator re-dropping a JSON history imported under the old
    # reading, with one booking edited by hand, one row whose time drifted,
    # and one stored sale the preview now refuses,
    # I want exactly those three lines, and a confirm that corrects the
    # drifted sale alone,
    # so that the 25.07 left on the account is named on the page.
    #
    # Acceptance criteria:
    # - PP shows Test-Cash at 1,049.23; stored under the old reading it reads
    #   1,099.23 (the refused sale's 25.00 and the drifted sale's 25.00 too
    #   high); after the hand edit of 0.07, 1,099.30.
    # - The re-drop lists the refused sale (no confirm), the dividend as
    #   edited (no confirm), and the drifted sale matched by its figures,
    #   with a confirm.
    # - After the confirm Test-Cash reads 1,074.30: 25.07 above PP, the
    #   refused sale's 25.00 and the kept edit's 0.07, each still listed.
    test "round trip 3: the refused, the edited and the drifted on one account" do
      portfolio = portfolio!("Round trip 3")

      history = fn time ->
        [
          deposit("2026-03-02", 1100.0),
          purchase("2026-03-03", 10.0, 100.0),
          purchase("2026-04-02", 10.0, 100.0),
          sale("2026-04-15", "11:00", 20.10),
          dividend("2026-05-15", 9.13),
          sale("2026-06-15", time, 120.0)
        ]
      end

      apply!(stored_with_refused(parse_rows(history.("15:30"))), portfolio)
      assert balances(portfolio) == %{"Test-Cash" => "1099.23"}

      {:ok, _} =
        Ledger.update_transaction(Actor.owner_ui(), booking(portfolio, "dividend"), %{
          gross_amount: "9.20"
        })

      assert balances(portfolio) == %{"Test-Cash" => "1099.3"}

      drifted = parse_rows(history.("15:31"))
      items = listed(drifted, portfolio)
      assert states(items) == [{4, :refused}, {5, :edited}, {6, :confirm}]
      assert Enum.map(items, & &1.match) == [:hash, :hash, :figures]

      assert [%Item{row: 6}] = correct!(drifted, portfolio)
      assert balances(portfolio) == %{"Test-Cash" => "1074.3"}
      assert states(listed(drifted, portfolio)) == [{4, :refused}, {5, :edited}]
    end
  end

  # A sale stored with the file's cash and an older price, as an import
  # stored it before ADR-0053 A2; written below the ledger, since an edit of
  # the price alone on a stored-cash trade states its cash since #1371 (the
  # ADR-0053 amendment of 2026-11-02). No actor's edit is journaled.
  defp store_old_price!(%Transaction{} = row, price) do
    {:ok, stored} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'import_session', true)")
        row |> Ecto.Changeset.change(price: Decimal.new(price)) |> Repo.update!()
      end)

    stored
  end
end
