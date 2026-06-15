defmodule Portfolixir.Ledger.CrossCurrencySettlementTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.Valuation

  # User story:
  # As a local portfolio maintainer who buys a USD security through a EUR
  # cash account (the ordinary comdirect flow),
  # I want to book the trade in the security's own currency while the cash
  # leg settles in EUR at the broker's FX rate,
  # so that per-position cost basis and P&L read against the USD price are
  # FX-honest (no phantom day-one P&L) and the EUR cash debit stays correct.
  #
  # Acceptance criteria (ADR-0015, FR1-FR4):
  # - A buy whose currency differs from its cash account is accepted when a
  #   settlement FX rate (and the two linked amounts) are supplied, instead
  #   of being rejected as under #343.
  # - The three linked figures are persisted as Decimal: the security-currency
  #   trade amount, the settlement-currency cash amount, and the FX rate.
  # - Cost basis / avg_cost is computed in the security's own currency, so a
  #   foreign position reads ~0% P&L on zero real movement on day one.
  # - The cash leg debits the settlement (account) currency.
  # - A mismatch with no settlement FX rate is rejected with a changeset error.
  # - A same-currency trade is unchanged: no FX leg, no settlement fields.

  defp world do
    world = base_world(name: "Cross FX", cash_name: "EUR Cash", depot_name: "Depot")
    security = create_security!(name: "US Equity", ticker: "USX", currency: "USD")
    Map.put(world, :security, security)
  end

  # EUR-hub rates (1 EUR = rate units of quote). USD at 1.10 means
  # 1 USD = 1 / 1.10 EUR, so a USD trade settles in EUR at ~0.909091.
  defp seed_usd_rate(date) do
    {:ok, _} =
      Fx.upsert_many([
        %{base_currency: "EUR", quote_currency: "USD", date: date, rate: "1.10", source: "manual"}
      ])

    :ok
  end

  defp cross_currency_buy(w, overrides) do
    base = %{
      portfolio_id: w.portfolio.id,
      securities_account_id: w.depot.id,
      cash_account_id: w.cash.id,
      security_id: w.security.id,
      type: "buy",
      date: ~D[2026-04-01],
      quantity: Decimal.new("10"),
      price: Decimal.new("200.00"),
      currency_code: "USD",
      security_amount: Decimal.new("2000.00"),
      settlement_amount: Decimal.new("1818.181818"),
      settlement_fx_rate: Decimal.new("0.909091"),
      gross_amount: Decimal.new("1818.181818")
    }

    Ledger.create_transaction(Map.merge(base, overrides))
  end

  describe "booking a foreign-currency trade with a settlement FX rate (FR1, FR3)" do
    test "accepts a USD buy through a EUR cash account with a stored FX rate" do
      w = world()

      assert {:ok, %Transaction{} = tx} = cross_currency_buy(w, %{})

      assert tx.currency_code == "USD"
      assert Decimal.equal?(tx.security_amount, Decimal.new("2000.000000"))
      assert Decimal.equal?(tx.settlement_amount, Decimal.new("1818.181818"))
      assert Decimal.equal?(tx.settlement_fx_rate, Decimal.new("0.909091"))
    end

    test "derives the settlement FX rate from the two amounts when omitted" do
      w = world()

      assert {:ok, %Transaction{} = tx} =
               cross_currency_buy(w, %{settlement_fx_rate: nil})

      # 1818.181818 / 2000.000000 = 0.909090909..., stored at scale 6.
      assert Decimal.equal?(tx.settlement_fx_rate, Decimal.new("0.909091"))
    end

    test "rejects a mismatch with no settlement FX rate and no amounts to derive one" do
      w = world()

      assert {:error, changeset} =
               cross_currency_buy(w, %{
                 settlement_fx_rate: nil,
                 security_amount: nil,
                 settlement_amount: nil
               })

      assert %{settlement_fx_rate: ["is required for a cross-currency settlement"]} =
               errors_on(changeset)
    end
  end

  describe "native-currency cost basis and day-one P&L (FR2)" do
    test "avg_cost is the security-currency price, so day-one P&L is ~0%" do
      w = world()
      assert {:ok, _} = cross_currency_buy(w, %{})

      # Latest USD quote equals the trade price: zero real movement.
      put_quote!(w.security, ~D[2026-04-01], Decimal.new("200.00"))

      [holding] = Ledger.holdings_for_portfolio(w.portfolio.id)

      assert Decimal.equal?(holding.avg_cost, Decimal.new("200.00"))
      assert Decimal.equal?(holding.cost_basis, Decimal.new("2000.00"))
      assert Decimal.equal?(holding.market_value, Decimal.new("2000.00"))
      assert Decimal.equal?(holding.unrealized_pnl_abs, Decimal.new("0"))
      assert Decimal.equal?(holding.unrealized_pnl_pct, Decimal.new("0"))
    end
  end

  describe "cash leg settles in the account currency (FR2)" do
    test "the EUR cash balance is debited by the settlement amount, not the USD amount" do
      w = world()
      assert {:ok, _} = cross_currency_buy(w, %{})

      balances = Ledger.cash_balances(portfolio_id: w.portfolio.id)

      assert Decimal.equal?(balances[w.cash.id], Decimal.new("-1818.181818"))
    end
  end

  describe "no usable FX rate path keeps the position honest (FR4)" do
    test "a held foreign position with no rate path to base is reported unvalued" do
      w = world()
      assert {:ok, _} = cross_currency_buy(w, %{})
      put_quote!(w.security, ~D[2026-04-01], Decimal.new("200.00"))

      # No EUR/USD rate seeded: the EUR-base valuation cannot convert the USD
      # position, so it is marked unvalued rather than reported wrong.
      valuation = Valuation.for_portfolio(w.portfolio.id)
      position = Enum.find(valuation.positions, &(&1.security_id == w.security.id))

      refute position.valued
      assert is_nil(position.market_value)
      assert valuation.unvalued_count >= 1
    end

    test "with a seeded EUR/USD rate the position values into the EUR base total" do
      w = world()
      assert {:ok, _} = cross_currency_buy(w, %{})
      put_quote!(w.security, ~D[2026-04-01], Decimal.new("200.00"))
      seed_usd_rate(~D[2026-04-01])

      valuation = Valuation.for_portfolio(w.portfolio.id)
      position = Enum.find(valuation.positions, &(&1.security_id == w.security.id))

      assert position.valued
      # 10 * 200 USD = 2000 USD -> EUR at 1 EUR = 1.10 USD. Mirror the engine's
      # exact arithmetic: native * (1 / hub_rate), so the Decimal value matches.
      rate = Decimal.div(Decimal.new("1"), Decimal.new("1.10"))
      expected = Decimal.mult(Decimal.new("2000"), rate)
      assert Decimal.equal?(position.market_value, expected)
    end
  end

  describe "same-currency trade is unchanged (counter-metric)" do
    test "a EUR buy through a EUR account stores no settlement fields" do
      world = base_world(name: "Same CCY", cash_name: "EUR Cash", depot_name: "Depot")
      security = create_security!(name: "EU Equity", ticker: "EUX", currency: "EUR")

      assert {:ok, %Transaction{} = tx} =
               Ledger.create_transaction(%{
                 portfolio_id: world.portfolio.id,
                 securities_account_id: world.depot.id,
                 cash_account_id: world.cash.id,
                 security_id: security.id,
                 type: "buy",
                 date: ~D[2026-04-01],
                 quantity: Decimal.new("10"),
                 price: Decimal.new("100.00"),
                 gross_amount: Decimal.new("1000.00"),
                 currency_code: "EUR"
               })

      assert is_nil(tx.settlement_fx_rate)
      assert is_nil(tx.security_amount)
      assert is_nil(tx.settlement_amount)

      balances = Ledger.cash_balances(portfolio_id: world.portfolio.id)
      assert Decimal.equal?(balances[world.cash.id], Decimal.new("-1000.00"))
    end
  end
end
