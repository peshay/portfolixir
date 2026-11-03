defmodule Portfolixir.Ledger.OpenLotsTradePriceTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Valuation

  # All figures are synthetic. #1369 (Sprint 23 R4, plan D-4; ADR-0010's
  # amendment of 2026-06-10): the Trades tab's open lots and the sell
  # preview read the price the holdings and Wealth value a position at,
  # through `Valuation.price_points/2`, and name its source.

  defp sum(figures), do: Enum.reduce(figures, Decimal.new("0"), &Decimal.add(&2, &1))

  # User story (#1369; board ux-design-2026-11-02-sprint23/02-money ①b):
  # As a local portfolio maintainer whose security has no quote,
  # I want its open lots and the sell preview priced at its last own trade
  # price, the source named, as the holdings and Wealth already value it,
  # so that the Trades tab and the drawer never read "—" where the
  # Bestände tab shows a value.
  #
  # Acceptance criteria (Helios, no quote; 15 @ 18.00, then 5 @ 19.20):
  # - The open lots read 19.20 with price_source :trade and its date
  #   2025-03-14; their results are 15 x (19.20 - 18.00) = 18.00 and
  #   5 x 0 = 0.00.
  # - The open lots' market value, 20 x 19.20 = 384.00, is the figure the
  #   holdings read and Wealth state for the position, exactly.
  # - A sell of 5 is priced at 19.20, names :trade and its date, and its
  #   gross gain is 5 x (19.20 - 18.00) = 6.00.
  test "a security without a quote prices its open lots and the sell preview at its last trade price" do
    w = base_world(name: "Helios World", cash_name: "HW Cash", depot_name: "HW Depot")
    helios = create_security!(name: "Helios Example SE", ticker: "HLX")
    buy!(w, helios, quantity: "15", price: "18.00", date: ~D[2025-02-12])
    buy!(w, helios, quantity: "5", price: "19.20", date: ~D[2025-03-14])

    trades = Ledger.list_trades_for_security(helios.id)
    assert [first, second] = trades.open_lots

    for lot <- [first, second] do
      assert Decimal.equal?(lot.latest_price, Decimal.new("19.20"))
      assert lot.price_source == :trade
      assert lot.price_date == ~D[2025-03-14]
    end

    assert Decimal.equal?(first.unrealized_pnl_abs, Decimal.new("18.00"))
    assert Decimal.equal?(second.unrealized_pnl_abs, Decimal.new("0.00"))

    lots_value = sum(Enum.map(trades.open_lots, &Decimal.mult(&1.quantity, &1.latest_price)))
    assert Decimal.equal?(lots_value, Decimal.new("384.00"))

    [holding] = Ledger.holdings_for_security(helios.id)
    assert Decimal.equal?(holding.current_value, lots_value)
    assert holding.price_source == :trade

    [row] = Ledger.holdings_for_portfolio(w.portfolio.id)
    assert Decimal.equal?(row.market_value, lots_value)

    wealth = Map.fetch!(Valuation.holdings_by_security(), helios.id)
    assert Decimal.equal?(wealth.market_value, lots_value)

    preview = Ledger.sell_consumption_preview(helios.id, Decimal.new("5"))
    assert Decimal.equal?(preview.sell_price, Decimal.new("19.20"))
    assert preview.price_source == :trade
    assert preview.price_date == ~D[2025-03-14]
    assert [tranche] = preview.lots
    assert Decimal.equal?(tranche.gross_gain, Decimal.new("6.00"))
    assert Decimal.equal?(preview.total_gross_gain, Decimal.new("6.00"))
  end

  # User story (#1369, the regression pin):
  # As a maintainer whose security is quoted,
  # I want its open lots and the sell preview to read as before,
  # so that the trade-price rule changes nothing where a quote exists.
  #
  # Acceptance criteria:
  # - The open lot reads the quote 130.00, price_source :quote with the
  #   quote's date, result 10 x (130.00 - 100.00) = 300.00.
  # - The sell preview without an entered price reads 130.00 as :quote; an
  #   entered price stays :entered, with no date.
  test "a quoted security reads its quote, as before" do
    w = base_world(name: "Quoted World", cash_name: "QW Cash", depot_name: "QW Depot")
    quoted = create_security!(name: "Quoted Example AG", ticker: "QEX")
    buy!(w, quoted, quantity: "10", price: "100.00", date: ~D[2025-01-05])
    put_quote!(quoted, ~D[2025-06-30], "130.00")

    assert [lot] = Ledger.list_trades_for_security(quoted.id).open_lots
    assert Decimal.equal?(lot.latest_price, Decimal.new("130.00"))
    assert lot.price_source == :quote
    assert lot.price_date == ~D[2025-06-30]
    assert Decimal.equal?(lot.unrealized_pnl_abs, Decimal.new("300.00"))

    preview = Ledger.sell_consumption_preview(quoted.id, Decimal.new("4"))
    assert Decimal.equal?(preview.sell_price, Decimal.new("130.00"))
    assert preview.price_source == :quote
    assert preview.price_date == ~D[2025-06-30]
    assert Decimal.equal?(preview.total_gross_gain, Decimal.new("120.00"))

    entered =
      Ledger.sell_consumption_preview(quoted.id, Decimal.new("4"), price: Decimal.new("150"))

    assert entered.price_source == :entered
    assert entered.price_date == nil
    assert Decimal.equal?(entered.total_gross_gain, Decimal.new("200.00"))
  end

  # User story (#1369, the plan's carry-forward: the identity at a moving
  # rate):
  # As a maintainer holding an SGD security without a quote, bought from a
  # EUR account while the rate moved,
  # I want its open lots priced at the rate the holdings read and Wealth
  # convert its trade price at,
  # so that the Trades tab and Wealth state the same figure in EUR.
  #
  # Acceptance criteria (EUR-hub rates EUR->SGD 1.25 on 2025-02-12, 1.60 on
  # 2025-03-14, 1.25 on 2025-06-30, the latest):
  # - The last trade's price, 12.00 EUR, is 15.00 SGD at the latest rate:
  #   the price the holdings read states, and the open lots' price.
  # - The lots' results: 15 x (15.00 - 18.00) = -45.00 and
  #   5 x (15.00 - 19.20) = -21.00 SGD.
  # - In EUR, each lot's base_cost + total_return_base_abs is its value at
  #   the latest rate; together 300.00 SGD x 0.80 = 240.00 EUR, Wealth's
  #   market value for the position, exactly.
  test "an SGD security without a quote reads its trade price at the rate the holdings read uses" do
    w = base_world(name: "Arbolia World", cash_name: "AW Cash", depot_name: "AW Depot")
    arbolia = create_security!(name: "Arbolia Example Inc", ticker: "ARX", currency: "SGD")

    {:ok, _rates} =
      Fx.upsert_many(
        for {date, rate} <- [
              {~D[2025-02-12], "1.25"},
              {~D[2025-03-14], "1.60"},
              {~D[2025-06-30], "1.25"}
            ] do
          %{base_currency: "EUR", quote_currency: "SGD", date: date, rate: rate, source: "manual"}
        end
      )

    book_sgd_buy!(w, arbolia, ~D[2025-02-12], "15", "14.40", "270.00", "216.00", "0.80")
    book_sgd_buy!(w, arbolia, ~D[2025-03-14], "5", "12.00", "96.00", "60.00", "0.625")

    [holding] = Ledger.holdings_for_security(arbolia.id)
    assert Decimal.equal?(holding.latest_price, Decimal.new("15.00"))

    trades = Ledger.list_trades_for_security(arbolia.id)
    assert [first, second] = trades.open_lots

    for lot <- [first, second] do
      assert Decimal.equal?(lot.latest_price, holding.latest_price)
      assert lot.price_source == :trade
      assert lot.price_date == ~D[2025-03-14]
    end

    assert Decimal.equal?(first.unrealized_pnl_abs, Decimal.new("-45.00"))
    assert Decimal.equal?(second.unrealized_pnl_abs, Decimal.new("-21.00"))

    lots_eur =
      sum(Enum.map(trades.open_lots, &Decimal.add(&1.base_cost, &1.total_return_base_abs)))

    assert Decimal.equal?(lots_eur, Decimal.new("240.00"))

    wealth = Map.fetch!(Valuation.holdings_by_security(), arbolia.id)
    assert Decimal.equal?(wealth.market_value, lots_eur)
  end

  # Acceptance criteria (the sprint PR's closing act, coverage of #1369):
  # - An NZD security without a quote, bought in EUR (10 at 80.00, its cash
  #   800.00, no legs) with no EUR/NZD rate stored: its trade price cannot
  #   be stated in NZD, so the open lot and the sell preview read no price
  #   and name no source or date, and the preview's gross gain is nil.
  test "a trade price that cannot be stated in the security's currency prices nothing" do
    w = base_world(name: "Kauri World", cash_name: "KW Cash", depot_name: "KW Depot")
    kauri = create_security!(name: "Kauri Example Ltd", ticker: "KRX", currency: "NZD")

    {:ok, _buy} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: kauri.id,
        type: "buy",
        date: ~D[2025-02-12],
        quantity: "10",
        price: "80.00",
        currency_code: "EUR",
        gross_amount: "800.00"
      })

    assert [lot] = Ledger.list_trades_for_security(kauri.id).open_lots
    assert {lot.latest_price, lot.price_source, lot.price_date} == {nil, nil, nil}

    preview = Ledger.sell_consumption_preview(kauri.id, Decimal.new("4"))
    assert {preview.sell_price, preview.price_source, preview.price_date} == {nil, nil, nil}
    assert preview.total_gross_gain == nil
  end

  # An SGD security bought from the EUR account: the price recorded in EUR,
  # the security-currency and the settlement legs stated (ADR-0015).
  defp book_sgd_buy!(w, security, date, quantity, price_eur, sgd, eur, rate) do
    {:ok, _buy} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: security.id,
        type: "buy",
        date: date,
        quantity: quantity,
        price: price_eur,
        currency_code: "EUR",
        security_amount: sgd,
        settlement_amount: eur,
        settlement_fx_rate: rate
      })
  end
end
