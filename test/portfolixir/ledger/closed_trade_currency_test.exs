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
    only: [add_depot: 2, base_world: 1, buy!: 3, create_security!: 1, sell!: 3]

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
end
