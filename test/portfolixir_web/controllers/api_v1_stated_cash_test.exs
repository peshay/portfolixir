defmodule PortfolixirWeb.ApiV1StatedCashTest do
  # ADR-0053, amendment of 2026-11-02 (#1371): the identity the building
  # batch pins, at the JSON API. Risk tier (how a stored booking is
  # corrected, ADR-0036): every figure is an exact Decimal string.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.TradeMatcher
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @required "is required when quantity, price, fees or taxes change on a booking that stores its cash"

  # Every field a booking stores that a refused PATCH could move.
  @figures [
    :type,
    :date,
    :currency_code,
    :quantity,
    :price,
    :fees,
    :taxes,
    :gross_amount,
    :security_amount,
    :settlement_amount,
    :settlement_fx_rate,
    :notes
  ]

  defp api(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  # Synthetic figures only (#1371's example): an imported buy, 10 at 80.00,
  # fees 5.00, taxes 1.00, its cash 806.00 as the file stated it.
  defp imported_buy!(world, security, currency) do
    {:ok, buy} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          securities_account_id: world.depot.id,
          cash_account_id: world.cash.id,
          security_id: security.id,
          type: "buy",
          date: ~D[2026-04-15],
          quantity: "10",
          price: "80.00",
          fees: "5.00",
          taxes: "1.00",
          currency_code: currency,
          gross_amount: "806.00"
        },
        import_hash: String.duplicate("c", 64)
      )

    buy
  end

  defp patch_tx(conn, id, attrs),
    do: conn |> api() |> patch("/api/v1/transactions/#{id}", %{"transaction" => attrs})

  defp figures(id), do: Transaction |> Repo.get!(id) |> Map.take(@figures)

  defp cash_balance(conn, cash_id) do
    conn
    |> api()
    |> get("/api/v1/cash_accounts")
    |> json_response(200)
    |> Map.fetch!("data")
    |> Enum.find(&(&1["id"] == cash_id))
    |> Map.fetch!("balance")
  end

  defp holding(conn, portfolio_id, security_id) do
    conn
    |> api()
    |> get("/api/v1/portfolios/#{portfolio_id}/holdings")
    |> json_response(200)
    |> Map.fetch!("data")
    |> Enum.find(&(&1["security_id"] == security_id))
  end

  defp trades(conn, security_id) do
    conn
    |> api()
    |> get("/api/v1/securities/#{security_id}/trades")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  # User story (#1371):
  # As an API client correcting an imported buy (and the LLM I connect over
  # MCP),
  # I want a PATCH of its price to be refused unless it states the cash too,
  # and the stated cash checked to the cent,
  # so that the cash balance, the holding's cost and the lot read one cost.
  #
  # Acceptance criteria (ADR-0053, amendment of 2026-11-02, the identity):
  # - price 81.00 alone: 422 naming gross_amount, the row unchanged.
  # - price 81.00 with gross_amount "816.00": stored; the cash balance reads
  #   -816.00, the open lot 816.00 (10 × 81.00 + 5.00 + 1.00) and the closed
  #   trade's basis after a sale 816.00; the holding's cost basis, quantity ×
  #   price by its own rule, reads 810.00.
  # - price 81.00 with gross_amount "806.00": refused by §2's check, the
  #   message naming 816.00.
  test "the identity: 806.00 before, 816.00 after a stated edit, on every reading",
       %{conn: conn} do
    world = base_world(name: "Identity", cash_name: "ID Cash", depot_name: "ID Depot")
    security = create_security!(name: "Identity Co", ticker: "IDC", currency: "EUR")
    buy = imported_buy!(world, security, "EUR")
    stored = figures(buy.id)

    assert cash_balance(conn, world.cash.id) == "-806"

    # price 81.00 alone: refused, nothing moves.
    assert %{"errors" => %{"gross_amount" => [@required]}} =
             conn |> patch_tx(buy.id, %{"price" => "81.00"}) |> json_response(422)

    assert figures(buy.id) == stored

    # with the cash the old figures gave: refused by §2's check.
    assert %{"errors" => %{"gross_amount" => [mismatch]}} =
             conn
             |> patch_tx(buy.id, %{"price" => "81.00", "gross_amount" => "806.00"})
             |> json_response(422)

    assert mismatch == "does not match quantity × price, fees and taxes — expected 816.00"
    assert figures(buy.id) == stored

    # with the cash the new figures give: stored.
    data =
      conn
      |> patch_tx(buy.id, %{"price" => "81.00", "gross_amount" => "816.00"})
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["price"] == "81"
    assert data["gross_amount"] == "816"

    # The cash projection.
    assert cash_balance(conn, world.cash.id) == "-816"

    # The holding's cost basis is quantity × price by its own rule (ADR-0033,
    # fees and taxes outside it), so it reads the corrected price: 810.
    assert holding(conn, world.portfolio.id, security.id)["cost_basis"] == "810"

    # The open lot (TradeMatcher): 10 × 81.00 + 5.00 + 1.00.
    assert [lot] = trades(conn, security.id)["open_lots"]
    assert lot["buy_price"] == "81"
    assert {lot["buy_fees"], lot["buy_taxes"]} == {"5", "1"}

    assert [open] = Ledger.list_trades_for_security(security.id).open_lots
    assert Decimal.equal?(TradeMatcher.lot_cost(open), Decimal.new("816.00"))

    # The closed trade (realized): its basis is the same 816.00.
    sell!(world, security, quantity: "10", price: "90", date: ~D[2026-05-04])
    assert [closed] = trades(conn, security.id)["closed_trades"]
    assert closed["basis"] == "816"
    assert closed["realized_pnl_abs"] == "84"
  end

  # Acceptance criteria (a sell, whose cash is net of fees and taxes):
  # - price 91.00 alone is refused; with gross_amount "358.50" (4 × 91.00 −
  #   3.00 − 2.50) it is stored and the cash balance credits 358.50.
  test "a sell's edit states its net cash", %{conn: conn} do
    world = base_world(name: "Sell Side", cash_name: "SS Cash", depot_name: "SS Depot")
    security = create_security!(name: "Sell Side Co", ticker: "SSC", currency: "EUR")
    _buy = imported_buy!(world, security, "EUR")

    {:ok, sell} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2026-05-04],
        quantity: "4",
        price: "90.00",
        fees: "3.00",
        taxes: "2.50",
        currency_code: "EUR",
        gross_amount: "354.50"
      })

    assert %{"errors" => %{"gross_amount" => [@required]}} =
             conn |> patch_tx(sell.id, %{"price" => "91.00"}) |> json_response(422)

    assert %{"errors" => %{"gross_amount" => [_mismatch]}} =
             conn
             |> patch_tx(sell.id, %{"price" => "91.00", "gross_amount" => "354.50"})
             |> json_response(422)

    conn
    |> patch_tx(sell.id, %{"price" => "91.00", "gross_amount" => "358.50"})
    |> json_response(200)

    # -806.00 for the buy, +358.50 for the sale.
    assert cash_balance(conn, world.cash.id) == "-447.5"
  end

  # Acceptance criteria (the plan's carry-forward, D-7: a money identity is
  # checked at a moving rate too; ADR-0015, amendment of 2026-11-01, point 2):
  # - A legless cross-currency buy (a USD security, stored in EUR from a EUR
  #   account, no legs) follows the rule in its stored currency: the derived
  #   cash is 816.00 EUR whatever the EUR/USD rate on its day or today, and a
  #   cash converted at either rate is refused.
  # - With the rate moving between the buy's day and today, the stored cash
  #   and the cash balance read 816.00 EUR, and the row stays legless and in
  #   EUR.
  test "a legless cross-currency row follows the rule in its stored currency at a moving rate",
       %{conn: conn} do
    world = base_world(name: "Moving Rate", cash_name: "MR EUR Cash", depot_name: "MR Depot")
    usd = create_security!(name: "Moving Rate Inc.", ticker: "MRI", currency: "USD")
    buy = imported_buy!(world, usd, "EUR")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-04-15],
          rate: "1.25",
          source: "manual"
        },
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-05-15],
          rate: "1.10",
          source: "manual"
        }
      ])

    assert %{"errors" => %{"gross_amount" => [@required]}} =
             conn |> patch_tx(buy.id, %{"price" => "81.00"}) |> json_response(422)

    # 816.00 EUR at either rate: 1020.00 and 897.60 are refused.
    for converted <- ["1020.00", "897.60"] do
      assert %{"errors" => %{"gross_amount" => [mismatch]}} =
               conn
               |> patch_tx(buy.id, %{"price" => "81.00", "gross_amount" => converted})
               |> json_response(422)

      assert mismatch == "does not match quantity × price, fees and taxes — expected 816.00"
    end

    conn
    |> patch_tx(buy.id, %{"price" => "81.00", "gross_amount" => "816.00"})
    |> json_response(200)

    corrected = Repo.get!(Transaction, buy.id)
    assert corrected.currency_code == "EUR"
    assert Decimal.equal?(corrected.gross_amount, Decimal.new("816.00"))
    assert {corrected.settlement_amount, corrected.security_amount} == {nil, nil}
    assert is_nil(corrected.settlement_fx_rate)

    assert cash_balance(conn, world.cash.id) == "-816"
  end
end
