defmodule PortfolixirWeb.ApiV1LedgerDataQualityTest do
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp transaction_count, do: Repo.aggregate(Transaction, :count)

  # User story (#1292):
  # As an API client (and the LLM I connect over MCP),
  # I want the stored split events that miss a positioned portfolio over the
  # API,
  # so that a portfolio whose lots a split scales while its holding stays
  # unscaled is visible without a console.
  #
  # Acceptance criteria:
  # - GET /api/v1/splits/incomplete lists each such event with the security,
  #   the date, the integer ratio parts, the booked rows' portfolios and
  #   transaction ids, and each missing portfolio with its quantity entering
  #   the date as a Decimal string.
  # - The response is self-describing (as_of, note, remedy) and the read
  #   writes nothing; without such an event the list is empty.
  test "GET /api/v1/splits/incomplete lists the event and the missing portfolio",
       %{conn: conn} do
    security = create_security!(name: "Split Gap Co", ticker: "SGC", asset_class: "equity")
    a = base_world(name: "Portfolio A", cash_name: "A Cash", depot_name: "A Depot")
    b = base_world(name: "Portfolio B", cash_name: "B Cash", depot_name: "B Depot")
    buy!(a, security, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(b, security, quantity: "7.5", price: "100", date: ~D[2026-01-02])

    {:ok, split_a} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        %{
          portfolio_id: a.portfolio.id,
          security_id: security.id,
          type: "split",
          date: ~D[2026-02-02],
          currency_code: "EUR",
          split_ratio_numerator: 2,
          split_ratio_denominator: 1
        },
        split_flow: true
      )

    before = transaction_count()

    data =
      conn
      |> api_conn()
      |> get("/api/v1/splits/incomplete")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["as_of"] =~ ~r/^\d{4}-\d{2}-\d{2}$/
    assert data["note"] =~ "FIFO lots"
    assert data["remedy"] =~ "POST /api/v1/splits"

    assert [event] = data["rows"]

    assert event == %{
             "security_id" => security.id,
             "security_name" => "Split Gap Co",
             "isin" => nil,
             "date" => "2026-02-02",
             "ratio_numerator" => 2,
             "ratio_denominator" => 1,
             "booked_portfolio_ids" => [a.portfolio.id],
             "transaction_ids" => [split_a.id],
             "missing_portfolios" => [
               %{
                 "portfolio_id" => b.portfolio.id,
                 "portfolio_name" => "Portfolio B",
                 "quantity_before" => "7.5"
               }
             ]
           }

    assert transaction_count() == before
  end

  test "GET /api/v1/splits/incomplete answers an empty list without such an event",
       %{conn: conn} do
    data =
      conn
      |> api_conn()
      |> get("/api/v1/splits/incomplete")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["rows"] == []
  end

  # User story (#1290):
  # As an API client (and the LLM I connect over MCP),
  # I want the stored cross-currency trades with a settlement rate and
  # neither amount over the API,
  # so that T-19's rows have an operator surface beside the console.
  #
  # Acceptance criteria:
  # - GET /api/v1/transactions/rate_only lists each such trade with its
  #   figures, the cash booked, the cash its rate implies and the
  #   difference, every financial figure a Decimal string, whatever the
  #   size of the gap.
  # - The response is self-describing (as_of, note, remedy) and the read
  #   writes nothing; GET /api/v1/transactions/:id still answers a booking.
  test "GET /api/v1/transactions/rate_only lists the stored rate-only trades", %{conn: conn} do
    world = base_world(name: "Rate World", cash_name: "EUR Cash", depot_name: "Rate Depot")
    usd = create_security!(name: "US Rate Co", ticker: "URC", currency: "USD")
    row = insert_rate_only!(world, usd, ~D[2026-04-01], "1.000004")
    before = transaction_count()

    data =
      conn
      |> api_conn()
      |> get("/api/v1/transactions/rate_only")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["as_of"] =~ ~r/^\d{4}-\d{2}-\d{2}$/
    assert data["note"] =~ "settlement rate"
    assert data["remedy"] =~ "PATCH /api/v1/transactions/:id"

    assert [listed] = data["rows"]

    assert listed == %{
             "id" => row.id,
             "portfolio_id" => world.portfolio.id,
             "security_id" => usd.id,
             "security_name" => "US Rate Co",
             "cash_account_id" => world.cash.id,
             "cash_account_currency_code" => "EUR",
             "date" => "2026-04-01",
             "type" => "buy",
             "currency_code" => "USD",
             "quantity" => "10",
             "price" => "200",
             "fees" => "4.9",
             "taxes" => "0",
             "settlement_fx_rate" => "1.000004",
             "booked_cash" => "2004.9",
             "expected_cash" => "2004.908",
             "difference" => "-0.008"
           }

    assert transaction_count() == before

    assert conn
           |> api_conn()
           |> get("/api/v1/transactions/#{row.id}")
           |> json_response(200)
           |> get_in(["data", "id"]) == row.id
  end

  # A row stored before the guard refused the shape (H35), inserted below
  # the ledger the way the guard's own test stores one.
  defp insert_rate_only!(world, security, date, rate) do
    {:ok, row} =
      Repo.transaction(fn ->
        {type, _label} = Actor.to_columns(Actor.owner_ui())
        Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])

        Repo.insert!(%Transaction{
          portfolio_id: world.portfolio.id,
          securities_account_id: world.depot.id,
          cash_account_id: world.cash.id,
          security_id: security.id,
          type: "buy",
          date: date,
          quantity: Decimal.new("10"),
          price: Decimal.new("200.00"),
          fees: Decimal.new("4.90"),
          taxes: Decimal.new("0"),
          currency_code: "USD",
          settlement_fx_rate: Decimal.new(rate)
        })
      end)

    row
  end
end
