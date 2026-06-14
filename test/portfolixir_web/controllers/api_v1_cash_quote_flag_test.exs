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
  # I want to read and set a cash account's counts_toward_cash_quote flag,
  # so that a business account stays visible without distorting the private
  # cash quote.
  #
  # Acceptance criteria:
  # - Cash account responses carry counts_toward_cash_quote (default true).
  # - POST and PATCH /api/v1/cash_accounts accept the flag.
  # - The valuation lists excluded accounts with counts_toward_cash_quote
  #   false and computes cash_quote over counting accounts only.
  test "flag is readable and settable, excluded accounts stay listed but leave the quote", %{
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

    assert created["counts_toward_cash_quote"] == true

    business =
      conn
      |> api_conn()
      |> post("/api/v1/cash_accounts", %{
        "cash_account" => %{
          "portfolio_id" => portfolio.id,
          "name" => "Business Account",
          "currency_code" => "EUR",
          "counts_toward_cash_quote" => false
        }
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert business["counts_toward_cash_quote"] == false

    patched =
      conn
      |> api_conn()
      |> patch("/api/v1/cash_accounts/#{business["id"]}", %{
        "cash_account" => %{"counts_toward_cash_quote" => true}
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert patched["counts_toward_cash_quote"] == true

    conn
    |> api_conn()
    |> patch("/api/v1/cash_accounts/#{business["id"]}", %{
      "cash_account" => %{"counts_toward_cash_quote" => false}
    })
    |> json_response(200)

    shown =
      conn
      |> api_conn()
      |> get("/api/v1/cash_accounts/#{business["id"]}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert shown["counts_toward_cash_quote"] == false

    # Valuation: 800 invested + 200 private cash + 500 excluded business cash.
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
    assert data["cash_quote"] == "0.2"

    business_entry =
      Enum.find(data["cash_balances"], &(&1["cash_account_id"] == business["id"]))

    assert business_entry["counts_toward_cash_quote"] == false
    assert business_entry["balance"] == "500"

    private_entry =
      Enum.find(data["cash_balances"], &(&1["cash_account_id"] == created["id"]))

    assert private_entry["counts_toward_cash_quote"] == true
  end
end
