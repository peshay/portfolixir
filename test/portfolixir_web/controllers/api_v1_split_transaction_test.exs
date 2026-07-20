defmodule PortfolixirWeb.ApiV1SplitTransactionTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

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
end
