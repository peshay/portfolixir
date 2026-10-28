defmodule Portfolixir.Imports.RefusedTickerTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @name "Sorrel Bay Foods AG"

  @warning "#{@name}: the ticker in the file is not a valid ticker symbol and is not adopted; " <>
             "the security is created without a ticker. Record the ticker on the security afterwards."

  defp json(ticker) do
    security = %{"name" => @name, "currency" => "EUR", "ticker" => ticker}

    purchase = fn date ->
      %{
        "type" => "PURCHASE",
        "account" => "Synthetic-Cash",
        "portfolio" => "Synthetic-Depot",
        "date" => date,
        "currency" => "EUR",
        "amount" => "500.00",
        "shares" => "5",
        "security" => security
      }
    end

    Jason.encode!(%{
      "version" => 1,
      "transactions" => [
        %{
          "type" => "DEPOSIT",
          "account" => "Synthetic-Cash",
          "date" => "2024-03-01",
          "currency" => "EUR",
          "amount" => "2000.00"
        },
        purchase.("2024-04-01"),
        purchase.("2024-05-02")
      ]
    })
  end

  # User story (security review 2026-10-12, H57):
  # As the operator importing a JSON export whose security carries a ticker
  # the catalog refuses,
  # I want the ticker left out with one warning that names the security and
  # the remedy, and every booking of the file imported,
  # so that one unusable ticker never refuses the whole file.
  #
  # Acceptance criteria:
  # - The preview holds every row; one warning, on the security's first row,
  #   names the security; the security reference carries no ticker.
  # - The apply books every row and creates the security without a ticker.
  # - A ticker the catalog accepts is kept, with no warning.
  test "a refused ticker is dropped with one warning and every row imports" do
    for ticker <- ["VWCE DE", "A/B", "A?B", "A#B", "A%B", ".", "..", String.duplicate("A", 65)] do
      assert {:ok, preview} = PortfolioPerformance.parse(json(ticker), filename: "t.json")
      assert length(preview.entries) == 3, ticker
      assert preview.errors == [%{row: 2, message: @warning}], ticker
      assert Enum.all?(preview.entries, &(is_nil(&1.security) or is_nil(&1.security.ticker)))
    end

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import target",
        base_currency_code: "EUR"
      })

    {:ok, preview} = PortfolioPerformance.parse(json("VWCE DE"), filename: "t.json")
    before = Ledger.count_transactions()
    assert {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    assert Ledger.count_transactions() == before + 3

    assert [%{ticker_symbol: nil}] =
             Enum.filter(Catalog.list_securities(), &(&1.name == @name))

    assert {:ok, kept} = PortfolioPerformance.parse(json("VWCE.DE"), filename: "t.json")
    assert kept.errors == []
    assert Enum.at(kept.entries, 1).security.ticker == "VWCE.DE"
  end

  # User story (security review 2026-10-12, H57):
  # As the operator reading the Imports page in German,
  # I want the refused ticker's warning, and the catalog's own refusal of a
  # ticker, in German,
  # so that no message about a ticker reads in English on a German page.
  #
  # Acceptance criteria:
  # - The warning reads in German on a German page.
  # - The catalog's "is not a ticker symbol" reads "ist kein Ticker-Symbol".
  test "the warning and the catalog's refusal read in German" do
    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      assert {:ok, preview} = PortfolioPerformance.parse(json("VWCE DE"), filename: "t.json")

      assert preview.errors == [
               %{
                 row: 2,
                 message:
                   "#{@name}: Der Ticker aus der Datei ist kein gültiges Ticker-Symbol und wird " <>
                     "nicht übernommen; das Wertpapier wird ohne Ticker angelegt. Den Ticker " <>
                     "danach am Wertpapier erfassen."
               }
             ]

      assert Gettext.dgettext(PortfolixirWeb.Gettext, "errors", "is not a ticker symbol") ==
               "ist kein Ticker-Symbol"
    end)
  end
end
