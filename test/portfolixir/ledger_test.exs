defmodule Portfolixir.LedgerTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
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
end
