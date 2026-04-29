defmodule Portfolixir.LedgerTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.CashBalances
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Portfolios

  setup do
    {:ok, eur} = Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})
    {:ok, usd} = Catalog.create_currency(%{code: "USD", name: "US Dollar", minor_units: 2})

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{
        name: "Synthetic portfolio",
        base_currency_code: eur.code
      })

    {:ok, other_portfolio} =
      Portfolios.create_portfolio(%{
        name: "Other synthetic portfolio",
        base_currency_code: eur.code
      })

    {:ok, deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: eur.code
      })

    {:ok, securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        reference_deposit_account_id: deposit_account.id,
        name: "Depot",
        currency_code: eur.code
      })

    {:ok, security} =
      Catalog.create_security(%{
        name: "Synthetic ETF",
        symbol: "SYN",
        currency_code: eur.code
      })

    %{
      eur: eur,
      usd: usd,
      portfolio: portfolio,
      other_portfolio: other_portfolio,
      deposit_account: deposit_account,
      securities_account: securities_account,
      security: security
    }
  end

  test "create deposit transaction", %{portfolio: portfolio, deposit_account: deposit_account} do
    assert {:ok, transaction} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: deposit_account.id,
               type: "deposit",
               date: ~D[2026-01-02],
               currency_code: "EUR",
               amount: Decimal.new("1000.00"),
               notes: "Synthetic opening cash"
             })

    assert transaction.type == "deposit"
    assert transaction.date == ~D[2026-01-02]
    assert Decimal.equal?(transaction.amount, Decimal.new("1000.00"))
    assert transaction.deposit_account_id == deposit_account.id
    assert transaction.notes == "Synthetic opening cash"
  end

  test "create withdrawal transaction", %{portfolio: portfolio, deposit_account: deposit_account} do
    assert {:ok, transaction} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: deposit_account.id,
               type: "withdrawal",
               date: ~D[2026-01-03],
               currency_code: "EUR",
               amount: Decimal.new("125.50")
             })

    assert transaction.type == "withdrawal"
    assert Decimal.equal?(transaction.amount, Decimal.new("125.50"))
  end

  test "deposit transaction increases derived cash balance", %{
    portfolio: portfolio,
    deposit_account: deposit_account
  } do
    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: deposit_account.id,
               type: "deposit",
               date: ~D[2026-01-09],
               currency_code: "EUR",
               amount: Decimal.new("1000.00")
             })

    cash_balances = Ledger.cash_balances_for_portfolio(portfolio.id)

    assert Decimal.equal?(
             cash_balances.balances[{deposit_account.id, "EUR"}],
             Decimal.new("1000.00")
           )

    assert cash_balances.balances[{deposit_account.id, "USD"}] == nil
  end

  test "withdrawal transaction decreases derived cash balance", %{
    portfolio: portfolio,
    deposit_account: deposit_account
  } do
    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: deposit_account.id,
               type: "withdrawal",
               date: ~D[2026-01-09],
               currency_code: "EUR",
               amount: Decimal.new("75.00")
             })

    cash_balances = Ledger.cash_balances_for_portfolio(portfolio.id)

    assert Decimal.equal?(
             cash_balances.balances[{deposit_account.id, "EUR"}],
             Decimal.new("-75.00")
           )
  end

  test "deposit and withdrawal combine to the expected net cash balance", %{
    portfolio: portfolio,
    deposit_account: deposit_account
  } do
    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: deposit_account.id,
               type: "deposit",
               date: ~D[2026-01-09],
               currency_code: "EUR",
               amount: Decimal.new("300.00")
             })

    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: deposit_account.id,
               type: "withdrawal",
               date: ~D[2026-01-09],
               currency_code: "EUR",
               amount: Decimal.new("125.00")
             })

    cash_balances = Ledger.cash_balances_for_portfolio(portfolio.id)

    assert Decimal.equal?(
             cash_balances.balances[{deposit_account.id, "EUR"}],
             Decimal.new("175.00")
           )
  end

  test "deposit and withdrawal from another portfolio do not affect current portfolio cash balance",
       %{
         portfolio: portfolio,
         other_portfolio: other_portfolio,
         deposit_account: deposit_account
       } do
    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: deposit_account.id,
               type: "deposit",
               date: ~D[2026-01-09],
               currency_code: "EUR",
               amount: Decimal.new("100.00")
             })

    {:ok, other_deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: other_portfolio.id,
        name: "Other Cash",
        currency_code: "EUR"
      })

    base_cash_balances = Ledger.cash_balances_for_portfolio(portfolio.id)

    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: other_portfolio.id,
               deposit_account_id: other_deposit_account.id,
               type: "deposit",
               date: ~D[2026-01-10],
               currency_code: "EUR",
               amount: Decimal.new("250.00")
             })

    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: other_portfolio.id,
               deposit_account_id: other_deposit_account.id,
               type: "withdrawal",
               date: ~D[2026-01-10],
               currency_code: "EUR",
               amount: Decimal.new("50.00")
             })

    current_cash_balances = Ledger.cash_balances_for_portfolio(portfolio.id)

    assert current_cash_balances.balances == base_cash_balances.balances
  end

  test "deposit and withdrawal do not affect security positions", %{
    portfolio: portfolio,
    deposit_account: deposit_account,
    securities_account: securities_account,
    security: security
  } do
    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-11],
        currency_code: "EUR",
        quantity: Decimal.new("12.00"),
        price: Decimal.new("10.00"),
        amount: Decimal.new("120.00")
      })

    positions_before = Ledger.positions_for_portfolio(portfolio.id)

    assert Decimal.equal?(
             positions_before[{securities_account.id, security.id}],
             Decimal.new("12.00")
           )

    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: deposit_account.id,
               type: "deposit",
               date: ~D[2026-01-12],
               currency_code: "EUR",
               amount: Decimal.new("50.00")
             })

    assert {:ok, _} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: deposit_account.id,
               type: "withdrawal",
               date: ~D[2026-01-12],
               currency_code: "EUR",
               amount: Decimal.new("25.00")
             })

    positions_after = Ledger.positions_for_portfolio(portfolio.id)
    assert positions_after == positions_before
  end

  test "create buy transaction", %{
    portfolio: portfolio,
    securities_account: securities_account,
    security: security
  } do
    assert {:ok, transaction} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               securities_account_id: securities_account.id,
               security_id: security.id,
               type: "buy",
               date: ~D[2026-01-04],
               currency_code: "EUR",
               quantity: Decimal.new("5.25"),
               price: Decimal.new("100.00"),
               amount: Decimal.new("525.00"),
               fees: Decimal.new("1.50"),
               taxes: Decimal.new("0.00")
             })

    assert transaction.type == "buy"
    assert Decimal.equal?(transaction.quantity, Decimal.new("5.25"))
    assert Decimal.equal?(transaction.price, Decimal.new("100.00"))
  end

  test "create sell transaction", %{
    portfolio: portfolio,
    securities_account: securities_account,
    security: security
  } do
    assert {:ok, transaction} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               securities_account_id: securities_account.id,
               security_id: security.id,
               type: "sell",
               date: ~D[2026-01-05],
               currency_code: "EUR",
               quantity: Decimal.new("2.00"),
               price: Decimal.new("110.00"),
               amount: Decimal.new("220.00"),
               fees: Decimal.new("1.00"),
               taxes: Decimal.new("0.50")
             })

    assert transaction.type == "sell"
    assert Decimal.equal?(transaction.quantity, Decimal.new("2.00"))
    assert Decimal.equal?(transaction.amount, Decimal.new("220.00"))
  end

  test "sell transaction decreases positions for account and security", %{
    portfolio: portfolio,
    securities_account: securities_account,
    security: security
  } do
    {:ok, _buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-14],
        currency_code: "EUR",
        quantity: Decimal.new("10.00"),
        price: Decimal.new("100.00"),
        amount: Decimal.new("1000.00")
      })

    {:ok, _sell} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2026-01-15],
        currency_code: "EUR",
        quantity: Decimal.new("3.00"),
        price: Decimal.new("110.00"),
        amount: Decimal.new("330.00")
      })

    positions = Ledger.positions_for_portfolio(portfolio.id)

    assert Decimal.equal?(
             positions[{securities_account.id, security.id}],
             Decimal.new("7.00")
           )
  end

  test "create dividend transaction", %{
    portfolio: portfolio,
    deposit_account: deposit_account,
    security: security
  } do
    assert {:ok, transaction} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: deposit_account.id,
               security_id: security.id,
               type: "dividend",
               date: ~D[2026-01-06],
               currency_code: "EUR",
               amount: Decimal.new("12.34"),
               taxes: Decimal.new("3.21")
             })

    assert transaction.type == "dividend"
    assert transaction.security_id == security.id
    assert Decimal.equal?(transaction.amount, Decimal.new("12.34"))
  end

  test "reject invalid transaction type", %{portfolio: portfolio} do
    assert {:error, changeset} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               type: "transfer",
               date: ~D[2026-01-07],
               currency_code: "EUR",
               amount: Decimal.new("100.00")
             })

    assert %{type: ["is invalid"]} = errors_on(changeset)
  end

  test "reject missing required fields by type", %{portfolio: portfolio} do
    assert {:error, deposit_changeset} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               type: "deposit",
               date: ~D[2026-01-08],
               currency_code: "EUR"
             })

    assert %{
             deposit_account_id: ["can't be blank"],
             amount: ["can't be blank"]
           } = errors_on(deposit_changeset)

    assert {:error, buy_changeset} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               type: "buy",
               date: ~D[2026-01-08],
               currency_code: "EUR",
               amount: Decimal.new("100.00")
             })

    assert %{
             securities_account_id: ["can't be blank"],
             security_id: ["can't be blank"],
             quantity: ["can't be blank"],
             price: ["can't be blank"]
           } = errors_on(buy_changeset)
  end

  test "deposit and withdrawal reject non-positive amounts", %{
    portfolio: portfolio,
    deposit_account: deposit_account
  } do
    deposit_attrs = %{
      portfolio_id: portfolio.id,
      deposit_account_id: deposit_account.id,
      type: "deposit",
      date: ~D[2026-01-10],
      currency_code: "EUR"
    }

    assert {:error, zero_deposit_changeset} =
             Ledger.create_transaction(Map.put(deposit_attrs, :amount, Decimal.new("0.00")))

    assert %{amount: ["must be greater than 0"]} = errors_on(zero_deposit_changeset)

    assert {:error, negative_deposit_changeset} =
             Ledger.create_transaction(Map.put(deposit_attrs, :amount, Decimal.new("-1.00")))

    assert %{amount: ["must be greater than 0"]} = errors_on(negative_deposit_changeset)

    withdrawal_attrs = %{deposit_attrs | type: "withdrawal"}

    assert {:error, zero_withdrawal_changeset} =
             Ledger.create_transaction(Map.put(withdrawal_attrs, :amount, Decimal.new("0.00")))

    assert %{amount: ["must be greater than 0"]} = errors_on(zero_withdrawal_changeset)

    assert {:error, negative_withdrawal_changeset} =
             Ledger.create_transaction(Map.put(withdrawal_attrs, :amount, Decimal.new("-1.00")))

    assert %{amount: ["must be greater than 0"]} = errors_on(negative_withdrawal_changeset)
  end

  test "buy rejects non-positive quantity, price, and amount", %{
    portfolio: portfolio,
    securities_account: securities_account,
    security: security
  } do
    attrs = %{
      portfolio_id: portfolio.id,
      securities_account_id: securities_account.id,
      security_id: security.id,
      type: "buy",
      date: ~D[2026-01-11],
      currency_code: "EUR",
      quantity: Decimal.new("1.00"),
      price: Decimal.new("100.00"),
      amount: Decimal.new("100.00")
    }

    assert {:error, zero_quantity_changeset} =
             Ledger.create_transaction(Map.put(attrs, :quantity, Decimal.new("0.00")))

    assert %{quantity: ["must be greater than 0"]} = errors_on(zero_quantity_changeset)

    assert {:error, negative_quantity_changeset} =
             Ledger.create_transaction(Map.put(attrs, :quantity, Decimal.new("-1.00")))

    assert %{quantity: ["must be greater than 0"]} = errors_on(negative_quantity_changeset)

    assert {:error, zero_price_changeset} =
             Ledger.create_transaction(Map.put(attrs, :price, Decimal.new("0.00")))

    assert %{price: ["must be greater than 0"]} = errors_on(zero_price_changeset)

    assert {:error, negative_price_changeset} =
             Ledger.create_transaction(Map.put(attrs, :price, Decimal.new("-1.00")))

    assert %{price: ["must be greater than 0"]} = errors_on(negative_price_changeset)

    assert {:error, negative_amount_changeset} =
             Ledger.create_transaction(Map.put(attrs, :amount, Decimal.new("-1.00")))

    assert %{amount: ["must be greater than 0"]} = errors_on(negative_amount_changeset)
  end

  test "sell rejects missing securities account, missing security, and non-positive values", %{
    portfolio: portfolio,
    securities_account: securities_account,
    security: security
  } do
    attrs = %{
      portfolio_id: portfolio.id,
      securities_account_id: securities_account.id,
      security_id: security.id,
      type: "sell",
      date: ~D[2026-01-16],
      currency_code: "EUR",
      quantity: Decimal.new("1.00"),
      price: Decimal.new("100.00"),
      amount: Decimal.new("100.00")
    }

    assert {:error, missing_sa_changeset} =
             Ledger.create_transaction(Map.delete(attrs, :securities_account_id))

    assert %{securities_account_id: ["can't be blank"]} = errors_on(missing_sa_changeset)

    assert {:error, missing_security_changeset} =
             Ledger.create_transaction(Map.delete(attrs, :security_id))

    assert %{security_id: ["can't be blank"]} = errors_on(missing_security_changeset)

    assert {:error, zero_quantity_changeset} =
             Ledger.create_transaction(Map.put(attrs, :quantity, Decimal.new("0.00")))

    assert %{quantity: ["must be greater than 0"]} = errors_on(zero_quantity_changeset)

    assert {:error, zero_price_changeset} =
             Ledger.create_transaction(Map.put(attrs, :price, Decimal.new("0.00")))

    assert %{price: ["must be greater than 0"]} = errors_on(zero_price_changeset)

    assert {:error, zero_amount_changeset} =
             Ledger.create_transaction(Map.put(attrs, :amount, Decimal.new("0.00")))

    assert %{amount: ["must be greater than 0"]} = errors_on(zero_amount_changeset)
  end

  test "sell rejects negative fees and taxes", %{
    portfolio: portfolio,
    securities_account: securities_account,
    security: security
  } do
    attrs = %{
      portfolio_id: portfolio.id,
      securities_account_id: securities_account.id,
      security_id: security.id,
      type: "sell",
      date: ~D[2026-01-12],
      currency_code: "EUR",
      quantity: Decimal.new("1.00"),
      price: Decimal.new("100.00"),
      amount: Decimal.new("100.00"),
      fees: Decimal.new("0.00"),
      taxes: Decimal.new("0.00")
    }

    assert {:error, negative_fees_changeset} =
             Ledger.create_transaction(Map.put(attrs, :fees, Decimal.new("-1.00")))

    assert %{fees: ["must be greater than or equal to 0"]} = errors_on(negative_fees_changeset)

    assert {:error, negative_taxes_changeset} =
             Ledger.create_transaction(Map.put(attrs, :taxes, Decimal.new("-1.00")))

    assert %{taxes: ["must be greater than or equal to 0"]} = errors_on(negative_taxes_changeset)
  end

  test "dividend rejects zero amount and negative taxes", %{
    portfolio: portfolio,
    deposit_account: deposit_account,
    security: security
  } do
    attrs = %{
      portfolio_id: portfolio.id,
      deposit_account_id: deposit_account.id,
      security_id: security.id,
      type: "dividend",
      date: ~D[2026-01-13],
      currency_code: "EUR",
      amount: Decimal.new("10.00"),
      taxes: Decimal.new("0.00")
    }

    assert {:error, zero_amount_changeset} =
             Ledger.create_transaction(Map.put(attrs, :amount, Decimal.new("0.00")))

    assert %{amount: ["must be greater than 0"]} = errors_on(zero_amount_changeset)

    assert {:error, negative_taxes_changeset} =
             Ledger.create_transaction(Map.put(attrs, :taxes, Decimal.new("-1.00")))

    assert %{taxes: ["must be greater than or equal to 0"]} = errors_on(negative_taxes_changeset)
  end

  test "reject unknown foreign keys", %{portfolio: portfolio, deposit_account: deposit_account} do
    assert {:error, portfolio_changeset} =
             Ledger.create_transaction(%{
               portfolio_id: 9_999_999,
               deposit_account_id: deposit_account.id,
               type: "deposit",
               date: ~D[2026-01-09],
               currency_code: "EUR",
               amount: Decimal.new("100.00")
             })

    assert %{portfolio: ["does not exist"]} = errors_on(portfolio_changeset)

    assert {:error, currency_changeset} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: deposit_account.id,
               type: "deposit",
               date: ~D[2026-01-09],
               currency_code: "ZZZ",
               amount: Decimal.new("100.00")
             })

    assert %{currency: ["does not exist"]} = errors_on(currency_changeset)

    assert {:error, account_changeset} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: 9_999_999,
               type: "deposit",
               date: ~D[2026-01-09],
               currency_code: "EUR",
               amount: Decimal.new("100.00")
             })

    assert %{deposit_account_id: ["does not exist"]} = errors_on(account_changeset)

    assert {:error, security_changeset} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               deposit_account_id: deposit_account.id,
               security_id: 9_999_999,
               type: "dividend",
               date: ~D[2026-01-09],
               currency_code: "EUR",
               amount: Decimal.new("100.00")
             })

    assert %{security: ["does not exist"]} = errors_on(security_changeset)
  end

  test "list transactions for one portfolio only and newest first", %{
    portfolio: portfolio,
    other_portfolio: other_portfolio,
    deposit_account: deposit_account
  } do
    {:ok, oldest} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "deposit",
        date: ~D[2026-01-02],
        currency_code: "EUR",
        amount: Decimal.new("100.00")
      })

    {:ok, newest} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "deposit",
        date: ~D[2026-01-03],
        currency_code: "EUR",
        amount: Decimal.new("200.00")
      })

    {:ok, other_deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: other_portfolio.id,
        name: "Other Cash",
        currency_code: "EUR"
      })

    {:ok, _other_transaction} =
      Ledger.create_transaction(%{
        portfolio_id: other_portfolio.id,
        deposit_account_id: other_deposit_account.id,
        type: "deposit",
        date: ~D[2026-01-04],
        currency_code: "EUR",
        amount: Decimal.new("300.00")
      })

    assert [listed_newest, listed_oldest] = Ledger.list_transactions_for_portfolio(portfolio.id)
    assert listed_newest.id == newest.id
    assert listed_oldest.id == oldest.id
  end

  test "cash balance missing impact rows are scoped to the selected portfolio", %{
    portfolio: portfolio,
    other_portfolio: other_portfolio,
    security: security
  } do
    {:ok, unlinked_primary_depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        name: "Primary Unlinked Depot",
        currency_code: "EUR"
      })

    {:ok, primary_buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: unlinked_primary_depot.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-15],
        currency_code: "EUR",
        quantity: Decimal.new("1.00"),
        price: Decimal.new("100.00"),
        amount: Decimal.new("100.00")
      })

    {:ok, unlinked_other_depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: other_portfolio.id,
        name: "Other Unlinked Depot",
        currency_code: "EUR"
      })

    {:ok, other_buy} =
      Ledger.create_transaction(%{
        portfolio_id: other_portfolio.id,
        securities_account_id: unlinked_other_depot.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-16],
        currency_code: "EUR",
        quantity: Decimal.new("2.00"),
        price: Decimal.new("50.00"),
        amount: Decimal.new("100.00")
      })

    result = Ledger.cash_balances_for_portfolio(portfolio.id)
    [only_row] = result.missing_cash_impacts

    assert only_row.transaction_id == primary_buy.id
    assert only_row.type == "buy"
    refute Enum.any?(result.missing_cash_impacts, &(&1.transaction_id == other_buy.id))
  end

  test "cash balance from deposit and withdrawal", %{
    portfolio: portfolio,
    deposit_account: deposit_account
  } do
    {:ok, deposit} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "deposit",
        date: ~D[2026-02-01],
        currency_code: "EUR",
        amount: Decimal.new("1000.00")
      })

    {:ok, withdrawal} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "withdrawal",
        date: ~D[2026-02-02],
        currency_code: "EUR",
        amount: Decimal.new("125.25")
      })

    result = CashBalances.calculate([deposit, withdrawal])

    assert result.missing_cash_impacts == []

    assert Decimal.equal?(
             result.balances[{deposit_account.id, "EUR"}],
             Decimal.new("874.75")
           )
  end

  test "position from buy", %{
    portfolio: portfolio,
    securities_account: securities_account,
    security: security
  } do
    {:ok, buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-02-03],
        currency_code: "EUR",
        quantity: Decimal.new("3.50"),
        price: Decimal.new("100.00"),
        amount: Decimal.new("350.00")
      })

    positions = Positions.calculate([buy])

    assert Decimal.equal?(
             positions[{securities_account.id, security.id}],
             Decimal.new("3.50")
           )
  end

  test "position from buy and sell", %{
    portfolio: portfolio,
    securities_account: securities_account,
    security: security
  } do
    {:ok, buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-02-04],
        currency_code: "EUR",
        quantity: Decimal.new("10.00"),
        price: Decimal.new("100.00"),
        amount: Decimal.new("1000.00")
      })

    {:ok, sell} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2026-02-05],
        currency_code: "EUR",
        quantity: Decimal.new("4.25"),
        price: Decimal.new("110.00"),
        amount: Decimal.new("467.50")
      })

    positions = Positions.calculate([buy, sell])

    assert Decimal.equal?(
             positions[{securities_account.id, security.id}],
             Decimal.new("5.75")
           )
  end

  test "buy impacts linked reference deposit account", %{
    portfolio: portfolio,
    deposit_account: deposit_account,
    securities_account: securities_account,
    security: security
  } do
    {:ok, buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-02-06],
        currency_code: "EUR",
        quantity: Decimal.new("2.00"),
        price: Decimal.new("100.00"),
        amount: Decimal.new("200.00"),
        fees: Decimal.new("1.50"),
        taxes: Decimal.new("0.50")
      })

    result = Ledger.cash_balances_for_portfolio(portfolio.id)

    expected_cash_impact =
      Decimal.add(
        Decimal.add(Decimal.new("200.00"), Decimal.new("1.50")),
        Decimal.new("0.50")
      )

    assert result.missing_cash_impacts == []

    assert Decimal.equal?(
             result.balances[{deposit_account.id, "EUR"}],
             Decimal.negate(expected_cash_impact)
           )

    direct_result = CashBalances.calculate([Repo.preload(buy, :securities_account)])

    assert Decimal.equal?(
             result.balances[{deposit_account.id, "EUR"}],
             direct_result.balances[{deposit_account.id, "EUR"}]
           )
  end

  test "sell impacts linked reference deposit account", %{
    portfolio: portfolio,
    deposit_account: deposit_account,
    securities_account: securities_account,
    security: security
  } do
    {:ok, _sell} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2026-02-07],
        currency_code: "EUR",
        quantity: Decimal.new("2.00"),
        price: Decimal.new("110.00"),
        amount: Decimal.new("220.00"),
        fees: Decimal.new("1.00"),
        taxes: Decimal.new("0.50")
      })

    result = Ledger.cash_balances_for_portfolio(portfolio.id)

    assert result.missing_cash_impacts == []

    assert Decimal.equal?(
             result.balances[{deposit_account.id, "EUR"}],
             Decimal.new("218.50")
           )
  end

  test "sell without linked reference deposit account reports missing cash impact", %{
    portfolio: portfolio,
    security: security
  } do
    {:ok, unlinked_securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        name: "Unlinked Sell Depot",
        currency_code: "EUR"
      })

    {:ok, sell} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: unlinked_securities_account.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2026-02-14],
        currency_code: "EUR",
        quantity: Decimal.new("1.00"),
        price: Decimal.new("120.00"),
        amount: Decimal.new("120.00")
      })

    result = Ledger.cash_balances_for_portfolio(portfolio.id)

    assert result.balances == %{}

    assert [
             %{
               transaction_id: sell_transaction_id,
               type: "sell",
               reason: :missing_reference_deposit_account
             }
           ] = result.missing_cash_impacts

    assert sell_transaction_id == sell.id
  end

  test "buy without linked reference deposit account records missing cash impact", %{
    portfolio: portfolio,
    security: security
  } do
    {:ok, unlinked_securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        name: "Unlinked Depot",
        currency_code: "EUR"
      })

    {:ok, buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: unlinked_securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-02-08],
        currency_code: "EUR",
        quantity: Decimal.new("1.00"),
        price: Decimal.new("100.00"),
        amount: Decimal.new("100.00")
      })

    result = Ledger.cash_balances_for_portfolio(portfolio.id)
    buy_id = buy.id

    assert result.balances == %{}

    assert [
             %{
               transaction_id: ^buy_id,
               type: "buy",
               reason: :missing_reference_deposit_account
             }
           ] = result.missing_cash_impacts
  end

  test "multiple portfolios do not mix in derived balances and positions", %{
    portfolio: portfolio,
    other_portfolio: other_portfolio,
    deposit_account: deposit_account,
    securities_account: securities_account,
    security: security
  } do
    {:ok, _deposit} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "deposit",
        date: ~D[2026-02-09],
        currency_code: "EUR",
        amount: Decimal.new("100.00")
      })

    {:ok, _buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-02-09],
        currency_code: "EUR",
        quantity: Decimal.new("1.00"),
        price: Decimal.new("25.00"),
        amount: Decimal.new("25.00")
      })

    {:ok, other_deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: other_portfolio.id,
        name: "Other Cash",
        currency_code: "EUR"
      })

    {:ok, other_securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: other_portfolio.id,
        reference_deposit_account_id: other_deposit_account.id,
        name: "Other Depot",
        currency_code: "EUR"
      })

    {:ok, _other_deposit} =
      Ledger.create_transaction(%{
        portfolio_id: other_portfolio.id,
        deposit_account_id: other_deposit_account.id,
        type: "deposit",
        date: ~D[2026-02-09],
        currency_code: "EUR",
        amount: Decimal.new("500.00")
      })

    {:ok, _other_buy} =
      Ledger.create_transaction(%{
        portfolio_id: other_portfolio.id,
        securities_account_id: other_securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-02-09],
        currency_code: "EUR",
        quantity: Decimal.new("3.00"),
        price: Decimal.new("25.00"),
        amount: Decimal.new("75.00")
      })

    cash_result = Ledger.cash_balances_for_portfolio(portfolio.id)
    positions = Ledger.positions_for_portfolio(portfolio.id)

    assert Map.keys(cash_result.balances) == [{deposit_account.id, "EUR"}]
    assert Decimal.equal?(cash_result.balances[{deposit_account.id, "EUR"}], Decimal.new("75.00"))
    assert Map.keys(positions) == [{securities_account.id, security.id}]
    assert Decimal.equal?(positions[{securities_account.id, security.id}], Decimal.new("1.00"))
  end

  test "multiple securities do not mix in derived positions", %{
    portfolio: portfolio,
    securities_account: securities_account,
    security: first_security
  } do
    {:ok, second_security} =
      Catalog.create_security(%{
        name: "Synthetic Bond",
        symbol: "BND",
        currency_code: "EUR"
      })

    {:ok, _first_buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: first_security.id,
        type: "buy",
        date: ~D[2026-02-10],
        currency_code: "EUR",
        quantity: Decimal.new("2.00"),
        price: Decimal.new("50.00"),
        amount: Decimal.new("100.00")
      })

    {:ok, _second_buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: second_security.id,
        type: "buy",
        date: ~D[2026-02-10],
        currency_code: "EUR",
        quantity: Decimal.new("7.00"),
        price: Decimal.new("20.00"),
        amount: Decimal.new("140.00")
      })

    positions = Ledger.positions_for_portfolio(portfolio.id)

    assert Decimal.equal?(
             positions[{securities_account.id, first_security.id}],
             Decimal.new("2.00")
           )

    assert Decimal.equal?(
             positions[{securities_account.id, second_security.id}],
             Decimal.new("7.00")
           )
  end

  test "buy in another portfolio does not alter current portfolio derived state", %{
    portfolio: portfolio,
    other_portfolio: other_portfolio,
    deposit_account: deposit_account,
    securities_account: securities_account,
    security: security
  } do
    {:ok, other_deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: other_portfolio.id,
        name: "Other Cash",
        currency_code: "EUR"
      })

    {:ok, other_securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: other_portfolio.id,
        reference_deposit_account_id: other_deposit_account.id,
        name: "Other Depot",
        currency_code: "EUR"
      })

    {:ok, _primary_buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-02-10],
        currency_code: "EUR",
        quantity: Decimal.new("4.00"),
        price: Decimal.new("100.00"),
        amount: Decimal.new("400.00"),
        fees: Decimal.new("1.00"),
        taxes: Decimal.new("0.00")
      })

    {:ok, _other_buy} =
      Ledger.create_transaction(%{
        portfolio_id: other_portfolio.id,
        securities_account_id: other_securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-02-11],
        currency_code: "EUR",
        quantity: Decimal.new("2.00"),
        price: Decimal.new("200.00"),
        amount: Decimal.new("400.00"),
        fees: Decimal.new("2.00"),
        taxes: Decimal.new("0.00")
      })

    primary_cash = Ledger.cash_balances_for_portfolio(portfolio.id)
    other_cash = Ledger.cash_balances_for_portfolio(other_portfolio.id)
    primary_positions = Ledger.positions_for_portfolio(portfolio.id)
    other_positions = Ledger.positions_for_portfolio(other_portfolio.id)

    assert Decimal.equal?(
             primary_cash.balances[{deposit_account.id, "EUR"}],
             Decimal.new("-401.00")
           )

    assert Decimal.equal?(
             other_cash.balances[{other_deposit_account.id, "EUR"}],
             Decimal.new("-402.00")
           )

    assert Map.has_key?(primary_positions, {securities_account.id, security.id})
    assert Map.has_key?(other_positions, {other_securities_account.id, security.id})

    assert Map.get(other_positions, {securities_account.id, security.id}, Decimal.new("0")) ==
             Decimal.new("0")

    assert Map.get(
             primary_positions,
             {other_securities_account.id, security.id},
             Decimal.new("0")
           ) == Decimal.new("0")
  end

  test "sell in another portfolio does not alter current portfolio derived state", %{
    portfolio: portfolio,
    other_portfolio: other_portfolio,
    deposit_account: deposit_account,
    securities_account: securities_account,
    security: security
  } do
    {:ok, primary_buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-03-01],
        currency_code: "EUR",
        quantity: Decimal.new("5.00"),
        price: Decimal.new("100.00"),
        amount: Decimal.new("500.00")
      })

    {:ok, other_deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: other_portfolio.id,
        name: "Other Sell Cash",
        currency_code: "EUR"
      })

    {:ok, other_securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: other_portfolio.id,
        reference_deposit_account_id: other_deposit_account.id,
        name: "Other Sell Depot",
        currency_code: "EUR"
      })

    {:ok, _other_sell} =
      Ledger.create_transaction(%{
        portfolio_id: other_portfolio.id,
        securities_account_id: other_securities_account.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2026-03-02],
        currency_code: "EUR",
        quantity: Decimal.new("2.00"),
        price: Decimal.new("110.00"),
        amount: Decimal.new("220.00")
      })

    primary_positions = Ledger.positions_for_portfolio(portfolio.id)
    primary_cash = Ledger.cash_balances_for_portfolio(portfolio.id)
    primary_transactions = Ledger.list_transactions_for_portfolio(portfolio.id)
    other_transactions = Ledger.list_transactions_for_portfolio(other_portfolio.id)

    assert Decimal.equal?(
             primary_positions[{securities_account.id, security.id}],
             Decimal.new("5.00")
           )

    assert Decimal.equal?(
             primary_cash.balances[{deposit_account.id, "EUR"}],
             Decimal.new("-500.00")
           )

    assert Enum.any?(primary_transactions, fn tx -> tx.id == primary_buy.id end)
    assert Enum.any?(other_transactions, fn tx -> tx.type == "sell" end)
    refute Enum.any?(primary_transactions, fn tx -> tx.type == "sell" end)
  end

  test "integration flow derives transactions, position, and cash balance", %{
    portfolio: portfolio,
    deposit_account: deposit_account,
    securities_account: securities_account,
    security: security
  } do
    {:ok, deposit} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "deposit",
        date: ~D[2026-03-01],
        currency_code: "EUR",
        amount: Decimal.new("1000.00")
      })

    {:ok, buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-03-02],
        currency_code: "EUR",
        quantity: Decimal.new("5.00"),
        price: Decimal.new("50.00"),
        amount: Decimal.new("250.00"),
        fees: Decimal.new("2.00"),
        taxes: Decimal.new("1.00")
      })

    {:ok, sell} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2026-03-03],
        currency_code: "EUR",
        quantity: Decimal.new("2.00"),
        price: Decimal.new("60.00"),
        amount: Decimal.new("120.00"),
        fees: Decimal.new("1.00"),
        taxes: Decimal.new("0.50")
      })

    assert [listed_sell, listed_buy, listed_deposit] =
             Ledger.list_transactions_for_portfolio(portfolio.id)

    assert listed_sell.id == sell.id
    assert listed_buy.id == buy.id
    assert listed_deposit.id == deposit.id

    positions = Ledger.positions_for_portfolio(portfolio.id)
    cash_result = Ledger.cash_balances_for_portfolio(portfolio.id)

    assert Decimal.equal?(
             positions[{securities_account.id, security.id}],
             Decimal.new("3.00")
           )

    assert cash_result.missing_cash_impacts == []

    assert Decimal.equal?(
             cash_result.balances[{deposit_account.id, "EUR"}],
             Decimal.new("865.50")
           )
  end
end
