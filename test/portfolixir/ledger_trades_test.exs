defmodule Portfolixir.LedgerTradesTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  # User story:
  # As a local portfolio maintainer,
  # I want my buy and sell transactions for a security collapsed into
  # FIFO-matched trades with realised and unrealised P&L,
  # so that I can see the actual performance of round-trips and the
  # current open exposure without doing the maths by hand.

  defp setup_world do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Apple Inc.",
        ticker_symbol: "AAPL",
        isin: "US0378331005",
        currency_code: "USD",
        asset_class: "equity"
      })

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

    %{security: security, portfolio: portfolio, cash: cash, depot: depot}
  end

  defp put_quote!(security, date, close) do
    {:ok, _} =
      Quotes.upsert_many(security.id, [
        %{date: date, close: close, source: "manual"}
      ])
  end

  defp create_tx!(%{security: s, portfolio: p, depot: d, cash: c}, type, date, qty, price) do
    {:ok, tx} =
      Ledger.create_transaction(%{
        portfolio_id: p.id,
        securities_account_id: d.id,
        cash_account_id: c.id,
        security_id: s.id,
        type: type,
        date: date,
        quantity: Decimal.new(qty),
        price: Decimal.new(price),
        fees: Decimal.new("0"),
        taxes: Decimal.new("0"),
        currency_code: "USD"
      })

    tx
  end

  test "an open lot reports unrealised P&L vs. the latest quote close" do
    world = setup_world()
    _buy = create_tx!(world, "buy", ~D[2026-01-10], "10", "100.00")
    put_quote!(world.security, ~D[2026-05-15], "150.00")

    %{open_lots: [lot], closed_trades: [], orphan_sells: []} =
      Ledger.list_trades_for_security(world.security.id)

    assert Decimal.equal?(lot.quantity, Decimal.new("10"))
    # 10 * (150 - 100) = 500
    assert Decimal.equal?(lot.unrealized_pnl_abs, Decimal.new("500"))
    # +50 %
    assert Decimal.equal?(lot.unrealized_pnl_pct, Decimal.new("0.5"))
  end

  test "a closed round-trip surfaces realised P&L in the closed_trades list" do
    world = setup_world()
    _ = create_tx!(world, "buy", ~D[2026-01-10], "10", "100.00")
    _ = create_tx!(world, "sell", ~D[2026-04-10], "10", "150.00")

    %{open_lots: [], closed_trades: [trade]} =
      Ledger.list_trades_for_security(world.security.id)

    assert Decimal.equal?(trade.quantity, Decimal.new("10"))
    assert Decimal.equal?(trade.realized_pnl_abs, Decimal.new("500"))
    assert trade.open_date == ~D[2026-01-10]
    assert trade.close_date == ~D[2026-04-10]
  end

  test "open lots without a latest quote get nil unrealised P&L (not a crash)" do
    world = setup_world()
    _ = create_tx!(world, "buy", ~D[2026-01-10], "10", "100.00")

    %{open_lots: [lot]} = Ledger.list_trades_for_security(world.security.id)

    assert is_nil(lot.unrealized_pnl_abs)
    assert is_nil(lot.unrealized_pnl_pct)
  end
end
