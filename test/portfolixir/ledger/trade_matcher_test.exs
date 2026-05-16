defmodule Portfolixir.Ledger.TradeMatcherTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Ledger.TradeMatcher

  defp buy(date, qty, price, opts \\ []) do
    %{
      type: "buy",
      date: date,
      quantity: Decimal.new(qty),
      price: Decimal.new(price),
      fees: Decimal.new(Keyword.get(opts, :fees, "0")),
      taxes: Decimal.new(Keyword.get(opts, :taxes, "0")),
      currency_code: Keyword.get(opts, :currency_code, "USD")
    }
  end

  defp sell(date, qty, price, opts \\ []) do
    %{
      type: "sell",
      date: date,
      quantity: Decimal.new(qty),
      price: Decimal.new(price),
      fees: Decimal.new(Keyword.get(opts, :fees, "0")),
      taxes: Decimal.new(Keyword.get(opts, :taxes, "0")),
      currency_code: Keyword.get(opts, :currency_code, "USD")
    }
  end

  describe "match/1" do
    test "returns no trades and no lots for an empty list" do
      assert TradeMatcher.match([]) == %{open_lots: [], closed_trades: [], orphan_sells: []}
    end

    test "a single buy produces one open lot and no closed trades" do
      result = TradeMatcher.match([buy(~D[2026-01-10], "10", "100.00")])

      assert [lot] = result.open_lots
      assert Decimal.equal?(lot.quantity, Decimal.new("10"))
      assert Decimal.equal?(lot.buy_price, Decimal.new("100.00"))
      assert lot.open_date == ~D[2026-01-10]
      assert result.closed_trades == []
      assert result.orphan_sells == []
    end

    test "a buy then a fully-matching sell closes the lot and records the trade" do
      transactions = [
        buy(~D[2026-01-10], "10", "100.00", fees: "5", taxes: "0"),
        sell(~D[2026-04-10], "10", "150.00", fees: "5", taxes: "0")
      ]

      result = TradeMatcher.match(transactions)

      assert result.open_lots == []
      assert [trade] = result.closed_trades

      assert Decimal.equal?(trade.quantity, Decimal.new("10"))
      assert Decimal.equal?(trade.avg_buy_price, Decimal.new("100.00"))
      assert Decimal.equal?(trade.avg_sell_price, Decimal.new("150.00"))
      # proceeds = 10 * 150 - 5 = 1495; basis = 10 * 100 + 5 = 1005
      assert Decimal.equal?(trade.realized_pnl_abs, Decimal.new("490"))
      assert trade.open_date == ~D[2026-01-10]
      assert trade.close_date == ~D[2026-04-10]
      assert trade.holding_period_days == 90
    end

    test "a buy followed by a partial sell leaves a residual open lot" do
      transactions = [
        buy(~D[2026-01-10], "10", "100.00"),
        sell(~D[2026-02-10], "4", "120.00")
      ]

      result = TradeMatcher.match(transactions)

      assert [lot] = result.open_lots
      assert Decimal.equal?(lot.quantity, Decimal.new("6"))
      assert Decimal.equal?(lot.buy_price, Decimal.new("100.00"))

      assert [trade] = result.closed_trades
      assert Decimal.equal?(trade.quantity, Decimal.new("4"))
      assert Decimal.equal?(trade.avg_buy_price, Decimal.new("100.00"))
      assert Decimal.equal?(trade.avg_sell_price, Decimal.new("120.00"))
      # proceeds = 4 * 120 = 480; basis = 4 * 100 = 400 → +80
      assert Decimal.equal?(trade.realized_pnl_abs, Decimal.new("80"))
    end

    test "a sale that spans multiple buy lots produces one trade with weighted avg basis" do
      # 5 @ 100 and 5 @ 200, then sell 7 at 250
      transactions = [
        buy(~D[2026-01-01], "5", "100.00"),
        buy(~D[2026-02-01], "5", "200.00"),
        sell(~D[2026-03-01], "7", "250.00")
      ]

      result = TradeMatcher.match(transactions)

      # 3 units remain from the second lot
      assert [lot] = result.open_lots
      assert Decimal.equal?(lot.quantity, Decimal.new("3"))
      assert Decimal.equal?(lot.buy_price, Decimal.new("200.00"))

      assert [trade] = result.closed_trades
      assert Decimal.equal?(trade.quantity, Decimal.new("7"))
      # 5 @ 100 + 2 @ 200 → 900 / 7 ≈ 128.571428…
      assert Decimal.compare(trade.avg_buy_price, Decimal.new("128.57")) == :gt
      assert Decimal.compare(trade.avg_buy_price, Decimal.new("128.58")) == :lt
      # proceeds = 7 * 250 = 1750; basis = 5*100 + 2*200 = 900 → +850
      assert Decimal.equal?(trade.realized_pnl_abs, Decimal.new("850"))
    end

    test "orphan sells (no preceding buys) are surfaced separately and skipped" do
      transactions = [
        sell(~D[2026-01-01], "5", "100.00"),
        buy(~D[2026-02-01], "3", "120.00")
      ]

      result = TradeMatcher.match(transactions)

      assert [orphan] = result.orphan_sells
      assert Decimal.equal?(orphan.quantity, Decimal.new("5"))

      assert [lot] = result.open_lots
      assert Decimal.equal?(lot.quantity, Decimal.new("3"))
      assert result.closed_trades == []
    end

    test "a sale larger than available buys produces a closed trade plus an orphan remainder" do
      transactions = [
        buy(~D[2026-01-01], "2", "100.00"),
        sell(~D[2026-02-01], "5", "120.00")
      ]

      result = TradeMatcher.match(transactions)

      assert result.open_lots == []
      assert [trade] = result.closed_trades
      assert Decimal.equal?(trade.quantity, Decimal.new("2"))

      assert [orphan] = result.orphan_sells
      assert Decimal.equal?(orphan.quantity, Decimal.new("3"))
    end

    test "fees and taxes are allocated proportionally on partial closes" do
      transactions = [
        buy(~D[2026-01-01], "10", "100.00", fees: "10", taxes: "0"),
        sell(~D[2026-02-01], "4", "120.00", fees: "2", taxes: "0")
      ]

      result = TradeMatcher.match(transactions)

      assert [trade] = result.closed_trades
      # Buy fees allocated: 10 * (4/10) = 4
      # basis = 4 * 100 + 4 = 404; proceeds = 4 * 120 - 2 = 478 → +74
      assert Decimal.equal?(trade.realized_pnl_abs, Decimal.new("74"))
    end
  end
end
