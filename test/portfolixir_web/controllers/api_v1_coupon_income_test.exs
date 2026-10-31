defmodule PortfolixirWeb.ApiV1CouponIncomeTest do
  # #928 (Sprint 21 α4; ADR-0051's amendment of 2026-10-09, points 2, 5 and
  # 6): an interest booking that names a security is that position's income
  # in every contribution read, and the bond's row on the income read, however
  # it was written. Here it is written over the API, as an agent writes it.
  # I12's figures, invented throughout.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world(name: "Coupon API", cash_name: "Coupon-Cash", depot_name: "Coupon-Depot")

    bond =
      create_security!(
        name: "Larkspur Rail AG 4,00 % Anleihe 2031",
        ticker: "LRK31",
        isin: "XSLARKSPUR33"
      )

    deposit!(world, "10000.00", ~D[2025-03-02])
    buy!(world, bond, quantity: "100", price: "99.50", fees: "5.00", date: ~D[2025-03-10])
    put_quotes!(bond, [{~D[2025-12-31], "99.00"}, {~D[2026-06-30], "100.25"}])

    %{conn: conn, world: world, bond: bond}
  end

  defp interest(world, date, amount, security) do
    %{
      "portfolio_id" => world.portfolio.id,
      "cash_account_id" => world.cash.id,
      "type" => "interest",
      "date" => date,
      "gross_amount" => amount,
      "currency_code" => "EUR",
      "security_id" => security && security.id
    }
  end

  defp cash_only_view!(world) do
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Coupon cash"})
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), world.cash, [bucket.id])

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{name: "Coupon cash only", include_all: false})

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])
    view
  end

  defp book!(conn, body) do
    conn
    |> post("/api/v1/transactions", %{"transaction" => body})
    |> json_response(201)
  end

  # Financial decimals are strings (ADR-0003); each is compared as a Decimal.
  defp assert_figures(payload, expected) do
    for {field, value} <- expected do
      actual = Map.fetch!(payload, Atom.to_string(field))
      assert is_binary(actual), "#{field} is not a string"
      assert Decimal.equal?(Decimal.new(actual), Decimal.new(value)), "#{field}: #{actual}"
    end
  end

  defp read(conn, path), do: conn |> get(path) |> json_response(200) |> Map.fetch!("data")

  # User story (#928, Sprint 21 α4; ADR-0051 I12 over the API):
  # As the operator's agent that books a bond's coupon with
  # `portfolixir.transactions.create`, naming the bond,
  # I want every contribution read to count it as the bond's income and the
  # income read to put it on the bond's row,
  # so that the figures I hand the operator say which position paid it.
  #
  # Acceptance criteria:
  # - The coupon, 400.00 naming the bond, and an account interest of 1.10
  #   naming none, both booked over POST /api/v1/transactions.
  # - Over from=2026-01-01&to=2026-06-30, the portfolio's and the view-less
  #   contribution reads each answer the bond with income "400.00" and
  #   contribution "525.00", the interest line "1.10" and the result
  #   "526.10", and the basis names the new income term and the narrower
  #   interest line.
  # - The view read, for a view holding the cash account but not the depot
  #   (I13), answers the bond with income and contribution "400.00", the
  #   interest line "1.10" and the result "401.10".
  # - The income read's per-position rows: the bond 400.00, one payment,
  #   last 2026-04-15; the row without a security 1.10, one payment, last
  #   2026-03-31.
  test "a coupon naming its bond, booked over the API, is the bond's income in every read",
       %{conn: conn, world: world, bond: bond} do
    book!(conn, interest(world, "2026-03-31", "1.10", nil))
    coupon = book!(conn, interest(world, "2026-04-15", "400.00", bond))
    assert coupon["data"]["security_id"] == bond.id

    window = "from=2026-01-01&to=2026-06-30"

    for path <- [
          "/api/v1/portfolios/#{world.portfolio.id}/performance/contribution?#{window}",
          "/api/v1/performance/contribution?#{window}"
        ] do
      data = read(conn, path)
      assert [row] = data["positions"], path

      assert row["security_id"] == bond.id, path

      assert_figures(row,
        start_value: "9900.00",
        end_value: "10025.00",
        net_flows: "0",
        income: "400.00",
        costs: "0",
        contribution: "525.00"
      )

      assert_figures(data["remainder"],
        interest: "1.10",
        standalone_fees_and_taxes: "0",
        cash_currency_effect: "0"
      )

      assert Decimal.equal?(Decimal.new(data["totals"]["result"]), Decimal.new("526.10")), path

      assert data["computation_basis"]["assumptions"] =~
               "income is the dividends and the interest bookings that name the position's security"

      assert data["computation_basis"]["assumptions"] =~
               "interest is the interest bookings that name no security"
    end

    cash_view = cash_only_view!(world)
    data = read(conn, "/api/v1/views/#{cash_view.id}/performance/contribution?#{window}")
    assert [row] = data["positions"]
    assert row["security_id"] == bond.id

    assert_figures(row,
      start_value: "0",
      end_value: "0",
      income: "400.00",
      contribution: "400.00"
    )

    assert_figures(data["remainder"], interest: "1.10")
    assert_figures(data["totals"], result: "401.10")

    income = read(conn, "/api/v1/portfolios/#{world.portfolio.id}/income")

    assert [bond_row, account_row] = income["positions"]
    assert bond_row["security_id"] == bond.id
    assert Decimal.equal?(Decimal.new(bond_row["gross"]), Decimal.new("400.00"))
    assert {bond_row["payment_count"], bond_row["last_payment"]} == {1, "2026-04-15"}

    assert account_row["security_id"] == nil
    assert Decimal.equal?(Decimal.new(account_row["gross"]), Decimal.new("1.10"))
    assert {account_row["payment_count"], account_row["last_payment"]} == {1, "2026-03-31"}
  end
end
