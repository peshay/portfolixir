defmodule Portfolixir.Imports.ParserRobustnessTest do
  # Issue #768: the parsers run inside the operator's LiveView process, so a
  # crafted export must come back as an error, never as an exception. Each
  # fixture below is a synthetic two-row export with one hostile field.
  use ExUnit.Case, async: true

  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview

  @csv_header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle"
  @csv_ok "2024-01-15 10:01:00;Kauf;Synthetic AG;10;150,25;1.502,50;2,50;;1.502,50;Test-Depot;Test-Cash;;"

  defp csv(rows), do: Enum.join([@csv_header | rows], "\n")

  defp json(transactions) do
    Jason.encode!(%{"version" => 1, "transactions" => transactions})
  end

  defp base_tx do
    %{
      "type" => "PURCHASE",
      "account" => "Test-Cash",
      "portfolio" => "Test-Depot",
      "date" => "2024-04-01",
      "currency" => "EUR",
      "amount" => "500.00",
      "shares" => "5",
      "security" => %{"name" => "Synthetic AG", "currency" => "EUR"}
    }
  end

  # User story:
  # As an operator importing an export I did not write myself,
  # I want a malformed row reported as a row error and a malformed file as a file error,
  # so that nothing I upload can take the import screen down.
  #
  # Acceptance criteria:
  # - Non-finite decimals (NaN, Infinity) are row errors, not exceptions.
  # - Type confusion in a JSON row (a number for a date, a string for the
  #   security, a bare value for a unit) is a row error, not an exception.
  # - Every case still parses the sound row next to it.
  test "hostile CSV cells become row errors and the sound row survives" do
    for hostile <- [
          "2024-01-16 10:01:00;Kauf;Synthetic AG;10;150,25;1.502,50;2,50;NaN;1.502,50;Test-Depot;Test-Cash;;",
          "2024-01-16 10:01:00;Kauf;Synthetic AG;10;150,25;1.502,50;Infinity;;1.502,50;Test-Depot;Test-Cash;;",
          "2024-01-16 10:01:00;Kauf;Synthetic AG;NaN;150,25;1.502,50;;;1.502,50;Test-Depot;Test-Cash;;",
          "2024-01-16 10:01:00;Kauf;Synthetic AG;10;-Infinity;1.502,50;;;1.502,50;Test-Depot;Test-Cash;;"
        ] do
      assert {:ok, %Preview{entries: [_sound], errors: [%{row: 2, message: message}]}} =
               PortfolioPerformance.parse(csv([@csv_ok, hostile]), filename: "hostile.csv"),
             hostile

      assert is_binary(message)
    end
  end

  test "hostile JSON fields become row errors and the sound row survives" do
    for {label, hostile} <- [
          {"numeric date", Map.put(base_tx(), "date", 123)},
          {"numeric time", Map.put(base_tx(), "time", 123)},
          {"string security", Map.put(base_tx(), "security", "abc")},
          {"bare unit", Map.put(base_tx(), "units", [1])},
          {"unit amount text",
           Map.put(base_tx(), "units", [%{"type" => "TAX", "amount" => "abc"}])},
          {"unit amount list",
           Map.put(base_tx(), "units", [%{"type" => "TAX", "amount" => [1]}])},
          {"unit NaN", Map.put(base_tx(), "units", [%{"type" => "TAX", "amount" => "NaN"}])},
          {"amount NaN", Map.put(base_tx(), "amount", "NaN")},
          {"amount Infinity", Map.put(base_tx(), "amount", "Infinity")},
          {"shares NaN", Map.put(base_tx(), "shares", "-NaN")},
          {"units not a list", Map.put(base_tx(), "units", %{"type" => "TAX"})},
          {"note not a string", Map.put(base_tx(), "note", %{"a" => 1})},
          {"portfolio not a string", Map.put(base_tx(), "portfolio", 42)}
        ] do
      assert {:ok, %Preview{entries: entries, errors: errors}} =
               PortfolioPerformance.parse(json([base_tx(), hostile]), filename: "hostile.json"),
             label

      assert length(entries) + length(errors) == 2, label
      assert entries != [], label
    end
  end

  test "a payload that is not an export is a file error, never an exception" do
    for {label, body} <- [
          {"json list", "[1, 2, 3]"},
          {"json string", ~s("hello")},
          {"transactions not a list", ~s({"version": 1, "transactions": {"a": 1}})},
          {"transaction not a map", ~s({"version": 1, "transactions": [1, "x", null]})},
          {"deeply nested", String.duplicate("[", 5000) <> String.duplicate("]", 5000)},
          {"binary garbage", <<0, 255, 254, 1, 2, 3>>}
        ] do
      case PortfolioPerformance.parse(body, filename: "garbage.json") do
        {:error, _reason} -> :ok
        {:ok, %Preview{entries: [], errors: errors}} when is_list(errors) -> :ok
        other -> flunk("#{label}: #{inspect(other)}")
      end
    end
  end

  # User story:
  # As an operator,
  # I want an export with more rows than the importer is sized for refused up front,
  # so that one file cannot hold a multiple of its size in memory for hours.
  #
  # Acceptance criteria:
  # - Both parsers refuse a file over the row cap with {:error, {:too_many_rows, n}}.
  test "refuses a file over the row cap" do
    cap = PortfolioPerformance.max_rows()

    rows = List.duplicate(@csv_ok, cap + 1)

    assert {:error, {:too_many_rows, n}} =
             PortfolioPerformance.parse(csv(rows), filename: "big.csv")

    assert n == cap + 1

    txs = List.duplicate(base_tx(), cap + 1)

    assert {:error, {:too_many_rows, _}} =
             PortfolioPerformance.parse(json(txs), filename: "big.json")
  end

  # User story (E25 S5, F34):
  # As an operator dropping an export that was saved in another encoding,
  # I want the file refused with a named file error before anything is parked,
  # so that the import page stays usable and says how to fix the file.
  #
  # Acceptance criteria:
  # - A body with bytes that are not UTF-8, in any cell of a CSV or anywhere
  #   in a JSON export, is refused as {:error, :invalid_encoding}.
  # - A UTF-8 body, with or without a byte-order mark, still parses.
  test "a body that is not UTF-8 is refused with a named file error" do
    for cell <- ["Wertpapier", "Quelle", "Typ"] do
      row =
        case cell do
          "Wertpapier" ->
            <<"2024-01-16 10:01:00;Kauf;Synthetic M", 0xFC,
              "nchen AG;10;150,25;1.502,50;2,50;;1.502,50;Test-Depot;Test-Cash;;">>

          "Quelle" ->
            <<"2024-01-16 10:01:00;Kauf;Synthetic AG;10;150,25;1.502,50;2,50;;1.502,50;Test-Depot;Test-Cash;;M",
              0xFC, "nchen">>

          "Typ" ->
            <<"2024-01-16 10:01:00;K", 0xE4,
              "uf;Synthetic AG;10;150,25;1.502,50;2,50;;1.502,50;Test-Depot;Test-Cash;;">>
        end

      assert {:error, :invalid_encoding} =
               PortfolioPerformance.parse(csv([@csv_ok, row]), filename: "latin1.csv"),
             cell
    end

    body =
      <<(~s({"version":1,"transactions":[{"type":"DEPOSIT","note":"M)), 0xFC, ~s(nchen"}]})>>

    assert {:error, :invalid_encoding} = PortfolioPerformance.parse(body, filename: "x.json")

    assert {:ok, %Preview{entries: [_]}} =
             PortfolioPerformance.parse("\uFEFF" <> csv([@csv_ok]), filename: "bom.csv")
  end

  # User story (E25 S5, F33, board 11):
  # As an operator importing an export with a security entry that names nothing,
  # I want that row listed as a parser warning and left out,
  # so that the rest of the file previews and imports.
  #
  # Acceptance criteria:
  # - A row whose security carries no name, ISIN, WKN or ticker is a row
  #   warning naming the reason, and is not an entry.
  # - A security with only a WKN or a ticker is a partial reference and stays.
  # - The sound rows next to it are entries.
  test "a security reference that names nothing is a row warning, a partial one stays" do
    blank = Map.put(base_tx(), "security", %{"currency" => "EUR", "name" => "  "})
    wkn_only = Map.put(base_tx(), "security", %{"wkn" => "A0RPWH", "currency" => "EUR"})
    ticker_only = Map.put(base_tx(), "security", %{"ticker" => "SYN", "currency" => "EUR"})

    assert {:ok, %Preview{entries: entries, errors: [%{row: 2, message: message}]}} =
             PortfolioPerformance.parse(json([base_tx(), blank, wkn_only, ticker_only]),
               filename: "blank.json"
             )

    assert message == "security without a name and without an ISIN — row not imported"
    assert Enum.map(entries, & &1.source_row) == [1, 3, 4]
  end

  # User story (E25 S5, F35, board 11):
  # As an operator dropping an export,
  # I want a file naming more accounts, depots or securities than one preview
  # can show refused with a named file error,
  # so that the preview never grows past what the page can render.
  #
  # Acceptance criteria:
  # - A file past the distinct account-and-depot name cap, or past the
  #   distinct security cap, is refused as {:error, :too_many_names}, in both
  #   formats.
  # - A file exactly at each cap still parses.
  test "a file past the distinct-name cap is refused with a named file error" do
    %{accounts: accounts, securities: securities} = PortfolioPerformance.max_names()

    deposit = fn i -> "2024-01-15;Einlage;;;;100,00;;;100,00;Cash-#{i};;;" end

    assert {:ok, %Preview{}} =
             PortfolioPerformance.parse(csv(Enum.map(1..accounts, deposit)), filename: "a.csv")

    assert {:error, :too_many_names} =
             PortfolioPerformance.parse(csv(Enum.map(1..(accounts + 1), deposit)),
               filename: "a.csv"
             )

    buy = fn i ->
      "2024-01-15 10:01:00;Kauf;Synthetic #{i} AG;1;1,00;1,00;;;1,00;Test-Depot;Test-Cash;;"
    end

    assert {:ok, %Preview{}} =
             PortfolioPerformance.parse(csv(Enum.map(1..securities, buy)), filename: "s.csv")

    assert {:error, :too_many_names} =
             PortfolioPerformance.parse(csv(Enum.map(1..(securities + 1), buy)),
               filename: "s.csv"
             )

    depots =
      Enum.map(1..(accounts + 1), fn i ->
        base_tx() |> Map.put("portfolio", "Depot-#{i}") |> Map.put("account", "Test-Cash")
      end)

    assert {:error, :too_many_names} =
             PortfolioPerformance.parse(json(depots), filename: "d.json")
  end

  # User story (E25 S5, F38):
  # As an operator,
  # I want the row cap to count the entries a file expands into,
  # so that one transaction splitting into tax refunds cannot multiply what
  # the preview holds.
  #
  # Acceptance criteria:
  # - A file within the row cap whose rows and split-off tax refunds together
  #   pass it is refused as {:error, {:too_many_entries, n}}, in both formats,
  #   before any entry is built.
  # - A row with more units than one booking carries is a row error, and the
  #   sound row next to it survives.
  test "the row cap counts the entries a file expands into" do
    cap = PortfolioPerformance.max_rows()
    rows = div(cap, 2) + 1

    refund_tx =
      Map.put(base_tx(), "units", [%{"type" => "TAX", "amount" => "-1.00"}])

    assert {:error, {:too_many_entries, n}} =
             PortfolioPerformance.parse(json(List.duplicate(refund_tx, rows)), filename: "r.json")

    assert n == rows * 2

    refund_row =
      "2024-01-16 10:01:00;Kauf;Synthetic AG;10;150,25;1.502,50;;-1,00;1.502,50;Test-Depot;Test-Cash;;"

    assert {:error, {:too_many_entries, ^n}} =
             PortfolioPerformance.parse(csv(List.duplicate(refund_row, rows)), filename: "r.csv")

    many_units =
      Map.put(
        base_tx(),
        "units",
        List.duplicate(
          %{"type" => "TAX", "amount" => "-1.00"},
          PortfolioPerformance.max_units() + 1
        )
      )

    assert {:ok, %Preview{entries: [_sound], errors: [%{row: 2, message: message}]}} =
             PortfolioPerformance.parse(json([base_tx(), many_units]), filename: "u.json")

    assert message =~ "units"
  end

  # User story (E25 S5, F39):
  # As an operator importing an export with a value no ledger column holds,
  # I want that row named as a row error in the preview,
  # so that the apply never fails on it after I confirmed.
  #
  # Acceptance criteria:
  # - A quantity, price, amount, fee, tax or split-off refund past its
  #   column's integer digits (after rounding to the column's scale) is a
  #   named row error naming the field; a derived price counts too.
  # - A number past the parser's bound is a named row error, not an
  #   inspected term.
  # - The sound row next to each survives.
  test "values past their ledger column are named row errors" do
    for {label, hostile, field} <- [
          {"amount", Map.put(base_tx(), "amount", "123456789012345678"), "gross amount"},
          {"shares", Map.put(base_tx(), "shares", "1234567890123456789"), "quantity"},
          {"derived price",
           base_tx() |> Map.put("amount", "99999999999999") |> Map.put("shares", "0.0000001"),
           "price"},
          {"fee", Map.put(base_tx(), "units", [%{"type" => "FEE", "amount" => "1e15"}]), "fees"},
          {"refund", Map.put(base_tx(), "units", [%{"type" => "TAX", "amount" => "-1e15"}]),
           "tax refund"},
          {"rounds past", Map.put(base_tx(), "amount", "99999999999999.9999999"), "gross amount"},
          {"parser bound", Map.put(base_tx(), "amount", "1e40"), "number"}
        ] do
      assert {:ok, %Preview{entries: [_sound], errors: [%{row: 2, message: message}]}} =
               PortfolioPerformance.parse(json([base_tx(), hostile]), filename: "b.json"),
             label

      assert message =~ field, "#{label}: #{message}"
      refute message =~ "{", "#{label}: #{message}"
    end

    csv_row =
      "2024-01-16 10:01:00;Kauf;Synthetic AG;10;150,25;123.456.789.012.345.678,00;;;1.502,50;Test-Depot;Test-Cash;;"

    assert {:ok, %Preview{entries: [_], errors: [%{row: 2, message: message}]}} =
             PortfolioPerformance.parse(csv([@csv_ok, csv_row]), filename: "b.csv")

    assert message =~ "gross amount"
  end

  test "a version-1 payload whose transactions are not a list is malformed, and a BOM is not a column" do
    assert {:error, :malformed_payload} =
             PortfolioPerformance.parse(~s({"version":1,"transactions":"x"}), filename: "x.json")

    assert {:ok, %Preview{entries: [_ | _]}} =
             PortfolioPerformance.parse("\uFEFF" <> csv([@csv_ok]), filename: "bom.csv")
  end
end
