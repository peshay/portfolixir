defmodule Portfolixir.Ledger.HoldingsSplitBasisTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits

  defp insert_quote!(security, date, close, source) do
    {:ok, _} =
      %SecurityQuote{}
      |> SecurityQuote.changeset(%{
        security_id: security.id,
        date: date,
        close: Decimal.new(close),
        source: source
      })
      |> Repo.insert()
  end

  defp book_split!(security, date, {p, q}) do
    {:ok, txs} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: date,
        ratio_numerator: p,
        ratio_denominator: q
      })

    txs
  end

  # User story (ADR-0028 §2 close-reading call sites, issue #590):
  # As a user of the holdings and trades views,
  # I want their latest-price comparisons served in the current display
  # basis,
  # so that a stale raw close from before the effective date never inflates
  # the market value or the unrealised P&L of a post-split position.
  test "holdings and FIFO open lots compare against the basis-adjusted latest close" do
    world = base_world(name: "HB World", cash_name: "HB Cash", depot_name: "HB Depot")
    security = create_security!(name: "HB Co", ticker: "HBB")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    book_split!(security, ~D[2026-02-01], {10, 1})
    # Stale raw close from before the effective date: 110 as traded.
    insert_quote!(security, ~D[2026-01-31], "110", "manual")

    assert [holding] = Ledger.holdings_for_portfolio(world.portfolio.id)
    assert Decimal.equal?(holding.quantity, Decimal.new("100"))
    assert Decimal.equal?(holding.latest_price, Decimal.new("11"))
    assert Decimal.equal?(holding.market_value, Decimal.new("1100"))
    assert Decimal.equal?(holding.cost_basis, Decimal.new("1000"))
    assert Decimal.equal?(holding.unrealized_pnl_abs, Decimal.new("100"))

    assert [by_security] = Ledger.holdings_for_security(security.id)
    assert Decimal.equal?(by_security.latest_price, Decimal.new("11"))
    assert Decimal.equal?(by_security.unrealized_pnl_abs, Decimal.new("100"))

    trades = Ledger.list_trades_for_security(security.id)
    assert [lot] = trades.open_lots
    assert Decimal.equal?(lot.quantity, Decimal.new("100"))
    assert Decimal.equal?(lot.buy_price, Decimal.new("10"))
    assert Decimal.equal?(lot.latest_price, Decimal.new("11"))
    assert Decimal.equal?(lot.unrealized_pnl_abs, Decimal.new("100"))
  end

  # User story (ADR-0028 §2 trade-price-fallback era, issue #590):
  # As a consumer of the latest-own-trade-price fallback,
  # I want each fallback price divided by the cumulative ratio of splits
  # effective after its trade date,
  # so that every valuation surface prices post-split quantities in the
  # current basis even without any stored quote.
  test "latest_trade_prices serves pre-split trade prices in the current basis" do
    world = base_world(name: "TP World", cash_name: "TP Cash", depot_name: "TP Depot")
    security = create_security!(name: "TP Co", ticker: "TPP")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    book_split!(security, ~D[2026-02-01], {10, 1})

    global = Ledger.latest_trade_prices()
    scoped = Ledger.latest_trade_prices(world.portfolio.id)

    assert Decimal.equal?(global[security.id].price, Decimal.new("10"))
    assert Decimal.equal?(scoped[security.id].price, Decimal.new("10"))
    assert global[security.id].date == ~D[2026-01-05]

    # A post-split trade replaces the fallback and stays as booked.
    buy!(world, security, quantity: "1", price: "12", date: ~D[2026-02-10])
    assert Decimal.equal?(Ledger.latest_trade_prices()[security.id].price, Decimal.new("12"))
  end
end
