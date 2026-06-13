defmodule PortfolixirWeb.ApiV1SecurityExcludeFlagTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Catalog.Quotes

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", elem(@auth, 1))
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want to read and set a security's excluded_from_allocation_targets flag,
  # so that a store-of-value position (e.g. Bitcoin) stays in the totals but out
  # of the allocation steering basis.
  #
  # Acceptance criteria:
  # - Security responses carry excluded_from_allocation_targets (default false).
  # - POST and PATCH /api/v1/securities accept the flag.
  # - The allocation response carries the excluded total in an `excluded` block
  #   and leaves the flagged position out of the steering basis.
  test "flag is readable and settable; allocation surfaces the excluded block", %{conn: conn} do
    created =
      conn
      |> api_conn()
      |> post("/api/v1/securities", %{
        "security" => %{"name" => "Core Equity", "currency_code" => "EUR"}
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert created["excluded_from_allocation_targets"] == false

    bitcoin =
      conn
      |> api_conn()
      |> post("/api/v1/securities", %{
        "security" => %{
          "name" => "Bitcoin",
          "currency_code" => "EUR",
          "asset_class" => "crypto",
          "excluded_from_allocation_targets" => true
        }
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert bitcoin["excluded_from_allocation_targets"] == true

    patched =
      conn
      |> api_conn()
      |> patch("/api/v1/securities/#{created["id"]}", %{
        "security" => %{"excluded_from_allocation_targets" => true}
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert patched["excluded_from_allocation_targets"] == true

    conn
    |> api_conn()
    |> patch("/api/v1/securities/#{created["id"]}", %{
      "security" => %{"excluded_from_allocation_targets" => false}
    })
    |> json_response(200)

    shown =
      conn
      |> api_conn()
      |> get("/api/v1/securities/#{created["id"]}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert shown["excluded_from_allocation_targets"] == false

    # Build an allocation with the flagged Bitcoin out of the basis.
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Local Portfolio", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Local Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Main Depot"
      })

    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, equities} =
      Classifications.create_category(%{classification_id: classification.id, name: "Equities"})

    {:ok, crypto} =
      Classifications.create_category(%{classification_id: classification.id, name: "Crypto"})

    {:ok, _} = Classifications.assign_security(created["id"], classification.id, equities.id)
    {:ok, _} = Classifications.assign_security(bitcoin["id"], classification.id, crypto.id)

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: created["id"],
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "6",
        price: "100",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: bitcoin["id"],
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "4",
        price: "100",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    {:ok, _} =
      Quotes.upsert_many(created["id"], [%{date: ~D[2026-06-01], close: "100", source: "manual"}])

    {:ok, _} =
      Quotes.upsert_many(bitcoin["id"], [%{date: ~D[2026-06-01], close: "100", source: "manual"}])

    data =
      conn
      |> api_conn()
      |> get(
        "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    # Steering basis is 600 (Bitcoin's 400 left out); excluded block carries 400.
    assert data["total_value"] == "600"
    assert data["excluded"]["market_value"] == "400"

    equity_row = Enum.find(data["categories"], &(&1["category_id"] == equities.id))
    assert equity_row["actual_weight"] == "1"
    assert Enum.find(data["categories"], &(&1["category_id"] == crypto.id)) == nil

    [excluded_position] = data["excluded"]["positions"]
    assert excluded_position["security_id"] == bitcoin["id"]
    assert excluded_position["market_value"] == "400"
  end
end
