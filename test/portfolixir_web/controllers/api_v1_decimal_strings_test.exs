defmodule PortfolixirWeb.ApiV1DecimalStringsTest do
  # Risk-tier (ADR-0036, money; ADR-0003 as amended 2026-11-01, #1291): a
  # JSON number in a financial field is decoded as a binary float before
  # Ecto casts it, so a value past about 17 significant digits was stored as
  # a different number than the one sent. Every write under /api/v1 now
  # refuses it with a 422 naming the field; a decimal string is accepted as
  # before. Each test pins one field family on a real endpoint.
  use PortfolixirWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, deposit!: 3]

  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
  alias Portfolixir.Tax.Parameters

  @refusal ["must be a decimal string"]

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world(name: "Decimal Strings", cash_name: "EUR Cash", depot_name: "String Depot")
    security = create_security!(name: "Strict Decimal Co", ticker: "SDC")
    deposit!(world, Decimal.new("10000"), ~D[2026-03-01])

    %{conn: conn, world: world, security: security}
  end

  defp send_json(conn, method, path, body),
    do: Phoenix.ConnTest.dispatch(conn, @endpoint, method, path, Jason.encode!(body))

  defp buy(w, s, extra) do
    %{
      "transaction" =>
        Map.merge(
          %{
            "portfolio_id" => w.portfolio.id,
            "securities_account_id" => w.depot.id,
            "security_id" => s.id,
            "type" => "buy",
            "date" => "2026-04-01",
            "quantity" => "10",
            "price" => "100",
            "currency_code" => "EUR"
          },
          extra
        )
    }
  end

  defp trade_count(w) do
    Repo.aggregate(
      from(t in Transaction, where: t.portfolio_id == ^w.portfolio.id and t.type == "buy"),
      :count
    )
  end

  # User story:
  # As a hand-written client booking a trade through the API,
  # I want a quantity, price, fee, tax, money or rate sent as a JSON number
  # refused with a 422 that names the field,
  # so that a float never decides which number the ledger stores.
  #
  # Acceptance criteria:
  # - POST /api/v1/transactions with a JSON number (float or integer) in
  #   quantity, price, fees, taxes, gross_amount or settlement_fx_rate
  #   answers 422 with errors.<field> == ["must be a decimal string"].
  # - Nothing is booked.
  # - The same trade with decimal strings answers 201.
  test "a trade refuses a JSON number in each financial field family",
       %{conn: conn, world: w, security: s} do
    cases = [
      {"quantity", 10.5},
      {"quantity", 10},
      {"price", 100.1},
      {"fees", 1.5},
      {"taxes", 2},
      {"gross_amount", 1001},
      {"settlement_fx_rate", 0.9}
    ]

    for {field, number} <- cases do
      body =
        conn
        |> send_json(:post, "/api/v1/transactions", buy(w, s, %{field => number}))
        |> json_response(422)

      assert body == %{"errors" => %{field => @refusal}}, "#{field}: #{inspect(body)}"
    end

    assert trade_count(w) == 0

    assert conn
           |> send_json(:post, "/api/v1/transactions", buy(w, s, %{"fees" => "1.5"}))
           |> json_response(201)

    assert trade_count(w) == 1
  end

  # Acceptance criteria:
  # - PATCH /api/v1/transactions/:id with a JSON number in price answers
  #   422 naming price, and the stored price is unchanged.
  test "an edit refuses a JSON number and keeps the stored value",
       %{conn: conn, world: w, security: s} do
    %{"data" => %{"id" => id}} =
      conn
      |> send_json(:post, "/api/v1/transactions", buy(w, s, %{}))
      |> json_response(201)

    assert %{"errors" => %{"price" => @refusal}} =
             conn
             |> send_json(:patch, "/api/v1/transactions/#{id}", %{
               "transaction" => %{"price" => 101.25}
             })
             |> json_response(422)

    assert Decimal.equal?(Repo.get!(Transaction, id).price, Decimal.new("100"))
  end

  # Acceptance criteria:
  # - A quantity of "1234567890.12345678" (18 significant digits, past what
  #   a binary float holds) sent as a string is stored exactly.
  # - The same value sent as a JSON number is refused, not rounded to
  #   1234567890.1234567.
  test "a string past float precision is stored exactly; the number is refused",
       %{conn: conn, world: w, security: s} do
    exact = "1234567890.12345678"

    assert %{"errors" => %{"quantity" => @refusal}} =
             conn
             |> send_json(
               :post,
               "/api/v1/transactions",
               buy(w, s, %{"quantity" => 1_234_567_890.123_456_78, "price" => "0.000001"})
             )
             |> json_response(422)

    %{"data" => %{"id" => id, "quantity" => served}} =
      conn
      |> send_json(
        :post,
        "/api/v1/transactions",
        buy(w, s, %{"quantity" => exact, "price" => "0.000001"})
      )
      |> json_response(201)

    assert served == exact
    stored = Repo.get!(Transaction, id).quantity
    assert Decimal.equal?(stored, Decimal.new(exact))
    refute Decimal.equal?(stored, Decimal.from_float(1_234_567_890.123_456_78))
  end

  # Acceptance criteria (money): a cash-balance snapshot with "amount" as a
  # JSON number answers 422 naming amount; as a string it answers 201.
  test "a cash balance refuses a JSON number amount", %{conn: conn, world: w} do
    path = "/api/v1/cash_accounts/#{w.cash.id}/balance"

    assert conn
           |> send_json(:post, path, %{"date" => "2026-06-01", "amount" => 4250})
           |> json_response(422) == %{"errors" => %{"amount" => @refusal}}

    assert conn
           |> send_json(:post, path, %{"date" => "2026-06-01", "amount" => "4250.00"})
           |> json_response(201)
  end

  # Acceptance criteria (price, nested rows): a quote upsert whose second
  # row carries close as a JSON number answers 422 naming close and stores
  # no row of the batch.
  test "a quote batch refuses a JSON number close in any row",
       %{conn: conn, security: s} do
    path = "/api/v1/securities/#{s.id}/quotes"

    rows = [
      %{"date" => "2026-01-02", "close" => "10.5", "source" => "manual"},
      %{"date" => "2026-01-05", "close" => 11.25, "source" => "manual"}
    ]

    assert conn |> send_json(:put, path, %{"quotes" => rows}) |> json_response(422) ==
             %{"errors" => %{"close" => @refusal}}

    assert Repo.aggregate(Quote, :count) == 0
  end

  # Acceptance criteria (tax, and a list of rates): tax parameters with a
  # JSON number capital_gains_tax_rate, or a church_tax_rates list holding a
  # number, answer 422 naming the field and store nothing.
  test "tax parameters refuse a JSON number rate, also inside a list", %{conn: conn} do
    valid = %{
      "jurisdiction" => "DE",
      "tax_year" => 2031,
      "capital_gains_tax_rate" => "0.25",
      "solidarity_surcharge_rate" => "0.055",
      "saver_allowance_single" => "1000.00",
      "saver_allowance_joint" => "2000.00"
    }

    for {field, value} <- [{"capital_gains_tax_rate", 0.25}, {"church_tax_rates", ["0.08", 0.09]}] do
      body =
        conn
        |> send_json(:put, "/api/v1/tax/parameters", %{
          "parameters" => Map.put(valid, field, value)
        })
        |> json_response(422)

      assert body == %{"errors" => %{field => @refusal}}, "#{field}: #{inspect(body)}"
    end

    assert Repo.aggregate(from(p in Parameters, where: p.tax_year == 2031), :count) == 0
  end

  # Acceptance criteria (rate on the catalog): a security edit with
  # coupon_rate as a JSON number answers 422 naming coupon_rate.
  test "a security edit refuses a JSON number coupon rate", %{conn: conn, security: s} do
    assert conn
           |> send_json(:patch, "/api/v1/securities/#{s.id}", %{
             "security" => %{"coupon_rate" => 2.5}
           })
           |> json_response(422) == %{"errors" => %{"coupon_rate" => @refusal}}
  end

  # Acceptance criteria: a field outside the six families keeps taking a
  # JSON integer (tax_year, an id), and a JSON null in a financial field is
  # not a number, so it reaches the changeset as before.
  test "non-financial integers and nulls pass the guard", %{conn: conn, world: w, security: s} do
    assert conn
           |> send_json(:post, "/api/v1/transactions", buy(w, s, %{"fees" => nil}))
           |> json_response(201)
  end
end
