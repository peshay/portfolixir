defmodule PortfolixirWeb.ApiV1SplitPooledLotsTest do
  # Risk-tier (ADR-0036, money): the FIFO queue is one per security across
  # portfolios (the ADR-0015 amendment of 2026-10-09), and a split scales it
  # whole. Synthetic data, exact Decimal identities, one at a time. Equal buy
  # prices make the truth independent of which portfolio's lot a sale takes:
  # B realizes 10 × (110 - 100) = +100, A realizes 20 × 55 - 1000 = +100.
  use PortfolixirWeb.ConnCase, async: false

  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp dec(value) when is_binary(value), do: Decimal.new(value)
  defp dec(%Decimal{} = value), do: value

  defp sum(list, fun), do: Enum.reduce(list, Decimal.new(0), &Decimal.add(&2, dec(fun.(&1))))

  defp assert_dec(actual, expected),
    do: assert(Decimal.equal?(dec(actual), Decimal.new(expected)), "#{actual} != #{expected}")

  # Two portfolios hold one security. A buys first, B buys the next day and
  # sells out the day after, then a 2:1 split is booked through the split
  # flow, which books a row for every portfolio positioned at its date.
  defp world(opts \\ []) do
    a = WorldFixtures.base_world(name: "Pool A", cash_name: "Pool A Cash", depot_name: "A Depot")
    b = WorldFixtures.base_world(name: "Pool B", cash_name: "Pool B Cash", depot_name: "B Depot")
    security = WorldFixtures.create_security!(name: "Pooled Split Co", ticker: "PSC")

    WorldFixtures.deposit!(a, "10000", ~D[2026-01-01])
    WorldFixtures.deposit!(b, "10000", ~D[2026-01-01])

    WorldFixtures.buy!(a, security, quantity: "10", price: "100", date: ~D[2026-02-02])
    WorldFixtures.buy!(b, security, quantity: "10", price: "100", date: ~D[2026-02-03])

    if Keyword.get(opts, :b_sells?, true) do
      WorldFixtures.sell!(b, security, quantity: "10", price: "110", date: ~D[2026-02-04])
    end

    split_conn =
      build_conn()
      |> api_conn()
      |> post(
        "/api/v1/splits",
        Jason.encode!(%{
          security_id: security.id,
          date: "2026-03-02",
          ratio_numerator: 2,
          ratio_denominator: 1
        })
      )

    %{"data" => %{"transactions" => rows}} = json_response(split_conn, 201)

    # A close after the effective date, so the reads value at 55 unadjusted.
    WorldFixtures.put_quote!(security, ~D[2026-03-03], "55")

    %{a: a, b: b, security: security, split_rows: rows}
  end

  defp trades(security) do
    build_conn()
    |> api_conn()
    |> get("/api/v1/securities/#{security.id}/trades")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  # User story (security review 2026-10-12, K09):
  # As the operator holding one security in two portfolios,
  # I want a split to scale every open lot of the security's FIFO queue once,
  # whatever portfolio the lot was bought in,
  # so that the trades, the realized gains and the sell preview follow the
  # shares actually held, as the holdings do.
  #
  # Acceptance criteria:
  # - Without a cross-portfolio sale, the split's two rows scale the open
  #   lots once: 40 shares in lots, 40 held.
  # - After B's sale consumed A's older lot and the split booked a row for A
  #   only, the remaining lot reads 20 shares at 50, unrealized +100 at 55,
  #   exactly what the holdings read.
  # - When A then sells its 20 shares at 55, the closed trades realize +100
  #   and +100, and no sell is left unmatched.
  # - The realized-gains read states realized_total 200, hit_rate 1 and no
  #   unmatched sells.
  # - The sell preview of A's 20 shares at 55 has no shortfall and a gross
  #   gain of exactly +100.
  describe "a split scales the security's whole FIFO queue" do
    test "without a cross-portfolio sale, the open lots cover the shares held" do
      w = world(b_sells?: false)
      assert length(w.split_rows) == 2

      held = sum(Ledger.holdings_for_security(w.security.id), & &1.quantity)
      open_lots = trades(w.security)["open_lots"]

      assert_dec(held, "40")
      assert_dec(sum(open_lots, & &1["quantity"]), "40")

      assert Enum.map(open_lots, & &1["quantity"])
             |> Enum.map(&dec/1)
             |> Enum.all?(&Decimal.equal?(&1, 20))

      assert Enum.all?(open_lots, &Decimal.equal?(dec(&1["buy_price"]), 50))
    end

    test "after the split, the open lot holds the shares held at their cost" do
      w = world()

      # The split flow booked a row for A only: B was flat at its date.
      assert [%{"portfolio_id" => a_id}] = w.split_rows
      assert a_id == w.a.portfolio.id

      holdings = Ledger.holdings_for_security(w.security.id)
      assert_dec(sum(holdings, & &1.quantity), "20")
      assert_dec(sum(holdings, & &1.unrealized_pnl_abs), "100")

      assert [lot] = trades(w.security)["open_lots"]
      assert_dec(lot["quantity"], "20")
      assert_dec(lot["buy_price"], "50")
      assert_dec(lot["unrealized_pnl_abs"], "100")
    end

    test "after A sells its post-split shares, the closed trades realize what the bookings did" do
      w = world()
      WorldFixtures.sell!(w.a, w.security, quantity: "20", price: "55", date: ~D[2026-03-05])

      assert Ledger.holdings_for_security(w.security.id) == []

      data = trades(w.security)
      assert data["orphan_sells"] == []
      assert data["open_lots"] == []

      assert [b_trade, a_trade] = data["closed_trades"]
      assert_dec(b_trade["quantity"], "10")
      assert_dec(b_trade["basis"], "1000")
      assert_dec(b_trade["proceeds"], "1100")
      assert_dec(b_trade["realized_pnl_abs"], "100")

      assert_dec(a_trade["quantity"], "20")
      assert_dec(a_trade["avg_buy_price"], "50")
      assert_dec(a_trade["basis"], "1000")
      assert_dec(a_trade["proceeds"], "1100")
      assert_dec(a_trade["realized_pnl_abs"], "100")
    end

    test "the realized-gains read matches the cash the bookings moved" do
      w = world()
      WorldFixtures.sell!(w.a, w.security, quantity: "20", price: "55", date: ~D[2026-03-05])

      report =
        build_conn()
        |> api_conn()
        |> get("/api/v1/realized_gains")
        |> json_response(200)
        |> Map.fetch!("data")

      assert_dec(report["summary"]["realized_total"], "200")
      assert_dec(report["summary"]["hit_rate"], "1")
      assert report["unmatched_sells"]["count"] == 0
    end

    test "the sell preview covers the shares held and prices them at their cost" do
      w = world()

      preview =
        Ledger.sell_consumption_preview(w.security.id, Decimal.new("20"),
          price: Decimal.new("55")
        )

      assert_dec(preview.shortfall, "0")
      assert_dec(preview.total_gross_gain, "100")
    end
  end
end
