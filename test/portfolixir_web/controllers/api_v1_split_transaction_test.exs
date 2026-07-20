defmodule PortfolixirWeb.ApiV1SplitTransactionTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger

  @auth {"authorization", "Bearer test-api-token"}

  # User story (ADR-0028 §5, issue #589 slice 1):
  # As an API/MCP client reading the ledger,
  # I want a booked split row to come back with its normalized ratio integers,
  # so that no ledger data is lost on the read path. (The one-request
  # per-portfolio booking fan-out endpoint is a later slice; this slice only
  # guarantees the generic transaction read path carries the new kind.)
  #
  # Acceptance criteria:
  # - GET /api/v1/transactions serializes type "split" with
  #   split_ratio_numerator/denominator as integers (normalized pair).
  # - The forbidden financial fields of a split serialize as null.
  test "GET /api/v1/transactions serializes a split row with its normalized ratio", %{conn: conn} do
    world = base_world(name: "Api Split World")
    security = create_security!(name: "Api Split Co", ticker: "ASP")

    {:ok, _tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        security_id: security.id,
        type: "split",
        date: ~D[2026-03-01],
        currency_code: "EUR",
        split_ratio_numerator: 10,
        split_ratio_denominator: 5
      })

    response =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header(elem(@auth, 0), elem(@auth, 1))
      |> get("/api/v1/transactions?portfolio_id=#{world.portfolio.id}")
      |> json_response(200)

    assert [row] = response["data"]
    assert row["type"] == "split"
    assert row["split_ratio_numerator"] == 2
    assert row["split_ratio_denominator"] == 1
    assert row["security_id"] == security.id
    assert row["date"] == "2026-03-01"
    assert row["quantity"] == nil
    assert row["price"] == nil
    assert row["gross_amount"] == nil
    assert row["cash_account_id"] == nil
  end

  # User story (ADR-0028 §1, issue #589 slice 1):
  # As the maintainer of the local ledger,
  # I want the generic transaction write API to refuse a `split`,
  # so that a split can only ever be booked through the dedicated
  # per-portfolio fan-out flow (a later slice) and never lands as a single
  # generic row before the quote/price-basis adjustment engine (#590) exists.
  #
  # Acceptance criteria:
  # - POST /api/v1/transactions with type "split" is rejected with HTTP 422
  #   and a message pointing at the dedicated split flow, BEFORE any write.
  # - PATCH /api/v1/transactions/:id changing an existing row to type "split"
  #   is rejected the same way.
  # - Every other kind (e.g. a buy) still creates/updates exactly as before.
  @split_message "split transactions are booked via the dedicated split flow, not the generic transaction endpoint"

  defp authed(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  test "POST /api/v1/transactions rejects type \"split\" with 422 before any write", %{conn: conn} do
    world = base_world(name: "Api Split Reject World")
    security = create_security!(name: "Reject Co", ticker: "RJC")

    response =
      conn
      |> authed()
      |> post("/api/v1/transactions", %{
        "transaction" => %{
          "portfolio_id" => world.portfolio.id,
          "security_id" => security.id,
          "type" => "split",
          "date" => "2026-03-01",
          "currency_code" => "EUR",
          "split_ratio_numerator" => 10,
          "split_ratio_denominator" => 5
        }
      })
      |> json_response(422)

    assert response["errors"]["type"] == [@split_message]

    # Nothing was written.
    assert Ledger.list_transactions(portfolio_id: world.portfolio.id) == []
  end

  test "PATCH /api/v1/transactions/:id rejects a change to type \"split\" with 422", %{conn: conn} do
    world = base_world(name: "Api Split Update World")
    security = create_security!(name: "Update Co", ticker: "UPC")
    buy = buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])

    response =
      conn
      |> authed()
      |> patch("/api/v1/transactions/#{buy.id}", %{"transaction" => %{"type" => "split"}})
      |> json_response(422)

    assert response["errors"]["type"] == [@split_message]

    # The row is untouched.
    assert Ledger.get_transaction(buy.id).type == "buy"
  end

  test "POST /api/v1/transactions still creates a normal buy (regression)", %{conn: conn} do
    world = base_world(name: "Api Buy World")
    security = create_security!(name: "Buy Co", ticker: "BUY")

    response =
      conn
      |> authed()
      |> post("/api/v1/transactions", %{
        "transaction" => %{
          "portfolio_id" => world.portfolio.id,
          "securities_account_id" => world.depot.id,
          "cash_account_id" => world.cash.id,
          "security_id" => security.id,
          "type" => "buy",
          "date" => "2026-01-02",
          "currency_code" => "EUR",
          "quantity" => "10",
          "price" => "100"
        }
      })
      |> json_response(201)

    assert response["data"]["type"] == "buy"
    assert [_row] = Ledger.list_transactions(portfolio_id: world.portfolio.id)
  end
end
