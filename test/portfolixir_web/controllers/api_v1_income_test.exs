defmodule PortfolixirWeb.ApiV1IncomeTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp dividend!(world, security, opts) do
    {:ok, tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: WorldFixtures.security_id_for(security),
        type: "dividend",
        date: Keyword.fetch!(opts, :date),
        gross_amount: Keyword.fetch!(opts, :net),
        taxes: Keyword.get(opts, :tax, "0"),
        currency_code: Keyword.get(opts, :currency, "EUR")
      })

    tx
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want the portfolio's received dividends and interest from one endpoint,
  # so that the income report is available without a manual ledger query.
  #
  # Acceptance criteria:
  # - GET /portfolios/:id/income returns the annual matrix, per-position rows
  #   and per-transaction detail with all amounts as Decimal strings.
  # - Foreign-currency income is converted via the EUR hub; the original
  #   currency stays visible.
  # - An unknown portfolio returns 404.
  test "returns the income report with Decimal strings", %{conn: conn} do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2025-04-01],
          rate: "1.25",
          source: "manual"
        }
      ])

    world = WorldFixtures.base_world(currency: "EUR")
    security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")

    fx_world =
      WorldFixtures.add_depot(world.portfolio,
        cash_currency: "USD",
        cash_name: "USD Cash",
        depot_name: "USD Depot"
      )

    usd_security =
      WorldFixtures.create_security!(name: "US Payer", ticker: "USP", currency: "USD")

    dividend!(world, security, date: ~D[2025-03-15], net: "80", tax: "20")

    dividend!(
      %{portfolio: world.portfolio, cash: fx_world.cash},
      usd_security,
      date: ~D[2025-04-01],
      net: "100",
      tax: "25",
      currency: "USD"
    )

    data =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/income")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["base_currency"] == "EUR"
    assert data["conversion_note"] =~ "EUR"

    [year] = data["annual"]
    assert year["year"] == 2025
    # 100 EUR (gross of the EUR dividend) + 100 EUR (125 USD / 1.25) = 200.
    assert year["dividends_total"] == "200"
    assert year["total"] == "200"
    assert year["months"]["3"]["dividends"] == "100"

    usd_row = Enum.find(data["positions"], &(&1["security_id"] == usd_security.id))
    assert usd_row["security_currency"] == "USD"
    assert usd_row["gross"] == "100"
    assert usd_row["tax"] == "20"
    assert usd_row["net"] == "80"
    assert usd_row["payment_count"] == 1
    assert usd_row["last_payment"] == "2025-04-01"

    assert is_list(data["transactions"])
    assert Enum.any?(data["transactions"], &(&1["kind"] == "dividend"))

    missing =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/999999/income")
      |> json_response(404)

    assert missing == %{"errors" => %{"detail" => "not found"}}
  end

  # User story (the ADR-0015 amendment of 2026-10-07, the income report's
  # sibling of #1107):
  # As the operating LLM agent,
  # I want a dividend credited to an account in another currency than its
  # security's read in the account's currency,
  # so that the native amounts I quote carry the currency they are in and the
  # converted ones are the cash that arrived.
  #
  # Acceptance criteria:
  # - A USD security's dividend credited 80.00 EUR net with 20.00 EUR withheld
  #   to a EUR account reads gross 100, tax 20, net 80, its detail with
  #   currency EUR and native_gross 100 (before: 80, 16 and 64, and USD).
  # - conversion_note says the cash is read in the account's currency.
  test "a dividend credited across currencies is read in its account's currency", %{
    conn: conn
  } do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2025-07-01],
          rate: "1.25",
          source: "manual"
        }
      ])

    world = WorldFixtures.base_world(currency: "EUR")
    security = WorldFixtures.create_security!(name: "Wire Payer", ticker: "WPY", currency: "USD")

    {:ok, _dividend} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: "dividend",
        date: ~D[2025-07-01],
        gross_amount: "80.00",
        taxes: "20.00",
        currency_code: "USD",
        settlement_fx_rate: "0.8"
      })

    %{"data" => data} =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/income")
      |> json_response(200)

    assert [detail] = data["transactions"]

    assert Map.take(detail, [
             "currency",
             "native_gross",
             "native_tax",
             "native_net",
             "gross",
             "tax",
             "net",
             "converted"
           ]) == %{
             "currency" => "EUR",
             "native_gross" => "100",
             "native_tax" => "20",
             "native_net" => "80",
             "gross" => "100",
             "tax" => "20",
             "net" => "80",
             "converted" => true
           }

    assert [%{"security_currency" => "USD", "gross" => "100", "net" => "80"}] =
             data["positions"]

    assert data["conversion_note"] =~ "cash account's currency"
  end
end
