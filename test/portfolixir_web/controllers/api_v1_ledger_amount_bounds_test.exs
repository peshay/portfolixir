defmodule PortfolixirWeb.ApiV1LedgerAmountBoundsTest do
  # E25 S4, G16 and G17 (#889). G16: a ledger amount with more decimals than
  # its column's scale was rounded by the database after validation, so the
  # row, the answer and the journal disagreed and a positive amount that
  # rounds to zero passed. G17: an amount past its column's precision failed
  # in the database with a 500 instead of a field error.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Journal
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world(name: "Amount bounds")
    security = create_security!(name: "Meridian Global Equity ETF", ticker: "MGE")
    %{conn: conn, world: world, security: security}
  end

  defp deposit(world, overrides) do
    Map.merge(
      %{
        "portfolio_id" => world.portfolio.id,
        "cash_account_id" => world.cash.id,
        "type" => "deposit",
        "date" => "2026-01-02",
        "gross_amount" => "100",
        "currency_code" => "EUR"
      },
      overrides
    )
  end

  defp buy(world, security, overrides) do
    Map.merge(
      %{
        "portfolio_id" => world.portfolio.id,
        "securities_account_id" => world.depot.id,
        "security_id" => security.id,
        "type" => "buy",
        "date" => "2026-01-02",
        "quantity" => "3",
        "price" => "10",
        "currency_code" => "EUR"
      },
      overrides
    )
  end

  # User story:
  # As the operator's agent booking an amount with more decimals than the
  # ledger keeps,
  # I want the amount rounded once, to the ledger's own scale, before it is
  # checked,
  # so that what I am answered, what is stored and what the journal records
  # are the same number — and an amount that rounds to nothing is refused.
  #
  # Acceptance criteria:
  # - An over-scale amount and quantity are stored, answered and journaled
  #   identically, rounded half up to the column's scale.
  # - A positive amount or quantity that rounds to zero answers 422 on its
  #   field and stores nothing.
  test "an over-scale amount is stored, answered and journaled identically",
       %{conn: conn, world: world, security: security} do
    %{"data" => created} =
      conn
      |> post("/api/v1/transactions", %{
        "transaction" =>
          buy(world, security, %{"quantity" => "1.0000000000005", "price" => "10.1234565"})
      })
      |> json_response(201)

    stored = Repo.get!(Transaction, created["id"])
    [entry] = Journal.list_entries(resource_type: "transaction")

    assert Decimal.equal?(stored.quantity, Decimal.new("1.000000000001"))
    assert Decimal.equal?(stored.price, Decimal.new("10.123457"))

    for field <- ["quantity", "price"] do
      stored_value = Map.fetch!(stored, String.to_existing_atom(field))
      assert Decimal.equal?(Decimal.new(created[field]), stored_value), field
      assert Decimal.equal?(Decimal.new(entry.after[field]), stored_value), field
    end
  end

  test "a positive amount that rounds to zero answers 422 and stores nothing",
       %{conn: conn, world: world, security: security} do
    body =
      conn
      |> post("/api/v1/transactions", %{
        "transaction" => deposit(world, %{"gross_amount" => "0.0000004"})
      })
      |> json_response(422)

    assert Map.has_key?(body["errors"], "gross_amount")

    body =
      conn
      |> post("/api/v1/transactions", %{
        "transaction" => buy(world, security, %{"quantity" => "0.0000000000004"})
      })
      |> json_response(422)

    assert Map.has_key?(body["errors"], "quantity")
    assert Repo.aggregate(Transaction, :count) == 0
  end

  # User story:
  # As the operator's agent,
  # I want an amount larger than the ledger can hold refused as a field error,
  # so that a typo answers a 422 naming the field instead of a server error.
  #
  # Acceptance criteria:
  # - Every money field and the quantity past its column's precision answers
  #   422 naming that field, on create and on update, and stores nothing.
  test "an out-of-range amount answers 422 naming its field",
       %{conn: conn, world: world, security: security} do
    too_big_money = "100000000000000"
    too_big_quantity = "1000000000000000000"

    cases = [
      {deposit(world, %{"gross_amount" => too_big_money}), "gross_amount"},
      {deposit(world, %{"gross_amount" => "1e300"}), "gross_amount"},
      {deposit(world, %{"fees" => too_big_money}), "fees"},
      {deposit(world, %{"taxes" => too_big_money}), "taxes"},
      {buy(world, security, %{"price" => too_big_money}), "price"},
      {buy(world, security, %{"quantity" => too_big_quantity}), "quantity"}
    ]

    for {attrs, field} <- cases do
      body = conn |> post("/api/v1/transactions", %{"transaction" => attrs}) |> json_response(422)
      assert Map.has_key?(body["errors"], field), "#{field}: #{inspect(body)}"
    end

    assert Repo.aggregate(Transaction, :count) == 0

    %{"data" => booked} =
      conn
      |> post("/api/v1/transactions", %{"transaction" => deposit(world, %{})})
      |> json_response(201)

    body =
      conn
      |> patch("/api/v1/transactions/#{booked["id"]}", %{
        "transaction" => %{"gross_amount" => too_big_money}
      })
      |> json_response(422)

    assert Map.has_key?(body["errors"], "gross_amount")
    assert Decimal.equal?(Repo.get!(Transaction, booked["id"]).gross_amount, 100)
  end
end
