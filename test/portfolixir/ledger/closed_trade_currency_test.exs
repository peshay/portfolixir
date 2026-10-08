defmodule Portfolixir.Ledger.ClosedTradeCurrencyTest do
  # The ADR-0015 amendment of 2026-10-07 (#1108, risk-tier money, ADR-0036):
  # a booking's fees and taxes are in its cash account's currency, and a
  # figure the FIFO matcher keeps in the trade's price currency — a lot's
  # basis, a closed trade's proceeds and its realized result — converts them
  # at the trade's own stored `settlement_fx_rate` (fee ÷ rate, the rate in
  # account units per one security unit). Identities 1, 3 and 4.
  #
  # Synthetic figures only. Not async: the reads below are instance-wide
  # (the realized-gains report reads every security), and the rates are
  # stored rows another module could hold on the same dates.
  use Portfolixir.DataCase

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, buy!: 3, create_security!: 1, cross_trade!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.RealizedGains

  defp usd_rate!(dates) do
    {:ok, _} =
      dates
      |> Enum.map(fn date ->
        %{base_currency: "EUR", quote_currency: "USD", date: date, rate: "1.25", source: "manual"}
      end)
      |> Fx.upsert_many()
  end

  # Every Decimal as its exact string, scale included: "byte-identical" means
  # the same digits, not an equal number.
  defp exact(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp exact(list) when is_list(list), do: Enum.map(list, &exact/1)
  defp exact(%Date{} = date), do: date

  defp exact(%{} = map) when not is_struct(map),
    do: Map.new(map, fn {key, value} -> {key, exact(value)} end)

  defp exact(other), do: other

  @trade_keys [
    :open_date,
    :close_date,
    :quantity,
    :avg_buy_price,
    :avg_sell_price,
    :buy_fees,
    :buy_taxes,
    :sell_fees,
    :sell_taxes,
    :basis,
    :proceeds,
    :realized_pnl_abs,
    :realized_pnl_pct,
    :holding_period_days,
    :currency_code,
    :lots,
    :annualized_return,
    :annualized_return_reason
  ]

  @lot_keys [
    :open_date,
    :quantity,
    :original_quantity,
    :buy_price,
    :buy_price_native,
    :buy_fees,
    :buy_taxes,
    :currency_code,
    :base_cost,
    :base_currency
  ]

  defp closed(security), do: Ledger.list_trades_for_security(security.id).closed_trades
  defp open(security), do: Ledger.list_trades_for_security(security.id).open_lots

  defp realized_row(security) do
    RealizedGains.report(base_currency: "EUR").trades
    |> Enum.find(&(&1.security_id == security.id))
  end

  # A cross-currency trade as a Portfolio Performance export books it
  # (ADR-0033, #569): in the ACCOUNT's currency, its price the account-
  # currency amount per share, with the ADR-0015 legs the import derives
  # beside it. Fees and taxes are in the account's currency, which is the
  # booking's currency here, so nothing about them is converted.
  defp account_currency_trade!(world, security, opts) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: Keyword.fetch!(opts, :type),
        date: Keyword.fetch!(opts, :date),
        quantity: Keyword.fetch!(opts, :quantity),
        price: Keyword.fetch!(opts, :price),
        fees: Keyword.get(opts, :fees, "0"),
        taxes: Keyword.get(opts, :taxes, "0"),
        currency_code: world.cash.currency_code,
        security_amount: Keyword.fetch!(opts, :security_amount),
        settlement_amount: Keyword.fetch!(opts, :settled),
        settlement_fx_rate: Keyword.fetch!(opts, :rate),
        gross_amount: Keyword.fetch!(opts, :gross)
      })

    tx
  end

  # -- identity 4: what does not move ------------------------------------------

  # User story (#1108, the ADR-0015 amendment's identity 4):
  # As a maintainer whose trades settle in the security's own currency,
  # I want their closed trades, open lots and realized results to read
  # exactly what they read before the cross-currency fix,
  # so that fixing one case moves nothing else.
  #
  # Acceptance criteria:
  # - A EUR security through a EUR account and a USD security through a USD
  #   account read the same closed-trade and open-lot figures, digit for
  #   digit, as before the amendment, and the same realized result in EUR.
  test "a same-currency trade reads byte-identical figures (identity 4)" do
    world = base_world(name: "Same Euro", cash_name: "Euro Cash", depot_name: "Euro Depot")

    usd_world =
      Map.merge(
        world,
        add_depot(world.portfolio,
          cash_currency: "USD",
          cash_name: "Dollar Cash",
          depot_name: "Dollar Depot"
        )
      )

    usd_rate!([~D[2025-02-03], ~D[2025-03-03]])

    mill = create_security!(name: "Euro Mill", ticker: "EUM")
    forge = create_security!(name: "Dollar Forge", ticker: "DLF", currency: "USD")

    buy!(world, mill,
      quantity: "10",
      price: "100",
      fees: "5",
      taxes: "1",
      date: ~D[2025-02-03]
    )

    sell!(world, mill, quantity: "6", price: "120", fees: "3", date: ~D[2025-03-03])

    buy!(usd_world, forge,
      quantity: "10",
      price: "100",
      fees: "5",
      taxes: "1",
      date: ~D[2025-02-03],
      currency: "USD"
    )

    sell!(usd_world, forge,
      quantity: "6",
      price: "120",
      fees: "3",
      date: ~D[2025-03-03],
      currency: "USD"
    )

    for security <- [mill, forge] do
      assert [trade] = closed(security)
      assert [lot] = open(security)

      currency = security.currency_code

      assert trade |> Map.take(@trade_keys) |> exact() == %{
               open_date: ~D[2025-02-03],
               close_date: ~D[2025-03-03],
               quantity: "6.000000000000",
               avg_buy_price: "100.000000",
               avg_sell_price: "120.000000",
               buy_fees: "3.0000000",
               buy_taxes: "0.6000000",
               sell_fees: "3.000000",
               sell_taxes: "0.000000",
               basis: "603.600000000000000000",
               proceeds: "717.000000000000000000",
               realized_pnl_abs: "113.400000000000000000",
               realized_pnl_pct: "0.1878727634194831013916500994035785",
               holding_period_days: 28,
               currency_code: currency,
               lots: [
                 %{
                   open_date: ~D[2025-02-03],
                   quantity: "6.000000000000",
                   cost: "603.600000000000000000"
                 }
               ],
               annualized_return: nil,
               annualized_return_reason: :holding_period_under_365_days
             }

      assert lot |> Map.take(@lot_keys) |> exact() == %{
               open_date: ~D[2025-02-03],
               quantity: "4.000000000000",
               original_quantity: "10.000000000000",
               buy_price: "100.000000",
               buy_price_native: "100.000000",
               buy_fees: "5.000000",
               buy_taxes: "1.000000",
               currency_code: currency,
               base_cost: "400.000000000000000000",
               base_currency: currency
             }
    end

    assert exact(realized_row(mill).realized_base) == "113.400000000000000000"
    assert exact(realized_row(forge).realized_base) == "90.7200000000000000000"
  end

  # User story (#1108, the ADR-0015 amendment's identity 4):
  # As a maintainer whose cross-currency trades came from a Portfolio
  # Performance import, booked in my account's currency,
  # I want their closed trades to read exactly what they read before,
  # so that the fix converts only fees that are in another currency than
  # the price they are added to.
  #
  # Acceptance criteria:
  # - A trade priced in the account's currency, with the ADR-0015 legs and a
  #   stored rate beside it, reads the same closed-trade and open-lot
  #   figures, digit for digit, and the same realized result in EUR: its
  #   fees are in its price currency already, so nothing is converted.
  test "a cross-currency trade booked in the account's currency reads byte-identical figures (identity 4)" do
    world = base_world(name: "Imported", cash_name: "Import Cash", depot_name: "Import Depot")
    usd_rate!([~D[2025-02-03], ~D[2025-03-03]])
    fund = create_security!(name: "Imported Fund", ticker: "IMF", currency: "USD")

    # 10 at 80 EUR (1,000 USD at 0.8), fees 5 and taxes 1 EUR: 806 paid.
    account_currency_trade!(world, fund,
      type: "buy",
      date: ~D[2025-02-03],
      quantity: "10",
      price: "80",
      fees: "5",
      taxes: "1",
      security_amount: "1000",
      settled: "800",
      rate: "0.8",
      gross: "806"
    )

    # 6 at 96 EUR (720 USD at 0.8), fees 3 EUR: 573 received.
    account_currency_trade!(world, fund,
      type: "sell",
      date: ~D[2025-03-03],
      quantity: "6",
      price: "96",
      fees: "3",
      security_amount: "720",
      settled: "576",
      rate: "0.8",
      gross: "573"
    )

    assert [trade] = closed(fund)
    assert [lot] = open(fund)

    assert trade |> Map.take(@trade_keys) |> exact() == %{
             open_date: ~D[2025-02-03],
             close_date: ~D[2025-03-03],
             quantity: "6.000000000000",
             avg_buy_price: "80.000000",
             avg_sell_price: "96.000000",
             buy_fees: "3.0000000",
             buy_taxes: "0.6000000",
             sell_fees: "3.000000",
             sell_taxes: "0.000000",
             basis: "483.600000000000000000",
             proceeds: "573.000000000000000000",
             realized_pnl_abs: "89.400000000000000000",
             realized_pnl_pct: "0.1848635235732009925558312655086849",
             holding_period_days: 28,
             currency_code: "EUR",
             lots: [
               %{
                 open_date: ~D[2025-02-03],
                 quantity: "6.000000000000",
                 cost: "483.600000000000000000"
               }
             ],
             annualized_return: nil,
             annualized_return_reason: :holding_period_under_365_days
           }

    assert lot |> Map.take(@lot_keys) |> exact() == %{
             open_date: ~D[2025-02-03],
             quantity: "4.000000000000",
             original_quantity: "10.000000000000",
             buy_price: "80.000000",
             buy_price_native: "100",
             buy_fees: "5.000000",
             buy_taxes: "1.000000",
             currency_code: "EUR",
             base_cost: "320.00000000000",
             base_currency: "EUR"
           }

    assert exact(realized_row(fund).realized_base) == "89.400000000000000000"
  end

  # User story (#1108, the ADR-0015 amendment's identity 4):
  # As a maintainer with a booking priced in neither its security's currency
  # nor its account's,
  # I want the fix to leave it alone,
  # so that a rate stored between the account's and the security's currency
  # never converts fees into a third one.
  #
  # Acceptance criteria:
  # - A CHF security bought through a EUR account, priced in USD, with a
  #   stored settlement rate (EUR per CHF), keeps its fees as recorded: the
  #   open lot's buy_fees read "5.000000" as before. Only a trade priced in
  #   the security's currency converts them.
  test "a booking priced in a third currency keeps its fees as recorded (identity 4)" do
    world = base_world(name: "Third", cash_name: "Third Cash", depot_name: "Third Depot")
    swiss = create_security!(name: "Swiss Third", ticker: "SWT", currency: "CHF")

    {:ok, _buy} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: swiss.id,
        type: "buy",
        date: ~D[2025-04-01],
        quantity: "10",
        price: "100",
        fees: "5",
        currency_code: "USD",
        security_amount: "900",
        settlement_amount: "800",
        settlement_fx_rate: "0.888889",
        gross_amount: "805"
      })

    assert [lot] = open(swiss)
    assert exact(lot.buy_fees) == "5.000000"
    assert exact(lot.buy_taxes) == "0.000000"
  end

  # -- identities 1 and 3: a closed trade in one currency ------------------------

  defp exactly?(%Decimal{} = value, expected), do: Decimal.equal?(value, Decimal.new(expected))

  defp cross_world do
    world = base_world(name: "Cross", cash_name: "Cross Cash", depot_name: "Cross Depot")
    fund = create_security!(name: "Dollar Fund", ticker: "DFD", currency: "USD")

    # 1 EUR = 1.25 USD on every date, the rate stored as EUR per USD (0.8).
    usd_rate!([~D[2025-04-01], ~D[2025-05-02]])

    {world, fund}
  end

  # User story (#1108, the ADR-0015 amendment's identity 1):
  # As a maintainer who buys and sells a USD security through my EUR account,
  # I want the closed trade's basis, proceeds and realized result in dollars,
  # with the fees my broker charged in euros converted at the trade's own rate,
  # so that the realized result in euros is the cash the round trip moved.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - Buy 10 at 100 USD settled 800.00 EUR, fees 5.00 and taxes 1.00 EUR;
  #   sell 10 at 120 USD settled 960.00 EUR, fees 3.00 EUR: basis 1,007.50
  #   USD, proceeds 1,196.25 USD, realized 188.75 USD.
  # - The fees and taxes the trade shows are in dollars: 6.25, 1.25 and 3.75.
  # - The realized result is 151.00 EUR at the sale date's hub rate, equal to
  #   the cash the round trip moved: 957.00 − 806.00.
  # - The realized-gains report and the Overview card's newest trades read it.
  test "a cross-currency closed trade is in its price currency, fees at its own rate (identity 1)" do
    {world, fund} = cross_world()

    buy =
      cross_trade!(world, fund,
        quantity: "10",
        price: "100",
        settled: "800.00",
        fees: "5.00",
        taxes: "1.00",
        gross: "806.00",
        date: ~D[2025-04-01]
      )

    sell =
      cross_trade!(world, fund,
        type: "sell",
        quantity: "10",
        price: "120",
        settled: "960.00",
        fees: "3.00",
        gross: "957.00",
        date: ~D[2025-05-02]
      )

    assert [trade] = closed(fund)
    assert trade.currency_code == "USD"
    assert exactly?(trade.basis, "1007.50")
    assert exactly?(trade.proceeds, "1196.25")
    assert exactly?(trade.realized_pnl_abs, "188.75")
    assert exactly?(trade.buy_fees, "6.25")
    assert exactly?(trade.buy_taxes, "1.25")
    assert exactly?(trade.sell_fees, "3.75")
    assert exactly?(trade.sell_taxes, "0")
    assert [%{cost: lot_cost}] = trade.lots
    assert exactly?(lot_cost, "1007.50")

    cash_moved = Decimal.sub(sell.gross_amount, buy.gross_amount)
    assert exactly?(cash_moved, "151.00")

    row = realized_row(fund)
    assert exactly?(row.realized_base, "151.00")
    assert Decimal.equal?(row.realized_base, cash_moved)

    assert %{trades: [newest]} = RealizedGains.newest_trades(1, base_currency: "EUR")
    assert newest.security_id == fund.id
    assert exactly?(newest.realized_base, "151.00")
    assert exactly?(newest.basis, "1007.50")
  end

  # User story (#1108, the ADR-0015 amendment's identity 3):
  # As a maintainer whose broker's rate is not the hub's,
  # I want a cross-currency trade's fees converted at the rate the broker
  # applied to that trade, not at the hub rate of its day,
  # so that a cost converted once by the broker is not converted a second,
  # different time.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - Buy 10 at 100 USD settled 750.00 EUR (0.75 EUR per USD), fees 6.00 and
  #   taxes 1.50 EUR; sell 10 at 120 USD settled 960.00 EUR, fees 4.00 EUR:
  #   basis 1,010.00 USD, proceeds 1,195.00 USD, realized 185.00 USD.
  # - The realized result is 148.00 EUR at the sale date's hub rate; the hub
  #   rate alternative would read 148.50, the code before the amendment
  #   150.80.
  test "a cross-currency trade's fees convert at the trade's own rate, not the hub's (identity 3)" do
    {world, fund} = cross_world()

    cross_trade!(world, fund,
      quantity: "10",
      price: "100",
      settled: "750.00",
      fees: "6.00",
      taxes: "1.50",
      gross: "757.50",
      date: ~D[2025-04-01]
    )

    cross_trade!(world, fund,
      type: "sell",
      quantity: "10",
      price: "120",
      settled: "960.00",
      fees: "4.00",
      gross: "956.00",
      date: ~D[2025-05-02]
    )

    assert [trade] = closed(fund)
    assert exactly?(trade.basis, "1010.00")
    assert exactly?(trade.proceeds, "1195.00")
    assert exactly?(trade.realized_pnl_abs, "185.00")

    assert exactly?(realized_row(fund).realized_base, "148.00")
  end
end
