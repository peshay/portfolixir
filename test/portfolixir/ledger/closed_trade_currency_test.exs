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
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.RealizedGains
  alias Portfolixir.Repo

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

  # A trade in the security's currency through an account in that same
  # currency, with a settlement_fx_rate of 0.8 stored beside it.
  defp same_currency_rated_trade!(world, security, opts) do
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
        currency_code: security.currency_code,
        settlement_fx_rate: "0.8"
      })

    assert Decimal.equal?(tx.settlement_fx_rate, Decimal.new("0.8"))
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

    # The USD trades carry a stored settlement_fx_rate the ledger accepts on
    # a same-currency booking (closing act, BML-1): their fees stay as
    # recorded because the account is in the price's currency, not because
    # no rate is stored, so a matcher that converted at any stored rate
    # (5 / 0.8 = 6.25) would move every figure below.
    same_currency_rated_trade!(usd_world, forge,
      type: "buy",
      quantity: "10",
      price: "100",
      fees: "5",
      taxes: "1",
      date: ~D[2025-02-03]
    )

    same_currency_rated_trade!(usd_world, forge,
      type: "sell",
      quantity: "6",
      price: "120",
      fees: "3",
      date: ~D[2025-03-03]
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
  # - Since #1199 (the ADR-0015 amendment of 2026-10-09, identity 5) the
  #   ledger refuses a new booking priced in a third currency, so the row is
  #   written as a database stored it before the check: the case is a
  #   stored row's, and its expectation stands.
  test "a booking priced in a third currency keeps its fees as recorded (identity 4)" do
    world = base_world(name: "Third", cash_name: "Third Cash", depot_name: "Third Depot")
    swiss = create_security!(name: "Swiss Third", ticker: "SWT", currency: "CHF")

    {:ok, _buy} =
      Repo.transaction(fn ->
        {type, _label} = Actor.to_columns(Actor.owner_ui())
        Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])

        Repo.insert!(%Transaction{
          portfolio_id: world.portfolio.id,
          securities_account_id: world.depot.id,
          cash_account_id: world.cash.id,
          security_id: swiss.id,
          type: "buy",
          date: ~D[2025-04-01],
          quantity: Decimal.new("10"),
          price: Decimal.new("100"),
          fees: Decimal.new("5"),
          taxes: Decimal.new("0"),
          currency_code: "USD",
          security_amount: Decimal.new("900"),
          settlement_amount: Decimal.new("800"),
          settlement_fx_rate: Decimal.new("0.888889"),
          gross_amount: Decimal.new("805")
        })
      end)

    assert [lot] = open(swiss)
    assert exact(lot.buy_fees) == "5.000000"
    assert exact(lot.buy_taxes) == "0.000000"
  end

  # User story (#1198, Sprint 21 α3; the ADR-0015 amendment of 2026-10-09,
  # identity 4):
  # As a maintainer whose cross-currency round trip came wholly from a
  # Portfolio Performance import, booked in my account's currency,
  # I want its closed trade to read exactly what it read before a closed
  # trade was put in one currency,
  # so that the conversion runs only where a sell closes a lot booked in
  # another currency, and the import-only round trip's result in euros stays
  # the cash it moved.
  #
  # Acceptance criteria:
  # - Identity 1's imported buy (10 at 80.00 EUR, fees 5.00 and taxes 1.00
  #   EUR, legs 800.00 EUR, 1,000.00 USD, 0.800000) sold through an import
  #   (10 at 96.00 EUR, fees 3.00 EUR, legs 960.00 EUR, 1,200.00 USD,
  #   0.800000) reads basis 806.00, proceeds 957.00 and realized 151.00 EUR,
  #   digit for digit; option (a) would read 1,007.50, 1,196.25 and 188.75
  #   USD.
  test "an import-only cross-currency round trip reads byte-identical figures (identity 4)" do
    world = base_world(name: "Import Only", cash_name: "Import Cash", depot_name: "Import Depot")
    usd_rate!([~D[2025-04-01], ~D[2025-05-02]])
    fund = create_security!(name: "Import Round Fund", ticker: "IRF", currency: "USD")

    account_currency_trade!(world, fund,
      type: "buy",
      date: ~D[2025-04-01],
      quantity: "10",
      price: "80",
      fees: "5",
      taxes: "1",
      security_amount: "1000",
      settled: "800",
      rate: "0.8",
      gross: "806"
    )

    account_currency_trade!(world, fund,
      type: "sell",
      date: ~D[2025-05-02],
      quantity: "10",
      price: "96",
      fees: "3",
      security_amount: "1200",
      settled: "960",
      rate: "0.8",
      gross: "957"
    )

    assert [trade] = closed(fund)

    assert trade |> Map.take(@trade_keys) |> exact() == %{
             open_date: ~D[2025-04-01],
             close_date: ~D[2025-05-02],
             quantity: "10.000000000000",
             avg_buy_price: "80.000000",
             avg_sell_price: "96.000000",
             buy_fees: "5.000000",
             buy_taxes: "1.000000",
             sell_fees: "3.000000",
             sell_taxes: "0.000000",
             basis: "806.000000000000000000",
             proceeds: "957.000000000000000000",
             realized_pnl_abs: "151.000000000000000000",
             realized_pnl_pct: "0.1873449131513647642679900744416873",
             holding_period_days: 31,
             currency_code: "EUR",
             lots: [
               %{
                 open_date: ~D[2025-04-01],
                 quantity: "10.000000000000",
                 cost: "806.000000000000000000"
               }
             ],
             annualized_return: nil,
             annualized_return_reason: :holding_period_under_365_days
           }

    assert exact(realized_row(fund).realized_base) == "151.000000000000000000"
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

  # User story (#1108 closing act, BML-2; ADR-0016 §1):
  # As a maintainer whose broker's rate has six places,
  # I want a converted fee to keep every digit of fee ÷ rate,
  # so that no figure is rounded in the computation, only on the screen.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - Buy 7 at 113.37 USD (793.59 USD) settled 731.22 EUR, the stored rate
  #   0.921408 EUR per USD, fees 4.90 EUR: the open lot's buy_fees read
  #   4.90 ÷ 0.921408 unrounded, to Decimal's 34 significant digits,
  #   "5.317948183649371396818781690629992" -- a quotient that does not
  #   terminate, so a rounding step shows.
  test "a converted fee keeps every digit of a quotient that does not terminate" do
    {world, fund} = cross_world()

    {:ok, _buy} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: fund.id,
        type: "buy",
        date: ~D[2025-04-01],
        quantity: "7",
        price: "113.37",
        fees: "4.90",
        currency_code: "USD",
        security_amount: "793.59",
        settlement_amount: "731.22",
        settlement_fx_rate: "0.921408",
        gross_amount: "736.12"
      })

    assert [lot] = open(fund)
    assert exact(lot.buy_fees) == "5.317948183649371396818781690629992"
    assert Decimal.equal?(lot.buy_fees, Decimal.div(Decimal.new("4.90"), Decimal.new("0.921408")))
    assert exact(lot.buy_taxes) == "0"
  end

  # -- #1198, Sprint 21 α3: a closed trade is in one currency, whatever booked
  # its lots (the ADR-0015 amendment of 2026-10-09, points 2 to 5) -----------

  # Identity 1's imported purchase: 10 at 80.00 EUR into the EUR account,
  # fees 5.00 and taxes 1.00 EUR (cash 806.00), with the legs the import
  # stores when the rate is there (800.00 EUR, 1,000.00 USD, 0.800000), or
  # none when it was not.
  defp imported_buy!(world, fund, legs?) do
    legs =
      if legs?,
        do: [security_amount: "1000", settled: "800", rate: "0.8"],
        else: [security_amount: nil, settled: nil, rate: nil]

    account_currency_trade!(
      world,
      fund,
      [
        type: "buy",
        date: ~D[2025-04-01],
        quantity: "10",
        price: "80",
        fees: "5",
        taxes: "1",
        gross: "806"
      ] ++ legs
    )
  end

  # Identity 1's sale through the booking form: 10 at 120 USD, settled
  # 960.00 EUR, fees 3.00 EUR (cash 957.00).
  defp form_sale!(world, fund) do
    cross_trade!(world, fund,
      type: "sell",
      quantity: "10",
      price: "120",
      settled: "960.00",
      fees: "3.00",
      gross: "957.00",
      date: ~D[2025-05-02]
    )
  end

  # User story (#1198, Sprint 21 α3; identity 1, round trip 1 of the plan's
  # D-1):
  # As the operator who imported a dollar share bought from my euro account
  # and sold it through the booking form in dollars,
  # I want the closed trade in the sale's currency, the imported lot entering
  # through its own stored legs,
  # so that its result in euros is the cash the two bookings moved.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - The lot enters at 100 USD a share (1,000.00 USD ÷ 10), its fees and
  #   taxes at 6.25 and 1.25 USD (÷ 0.800000), the sale's fees at 3.75 USD:
  #   basis 1,007.50 USD, proceeds 1,196.25 USD, realized 188.75 USD.
  # - The realized-gains report and the Overview card's newest trades read
  #   151.00 EUR = 957.00 − 806.00. Before: basis 806.00, realized 390.25
  #   under USD, read as 312.20 EUR.
  # - Mutation: entering the lot at its booked price with its fees converted
  #   (basis 807.50) turns this red.
  test "an imported lot sold through the booking form enters at its native leg (identity 1)" do
    {world, fund} = cross_world()
    buy = imported_buy!(world, fund, true)
    sell = form_sale!(world, fund)

    assert [trade] = closed(fund)
    assert trade.currency_code == "USD"
    assert exactly?(trade.avg_buy_price, "100")
    assert exactly?(trade.buy_fees, "6.25")
    assert exactly?(trade.buy_taxes, "1.25")
    assert exactly?(trade.sell_fees, "3.75")
    assert exactly?(trade.basis, "1007.50")
    assert exactly?(trade.proceeds, "1196.25")
    assert exactly?(trade.realized_pnl_abs, "188.75")

    assert Decimal.equal?(
             trade.realized_pnl_pct,
             Decimal.div(Decimal.new("188.75"), Decimal.new("1007.50"))
           )

    assert [%{cost: lot_cost}] = trade.lots
    assert exactly?(lot_cost, "1007.50")

    assert is_nil(trade.unavailable_reason)

    cash_moved = Decimal.sub(sell.gross_amount, buy.gross_amount)
    assert exactly?(cash_moved, "151.00")
    assert exactly?(realized_row(fund).realized_base, "151.00")

    assert %{trades: [newest]} = RealizedGains.newest_trades(1, base_currency: "EUR")
    assert exactly?(newest.realized_base, "151.00")
    assert exactly?(newest.basis, "1007.50")
  end

  # User story (#1198, Sprint 21 α3; identity 2a, the shape #1198 records):
  # As the operator holding a dollar share bought once through the booking
  # form and once through an import,
  # I want a sale of both to add their costs in one currency,
  # so that the basis is 2,000 USD, never 1,000 USD plus 800 EUR.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - Booking-form buy of 10 at 100 USD settled 800.00 EUR, imported buy of
  #   10 at 80.00 EUR (legs 800.00 EUR, 1,000.00 USD, 0.800000), booking-form
  #   sale of 20 at 120 USD settled 1,920.00 EUR, no fees: basis 2,000 USD,
  #   realized 400 USD = 320.00 EUR = 1,920.00 − 800.00 − 800.00,
  #   realized_pnl_pct 0.2. Before: 1,800 and 600 under USD, 480.00 EUR,
  #   0.3333….
  test "a sale closing a form lot and an imported lot adds them in one currency (identity 2a)" do
    {world, fund} = cross_world()
    usd_rate!([~D[2025-04-02]])

    cross_trade!(world, fund,
      quantity: "10",
      price: "100",
      settled: "800.00",
      gross: "800.00",
      date: ~D[2025-04-01]
    )

    account_currency_trade!(world, fund,
      type: "buy",
      date: ~D[2025-04-02],
      quantity: "10",
      price: "80",
      security_amount: "1000",
      settled: "800",
      rate: "0.8",
      gross: "800"
    )

    cross_trade!(world, fund,
      type: "sell",
      quantity: "20",
      price: "120",
      settled: "1920.00",
      gross: "1920.00",
      date: ~D[2025-05-02]
    )

    assert [trade] = closed(fund)
    assert trade.currency_code == "USD"
    assert exactly?(trade.basis, "2000")
    assert exactly?(trade.realized_pnl_abs, "400")
    assert exactly?(trade.realized_pnl_pct, "0.2")
    assert exactly?(realized_row(fund).realized_base, "320.00")
  end

  # User story (#1198, Sprint 21 α3; identity 2b, the reverse pair):
  # As the operator who bought a dollar share through the booking form and
  # whose sale came in through an import in euros,
  # I want the closed trade in euros, the lot entering at the euros it cost,
  # so that a gain never reads as a loss.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - Booking-form buy of 10 at 100 USD settled 800.00 EUR, fees 5.00 and
  #   taxes 1.00 EUR (cash 806.00); imported sale of 10 at 96.00 EUR (cash
  #   957.00, fees 3.00 EUR; legs 960.00 EUR, 1,200.00 USD, 0.800000). The
  #   trade is in EUR; the lot enters at 80.00 EUR a share, its fees and
  #   taxes as recorded: basis 806.00 EUR, proceeds 957.00 EUR, realized
  #   151.00 EUR = 957.00 − 806.00. Before: basis 1,007.50 and realized
  #   −50.50 under EUR.
  # - Mutation: dividing the lot's fees by its rate when it enters its
  #   account's currency (basis 807.50 EUR) turns this red.
  test "a form lot closed by an imported sale enters at its settlement leg (identity 2b)" do
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
      account_currency_trade!(world, fund,
        type: "sell",
        date: ~D[2025-05-02],
        quantity: "10",
        price: "96",
        fees: "3",
        security_amount: "1200",
        settled: "960",
        rate: "0.8",
        gross: "957"
      )

    assert [trade] = closed(fund)
    assert trade.currency_code == "EUR"
    assert exactly?(trade.avg_buy_price, "80")
    assert exactly?(trade.buy_fees, "5.00")
    assert exactly?(trade.buy_taxes, "1.00")
    assert exactly?(trade.basis, "806.00")
    assert exactly?(trade.proceeds, "957.00")
    assert exactly?(trade.realized_pnl_abs, "151.00")
    assert [%{cost: lot_cost}] = trade.lots
    assert exactly?(lot_cost, "806.00")

    cash_moved = Decimal.sub(sell.gross_amount, buy.gross_amount)
    assert Decimal.equal?(trade.realized_pnl_abs, cash_moved)
    assert exactly?(realized_row(fund).realized_base, "151.00")
  end

  # The franc moving against the euro between a purchase and its sale: 1 EUR
  # = 0.94 CHF on the purchase's date and 0.95 CHF on the sale's, stored as
  # EUR per CHF (the close-date read converts at 1 / 0.95).
  defp moving_chf_rates! do
    {:ok, _} =
      [{~D[2026-07-11], "0.94"}, {~D[2026-10-21], "0.95"}]
      |> Enum.map(fn {date, rate} ->
        %{base_currency: "EUR", quote_currency: "CHF", date: date, rate: rate, source: "manual"}
      end)
      |> Fx.upsert_many()
  end

  # User story (#1198, Sprint 21 α3; the ADR-0015 amendment of 2026-10-09,
  # identity 1 with a moving rate, the note of 2026-10-31):
  # As the operator who imported a franc share bought from my euro account
  # and sold it through the booking form in francs, while the franc moved
  # against the euro,
  # I want the realized result in euros to be the cash the two bookings
  # moved,
  # so that it agrees with my bank's statement, not with the trade's franc
  # result converted at the sale date's rate.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - Imported buy of 20 at 50.00 EUR, fee 4.00 EUR (cash 1,004.00), legs
  #   1,000.00 EUR, 940.00 CHF, 1.063830 (the hub's 0.94 that day); booking-
  #   form sale of 20 at 55 CHF, settled 1,157.90 EUR, fee 3.00 EUR (cash
  #   1,154.90; the hub's 0.95 that day).
  # - The closed trade stays in francs, the lot entering at its native leg:
  #   basis 943.76, proceeds 1,097.15, realized 153.39 CHF (to the cent).
  # - The realized-gains report, its realized_total and the Overview card's
  #   newest trades read 150.90 EUR = 1,154.90 − 1,004.00, the sale's
  #   settlement less the lot's, and name the path: settlement_legs.
  #   Before: 161.46 EUR, the franc result at 1 / 0.95.
  # - A franc round trip booked wholly through the booking form, the same
  #   rates, keeps the close-date conversion (point 4, one currency): 100
  #   CHF = 100 / 0.95 EUR, path close_date_rate.
  # - Mutation: converting the trade's franc result at the close date where
  #   both sides carry their legs turns this red.
  test "an imported lot sold in the security's currency reads the cash it moved when the rate moved (identity 1)" do
    world = base_world(name: "Franc Move", cash_name: "Franc Cash", depot_name: "Franc Depot")
    moving_chf_rates!()
    works = create_security!(name: "Lakeside Turbines AG", ticker: "LKT", currency: "CHF")
    form = create_security!(name: "Lakeside Form AG", ticker: "LKF", currency: "CHF")

    buy =
      account_currency_trade!(world, works,
        type: "buy",
        date: ~D[2026-07-11],
        quantity: "20",
        price: "50",
        fees: "4",
        security_amount: "940",
        settled: "1000",
        rate: "1.063830",
        gross: "1004"
      )

    sell =
      cross_trade!(world, works,
        type: "sell",
        quantity: "20",
        price: "55",
        settled: "1157.90",
        fees: "3.00",
        gross: "1154.90",
        date: ~D[2026-10-21]
      )

    assert [trade] = closed(works)
    assert trade.currency_code == "CHF"
    assert exactly?(Decimal.round(trade.basis, 2), "943.76")
    assert exactly?(Decimal.round(trade.proceeds, 2), "1097.15")
    assert exactly?(Decimal.round(trade.realized_pnl_abs, 2), "153.39")

    cash_moved = Decimal.sub(sell.gross_amount, buy.gross_amount)
    assert exactly?(cash_moved, "150.90")

    row = realized_row(works)
    assert exactly?(row.realized_base, "150.90")
    assert Decimal.equal?(row.realized_base, cash_moved)
    assert row.realized_base_source == :settlement_legs

    assert %{trades: [newest]} = RealizedGains.newest_trades(1, base_currency: "EUR")
    assert newest.security_id == works.id
    assert exactly?(newest.realized_base, "150.90")
    assert newest.realized_base_source == :settlement_legs

    cross_trade!(world, form,
      quantity: "20",
      price: "50",
      settled: "1063.83",
      gross: "1063.83",
      date: ~D[2026-07-11]
    )

    cross_trade!(world, form,
      type: "sell",
      quantity: "20",
      price: "55",
      settled: "1157.89",
      gross: "1157.89",
      date: ~D[2026-10-21]
    )

    assert [one_currency] = closed(form)
    assert exactly?(one_currency.realized_pnl_abs, "100")

    form_row = realized_row(form)

    assert Decimal.equal?(
             form_row.realized_base,
             Decimal.mult(Decimal.new("100"), Decimal.div(Decimal.new("1"), Decimal.new("0.95")))
           )

    assert form_row.realized_base_source == :close_date_rate

    assert Decimal.equal?(
             RealizedGains.report(base_currency: "EUR").summary.realized_total,
             Decimal.add(row.realized_base, form_row.realized_base)
           )
  end

  # User story (#1198, Sprint 21 α3; identity 3, the fallback of point 3):
  # As the operator whose imported dollar share came in before any rate was
  # stored, so it carries no legs, and was then sold in dollars,
  # I want that closed trade named unavailable with the lot that lacks its
  # leg, and left out of every total,
  # so that no figure adds euros under a dollar code.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - The trades read keeps the trade with its sale's own figures (quantity,
  #   dates, avg_sell_price 120, sell_fees 3.75 USD, proceeds 1,196.25 USD),
  #   null for avg_buy_price, buy_fees, buy_taxes, basis, every lot's cost,
  #   realized_pnl_abs, realized_pnl_pct and annualized_return, the reason
  #   missing_settlement_leg, and the lot that lacks its leg: opened
  #   2025-04-01, booked in EUR.
  # - Beside it a EUR security bought 10 at 50.00 EUR, fees 1.00, and sold 10
  #   at 60.00 EUR, fees 1.00: realized 98.00 EUR. The realized-gains report
  #   names the dollar trade in excluded (reason missing_settlement_leg, apart
  #   from a missing close-date rate) and reads realized_total 98.00 EUR over
  #   trade_count 1, hit_rate 1.0000. Before: 410.20 EUR over two trades.
  # - The Overview card's newest trades leave it out and name it the same
  #   way.
  # - Once the lot's legs are stored (identity 6 derives them), the trade
  #   reads identity 1 and realized_total 249.00 EUR.
  # - Mutations: entering the lot as booked when its leg is missing turns it
  #   red, and so does leaving the trade out without naming it.
  test "a lot without its leg makes the closed trade unavailable and named (identity 3)" do
    {world, fund} = cross_world()
    buy = imported_buy!(world, fund, false)
    form_sale!(world, fund)

    mill = create_security!(name: "Euro Mill Three", ticker: "EM3")
    buy!(world, mill, quantity: "10", price: "50", fees: "1", date: ~D[2025-04-01])
    sell!(world, mill, quantity: "10", price: "60", fees: "1", date: ~D[2025-05-02])

    assert [trade] = closed(fund)
    assert trade.currency_code == "USD"
    assert exactly?(trade.quantity, "10")
    assert trade.open_date == ~D[2025-04-01]
    assert trade.close_date == ~D[2025-05-02]
    assert exactly?(trade.avg_sell_price, "120")
    assert exactly?(trade.sell_fees, "3.75")
    assert exactly?(trade.proceeds, "1196.25")

    for key <- [
          :avg_buy_price,
          :buy_fees,
          :buy_taxes,
          :basis,
          :realized_pnl_abs,
          :realized_pnl_pct,
          :annualized_return
        ] do
      assert is_nil(Map.fetch!(trade, key)), "#{key} is #{inspect(Map.fetch!(trade, key))}"
    end

    assert [%{cost: nil}] = trade.lots
    assert trade.unavailable_reason == :missing_settlement_leg

    assert trade.lots_missing_leg == [
             %{open_date: ~D[2025-04-01], currency_code: "EUR", reason: :missing_settlement_leg}
           ]

    report = RealizedGains.report(base_currency: "EUR")
    assert [only] = report.trades
    assert only.security_id == mill.id
    assert exactly?(report.summary.realized_total, "98.00")
    assert report.summary.trade_count == 1
    assert exact(report.summary.hit_rate) == "1.0000"

    assert report.excluded.count == 1
    assert report.excluded.securities == ["Dollar Fund"]
    assert report.excluded.by_reason.no_rate == %{count: 0, securities: []}

    assert report.excluded.by_reason.missing_settlement_leg == %{
             count: 1,
             securities: ["Dollar Fund"]
           }

    newest = RealizedGains.newest_trades(5, base_currency: "EUR")
    assert Enum.map(newest.trades, & &1.security_id) == [mill.id]
    assert newest.excluded.by_reason.missing_settlement_leg.securities == ["Dollar Fund"]

    # The legs the history backfill derives (identity 6), stored by hand.
    {:ok, _} =
      Ledger.update_transaction(Actor.owner_ui(), buy, %{
        security_amount: "1000",
        settlement_amount: "800",
        settlement_fx_rate: "0.8"
      })

    assert [derived] = closed(fund)
    assert is_nil(derived.unavailable_reason)
    assert exactly?(derived.basis, "1007.50")
    assert exactly?(derived.realized_pnl_abs, "188.75")
    assert exactly?(RealizedGains.report(base_currency: "EUR").summary.realized_total, "249.00")
  end

  # User story (#1198, Sprint 21 α3; point 3, "a lot booked in the currency
  # of another account than the sell's"):
  # As the operator holding one dollar share in a euro depot and a franc
  # depot,
  # I want a dollar sale closing a lot booked in francs named unavailable,
  # not converted through a leg that does not reach the sale's currency,
  # so that only a lot's own legs ever convert it.
  #
  # Acceptance criteria:
  # - A lot booked in CHF through a CHF account (legs to USD stored) closed by
  #   a sale in EUR through the EUR account is unavailable, missing_settlement_leg,
  #   the lot named by its date and CHF.
  test "a lot booked in another account's currency than the sale's is unavailable" do
    {world, fund} = cross_world()

    swiss =
      Map.merge(
        world,
        add_depot(world.portfolio,
          cash_currency: "CHF",
          cash_name: "Franc Cash",
          depot_name: "Franc Depot"
        )
      )

    account_currency_trade!(swiss, fund,
      type: "buy",
      date: ~D[2025-04-01],
      quantity: "10",
      price: "90",
      security_amount: "1000",
      settled: "900",
      rate: "0.9",
      gross: "900"
    )

    account_currency_trade!(world, fund,
      type: "sell",
      date: ~D[2025-05-02],
      quantity: "10",
      price: "96",
      security_amount: "1200",
      settled: "960",
      rate: "0.8",
      gross: "960"
    )

    assert [trade] = closed(fund)
    assert trade.currency_code == "EUR"
    assert is_nil(trade.basis)
    assert trade.unavailable_reason == :missing_settlement_leg

    assert trade.lots_missing_leg == [
             %{open_date: ~D[2025-04-01], currency_code: "CHF", reason: :missing_settlement_leg}
           ]
  end

  # A buy or sell as a database stored it before #1199's check: written past
  # the changeset, under the journal's actor. The ledger now refuses a new
  # booking priced in a third currency, so a third-currency row is a stored
  # row's case (the ADR-0015 amendment of 2026-10-09, identity 5).
  defp stored_trade!(world, security, attrs) do
    {:ok, tx} =
      Repo.transaction(fn ->
        {type, _label} = Actor.to_columns(Actor.owner_ui())
        Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])

        Repo.insert!(
          struct!(
            Transaction,
            Map.merge(
              %{
                portfolio_id: world.portfolio.id,
                securities_account_id: world.depot.id,
                cash_account_id: world.cash.id,
                security_id: security.id,
                taxes: Decimal.new("0")
              },
              attrs
            )
          )
        )
      end)

    tx
  end

  defp chf_rate!(dates) do
    {:ok, _} =
      dates
      |> Enum.map(fn date ->
        %{base_currency: "EUR", quote_currency: "CHF", date: date, rate: "0.95", source: "manual"}
      end)
      |> Fx.upsert_many()
  end

  # User story (#1198, Sprint 21 α3; point 3, "a lot or a sell priced in a
  # third currency"):
  # As the operator whose dollar share was bought through a franc account and
  # sold, in a row stored before #1199's refusal, at a franc price through my
  # euro account,
  # I want that closed trade named unavailable, not computed,
  # so that no figure subtracts a sale's euro fees from a franc price and no
  # total sums the result.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - A buy of 10 at 100 USD through the CHF account (legs 1,000.00 USD,
  #   900.00 CHF, 0.900000; fees 2.00 CHF, cash 902.00) and a stored sale of
  #   10 at 110 CHF through the EUR account, fees 3.00 EUR: the trade is in
  #   CHF, unavailable, basis and realized_pnl_abs null, the lot named by its
  #   date and USD; the sale's own avg_sell_price 110 stays.
  # - #1310: its reason is third_currency, its own, not
  #   missing_settlement_leg, whose remedy (a rate) cannot apply; the lot is
  #   named with that reason; proceeds, sell_fees and sell_taxes are null,
  #   since the sale's 3.00 EUR of fees under a CHF code is no figure. Before:
  #   missing_settlement_leg, proceeds 1097 (1,100 CHF less 3 EUR) and
  #   sell_fees 3.
  # - The realized-gains report leaves it out of trades and names it in
  #   excluded under third_currency, apart from missing_settlement_leg,
  #   though the close date has a CHF rate.
  # - A money identity at a moving rate: beside it a dollar round trip
  #   through a dollar account, 10 bought at 100 USD while 1 EUR = 1.10 USD
  #   and sold at 120 USD once 1 EUR = 1.25 USD, reads realized 200 USD =
  #   realized_base 160 EUR (200 / 1.25, the close date's rate), and the
  #   report's realized_total is exactly 160 over trade_count 1: the
  #   excluded trade moves no figure.
  # - Mutation: not reading the sale's third-currency flag turns it red.
  test "a sale priced in a third currency makes its closed trade unavailable" do
    {world, fund} = cross_world()
    chf_rate!([~D[2025-04-01], ~D[2025-05-02]])

    # The moving-rate dollar round trip beside it, on dates of its own.
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2025-02-03],
          rate: "1.10",
          source: "manual"
        },
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2025-06-02],
          rate: "1.25",
          source: "manual"
        }
      ])

    dollar = Map.merge(world, add_depot(world.portfolio, cash_currency: "USD"))
    tracker = create_security!(name: "Dollar Tracker", ticker: "DTR", currency: "USD")
    buy!(dollar, tracker, quantity: "10", price: "100", currency: "USD", date: ~D[2025-02-03])
    sell!(dollar, tracker, quantity: "10", price: "120", currency: "USD", date: ~D[2025-06-02])

    swiss =
      Map.merge(
        world,
        add_depot(world.portfolio,
          cash_currency: "CHF",
          cash_name: "Franc Cash",
          depot_name: "Franc Depot"
        )
      )

    cross_trade!(swiss, fund,
      type: "buy",
      quantity: "10",
      price: "100",
      settled: "900.00",
      fees: "2.00",
      gross: "902.00",
      date: ~D[2025-04-01]
    )

    stored_trade!(world, fund, %{
      type: "sell",
      date: ~D[2025-05-02],
      quantity: Decimal.new("10"),
      price: Decimal.new("110"),
      fees: Decimal.new("3"),
      currency_code: "CHF",
      security_amount: Decimal.new("1222.22"),
      settlement_amount: Decimal.new("1100.00"),
      settlement_fx_rate: Decimal.new("0.900000"),
      gross_amount: Decimal.new("1097.00")
    })

    assert [trade] = closed(fund)
    assert trade.currency_code == "CHF"
    assert trade.unavailable_reason == :third_currency
    assert is_nil(trade.basis)
    assert is_nil(trade.realized_pnl_abs)

    assert trade.lots_missing_leg == [
             %{open_date: ~D[2025-04-01], currency_code: "USD", reason: :third_currency}
           ]

    assert exactly?(trade.avg_sell_price, "110")
    assert exactly?(trade.quantity, "10")

    for key <- [:proceeds, :sell_fees, :sell_taxes] do
      assert is_nil(Map.fetch!(trade, key)), "#{key} is #{inspect(Map.fetch!(trade, key))}"
    end

    assert trade.annualized_return_reason == :third_currency

    report = RealizedGains.report(base_currency: "EUR")
    refute Enum.any?(report.trades, &(&1.security_id == fund.id))

    assert report.excluded.by_reason.third_currency == %{count: 1, securities: ["Dollar Fund"]}
    assert report.excluded.by_reason.missing_settlement_leg == %{count: 0, securities: []}
    assert report.excluded.count == 1

    assert [only] = report.trades
    assert only.security_id == tracker.id
    assert exactly?(only.realized_pnl_abs, "200")
    assert exactly?(only.realized_base, "160")
    assert only.realized_base_source == :close_date_rate
    assert exactly?(report.summary.realized_total, "160")
    assert report.summary.trade_count == 1

    newest = RealizedGains.newest_trades(5, base_currency: "EUR")
    assert Enum.map(newest.trades, & &1.security_id) == [tracker.id]
    assert newest.excluded.by_reason.third_currency.securities == ["Dollar Fund"]
  end

  # User story (#1198, Sprint 21 α3; point 3 ahead of point 4, the note of
  # 2026-10-31):
  # As the operator with a dollar share bought at a franc price through my
  # euro account, a row stored before #1199's refusal, and sold at a franc
  # price through my franc account,
  # I want their closed trade named unavailable although the sale and the lot
  # share one currency,
  # so that the lot's euro fees are never added to a franc basis.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - A stored buy of 10 at 90 CHF through the EUR account, fees 5.00 EUR,
  #   closed by a sale of 10 at 100 CHF through the CHF account (legs
  #   1,000.00 CHF, 1,250.00 USD, 0.800000; fees 3.00 CHF, cash 997.00): the
  #   trade is in CHF, unavailable, basis and realized_pnl_abs null, the lot
  #   named by its date and CHF. Before #1198's note: basis 905 and realized
  #   92 under CHF.
  # - #1310: its reason is third_currency, the lot named with it; the sale's
  #   own figures stay, since the sale is priced in its account's currency:
  #   proceeds 997 CHF (10 × 100 − 3), sell_fees 3. Before: the reason
  #   missing_settlement_leg, whose remedy (a rate) cannot apply.
  # - Mutation: not reading the lot's third-currency flag turns it red.
  test "a lot priced in a third currency makes the closed trade unavailable, even in that currency" do
    {world, fund} = cross_world()

    swiss =
      Map.merge(
        world,
        add_depot(world.portfolio,
          cash_currency: "CHF",
          cash_name: "Franc Cash",
          depot_name: "Franc Depot"
        )
      )

    stored_trade!(world, fund, %{
      type: "buy",
      date: ~D[2025-04-01],
      quantity: Decimal.new("10"),
      price: Decimal.new("90"),
      fees: Decimal.new("5"),
      currency_code: "CHF",
      security_amount: Decimal.new("1000"),
      settlement_amount: Decimal.new("800"),
      settlement_fx_rate: Decimal.new("0.888889"),
      gross_amount: Decimal.new("805")
    })

    account_currency_trade!(swiss, fund,
      type: "sell",
      date: ~D[2025-05-02],
      quantity: "10",
      price: "100",
      fees: "3",
      security_amount: "1250",
      settled: "1000",
      rate: "0.8",
      gross: "997"
    )

    assert [trade] = closed(fund)
    assert trade.currency_code == "CHF"
    assert trade.unavailable_reason == :third_currency
    assert is_nil(trade.basis)
    assert is_nil(trade.realized_pnl_abs)
    assert exactly?(trade.proceeds, "997")
    assert exactly?(trade.sell_fees, "3")

    assert trade.lots_missing_leg == [
             %{open_date: ~D[2025-04-01], currency_code: "CHF", reason: :third_currency}
           ]
  end

  # User story (#1310, Sprint 22 R5; the ADR-0015 amendment of 2026-10-09,
  # point 3):
  # As the operator whose dollar sale closes an imported buy that still lacks
  # its legs and a stored buy priced in francs through my euro account,
  # I want the trade's reason to be the franc buy, which no rate fixes, and
  # each lot named with its own reason,
  # so that I correct the booking first and know the other lot waits for a
  # rate.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - The imported buy of 10 at 80.00 EUR without legs (2025-04-01), a stored
  #   buy of 10 at 90 CHF through the EUR account (2025-04-02), and a
  #   booking-form sale of 20 at 120 USD settled 1,920.00 EUR, fees 3.00 EUR:
  #   unavailable_reason third_currency; lots_missing_leg names the EUR lot
  #   with missing_settlement_leg and the CHF lot with third_currency, in
  #   FIFO order; the sale's own figures stay: proceeds 2,396.25 USD
  #   (20 × 120 − 3.00 ÷ 0.8), sell_fees 3.75.
  test "a trade closing a legless lot and a third-currency lot names each with its reason" do
    {world, fund} = cross_world()
    imported_buy!(world, fund, false)

    stored_trade!(world, fund, %{
      type: "buy",
      date: ~D[2025-04-02],
      quantity: Decimal.new("10"),
      price: Decimal.new("90"),
      fees: Decimal.new("5"),
      currency_code: "CHF",
      security_amount: Decimal.new("1000"),
      settlement_amount: Decimal.new("800"),
      settlement_fx_rate: Decimal.new("0.888889"),
      gross_amount: Decimal.new("805")
    })

    cross_trade!(world, fund,
      type: "sell",
      quantity: "20",
      price: "120",
      settled: "1920.00",
      fees: "3.00",
      gross: "1917.00",
      date: ~D[2025-05-02]
    )

    assert [trade] = closed(fund)
    assert trade.currency_code == "USD"
    assert trade.unavailable_reason == :third_currency
    assert is_nil(trade.basis)
    assert exactly?(trade.proceeds, "2396.25")
    assert exactly?(trade.sell_fees, "3.75")

    assert trade.lots_missing_leg == [
             %{open_date: ~D[2025-04-01], currency_code: "EUR", reason: :missing_settlement_leg},
             %{open_date: ~D[2025-04-02], currency_code: "CHF", reason: :third_currency}
           ]
  end
end
