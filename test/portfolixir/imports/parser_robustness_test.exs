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
end
