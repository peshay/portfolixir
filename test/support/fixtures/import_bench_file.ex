defmodule Portfolixir.ImportBenchFile do
  @moduledoc """
  A synthetic Portfolio Performance CSV v1 file of any size, for timing the
  import apply's per-row cost (issue #971, which decides #925).

  `csv/1` returns the same bytes for the same row count, so two commits are
  timed on the same work. Every name is synthetic ("Bench …"); no row
  carries real data. The file opens with one deposit large enough for every
  buy, then cycles through ten securities: two buys, a sell of part of the
  holding and a dividend each round. Each row's time is its own second of
  its day, so no two rows share a content hash, and the importer books every
  row once.

  The timing itself is not committed: run the apply on a throwaway database,
  for example from `mix run` in the test environment, and read the clock.
  """

  @header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle"
  @securities 10
  @cash "Bench Cash"
  @depot "Bench Depot"

  @doc "A CSV of `rows` rows (at least 1), the header line first."
  @spec csv(pos_integer()) :: String.t()
  def csv(rows) when is_integer(rows) and rows >= 1 do
    body = Enum.map(1..rows, &row/1)
    Enum.join([@header | body], "\n") <> "\n"
  end

  defp row(1), do: line(1, "Einlage", "", "", "", "100.000.000,00", "", @cash, "")

  defp row(index) do
    n = index - 2

    security =
      "Bench Security #{String.pad_leading(Integer.to_string(rem(n, @securities) + 1), 2, "0")}"

    case rem(div(n, @securities), 4) do
      0 -> line(index, "Kauf", security, "10", "50,00", "501,00", "1,00", @depot, @cash)
      1 -> line(index, "Kauf", security, "10", "52,00", "521,00", "1,00", @depot, @cash)
      2 -> line(index, "Verkauf", security, "5", "55,00", "274,00", "1,00", @depot, @cash)
      3 -> line(index, "Dividende", security, "15", "", "3,75", "", @cash, "")
    end
  end

  defp line(index, type, security, quantity, price, amount, fees, account, counter) do
    Enum.join(
      [
        timestamp(index),
        type,
        security,
        quantity,
        price,
        amount,
        fees,
        "",
        "",
        account,
        counter,
        "",
        ""
      ],
      ";"
    )
  end

  # One row per second from 2020-01-01 00:00:01, wrapping into the next day
  # after 86,399 rows: every row's (date, time) is its own.
  defp timestamp(index) do
    start = ~N[2020-01-01 00:00:00]
    start |> NaiveDateTime.add(index, :second) |> NaiveDateTime.to_string()
  end
end
