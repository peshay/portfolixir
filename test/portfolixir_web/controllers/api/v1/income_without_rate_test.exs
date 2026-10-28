defmodule PortfolixirWeb.Api.V1.IncomeWithoutRateTest do
  # The income report converts each payment into the portfolio's base
  # currency through the EUR hub. A payment with no stored rate on or before
  # its booking date stays out of every base-currency total and is named, as
  # the sibling Cash-flow facets (realized gains, flows, costs) do; over the
  # API, and on the /cashflow page. Synthetic data only.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Income
  alias Portfolixir.WorldFixtures

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp dividend!(portfolio, cash, security, net, currency, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        security_id: WorldFixtures.security_id_for(security),
        type: "dividend",
        date: date,
        gross_amount: net,
        taxes: "0",
        currency_code: currency
      })

    tx
  end

  # A EUR portfolio with two depots: one on a EUR cash account (a 100 EUR
  # dividend) and one on a TWD cash account (a 3300 TWD dividend). No rate
  # is stored at all, so the TWD payment has no rate path to EUR.
  setup do
    world = WorldFixtures.base_world(name: "Synthetic Book", currency: "EUR")

    twd =
      WorldFixtures.add_depot(world.portfolio,
        cash_currency: "TWD",
        cash_name: "Synthetic TWD Cash",
        depot_name: "Synthetic TWD Depot"
      )

    eur_payer = WorldFixtures.create_security!(name: "Synthetic Euro Payer", ticker: "SEP")

    twd_payer =
      WorldFixtures.create_security!(
        name: "Synthetic Taipei Payer",
        ticker: "STP",
        currency: "TWD"
      )

    dividend!(world.portfolio, world.cash, eur_payer, "100", "EUR", ~D[2025-03-14])
    dividend!(world.portfolio, twd.cash, twd_payer, "3300", "TWD", ~D[2025-03-14])

    %{portfolio: world.portfolio, twd_payer: twd_payer}
  end

  test "control: the TWD payment has no rate path and is flagged", %{portfolio: portfolio} do
    report = Income.for_portfolio(portfolio.id)

    assert report.base_currency == "EUR"
    assert report.unconverted_count == 1

    assert [%{converted: false, currency: "TWD"}] =
             Enum.reject(report.transactions, & &1.converted)
  end

  # User story (security review 2026-10-12, K07):
  # As the operator or the agent reading the income report,
  # I want a payment with no rate path to the base currency left out of
  # every base-currency total and named, with its currency,
  # so that a total never adds two currencies one to one.
  #
  # Acceptance criteria:
  # - The year's totals, the months and the per-position rows count the
  #   EUR payment only; the TWD payer has no per-position row.
  # - excluded names the count and the currency with its security; the
  #   per-transaction detail keeps the payment, flagged converted false.
  # - The payload carries computation_basis, whose gaps say a payment
  #   without a rate is excluded and named; the conversion note says so.
  test "API: a payment without a rate path is excluded from every total and named",
       %{conn: conn, portfolio: portfolio, twd_payer: twd_payer} do
    data =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/income")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["base_currency"] == "EUR"
    assert data["unconverted_count"] == 1

    [year] = data["annual"]

    assert year["total"] == "100",
           "the 2025 income total is #{year["total"]} EUR (100 EUR + 3300 TWD counted 1:1)"

    assert year["dividends_total"] == "100"
    assert year["months"]["3"]["dividends"] == "100"
    refute Enum.any?(data["positions"], &(&1["security_id"] == twd_payer.id))

    assert data["excluded"] == %{
             "count" => 1,
             "currencies" => [
               %{
                 "currency_code" => "TWD",
                 "count" => 1,
                 "securities" => ["Synthetic Taipei Payer"]
               }
             ]
           }

    assert [%{"converted" => false, "currency" => "TWD"}] =
             Enum.reject(data["transactions"], & &1["converted"])

    basis = data["computation_basis"]
    assert is_map(basis), "income payload keys: #{inspect(data |> Map.keys() |> Enum.sort())}"
    assert basis["gaps"] =~ "excluded"
    assert basis["reference"] =~ "on or before"
    assert data["conversion_note"] =~ "excluded"
  end

  # User story (security review 2026-10-12, K07):
  # As the operator on the /cashflow income facet,
  # I want an attention note naming a payment the page could not convert,
  # with the backfill beside it, and figures that leave it out,
  # so that I read the total for what it is and know the remedy.
  #
  # Acceptance criteria:
  # - #income-excluded names the count and "TWD (Synthetic Taipei Payer)"
  #   and holds the backfill control.
  # - The 3,400.00 sum of two currencies is shown nowhere.
  # - The ⓘ states the rate rule: the most recent stored rate on or before
  #   each booking date, a payment with no such rate excluded and named.
  test "page: the income facet names a payment it could not convert", %{conn: conn} do
    {:ok, view, html} = live(conn, "/cashflow")

    assert html =~ "income-annual"
    assert html =~ "Synthetic Taipei Payer"

    assert has_element?(
             view,
             "#income-excluded",
             "1 payment could not be converted — no stored exchange rate to EUR on or before its booking date — and is excluded from every total."
           )

    assert has_element?(
             view,
             "#income-excluded",
             "Affected currency: TWD (Synthetic Taipei Payer)."
           )

    assert has_element?(view, "#income-excluded #fx-backfill-button")
    refute html =~ "3,400.00"

    assert has_element?(
             view,
             "[data-role='facet-composition']",
             "at the most recent stored rate on or before each booking date; a payment with no such rate is excluded and named"
           )
  end
end
