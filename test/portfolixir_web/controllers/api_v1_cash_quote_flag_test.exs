defmodule PortfolixirWeb.ApiV1CashQuoteFlagTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", elem(@auth, 1))
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want to read and set a cash account's liquidity_role,
  # so that an overdraft/Lombard or a business reserve stays visible without
  # reporting fake deployable cash.
  #
  # Acceptance criteria:
  # - Cash account responses carry liquidity_role (default free_cash).
  # - POST and PATCH /api/v1/cash_accounts accept liquidity_role.
  # - An unknown liquidity_role is rejected with 422.
  # - The valuation lists each account with its liquidity_role and a deployable
  #   flag, and computes cash_quote over deployable cash only.
  test "liquidity_role is readable, settable, validated; reserves leave the quote", %{
    conn: conn
  } do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Local Portfolio", base_currency_code: "EUR"})

    created =
      conn
      |> api_conn()
      |> post("/api/v1/cash_accounts", %{
        "cash_account" => %{
          "portfolio_id" => portfolio.id,
          "name" => "Local Cash",
          "currency_code" => "EUR"
        }
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert created["liquidity_role"] == "free_cash"

    business =
      conn
      |> api_conn()
      |> post("/api/v1/cash_accounts", %{
        "cash_account" => %{
          "portfolio_id" => portfolio.id,
          "name" => "Business Account",
          "currency_code" => "EUR",
          "liquidity_role" => "reserve"
        }
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert business["liquidity_role"] == "reserve"

    # Unknown role -> 422.
    errors =
      conn
      |> api_conn()
      |> post("/api/v1/cash_accounts", %{
        "cash_account" => %{
          "portfolio_id" => portfolio.id,
          "name" => "Bogus",
          "currency_code" => "EUR",
          "liquidity_role" => "nonsense"
        }
      })
      |> json_response(422)
      |> Map.fetch!("errors")

    assert errors["liquidity_role"] == ["is invalid"]

    patched =
      conn
      |> api_conn()
      |> patch("/api/v1/cash_accounts/#{business["id"]}", %{
        "cash_account" => %{"liquidity_role" => "free_cash"}
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert patched["liquidity_role"] == "free_cash"

    # Invalid role on update -> 422.
    update_errors =
      conn
      |> api_conn()
      |> patch("/api/v1/cash_accounts/#{business["id"]}", %{
        "cash_account" => %{"liquidity_role" => "nope"}
      })
      |> json_response(422)
      |> Map.fetch!("errors")

    assert update_errors["liquidity_role"] == ["is invalid"]

    conn
    |> api_conn()
    |> patch("/api/v1/cash_accounts/#{business["id"]}", %{
      "cash_account" => %{"liquidity_role" => "reserve"}
    })
    |> json_response(200)

    shown =
      conn
      |> api_conn()
      |> get("/api/v1/cash_accounts/#{business["id"]}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert shown["liquidity_role"] == "reserve"

    # Valuation: 800 invested + 200 deployable cash + 500 excluded reserve.
    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: created["id"],
        name: "Main Depot"
      })

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Core Equity",
        ticker_symbol: "CORE",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: created["id"],
        type: "deposit",
        date: ~D[2026-01-01],
        gross_amount: "1000",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: created["id"],
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "10",
        price: "80",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: business["id"],
        type: "deposit",
        date: ~D[2026-01-03],
        gross_amount: "500",
        currency_code: "EUR"
      })

    {:ok, _} =
      Quotes.upsert_many(security.id, [%{date: ~D[2026-06-01], close: "80", source: "manual"}])

    data =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/valuation")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["total_cash"] == "700"
    assert data["total_with_cash"] == "1500"
    assert data["counting_cash"] == "200"
    assert data["cash_quote"] == "0.2"

    business_entry =
      Enum.find(data["cash_balances"], &(&1["cash_account_id"] == business["id"]))

    assert business_entry["liquidity_role"] == "reserve"
    assert business_entry["deployable"] == false
    assert business_entry["balance"] == "500"

    private_entry =
      Enum.find(data["cash_balances"], &(&1["cash_account_id"] == created["id"]))

    assert private_entry["liquidity_role"] == "free_cash"
    assert private_entry["deployable"] == true
  end
end
