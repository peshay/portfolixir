defmodule PortfolixirWeb.ImportThenSellRoundTripTest do
  # Round trip 1 of the Sprint 21 plan's D-1, the round trip the UAT persona
  # walks at α's closing act (#1198; the ADR-0015 amendment of 2026-10-09,
  # identity 1, risk-tier money): a Portfolio Performance JSON file buys a
  # USD security from a EUR account, and the booking drawer sells it in USD.
  #
  # Every name and figure is synthetic. async: false: the applier's
  # after-commit enrichment needs the shared sandbox connection, and the
  # realized-gains read is instance-wide.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Imports
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.RealizedGains
  alias Portfolixir.Repo

  # A purchase of 10 Arbolia (USD) for 806.00 EUR from "Test-Cash": 800.00
  # EUR of shares, a fee of 5.00 and a tax of 1.00.
  @file_json """
  {
    "version": 1,
    "transactions": [
      {
        "type": "DEPOSIT",
        "account": "Test-Cash",
        "date": "2025-04-01",
        "currency": "EUR",
        "amount": 1000.0
      },
      {
        "type": "PURCHASE",
        "account": "Test-Cash",
        "portfolio": "Test-Depot",
        "date": "2025-04-01",
        "time": "10:01",
        "currency": "EUR",
        "amount": 806.0,
        "shares": 10.0,
        "security": {
          "name": "Arbolia Inc.",
          "isin": "USEXMPL10014",
          "ticker": "ARBL",
          "currency": "USD"
        },
        "units": [
          {"type": "FEE", "amount": 5.0},
          {"type": "TAX", "amount": 1.0}
        ]
      }
    ]
  }
  """

  defp exactly?(%Decimal{} = value, expected), do: Decimal.equal?(value, Decimal.new(expected))

  # User story (#1198, Sprint 21 α3; D-1 round trip 1):
  # As the operator who imported my Portfolio Performance history, a dollar
  # share bought from my euro account, and then sold it in the booking
  # drawer in dollars,
  # I want the closed trade's realized result to be the cash the two
  # bookings moved,
  # so that the first sale after my first import reads right.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - With 1 EUR = 1.25 USD stored, the import books the buy in EUR with its
  #   legs: 800.00 EUR, 1,000.00 USD, 0.800000.
  # - The drawer sells the 10 at 120 USD, settled 960.00 EUR, fee 3.00 EUR:
  #   cash 957.00 EUR.
  # - The closed trade reads 188.75 USD, and the realized-gains read 151.00
  #   EUR = 957.00 − 806.00. Before: 312.20 EUR.
  test "an imported dollar buy sold in the drawer reads 188.75 USD = 151.00 EUR", %{conn: conn} do
    {:ok, _} =
      [~D[2025-04-01], ~D[2025-05-02]]
      |> Enum.map(fn date ->
        %{base_currency: "EUR", quote_currency: "USD", date: date, rate: "1.25", source: "manual"}
      end)
      |> Fx.upsert_many()

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Round Trip",
        base_currency_code: "EUR"
      })

    {:ok, preview} = PortfolioPerformance.parse(@file_json, filename: "round_trip.json")
    assert preview.errors == []
    assert {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

    buy = Repo.get_by!(Transaction, type: "buy")
    assert buy.currency_code == "EUR"
    assert exactly?(buy.gross_amount, "806.00")
    assert exactly?(buy.settlement_amount, "800.00")
    assert exactly?(buy.security_amount, "1000.00")
    assert exactly?(buy.settlement_fx_rate, "0.800000")

    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#open-booking") |> render_click()

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "sell",
        "date" => "2025-05-02",
        "securities_account_id" => to_string(buy.securities_account_id),
        "security_id" => to_string(buy.security_id),
        "quantity" => "10",
        "price" => "120",
        "fees" => "3",
        "taxes" => "0",
        "notes" => "",
        "settlement_amount" => "960",
        "settlement_fx_rate" => "0.8"
      }
    })

    sell = Repo.get_by!(Transaction, type: "sell")
    assert sell.currency_code == "USD"
    assert exactly?(sell.gross_amount, "957.00")

    assert [trade] = Ledger.list_trades_for_security(buy.security_id).closed_trades
    assert trade.currency_code == "USD"
    assert exactly?(trade.basis, "1007.50")
    assert exactly?(trade.proceeds, "1196.25")
    assert exactly?(trade.realized_pnl_abs, "188.75")

    assert [row] = RealizedGains.report(base_currency: "EUR").trades
    assert exactly?(row.realized_base, "151.00")
    assert Decimal.equal?(row.realized_base, Decimal.sub(sell.gross_amount, buy.gross_amount))
  end

  # A purchase of 20 Lakeside Turbines (CHF) for 1,004.00 EUR from
  # "Franc-Cash": 1,000.00 EUR of shares and a fee of 4.00.
  @franc_json """
  {
    "version": 1,
    "transactions": [
      {
        "type": "DEPOSIT",
        "account": "Franc-Cash",
        "date": "2026-07-10",
        "currency": "EUR",
        "amount": 2000.0
      },
      {
        "type": "PURCHASE",
        "account": "Franc-Cash",
        "portfolio": "Franc-Depot",
        "date": "2026-07-11",
        "time": "10:15",
        "currency": "EUR",
        "amount": 1004.0,
        "shares": 20.0,
        "security": {
          "name": "Lakeside Turbines AG",
          "isin": "CH00LAKETRB2",
          "ticker": "LKT",
          "currency": "CHF"
        },
        "units": [
          {"type": "FEE", "amount": 4.0}
        ]
      }
    ]
  }
  """

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  # User story (#1198, Sprint 21 α3; D-1 round trip 1 with a moving rate, the
  # ADR-0015 amendment's note of 2026-10-31):
  # As the operator who imported a franc share bought from my euro account
  # and sold it in the booking drawer in francs, while the franc moved
  # against the euro,
  # I want the Trades facet and the Overview card to read the euros the two
  # bookings moved,
  # so that the result agrees with my bank's statement.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - With 1 EUR = 0.94 CHF stored for the purchase's date, the import books
  #   the buy in EUR with its legs: 1,000.00 EUR, 940.00 CHF, 1.063830.
  # - With 0.95 stored for the sale's date, the drawer sells the 20 at 55 CHF,
  #   settled 1,157.90 EUR, fee 3.00 EUR: cash 1,154.90 EUR.
  # - The realized-gains read, the facet's row and the Overview card read
  #   150.90 EUR = 1,154.90 − 1,004.00. Before: 161.46 EUR, the franc result
  #   converted at 1 / 0.95.
  test "an imported franc buy sold in the drawer while the rate moved reads the cash it moved",
       %{conn: conn} do
    {:ok, _} =
      [{~D[2026-07-11], "0.94"}, {~D[2026-10-21], "0.95"}]
      |> Enum.map(fn {date, rate} ->
        %{base_currency: "EUR", quote_currency: "CHF", date: date, rate: rate, source: "manual"}
      end)
      |> Fx.upsert_many()

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Franc Round Trip",
        base_currency_code: "EUR"
      })

    {:ok, preview} = PortfolioPerformance.parse(@franc_json, filename: "franc_round_trip.json")
    assert preview.errors == []
    assert {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

    buy = Repo.get_by!(Transaction, type: "buy")
    assert buy.currency_code == "EUR"
    assert exactly?(buy.gross_amount, "1004.00")
    assert exactly?(buy.settlement_amount, "1000.00")
    assert exactly?(buy.security_amount, "940.00")
    assert exactly?(buy.settlement_fx_rate, "1.063830")

    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#open-booking") |> render_click()

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "sell",
        "date" => "2026-10-21",
        "securities_account_id" => to_string(buy.securities_account_id),
        "security_id" => to_string(buy.security_id),
        "quantity" => "20",
        "price" => "55",
        "fees" => "3",
        "taxes" => "0",
        "notes" => "",
        "settlement_amount" => "1157.90",
        "settlement_fx_rate" => "1.052636"
      }
    })

    sell = Repo.get_by!(Transaction, type: "sell")
    assert sell.currency_code == "CHF"
    assert exactly?(sell.gross_amount, "1154.90")

    assert [row] = RealizedGains.report(base_currency: "EUR").trades
    assert exactly?(row.realized_base, "150.90")
    assert Decimal.equal?(row.realized_base, Decimal.sub(sell.gross_amount, buy.gross_amount))

    {:ok, facet, _html} = live(conn, "/cashflow?tab=realized")

    assert facet
           |> render()
           |> Floki.parse_document!()
           |> Floki.find("td[data-role='trade-result']")
           |> text() =~ "+150.90 EUR"

    {:ok, overview, _html} = live(conn, "/")

    assert overview
           |> render_async()
           |> Floki.parse_document!()
           |> Floki.find("[data-role='closed-trade'] .num")
           |> text() =~ "+150.90"
  end
end
