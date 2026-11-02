defmodule Portfolixir.Imports.CsvTimeRefusalTest do
  # Sprint 23 R1 (#1370; risk tier: import idempotency, ADR-0036). A
  # Portfolio Performance CSV row whose time of day the parser cannot read is
  # refused at the preview with its reason named, as #1306 refused such a
  # JSON v1 row, while the rest of the file previews and books. ADR-0053's
  # note of 2026-11-02 lists it among the refusals. That every time read
  # before reads the same, and hashes the same, is pinned in
  # `Portfolixir.Imports.CsvHashPinTest`.
  #
  # Every name and amount is synthetic.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle\n"

  @deposit "2025-03-01 00:00:00;Einlage;;;;1.000,00;;;1.000,00;Test-Cash;;;"

  defp removal(datum), do: "#{datum};Entnahme;;;;25,00;;;25,00;Test-Cash;;;"

  defp parse!(rows) do
    body = @header <> Enum.join(rows, "\n") <> "\n"
    {:ok, preview} = PortfolioPerformance.parse(body, filename: "times.csv")
    preview
  end

  defp target(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    portfolio
  end

  defp apply!(preview, portfolio) do
    {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    Ledger.list_transactions_for_portfolio(portfolio.id)
  end

  defp booked(transactions, type), do: Enum.filter(transactions, &(&1.type == type))

  defp balance(portfolio) do
    [cash] = Portfolios.list_cash_accounts_for_portfolio(portfolio.id)
    Ledger.cash_balances(portfolio_id: portfolio.id) |> Map.fetch!(cash.id)
  end

  # User story (#1370):
  # As the operator dropping a Portfolio Performance CSV export,
  # I want a row whose time of day the parser cannot read named as that
  # row's error, with the form it reads,
  # so that two same-day rows whose times were both dropped never fold into
  # one booking, the second counted as already imported.
  #
  # Acceptance criteria:
  # - Two removals of 25,00 on 2025-03-03 that differ only in their
  #   unreadable times ("9:15 AM", "09:45") are two row errors, rows 3 and
  #   4, "unreadable time “9:15 AM”: use HH:MM:SS — row not imported", and
  #   neither is an entry; a third removal that day at "10:30:00" previews.
  # - In German: "Uhrzeit „9:15 AM“ nicht lesbar: HH:MM:SS angeben — Zeile
  #   nicht übernommen".
  # - The apply books the deposit of 1000,00 and the one removal at 10:30:00
  #   alone: Test-Cash ends at 975,00.
  test "an unreadable time is a row error, so two rows differing only in it never fold into one" do
    preview =
      parse!([
        @deposit,
        removal("2025-03-03 9:15 AM"),
        removal("2025-03-03 09:45"),
        removal("2025-03-03 10:30:00")
      ])

    assert preview.errors == [
             %{row: 3, message: "unreadable time “9:15 AM”: use HH:MM:SS — row not imported"},
             %{row: 4, message: "unreadable time “09:45”: use HH:MM:SS — row not imported"}
           ]

    assert Enum.map(preview.entries, &{&1.source_row, &1.kind, &1.time}) == [
             {2, "deposit", nil},
             {5, "removal", ~T[10:30:00]}
           ]

    german =
      Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
        parse!([removal("2025-03-03 9:15 AM")])
      end)

    assert german.errors == [
             %{
               row: 2,
               message:
                 "Uhrzeit „9:15 AM“ nicht lesbar: HH:MM:SS angeben — Zeile nicht übernommen"
             }
           ]

    transactions = apply!(preview, portfolio = target("Unreadable time"))
    assert [removal] = booked(transactions, "removal")
    assert Decimal.equal?(removal.gross_amount, Decimal.new("25.00"))
    assert [deposit] = booked(transactions, "deposit")
    assert Decimal.equal?(deposit.gross_amount, Decimal.new("1000.00"))
    assert Decimal.equal?(balance(portfolio), Decimal.new("975.00"))
  end

  # User story (#1370):
  # As the operator dropping a Portfolio Performance CSV export,
  # I want a row whose `Datum` carries no time, or a blank one, read as no
  # time, as before,
  # so that only a time the parser cannot read is refused.
  #
  # Acceptance criteria:
  # - Removals dated "2025-03-04", "2025-03-05 " and "2025-03-06   " preview
  #   without a row error, each with no time.
  # - A row whose date is unreadable and whose time is too names the date,
  #   its check coming first.
  test "a blank or absent time is no time and no error; the date is checked first" do
    preview =
      parse!([
        removal("2025-03-04"),
        removal("2025-03-05 "),
        removal("2025-03-06   ")
      ])

    assert preview.errors == []
    assert Enum.map(preview.entries, &{&1.source_row, &1.time}) == [{2, nil}, {3, nil}, {4, nil}]

    implausible = parse!([removal("1899-12-31 9:15 AM")])

    assert implausible.errors == [
             %{
               row: 2,
               message:
                 "implausible date 1899-12-31 (before 1900) — fix the booking in the source and re-import"
             }
           ]
  end
end
