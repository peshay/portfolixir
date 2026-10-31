defmodule Portfolixir.Ledger.CrossCurrencySettlementTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.Valuation
  alias Portfolixir.Repo

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

    Ledger.create_transaction(Portfolixir.Actor.owner_ui(), Map.merge(base, overrides))
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
               Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
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

  # -- #1199, Sprint 21 α1: a trade priced in a third currency ------------------

  # A buy of the USD security through the EUR account, priced in CHF, with a
  # settlement rate and figures the settlement guard accepts: 10 at 90 CHF,
  # settled 800.00 EUR, cash 800.00 EUR. Synthetic.
  defp third_currency_attrs(w, overrides \\ %{}) do
    Map.merge(
      %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: w.security.id,
        type: "buy",
        date: ~D[2026-04-01],
        quantity: Decimal.new("10"),
        price: Decimal.new("90.00"),
        currency_code: "CHF",
        security_amount: Decimal.new("1000.00"),
        settlement_amount: Decimal.new("800.00"),
        settlement_fx_rate: Decimal.new("0.888889"),
        gross_amount: Decimal.new("800.00")
      },
      overrides
    )
  end

  # The row as a database holds it from before the check: written past the
  # changeset, under the journal's actor, as history already stored looks.
  defp stored_third_currency_buy!(w) do
    {:ok, tx} =
      Repo.transaction(fn ->
        {type, _label} = Actor.to_columns(Actor.owner_ui())
        Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])
        Repo.insert!(struct!(Transaction, third_currency_attrs(w)))
      end)

    tx
  end

  defp currency_error(changeset), do: errors_on(changeset)[:currency_code]

  defp transaction_journal(operation),
    do: Journal.list_entries(resource_type: "transaction", operation: operation)

  # User story (#1199, Sprint 21 α1; the ADR-0015 amendment of 2026-10-09,
  # point 1 and identity 5):
  # As the operator booking a trade,
  # I want a buy or sell priced in neither its security's currency nor its
  # cash account's refused, with both allowed currencies named,
  # so that no closed trade ever adds a lot in a currency no stored leg
  # converts.
  #
  # Acceptance criteria:
  # - Through a EUR account, a new buy of a USD security priced in CHF, with
  #   a settlement rate, is refused with an error on currency_code naming
  #   USD and EUR; nothing is stored and nothing is journaled.
  # - The same buy priced in USD (the security's currency) or in EUR (the
  #   account's, with its legs) is accepted.
  describe "a trade priced in a third currency (#1199, identity 5)" do
    test "a new buy priced in neither the security's currency nor the account's is refused" do
      w = world()

      assert {:error, changeset} =
               Ledger.create_transaction(Actor.owner_ui(), third_currency_attrs(w))

      assert [message] = currency_error(changeset)
      assert message =~ "USD"
      assert message =~ "EUR"
      assert Repo.aggregate(Transaction, :count) == 0
      assert transaction_journal(:create) == []
    end

    test "a sell priced in a third currency is refused the same way" do
      w = world()

      assert {:error, changeset} =
               Ledger.create_transaction(
                 Actor.owner_ui(),
                 third_currency_attrs(w, %{type: "sell"})
               )

      assert [_message] = currency_error(changeset)
    end

    # Acceptance criteria: where the security and its account share one
    # currency, a trade priced in another is refused naming that one.
    test "a buy of a EUR security through a EUR account priced in USD is refused" do
      w = world()
      euro = create_security!(name: "EU Equity Third", ticker: "EUT", currency: "EUR")

      assert {:error, changeset} =
               Ledger.create_transaction(
                 Actor.owner_ui(),
                 third_currency_attrs(w, %{security_id: euro.id, currency_code: "USD"})
               )

      assert currency_error(changeset) == [
               "must be EUR (the currency of the security and of its cash account)"
             ]
    end

    test "a buy priced in the security's or the account's currency is accepted" do
      w = world()

      assert {:ok, _usd} = cross_currency_buy(w, %{})

      assert {:ok, _eur} =
               Ledger.create_transaction(
                 Actor.owner_ui(),
                 third_currency_attrs(w, %{currency_code: "EUR", price: Decimal.new("80.00")})
               )
    end

    # Acceptance criteria (identity 5, the stored row):
    # - A stored buy priced in CHF, written as it was before the check, takes
    #   a notes-only edit: it is saved, journaled, and every figure stays.
    # - An update that changes a field the check reads -- the currency, the
    #   security, the cash account or the type -- runs it, as the
    #   settlement guard does (D-5), and is refused on currency_code.
    test "a notes-only edit of a stored third-currency row passes and keeps its figures" do
      w = world()
      stored = stored_third_currency_buy!(w)

      assert {:ok, updated} =
               Ledger.update_transaction(Actor.owner_ui(), stored, %{notes: "checked the note"})

      assert updated.notes == "checked the note"
      assert updated.currency_code == "CHF"

      for field <- [:quantity, :price, :security_amount, :settlement_amount, :gross_amount] do
        assert Decimal.equal?(Map.fetch!(updated, field), Map.fetch!(stored, field))
      end

      assert Decimal.equal?(updated.settlement_fx_rate, Decimal.new("0.888889"))
      assert [entry] = transaction_journal(:update)
      assert entry.resource_id == to_string(stored.id)
    end

    test "an update that changes the currency, the security, the cash account or the type is checked" do
      w = world()
      stored = stored_third_currency_buy!(w)
      twin = create_security!(name: "US Equity Twin", ticker: "USXT", currency: "USD")

      {:ok, other_cash} =
        Portfolixir.Portfolios.create_cash_account(Actor.owner_ui(), %{
          portfolio_id: w.portfolio.id,
          name: "Second EUR Cash",
          currency_code: "EUR"
        })

      for attrs <- [
            %{currency_code: "GBP"},
            %{security_id: twin.id},
            %{cash_account_id: other_cash.id},
            %{type: "sell"}
          ] do
        assert {:error, changeset} = Ledger.update_transaction(Actor.owner_ui(), stored, attrs),
               "#{inspect(attrs)} was not checked"

        assert [_message] = currency_error(changeset),
               "#{inspect(attrs)}: #{inspect(changeset.errors)}"
      end

      assert transaction_journal(:update) == []
    end
  end
end
