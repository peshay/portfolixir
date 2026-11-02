defmodule Portfolixir.Imports.StatedCashImportBoundaryTest do
  # ADR-0053, amendment of 2026-11-02 (#1371): "the stated cash must agree
  # with the new figures to the cent, as §2 asks of an imported row". An
  # imported row's price is a rounded figure: a CSV row's is its Kurs cell
  # as Portfolio Performance writes it (two to four places), a JSON row's is
  # its cash net of fees and taxes ÷ shares, rounded half up to the price
  # column's six places. §2 never relates quantity × price to the cash, so a
  # row that passed it misses quantity × price ± fees and taxes by up to its
  # quantity × half a unit of the price's last digit. Risk tier (ADR-0036):
  # every figure exact.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # must see this test's rows (as in the cash correction's tests).
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.StatedCash
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios

  # Synthetic figures only. Two §2-passing PP CSV rows whose Kurs is the
  # rounded display of their Betrag ÷ Stück:
  #   7 at 14,29 (100,00 ÷ 7 = 14,285714…): 7 × 14,29 = 100,03, 0,03 above
  #     Betrag; Gesamtpreis 101,00 = 100,00 + 1,00.
  #   1.234 at 12,3457 (15.234,56 ÷ 1.234 = 12,345672…): 15.234,5938,
  #     0,0338 above Betrag; Gesamtpreis 15.239,46 = 15.234,56 + 4,90.
  @csv """
  Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
  2026-01-02 00:00:00;Einlage;;;;20.000,00;;;20.000,00;Test-Cash;;;
  2026-01-14 10:00:00;Kauf;Arbolia Inc.;7;14,29;100,00;1,00;;101,00;Test-Depot;Test-Cash;;
  2026-01-15 10:00:00;Kauf;Arbolia Inc.;1.234;12,3457;15.234,56;4,90;;15.239,46;Test-Depot;Test-Cash;;
  """

  # A JSON v1 purchase of 123,456.789 shares for 1,000,000.00 with a 4.90
  # fee: its price, (1,000,000.00 − 4.90) ÷ 123,456.789 = 8.0999603…, is
  # stored at six places, 8.099960, and 123,456.789 × 8.099960 + 4.90 is
  # 999,999.952628440, 0.047371560 below the cash.
  @json Jason.encode!(%{
          "version" => 1,
          "transactions" => [
            %{
              "type" => "DEPOSIT",
              "account" => "Test-Cash",
              "date" => "2026-01-02",
              "currency" => "EUR",
              "amount" => 1_000_000.0
            },
            %{
              "type" => "PURCHASE",
              "account" => "Test-Cash",
              "portfolio" => "Test-Depot",
              "date" => "2026-01-16",
              "time" => "10:00",
              "currency" => "EUR",
              "amount" => 1_000_000.0,
              "shares" => 123_456.789,
              "security" => %{
                "name" => "Arbolia Inc.",
                "isin" => "USEXMPL10014",
                "currency" => "EUR"
              },
              "units" => [%{"type" => "FEE", "amount" => 4.9}]
            }
          ]
        })

  defp import!(body, filename, name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    {:ok, preview} = PortfolioPerformance.parse(body, filename: filename)
    assert preview.errors == []

    assert {:ok, _result} =
             Imports.apply(preview, %{
               portfolio_id: portfolio.id,
               include_portfolios: Enum.map(Portfolios.list_portfolios(), & &1.id)
             })

    portfolio.id
    |> Ledger.list_transactions_for_portfolio()
    |> Enum.filter(&(&1.type == "buy"))
    |> Enum.sort_by(& &1.date, Date)
  end

  defp gap(%Transaction{} = row) do
    row.quantity
    |> Decimal.mult(row.price)
    |> Decimal.add(row.fees)
    |> Decimal.add(row.taxes)
    |> Decimal.sub(row.gross_amount)
  end

  defp listed_ids, do: StatedCash.report().rows |> Enum.map(& &1.id) |> MapSet.new()

  defp edit(row, attrs), do: Ledger.update_transaction(Actor.owner_ui(), row, attrs)

  # User story (#1371, the orchestrator's follow-up to R2):
  # As the operator whose imports passed ADR-0053 §2,
  # I want an untouched imported trade never listed as a cash mismatch and
  # never refused for stating the cash it stores,
  # so that the check names only rows whose cash and figures really part.
  #
  # Acceptance criteria:
  # - The CSV rows store their Kurs as written (14.29, 12.3457) and their
  #   Gesamtpreis as cash (101.00, 15239.46): quantity × price + fees misses
  #   the cash by 0.03 and 0.0338.
  # - The JSON row stores its price at six places (8.099960) and its cash
  #   1,000,000.00: the figures miss it by -0.047371560.
  # - None of the three is listed by the check.
  # - A PATCH that corrects a fee and states the cash moved by the same
  #   amount is accepted; one off by more than the price's rounding is
  #   refused naming the figure the new figures give.
  test "an untouched imported row is not listed, and its stated cash is accepted" do
    [seven, large] = import!(@csv, "rounded.csv", "Rounded Kurs")
    [json] = import!(@json, "derived.json", "Derived price")

    assert Decimal.equal?(seven.price, Decimal.new("14.29"))
    assert Decimal.equal?(seven.gross_amount, Decimal.new("101.00"))
    assert Decimal.equal?(gap(seven), Decimal.new("0.03"))
    assert Decimal.equal?(large.price, Decimal.new("12.3457"))
    assert Decimal.equal?(large.gross_amount, Decimal.new("15239.46"))
    assert Decimal.equal?(gap(large), Decimal.new("0.0338"))
    assert Decimal.equal?(json.price, Decimal.new("8.099960"))
    assert Decimal.equal?(json.gross_amount, Decimal.new("1000000.00"))
    assert Decimal.equal?(gap(json), Decimal.new("-0.047371560"))

    listed = listed_ids()
    for row <- [seven, large, json], do: refute(MapSet.member?(listed, row.id))

    # The same cash stated beside unchanged figures, and a fee corrected
    # with the cash moved by the same 0.50.
    assert {:ok, _} = edit(large, %{"price" => "12.3457", "gross_amount" => "15239.46"})
    assert {:ok, corrected} = edit(large, %{"fees" => "5.40", "gross_amount" => "15239.96"})
    assert Decimal.equal?(corrected.gross_amount, Decimal.new("15239.96"))

    assert {:ok, _} = edit(json, %{"fees" => "5.40", "gross_amount" => "1000000.50"})

    # The 0.03 row's fee corrected, its cash moved by the same 0.50: its
    # stored Kurs keeps its rounding, 7 × 0.005 + 0.01 = 0.045 (the sprint
    # PR's closing act: only a price the edit sets is exact).
    assert {:ok, seven} = edit(seven, %{"fees" => "1.50", "gross_amount" => "101.50"})
    assert Decimal.equal?(seven.gross_amount, Decimal.new("101.50"))
    refute MapSet.member?(listed_ids(), seven.id)

    # Beyond the price's rounding (1,234 × 0.00005 = 0.0617) and the cent.
    assert {:error, changeset} =
             edit(corrected, %{"fees" => "4.90", "gross_amount" => "15239.36"})

    assert {"does not match quantity × price, fees and taxes — expected %{expected}", opts} =
             changeset.errors[:gross_amount]

    assert Decimal.equal?(opts[:expected], Decimal.new("15239.49"))
  end
end
