defmodule Portfolixir.Ledger.ZeroCostBasisTest do
  # #1142 (Sprint 20 β B3, plan D-6; board ux-design-2026-10-07/02-money-findings,
  # before/after): a closed trade or a held position whose cost basis is zero
  # has no percentage return. A share that cost nothing rose by an undefined
  # percentage, not by none, and "0.0 %" reads as a flat trade. Risk-tier
  # money math: every figure is an exact Decimal.
  #
  # The data is invented, the board's:
  # - "Larkspur Rail AG": 12 bonus shares booked as a buy at 0.00 on
  #   2025-03-03, 8 of them sold on 2026-08-13 at 41.25 (+330.00 EUR), 25
  #   bought at 38.50 on 2025-11-11; latest close 41.80;
  # - "Fennwick Labs AG": 15 shares delivered in at no price (a spin-off),
  #   latest close 22.40, worth 336.00.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.PnlDecomposition
  alias Portfolixir.Ledger.TradeMatcher
  alias Portfolixir.Ledger.TradeReturn
  alias Portfolixir.Portfolios.RealizedGains

  defp d(value), do: Decimal.new(value)

  defp matcher_row(type, date, qty, price, opts \\ []) do
    %{
      type: type,
      date: date,
      quantity: d(qty),
      price: d(price),
      fees: d(Keyword.get(opts, :fees, "0")),
      taxes: d(Keyword.get(opts, :taxes, "0")),
      currency_code: "EUR"
    }
  end

  defp larkspur! do
    world = base_world(name: "Bonus World", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "5000", ~D[2025-01-02])

    larkspur =
      create_security!(name: "Larkspur Rail AG", ticker: "LKR", isin: "DE000000001L")

    buy!(world, larkspur, quantity: "12", price: "0", date: ~D[2025-03-03])
    buy!(world, larkspur, quantity: "25", price: "38.50", date: ~D[2025-11-11])
    sell!(world, larkspur, quantity: "8", price: "41.25", date: ~D[2026-08-13])
    put_quote!(larkspur, ~D[2026-10-06], "41.80")

    %{world: world, larkspur: larkspur}
  end

  defp fennwick!(world) do
    fennwick =
      create_security!(name: "Fennwick Labs AG", ticker: "FWL", isin: "DE000000001F")

    {:ok, _delivery} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: fennwick.id,
        type: "inbound_delivery",
        date: ~D[2026-02-02],
        quantity: "15",
        currency_code: "EUR"
      })

    put_quote!(fennwick, ~D[2026-10-06], "22.40")
    fennwick
  end

  # User story (#1142, the realized side):
  # As a local portfolio maintainer who sold bonus shares booked at no cost,
  # I want the closed trade to carry no percentage return,
  # so that its +330.00 is not read as a flat trade.
  #
  # Acceptance criteria (exact Decimal expectations):
  # - A closed trade whose basis is 0 (a buy at 0.00, no fees or taxes) keeps
  #   basis 0, proceeds 330.00 and realized_pnl_abs 330.00, and its
  #   realized_pnl_pct is nil (before: 0).
  # - A buy at 0.00 with a fee has a basis, the fee, and a percentage:
  #   realized 49.00 on a basis of 1.00 is 49.
  test "a closed trade whose cost basis is zero has no percentage return" do
    %{closed_trades: [trade]} =
      TradeMatcher.match([
        matcher_row("buy", ~D[2025-03-03], "12", "0"),
        matcher_row("sell", ~D[2026-08-13], "8", "41.25")
      ])

    assert Decimal.equal?(trade.basis, d("0"))
    assert Decimal.equal?(trade.proceeds, d("330.00"))
    assert Decimal.equal?(trade.realized_pnl_abs, d("330.00"))
    assert trade.realized_pnl_pct == nil

    %{closed_trades: [with_fee]} =
      TradeMatcher.match([
        matcher_row("buy", ~D[2025-03-03], "10", "0", fees: "1.00"),
        matcher_row("sell", ~D[2025-06-03], "10", "5")
      ])

    assert Decimal.equal?(with_fee.basis, d("1.00"))
    assert Decimal.equal?(with_fee.realized_pnl_abs, d("49.00"))
    assert Decimal.equal?(with_fee.realized_pnl_pct, d("49"))
  end

  # User story (#1142; board 02: the p. a. cell takes the zero-basis reason,
  # which comes before the 365-day rule and the solver's):
  # As a local portfolio maintainer,
  # I want a trade with no cost to name that as the reason it has no annual
  # return,
  # so that its dash does not read as a total loss no rate solves, nor as a
  # trade held too short.
  #
  # Acceptance criteria:
  # - Held 528 days: annualized_return nil, reason :no_cost_basis (before:
  #   :no_sign_change, the solver's).
  # - Held 92 days: nil with :no_cost_basis (before:
  #   :holding_period_under_365_days).
  test "a closed trade with no cost basis is not annualized, for that reason first" do
    long =
      TradeMatcher.match([
        matcher_row("buy", ~D[2025-03-03], "12", "0"),
        matcher_row("sell", ~D[2026-08-13], "8", "41.25")
      ]).closed_trades
      |> hd()

    assert TradeReturn.annualized(long) ==
             %{annualized_return: nil, annualized_return_reason: :no_cost_basis}

    short =
      TradeMatcher.match([
        matcher_row("buy", ~D[2025-03-03], "12", "0"),
        matcher_row("sell", ~D[2025-06-03], "8", "41.25")
      ]).closed_trades
      |> hd()

    assert TradeReturn.annualized(short) ==
             %{annualized_return: nil, annualized_return_reason: :no_cost_basis}

    assert TradeReturn.basis() =~ "no_cost_basis"
  end

  # User story (#1142, the security's trades read and the realized-gains
  # report):
  # As the operator and the agent reading the closed trades,
  # I want both reads to serve the trade's missing percentage and its reason,
  # and the open lot of the remaining free shares to carry none either,
  # so that every surface over the matcher says the same.
  #
  # Acceptance criteria:
  # - Ledger.list_trades_for_security/1: the closed trade's realized_pnl_pct
  #   nil with annualized_return_reason :no_cost_basis; the open lot of the
  #   4 remaining bonus shares (buy_price_native 0.00, latest 41.80) has
  #   unrealized_pnl_abs 167.20 and unrealized_pnl_pct nil (before: 0); the
  #   lot bought at 38.50 keeps its percentage, 82.50 / 962.50.
  # - RealizedGains.report/0 and newest_trades/1 carry the same nil and
  #   reason.
  test "the trades read and the realized-gains report serve the missing percentage" do
    %{larkspur: larkspur} = larkspur!()

    trades = Ledger.list_trades_for_security(larkspur.id)

    assert [closed] = trades.closed_trades
    assert Decimal.equal?(closed.realized_pnl_abs, d("330.00"))
    assert closed.realized_pnl_pct == nil
    assert closed.annualized_return == nil
    assert closed.annualized_return_reason == :no_cost_basis

    assert [free, bought] = trades.open_lots
    assert Decimal.equal?(free.quantity, d("4"))
    assert Decimal.equal?(free.buy_price_native, d("0"))
    assert Decimal.equal?(free.unrealized_pnl_abs, d("167.20"))
    assert free.unrealized_pnl_pct == nil

    assert Decimal.equal?(bought.unrealized_pnl_abs, d("82.50"))
    assert Decimal.equal?(bought.unrealized_pnl_pct, Decimal.div(d("82.50"), d("962.50")))

    report = RealizedGains.report(base_currency: "EUR")
    assert [row] = report.trades
    assert Decimal.equal?(row.realized_base, d("330.00"))
    assert row.realized_pnl_pct == nil
    assert row.annualized_return_reason == :no_cost_basis

    assert %{trades: [newest]} = RealizedGains.newest_trades(5, base_currency: "EUR")
    assert newest.realized_pnl_pct == nil
    assert newest.annualized_return_reason == :no_cost_basis
  end

  # User story (#1142, the unrealized side, the issue's own example):
  # As a local portfolio maintainer holding shares delivered in at no cost,
  # I want the position to carry no percentage return,
  # so that a holding worth 336.00 on no cost is not read as flat.
  #
  # Acceptance criteria:
  # - Ledger.holdings_for_portfolio/1 (Wealth's positions and the holdings
  #   read) and Ledger.holdings_for_security/1 (the security's Holdings tab):
  #   Fennwick's cost_basis 0, market value 336.00, unrealized_pnl_abs
  #   336.00, unrealized_pnl_pct nil (before: 0).
  # - Larkspur's 4 remaining bonus shares beside 25 at 38.50 are one
  #   position with a cost basis, and it keeps its percentage.
  test "a held position whose cost basis is zero has no percentage return" do
    %{world: world, larkspur: larkspur} = larkspur!()
    fennwick = fennwick!(world)

    holdings = Ledger.holdings_for_portfolio(world.portfolio.id)
    row = Enum.find(holdings, &(&1.security_id == fennwick.id))

    assert Decimal.equal?(row.cost_basis, d("0"))
    assert Decimal.equal?(row.market_value, d("336.00"))
    assert Decimal.equal?(row.unrealized_pnl_abs, d("336.00"))
    assert row.unrealized_pnl_pct == nil

    # The moving-average fold removed the 8 sold at the running average, so
    # the 29 left carry a cost of their own and a percentage on it.
    priced = Enum.find(holdings, &(&1.security_id == larkspur.id))
    assert Decimal.compare(priced.cost_basis, d("0")) == :gt

    assert Decimal.equal?(
             priced.unrealized_pnl_pct,
             Decimal.div(priced.unrealized_pnl_abs, priced.cost_basis)
           )

    assert [held] = Ledger.holdings_for_security(fennwick.id)
    assert Decimal.equal?(held.cost_basis, d("0"))
    assert Decimal.equal?(held.current_value, d("336.00"))
    assert Decimal.equal?(held.unrealized_pnl_abs, d("336.00"))
    assert held.unrealized_pnl_pct == nil
  end

  # User story (#1142's last sibling, D-14; the plan's D-6 answers it):
  # As the operator and the agent reading a position's base-currency
  # decomposition,
  # I want its three percentages to carry no return on no cost either,
  # so that price_return_pct, currency_return_pct and total_return_base_pct
  # do not read "0" beside the null unrealized_pnl_pct.
  #
  # Acceptance criteria (exact Decimal expectations):
  # - Fennwick's holding (15 delivered in at no price, 336.00, base_cost 0):
  #   price_return_abs 336.00, currency_return_abs 0, total_return_base_abs
  #   336.00, decomposed true, and price_return_pct, currency_return_pct and
  #   total_return_base_pct nil (before: 0), on holdings_for_portfolio/1.
  # - Larkspur's open lot of the 4 remaining bonus shares (base_cost 0):
  #   price_return_abs 167.20 and total_return_base_abs 167.20, the three
  #   percentages nil (before: 0); the lot bought at 38.50 keeps them,
  #   82.50 / 962.50 on price and total, and 0 on currency.
  # - PnlDecomposition.decompose/4 on a zero base cost: the amounts, and nil
  #   percentages.
  test "a decomposition on a zero base cost has no percentage returns" do
    %{world: world, larkspur: larkspur} = larkspur!()
    fennwick = fennwick!(world)

    row =
      world.portfolio.id
      |> Ledger.holdings_for_portfolio()
      |> Enum.find(&(&1.security_id == fennwick.id))

    assert Decimal.equal?(row.base_cost, d("0"))
    assert row.decomposed == true
    assert Decimal.equal?(row.price_return_abs, d("336.00"))
    assert Decimal.equal?(row.currency_return_abs, d("0"))
    assert Decimal.equal?(row.total_return_base_abs, d("336.00"))

    assert Map.take(row, [:price_return_pct, :currency_return_pct, :total_return_base_pct]) ==
             %{price_return_pct: nil, currency_return_pct: nil, total_return_base_pct: nil}

    assert [free, bought] = Ledger.list_trades_for_security(larkspur.id).open_lots
    assert Decimal.equal?(free.base_cost, d("0"))
    assert Decimal.equal?(free.price_return_abs, d("167.20"))
    assert Decimal.equal?(free.total_return_base_abs, d("167.20"))

    assert Map.take(free, [:price_return_pct, :currency_return_pct, :total_return_base_pct]) ==
             %{price_return_pct: nil, currency_return_pct: nil, total_return_base_pct: nil}

    on_cost = Decimal.div(d("82.50"), d("962.50"))
    assert Decimal.equal?(bought.price_return_pct, on_cost)
    assert Decimal.equal?(bought.currency_return_pct, d("0"))
    assert Decimal.equal?(bought.total_return_base_pct, on_cost)

    decomposition = PnlDecomposition.decompose(d("336.00"), d("0"), d("0"), d("1"))
    assert Decimal.equal?(decomposition.total_return_base_abs, d("336.00"))
    assert decomposition.price_return_pct == nil
    assert decomposition.currency_return_pct == nil
    assert decomposition.total_return_base_pct == nil
  end
end
