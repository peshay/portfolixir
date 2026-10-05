defmodule Portfolixir.Imports.CsvGesamtpreisReimportTest do
  # ADR-0053 §3, §4 and K3 (risk-tier: import idempotency, ADR-0036). An
  # instance that imported a Portfolio Performance CSV while the importer
  # booked the Betrag must book nothing when the same history is dropped
  # again under the Gesamtpreis reading (ADR-0050 §2, "a file already
  # applied is a no-op").
  #
  # The old reading is reproduced by blanking the Gesamtpreis column: a row
  # without one books its Betrag, exactly as every row booked before
  # ADR-0053. Every name and amount is synthetic.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  # hash_pin.csv: 17 rows, one of which splits off a refund.
  @entries 18

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Gesamtpreis target",
        base_currency_code: "EUR"
      })

    %{portfolio: portfolio}
  end

  defp pp_file, do: File.read!(Path.join(@fixtures, "hash_pin.csv"))

  # The Gesamtpreis column, the ninth, emptied on every row.
  defp old_reading(csv) do
    csv
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.map_join("\n", fn
      {line, 0} -> line
      {"", _index} -> ""
      {line, _index} -> line |> String.split(";") |> List.replace_at(8, "") |> Enum.join(";")
    end)
  end

  # A re-export whose every time of day moved by one second: no row keeps
  # its content hash, and no booked field changes.
  defp drifted(csv) do
    Regex.replace(~r/^(\d{4}-\d\d-\d\d \d\d:\d\d):00;/m, csv, "\\1:01;")
  end

  defp parse!(csv) do
    {:ok, preview} = PortfolioPerformance.parse(csv, filename: "export.csv")
    assert preview.errors == []
    preview
  end

  defp apply!(csv, portfolio) do
    assert {:ok, %Result{} = result} =
             Imports.apply(parse!(csv), %{portfolio_id: portfolio.id})

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

  defp cash_balances(portfolio) do
    Ledger.cash_balances(portfolio_id: portfolio.id)
  end

  # User story (ADR-0053 §1, §3):
  # As the operator dropping a hand-made CSV whose rows give only a
  # Gesamtpreis,
  # I want two such rows on one day and one account to book both,
  # so that a blank Betrag never makes two different bookings one.
  #
  # Acceptance criteria:
  # - Two Einlage rows on one day, one account, with a blank Betrag and the
  #   Gesamtpreis 250,00 and 300,00 book two transactions, 550,00 in all:
  #   their hashes read the Gesamtpreis each books, never a shared blank
  #   (no such row was importable before ADR-0053, so no blank hash is
  #   stored).
  test "two rows with only a Gesamtpreis on one day and one account both book", %{
    portfolio: portfolio
  } do
    csv = """
    Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
    2024-01-02 00:00:00;Einlage;;;;;;;250,00;Gift-Cash;;;
    2024-01-02 00:00:00;Einlage;;;;;;;300,00;Gift-Cash;;;
    """

    result = apply!(csv, portfolio)

    assert result.created_transactions == 2
    assert result.duplicate_entries == []
    assert [balance] = portfolio |> cash_balances() |> Map.values()
    assert Decimal.equal?(balance, Decimal.new("550.00"))
  end

  # User story (ADR-0053 K3):
  # As the operator whose instance imported a Portfolio Performance CSV
  # before the importer booked its Gesamtpreis,
  # I want dropping the same export again to book nothing,
  # so that the reading's change never books a row of mine twice.
  #
  # Acceptance criteria:
  # - The export applied under the old reading, then dropped as Portfolio
  #   Performance wrote it, inserts no transaction and creates no cash
  #   account, depot or security; every entry, the split-off refund
  #   included, is a hash hit.
  # - The preview counts every entry as already imported by its hash.
  # - No stored value changes.
  test "a PP CSV applied under the old reading and dropped again books nothing", %{
    portfolio: portfolio
  } do
    first = apply!(old_reading(pp_file()), portfolio)
    assert first.created_transactions == @entries

    before = counts()
    balances = cash_balances(portfolio)

    preview = parse!(pp_file())
    counted = Imports.reimport_counts(preview, portfolio_id: portfolio.id)
    assert counted.total.hash == @entries
    assert counted.total.new == 0

    again = apply!(pp_file(), portfolio)

    assert again.created_transactions == 0
    assert again.created_cash_accounts == 0
    assert again.created_securities_accounts == 0
    assert again.created_securities == 0
    assert again.already_imported == %{hash: @entries, retired: 0, economics: 0}
    assert counts() == before
    assert cash_balances(portfolio) == balances
  end

  # User story (ADR-0053 §4):
  # As the operator whose fresh Portfolio Performance export moved a time of
  # day since the first import,
  # I want the rows booked under the old reading recognised by their
  # booking, even though their content hash and their cash moved,
  # so that a drifted re-export books nothing twice either.
  #
  # Acceptance criteria:
  # - The re-export's every time of day moved, so no content hash matches;
  #   every row is skipped as an equal economic booking, the rows whose
  #   Gesamtpreis differs from the stored Betrag through the key read with
  #   their Betrag, and the result names each row it skipped.
  # - The preview counts every entry under `economics`, none as new.
  # - Nothing is inserted or created, and no balance moves.
  test "a drifted re-export is recognised by the Betrag reading's economic key", %{
    portfolio: portfolio
  } do
    first = apply!(old_reading(pp_file()), portfolio)
    assert first.created_transactions == @entries

    before = counts()
    balances = cash_balances(portfolio)
    export = drifted(pp_file())
    refute export == pp_file()

    preview = parse!(export)
    counted = Imports.reimport_counts(preview, portfolio_id: portfolio.id)
    assert counted.total.economics == @entries
    assert counted.total.new == 0

    again = apply!(export, portfolio)

    assert again.created_transactions == 0
    assert again.already_imported == %{hash: 0, retired: 0, economics: @entries}

    assert again.duplicate_entries |> Enum.map(& &1.row) |> Enum.sort_by(&to_string/1) ==
             Enum.sort_by(Enum.to_list(1..17) ++ ["5.tax_refund.1"], &to_string/1)

    assert Enum.all?(again.duplicate_entries, &(&1.layer == :economics))
    assert counts() == before
    assert cash_balances(portfolio) == balances
  end
end
