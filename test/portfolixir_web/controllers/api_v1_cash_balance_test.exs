defmodule PortfolixirWeb.ApiV1CashBalanceTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Portfolios

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", elem(@auth, 1))
  end

  defp post_json(conn, path, body) do
    conn
    |> api_conn()
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want to set a cash account's balance with a single call,
  # so that external cash stays current without booking every movement.
  #
  # Acceptance criteria:
  # - POST /cash_accounts/:id/balance records a balance_adjustment snapshot.
  # - The cash account listing then reflects the snapshot balance.
  test "sets a cash balance snapshot and reflects it in the account balance", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "P",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    created =
      conn
      |> post_json("/api/v1/cash_accounts/#{cash.id}/balance", %{
        "date" => "2026-06-01",
        "amount" => "4250"
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert created["type"] == "balance_adjustment"
    assert created["cash_account_id"] == cash.id
    assert created["gross_amount"] == "4250"

    accounts =
      conn
      |> api_conn()
      |> get("/api/v1/cash_accounts")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [account] = accounts
    assert account["id"] == cash.id
    assert account["balance"] == "4250"
  end

  test "returns 404 for an unknown cash account", %{conn: conn} do
    response =
      conn
      |> post_json("/api/v1/cash_accounts/999999/balance", %{
        "date" => "2026-06-01",
        "amount" => "1"
      })
      |> json_response(404)

    assert response == %{"errors" => %{"detail" => "not found"}}
  end
end
