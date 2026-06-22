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
      WorldFixtures.add_depot(world.portfolio, cash_currency: "USD", cash_name: "USD Cash")

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
end
