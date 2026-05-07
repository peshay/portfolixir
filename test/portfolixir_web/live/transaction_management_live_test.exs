defmodule PortfolixirWeb.TransactionManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  setup context do
    Catalog.ensure_mvp_currencies!()

    if context[:no_portfolio] do
      %{}
    else
      {:ok, portfolio} =
        Portfolios.create_portfolio(%{name: "Primary", base_currency_code: "EUR"})

      {:ok, deposit_account} =
        Portfolios.create_deposit_account(%{
          portfolio_id: portfolio.id,
          name: "Settlement Cash",
          currency_code: "EUR"
        })

      {:ok, securities_account} =
        Portfolios.create_securities_account(%{
          portfolio_id: portfolio.id,
          reference_deposit_account_id: deposit_account.id,
          name: "Main Depot",
          currency_code: "EUR"
        })

      {:ok, security} =
        Catalog.create_security(%{
          name: "Synthetic ETF",
          symbol: "SYN",
          currency_code: "EUR"
        })

      %{
        portfolio: portfolio,
        deposit_account: deposit_account,
        securities_account: securities_account,
        security: security
      }
    end
  end

  test "visiting /transactions renders the transactions workspace", %{conn: conn} do
    {:ok, view, html} = live(conn, "/transactions")

    assert html =~ "Transactions"
    assert has_element?(view, "#current-portfolio-selector")
    assert has_element?(view, "a[href=\"/transactions\"]")
    assert has_element?(view, "#current-portfolio-select")
    assert has_element?(view, "#ledger-workspace.app-shell-workspace-grid")
    assert has_element?(view, "#transaction-history-panel[data-priority='primary']")
    assert has_element?(view, "#ledger-kpis .app-shell-stat-card", "Transactions")
    assert has_element?(view, "#ledger-kpis .app-shell-stat-card", "Positions")
    assert has_element?(view, "#positions[data-priority='secondary']")
    assert has_element?(view, "#transaction-form-panel[data-priority='secondary']")
    assert has_element?(view, "#transaction-form")
  end

  test "transactions workspace keeps history primary and form scannable", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account,
    securities_account: securities_account,
    security: security
  } do
    {:ok, _deposit} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "deposit",
        date: ~D[2026-04-01],
        currency_code: "EUR",
        amount: Decimal.new("1000.00")
      })

    {:ok, _buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-04-02],
        currency_code: "EUR",
        quantity: Decimal.new("5.00"),
        price: Decimal.new("50.00"),
        amount: Decimal.new("250.00")
      })

    {:ok, view, html} = live(conn, "/transactions")

    assert html =~ "Deposit and withdrawal use the deposit account"
    assert html =~ "Dividend uses the deposit account and a security"

    assert html =~
             "Buy and sell use the securities account plus security, quantity, price and amount."

    assert html =~ "Amount is the gross transaction amount."
    assert has_element?(view, "#position-list")
    assert has_element?(view, "#transaction-history-panel .app-shell-table-wrapper")

    assert has_element?(
             view,
             "#transaction-list-caption",
             "Transaction history table with date, type, account, security, quantity, price, amount, currency, and notes."
           )

    assert has_element?(
             view,
             "#position-list-caption",
             "Positions overview table with securities account, security, and quantity."
           )

    assert has_element?(view, "#transaction-form.app-shell-form-grid")
    assert has_element?(view, "#transaction-form .app-shell-fieldset")

    assert html =~ ~r/id="transaction-history-panel".*id="positions"/s
  end

  test "renders an empty state when there are no transactions", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/transactions")

    assert html =~ "No transactions yet"
    assert html =~ "Record the first ledger transaction."
  end

  test "shows a current portfolio selector for multiple portfolios", %{
    conn: conn,
    portfolio: portfolio
  } do
    _second_portfolio = create_portfolio("Secondary")

    {:ok, view, html} = live(conn, "/transactions")

    assert has_element?(view, "#current-portfolio-selector")
    assert has_element?(view, "#current-portfolio-select")

    assert has_element?(
             view,
             "#current-portfolio-select option[value='#{portfolio.id}'][selected]"
           )

    assert has_element?(
             view,
             "#current-portfolio-select option[value='#{portfolio.id}']",
             "Primary"
           )

    assert html =~ "Current portfolio"
    assert html =~ "Select portfolio"
  end

  test "switching current portfolio updates visible transactions", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account
  } do
    second_portfolio = create_portfolio("Secondary")
    second_deposit = create_deposit_account(second_portfolio, "Secondary Cash")

    {:ok, _primary_deposit} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "deposit",
        date: ~D[2026-04-01],
        currency_code: "EUR",
        amount: Decimal.new("100.00"),
        notes: "Primary portfolio deposit"
      })

    {:ok, _secondary_deposit} =
      Ledger.create_transaction(%{
        portfolio_id: second_portfolio.id,
        deposit_account_id: second_deposit.id,
        type: "deposit",
        date: ~D[2026-04-02],
        currency_code: "EUR",
        amount: Decimal.new("200.00"),
        notes: "Secondary portfolio deposit"
      })

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(view, "#transaction-list", "Primary portfolio deposit")
    refute has_element?(view, "#transaction-list", "Secondary portfolio deposit")

    assert select_current_portfolio(view, second_portfolio.id) =~ "Secondary portfolio deposit"
    assert has_element?(view, "#transaction-list", "Secondary portfolio deposit")
    refute has_element?(view, "#transaction-list", "Primary portfolio deposit")
  end

  test "switching current portfolio updates position rows", %{
    conn: conn,
    portfolio: portfolio,
    securities_account: securities_account,
    security: security
  } do
    secondary_portfolio = create_portfolio("Secondary")
    secondary_deposit = create_deposit_account(secondary_portfolio, "Secondary Cash")

    secondary_securities_account =
      create_securities_account(
        secondary_portfolio,
        secondary_deposit,
        "Secondary Depot"
      )

    secondary_security = create_security("Secondary synthetic ETF", "SYN2")

    {:ok, _primary_buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-04-03],
        currency_code: "EUR",
        quantity: Decimal.new("10.00"),
        price: Decimal.new("10.00"),
        amount: Decimal.new("100.00")
      })

    {:ok, _secondary_buy} =
      Ledger.create_transaction(%{
        portfolio_id: secondary_portfolio.id,
        securities_account_id: secondary_securities_account.id,
        security_id: secondary_security.id,
        type: "buy",
        date: ~D[2026-04-04],
        currency_code: "EUR",
        quantity: Decimal.new("20.00"),
        price: Decimal.new("20.00"),
        amount: Decimal.new("400.00")
      })

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(view, "#position-list", "Main Depot")
    refute has_element?(view, "#position-list", "Secondary Depot")
    assert has_element?(view, "#position-list", "Synthetic ETF")
    refute has_element?(view, "#position-list", "Secondary synthetic ETF")

    assert select_current_portfolio(view, secondary_portfolio.id) =~ "Secondary synthetic ETF"
    assert has_element?(view, "#position-list", "Secondary Depot")
    assert has_element?(view, "#position-list", "Secondary synthetic ETF")
    refute has_element?(view, "#position-list", "Synthetic ETF")
    refute has_element?(view, "#position-list", "Main Depot")
  end

  test "creates a transaction for the selected portfolio", %{
    conn: conn,
    portfolio: portfolio
  } do
    second_portfolio = create_portfolio("Secondary")
    second_deposit = create_deposit_account(second_portfolio, "Secondary Cash")

    {:ok, view, _html} = live(conn, "/transactions")

    assert select_current_portfolio(view, second_portfolio.id) =~ "Secondary Cash"

    html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "deposit",
          "date" => "2026-04-05",
          "currency_code" => "EUR",
          "amount" => "500.00",
          "deposit_account_id" => "#{second_deposit.id}",
          "notes" => "Scoped to secondary portfolio"
        }
      })
      |> render_submit()

    assert html =~ "Transaction created."
    assert html =~ "Scoped to secondary portfolio"
    assert html =~ "deposit"
    assert html =~ "Secondary Cash"

    second_transactions = Ledger.list_transactions_for_portfolio(second_portfolio.id)
    first_transactions = Ledger.list_transactions_for_portfolio(portfolio.id)

    assert Enum.any?(
             second_transactions,
             &(&1.notes == "Scoped to secondary portfolio")
           )

    refute Enum.any?(
             first_transactions,
             &(&1.notes == "Scoped to secondary portfolio")
           )
  end

  test "scopes deposit account options to the selected portfolio", %{
    conn: conn,
    deposit_account: deposit_account
  } do
    second_portfolio = create_portfolio("Secondary")
    second_deposit = create_deposit_account(second_portfolio, "Secondary Cash")

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(
             view,
             "#transaction-deposit-account option[value='#{deposit_account.id}']"
           )

    refute has_element?(view, "#transaction-deposit-account option[value='#{second_deposit.id}']")

    assert select_current_portfolio(view, second_portfolio.id) =~ "Secondary Cash"

    assert has_element?(view, "#transaction-deposit-account option[value='#{second_deposit.id}']")

    refute has_element?(
             view,
             "#transaction-deposit-account option[value='#{deposit_account.id}']"
           )
  end

  test "scopes securities account options to the selected portfolio", %{
    conn: conn,
    securities_account: securities_account
  } do
    second_portfolio = create_portfolio("Secondary")
    second_deposit = create_deposit_account(second_portfolio, "Secondary Cash")

    second_securities_account =
      create_securities_account(second_portfolio, second_deposit, "Secondary Depot")

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(
             view,
             "#transaction-securities-account option[value='#{securities_account.id}']"
           )

    refute has_element?(
             view,
             "#transaction-securities-account option[value='#{second_securities_account.id}']"
           )

    assert select_current_portfolio(view, second_portfolio.id) =~ "Secondary Depot"

    assert has_element?(
             view,
             "#transaction-securities-account option[value='#{second_securities_account.id}']"
           )

    refute has_element?(
             view,
             "#transaction-securities-account option[value='#{securities_account.id}']"
           )
  end

  test "invalid current portfolio selection does not switch context or expose other portfolio data",
       %{
         conn: conn,
         deposit_account: deposit_account,
         securities_account: securities_account
       } do
    second_portfolio = create_portfolio("Secondary")
    second_deposit = create_deposit_account(second_portfolio, "Secondary Cash")

    {:ok, _} =
      Portfolios.create_deposit_account(%{
        portfolio_id: second_portfolio.id,
        name: "Another Cash",
        currency_code: "EUR"
      })

    {:ok, second_securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: second_portfolio.id,
        name: "Another Depot",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(
             view,
             "#current-portfolio-select option[value='#{deposit_account.portfolio_id}'][selected]"
           )

    assert has_element?(
             view,
             "#transaction-deposit-account option[value='#{deposit_account.id}']"
           )

    refute has_element?(view, "#transaction-deposit-account option[value='#{second_deposit.id}']")

    assert has_element?(
             view,
             "#transaction-securities-account option[value='#{securities_account.id}']"
           )

    html =
      render_change(view, "select_current_portfolio", %{"portfolio_id" => "invalid-portfolio-id"})

    assert has_element?(
             view,
             "#current-portfolio-select option[value='#{deposit_account.portfolio_id}'][selected]"
           )

    assert has_element?(
             view,
             "#transaction-deposit-account option[value='#{deposit_account.id}']"
           )

    refute has_element?(view, "#transaction-deposit-account option[value='#{second_deposit.id}']")

    assert has_element?(
             view,
             "#transaction-securities-account option[value='#{securities_account.id}']"
           )

    assert html =~ "Primary"

    refute has_element?(
             view,
             "#transaction-securities-account option[value='#{second_securities_account.id}']"
           )
  end

  @tag :no_portfolio
  test "renders a focused first-run state when no portfolio exists", %{conn: conn} do
    {:ok, view, html} = live(conn, "/transactions")

    assert has_element?(view, "#transaction-first-run.app-shell-onboarding")
    assert has_element?(view, "#transaction-first-run h2", "Create a portfolio first")

    assert html =~
             "Transactions need a portfolio, accounts and securities before they can be recorded."

    assert has_element?(view, "#transaction-first-run a[href='/accounts']", "Go to Accounts")
    refute has_element?(view, "#ledger-kpis")
    refute has_element?(view, "#transaction-form")
  end

  test "creates a deposit transaction through /transactions", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account
  } do
    {:ok, view, _html} = live(conn, "/transactions")

    html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "deposit",
          "date" => "2026-04-01",
          "currency_code" => "EUR",
          "amount" => "1000.00",
          "deposit_account_id" => "#{deposit_account.id}",
          "notes" => "Synthetic opening deposit"
        }
      })
      |> render_submit()

    assert html =~ "Transaction created."
    assert has_element?(view, "#transaction-list", "2026-04-01")
    assert has_element?(view, "#transaction-list", "Deposit")
    assert html =~ "1000.00"
    assert html =~ "Settlement Cash"
    assert has_element?(view, "#transaction-list", "Synthetic opening deposit")

    selected_portfolio_transactions = Ledger.list_transactions_for_portfolio(portfolio.id)

    assert Enum.any?(
             selected_portfolio_transactions,
             &(&1.notes == "Synthetic opening deposit")
           )
  end

  test "creates a dividend transaction through /transactions", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account,
    security: security
  } do
    {:ok, view, _html} = live(conn, "/transactions")

    html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "dividend",
          "date" => "2026-05-01",
          "currency_code" => "EUR",
          "amount" => "42.00",
          "deposit_account_id" => "#{deposit_account.id}",
          "security_id" => "#{security.id}",
          "notes" => "Quarterly distribution"
        }
      })
      |> render_submit()

    assert html =~ "Transaction created."
    assert has_element?(view, "#transaction-list", "2026-05-01")
    assert has_element?(view, "#transaction-list", "Dividend")
    assert has_element?(view, "#transaction-list", "Settlement Cash")
    assert has_element?(view, "#transaction-list", "Synthetic ETF")
    assert has_element?(view, "#transaction-list", "42.00")
    assert has_element?(view, "#transaction-list", "Quarterly distribution")

    selected_portfolio_transactions = Ledger.list_transactions_for_portfolio(portfolio.id)

    assert Enum.any?(
             selected_portfolio_transactions,
             &(&1.notes == "Quarterly distribution")
           )
  end

  test "creates a dividend transaction for the selected portfolio", %{
    conn: conn,
    portfolio: portfolio,
    security: security
  } do
    second_portfolio = create_portfolio("Secondary")
    second_deposit = create_deposit_account(second_portfolio, "Secondary Cash")

    {:ok, view, _html} = live(conn, "/transactions")

    assert select_current_portfolio(view, second_portfolio.id) =~ "Secondary Cash"

    html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "dividend",
          "date" => "2026-05-02",
          "currency_code" => "EUR",
          "amount" => "18.00",
          "deposit_account_id" => "#{second_deposit.id}",
          "security_id" => "#{security.id}",
          "notes" => "Scoped dividend"
        }
      })
      |> render_submit()

    assert html =~ "Transaction created."
    assert has_element?(view, "#transaction-list", "Scoped dividend")
    assert has_element?(view, "#transaction-list", "Dividend")

    second_transactions = Ledger.list_transactions_for_portfolio(second_portfolio.id)
    first_transactions = Ledger.list_transactions_for_portfolio(portfolio.id)

    assert Enum.any?(second_transactions, &(&1.notes == "Scoped dividend"))
    refute Enum.any?(first_transactions, &(&1.notes == "Scoped dividend"))
  end

  test "creates a withdrawal transaction through /transactions", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account
  } do
    {:ok, view, _html} = live(conn, "/transactions")

    html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "withdrawal",
          "date" => "2026-04-02",
          "currency_code" => "EUR",
          "amount" => "250.00",
          "deposit_account_id" => "#{deposit_account.id}",
          "notes" => "Funds out"
        }
      })
      |> render_submit()

    assert html =~ "Transaction created."
    assert has_element?(view, "#transaction-list", "2026-04-02")
    assert has_element?(view, "#transaction-list", "Withdrawal")
    assert has_element?(view, "#transaction-list", "Settlement Cash")
    assert has_element?(view, "#transaction-list", "250.00")
    assert has_element?(view, "#transaction-list", "Funds out")

    selected_portfolio_transactions = Ledger.list_transactions_for_portfolio(portfolio.id)

    assert Enum.any?(selected_portfolio_transactions, &(&1.notes == "Funds out"))
  end

  test "German transaction type labels render while stored values remain English", %{
    conn: conn,
    deposit_account: deposit_account
  } do
    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(view, "#transaction-type option[value='deposit']", "Einzahlung")
    assert has_element?(view, "#transaction-type option[value='withdrawal']", "Auszahlung")
    assert has_element?(view, "#transaction-type option[value='buy']", "Kauf")
    assert has_element?(view, "#transaction-type option[value='sell']", "Verkauf")
    assert has_element?(view, "#transaction-type option[value='dividend']", "Dividende")

    html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "deposit",
          "date" => "2026-04-01",
          "currency_code" => "EUR",
          "amount" => "1000.00",
          "deposit_account_id" => "#{deposit_account.id}"
        }
      })
      |> render_submit()

    assert html =~ "Einzahlung"

    [transaction] = Ledger.list_transactions()
    assert transaction.type == "deposit"
  end

  test "creates a buy transaction using linked securities account and security", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account,
    securities_account: securities_account,
    security: security
  } do
    {:ok, view, _html} = live(conn, "/transactions")

    html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "buy",
          "date" => "2026-04-02",
          "currency_code" => "EUR",
          "amount" => "250.00",
          "securities_account_id" => "#{securities_account.id}",
          "security_id" => "#{security.id}",
          "quantity" => "5.00",
          "price" => "50.00",
          "fees" => "1.00",
          "taxes" => "0.00"
        }
      })
      |> render_submit()

    assert html =~ "Transaction created."
    assert html =~ "Buy"
    assert html =~ "Synthetic ETF"
    assert html =~ "5.00"
    assert html =~ "50.00"
    assert has_element?(view, "#position-list", "Main Depot")
    assert has_element?(view, "#position-list", "5.00")
    assert has_element?(view, "#transaction-list", "Main Depot")
    assert has_element?(view, "#transaction-list", "Synthetic ETF")

    cash_balances = Ledger.cash_balances_for_portfolio(portfolio.id)
    assert cash_balances.missing_cash_impacts == []

    assert Decimal.equal?(
             cash_balances.balances[{deposit_account.id, "EUR"}],
             Decimal.new("-251.00")
           )
  end

  test "creates a sell transaction reducing position in the current portfolio", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account,
    securities_account: securities_account,
    security: security
  } do
    {:ok, _buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-04-10],
        currency_code: "EUR",
        quantity: Decimal.new("5.00"),
        price: Decimal.new("100.00"),
        amount: Decimal.new("500.00")
      })

    {:ok, view, _html} = live(conn, "/transactions")

    html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "sell",
          "date" => "2026-04-11",
          "currency_code" => "EUR",
          "amount" => "250.00",
          "securities_account_id" => "#{securities_account.id}",
          "security_id" => "#{security.id}",
          "quantity" => "2.00",
          "price" => "125.00",
          "fees" => "1.00",
          "taxes" => "1.00",
          "notes" => "Sell part"
        }
      })
      |> render_submit()

    assert html =~ "Transaction created."
    assert has_element?(view, "#transaction-list", "Sell")
    assert has_element?(view, "#transaction-list", "Main Depot")
    assert has_element?(view, "#transaction-list", "Sell part")
    assert has_element?(view, "#position-list", "3.00")

    cash_balances = Ledger.cash_balances_for_portfolio(portfolio.id)

    assert cash_balances.missing_cash_impacts == []

    assert Decimal.equal?(
             cash_balances.balances[{deposit_account.id, "EUR"}],
             Decimal.new("-252.00")
           )
  end

  test "creates a buy transaction for the selected portfolio", %{
    conn: conn,
    portfolio: portfolio,
    security: security
  } do
    second_portfolio = create_portfolio("Secondary")
    second_deposit = create_deposit_account(second_portfolio, "Secondary Cash")

    second_securities_account =
      create_securities_account(
        second_portfolio,
        second_deposit,
        "Secondary Depot"
      )

    {:ok, view, _html} = live(conn, "/transactions")

    assert select_current_portfolio(view, second_portfolio.id) =~ "Secondary Cash"

    html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "buy",
          "date" => "2026-04-06",
          "currency_code" => "EUR",
          "amount" => "100.00",
          "securities_account_id" => "#{second_securities_account.id}",
          "security_id" => "#{security.id}",
          "quantity" => "1.00",
          "price" => "100.00",
          "notes" => "Secondary scoped buy"
        }
      })
      |> render_submit()

    assert html =~ "Transaction created."
    assert has_element?(view, "#transaction-list", "Secondary scoped buy")
    assert has_element?(view, "#transaction-list", "Secondary Depot")
    assert has_element?(view, "#position-list", "Secondary Depot")
    refute has_element?(view, "#position-list", "Main Depot")

    second_transactions = Ledger.list_transactions_for_portfolio(second_portfolio.id)
    first_transactions = Ledger.list_transactions_for_portfolio(portfolio.id)

    assert Enum.any?(second_transactions, &(&1.notes == "Secondary scoped buy"))
    refute Enum.any?(first_transactions, &(&1.notes == "Secondary scoped buy"))
  end

  test "shows validation errors for buy input", %{
    conn: conn,
    securities_account: securities_account,
    security: security
  } do
    {:ok, view, _html} = live(conn, "/transactions")

    assert_missing_securities_account =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "buy",
          "date" => "2026-04-07",
          "currency_code" => "EUR",
          "amount" => "100.00",
          "security_id" => "#{security.id}",
          "quantity" => "1.00",
          "price" => "100.00"
        }
      })
      |> render_submit()

    assert assert_missing_securities_account =~ "id=\"transaction-form-error\""
    assert assert_missing_securities_account =~ "Securities"
    assert assert_missing_securities_account =~ "blank"
    assert has_element?(view, "#transaction-form-error[role='alert']")

    assert_missing_security =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "buy",
          "date" => "2026-04-07",
          "currency_code" => "EUR",
          "amount" => "100.00",
          "securities_account_id" => "#{securities_account.id}",
          "quantity" => "1.00",
          "price" => "100.00"
        }
      })
      |> render_submit()

    assert assert_missing_security =~ "Security"

    assert_quantity_error =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "buy",
          "date" => "2026-04-07",
          "currency_code" => "EUR",
          "amount" => "100.00",
          "securities_account_id" => "#{securities_account.id}",
          "security_id" => "#{security.id}",
          "quantity" => "0.00",
          "price" => "100.00"
        }
      })
      |> render_submit()

    assert assert_quantity_error =~ "Quantity must be greater than 0"

    assert_price_error =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "buy",
          "date" => "2026-04-07",
          "currency_code" => "EUR",
          "amount" => "100.00",
          "securities_account_id" => "#{securities_account.id}",
          "security_id" => "#{security.id}",
          "quantity" => "1.00",
          "price" => "0.00"
        }
      })
      |> render_submit()

    assert assert_price_error =~ "Price must be greater than 0"

    assert_amount_error =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "buy",
          "date" => "2026-04-07",
          "currency_code" => "EUR",
          "amount" => "0.00",
          "securities_account_id" => "#{securities_account.id}",
          "security_id" => "#{security.id}",
          "quantity" => "1.00",
          "price" => "100.00"
        }
      })
      |> render_submit()

    assert assert_amount_error =~ "Amount must be greater than 0"
  end

  test "shows validation errors for sell input", %{
    conn: conn,
    securities_account: securities_account,
    security: security
  } do
    {:ok, view, _html} = live(conn, "/transactions")

    missing_securities_account =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "sell",
          "date" => "2026-04-12",
          "currency_code" => "EUR",
          "amount" => "100.00",
          "security_id" => "#{security.id}",
          "quantity" => "1.00",
          "price" => "100.00"
        }
      })
      |> render_submit()

    assert missing_securities_account =~ "id=\"transaction-form-error\""
    assert missing_securities_account =~ "Securities"

    missing_security =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "sell",
          "date" => "2026-04-12",
          "currency_code" => "EUR",
          "amount" => "100.00",
          "securities_account_id" => "#{securities_account.id}",
          "quantity" => "1.00",
          "price" => "100.00"
        }
      })
      |> render_submit()

    assert missing_security =~ "Security"

    invalid_quantity =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "sell",
          "date" => "2026-04-12",
          "currency_code" => "EUR",
          "amount" => "100.00",
          "securities_account_id" => "#{securities_account.id}",
          "security_id" => "#{security.id}",
          "quantity" => "0.00",
          "price" => "100.00"
        }
      })
      |> render_submit()

    assert invalid_quantity =~ "Quantity must be greater than 0"

    invalid_price =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "sell",
          "date" => "2026-04-12",
          "currency_code" => "EUR",
          "amount" => "100.00",
          "securities_account_id" => "#{securities_account.id}",
          "security_id" => "#{security.id}",
          "quantity" => "1.00",
          "price" => "0.00"
        }
      })
      |> render_submit()

    assert invalid_price =~ "Price must be greater than 0"

    invalid_amount =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "sell",
          "date" => "2026-04-12",
          "currency_code" => "EUR",
          "amount" => "0.00",
          "securities_account_id" => "#{securities_account.id}",
          "security_id" => "#{security.id}",
          "quantity" => "1.00",
          "price" => "100.00"
        }
      })
      |> render_submit()

    assert invalid_amount =~ "Amount must be greater than 0"
  end

  test "shows validation errors for missing deposit transaction input", %{
    conn: conn,
    deposit_account: deposit_account
  } do
    {:ok, view, _html} = live(conn, "/transactions")

    missing_deposit_account =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "deposit",
          "date" => "2026-04-14",
          "currency_code" => "EUR",
          "amount" => "100.00",
          "notes" => "Missing account"
        }
      })
      |> render_submit()

    assert missing_deposit_account =~ "id=\"transaction-form-error\""
    assert missing_deposit_account =~ "Deposit account"

    missing_amount =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "deposit",
          "date" => "2026-04-14",
          "currency_code" => "EUR",
          "amount" => "",
          "deposit_account_id" => "#{deposit_account.id}",
          "notes" => "Missing amount"
        }
      })
      |> render_submit()

    assert missing_amount =~ "id=\"transaction-form-error\""
    assert missing_amount =~ "Amount"
    assert missing_amount =~ "value=\"\""
    assert missing_amount =~ "Missing amount"

    assert missing_amount =~ "deposit"
  end

  test "shows validation errors for invalid withdrawal transaction amounts", %{
    conn: conn,
    deposit_account: deposit_account
  } do
    {:ok, view, _html} = live(conn, "/transactions")

    zero_amount =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "withdrawal",
          "date" => "2026-04-15",
          "currency_code" => "EUR",
          "amount" => "0.00",
          "deposit_account_id" => "#{deposit_account.id}"
        }
      })
      |> render_submit()

    assert zero_amount =~ "id=\"transaction-form-error\""
    assert zero_amount =~ "Amount must be greater than 0"

    negative_amount =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "withdrawal",
          "date" => "2026-04-15",
          "currency_code" => "EUR",
          "amount" => "-1.00",
          "deposit_account_id" => "#{deposit_account.id}"
        }
      })
      |> render_submit()

    assert negative_amount =~ "id=\"transaction-form-error\""
    assert negative_amount =~ "Amount must be greater than 0"
  end

  test "creates a withdrawal transaction for the selected portfolio", %{
    conn: conn,
    portfolio: portfolio
  } do
    second_portfolio = create_portfolio("Secondary")
    second_deposit = create_deposit_account(second_portfolio, "Secondary Cash")

    {:ok, view, _html} = live(conn, "/transactions")

    assert select_current_portfolio(view, second_portfolio.id) =~ "Secondary Cash"

    html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "withdrawal",
          "date" => "2026-04-16",
          "currency_code" => "EUR",
          "amount" => "300.00",
          "deposit_account_id" => "#{second_deposit.id}",
          "notes" => "Scoped withdrawal"
        }
      })
      |> render_submit()

    assert html =~ "Transaction created."
    assert has_element?(view, "#transaction-list", "Scoped withdrawal")
    assert has_element?(view, "#transaction-list", "Withdrawal")
    assert has_element?(view, "#transaction-list", "Secondary Cash")

    second_transactions = Ledger.list_transactions_for_portfolio(second_portfolio.id)
    first_transactions = Ledger.list_transactions_for_portfolio(portfolio.id)

    assert Enum.any?(second_transactions, &(&1.notes == "Scoped withdrawal"))
    refute Enum.any?(first_transactions, &(&1.notes == "Scoped withdrawal"))
  end

  test "shows validation error and keeps submitted values for invalid transaction", %{
    conn: conn,
    deposit_account: deposit_account
  } do
    {:ok, view, _html} = live(conn, "/transactions")

    html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "deposit",
          "date" => "2026-04-03",
          "currency_code" => "EUR",
          "amount" => "0.00",
          "deposit_account_id" => "#{deposit_account.id}",
          "notes" => "Keep this value"
        }
      })
      |> render_submit()

    assert html =~ "id=\"transaction-form-error\""
    assert has_element?(view, "#transaction-form-error[role='alert']")
    assert html =~ "Amount must be greater than 0"
    assert html =~ "value=\"0.00\""
    assert html =~ "Keep this value"
  end

  test "shows validation errors for invalid dividend input", %{
    conn: conn,
    deposit_account: deposit_account,
    security: security
  } do
    {:ok, view, _html} = live(conn, "/transactions")

    missing_deposit_html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "dividend",
          "date" => "2026-05-03",
          "currency_code" => "EUR",
          "amount" => "42.00",
          "security_id" => "#{security.id}",
          "notes" => "Missing deposit account"
        }
      })
      |> render_submit()

    assert missing_deposit_html =~ "id=\"transaction-form-error\""
    assert missing_deposit_html =~ "Deposit account"

    {:ok, view, _html} = live(conn, "/transactions")

    missing_security_html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "dividend",
          "date" => "2026-05-03",
          "currency_code" => "EUR",
          "amount" => "42.00",
          "deposit_account_id" => "#{deposit_account.id}",
          "security_id" => "",
          "notes" => "Missing security"
        }
      })
      |> render_submit()

    assert missing_security_html =~ "Security"

    {:ok, view, _html} = live(conn, "/transactions")

    missing_amount_html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "dividend",
          "date" => "2026-05-03",
          "currency_code" => "EUR",
          "deposit_account_id" => "#{deposit_account.id}",
          "security_id" => "#{security.id}",
          "amount" => "",
          "notes" => "Missing amount"
        }
      })
      |> render_submit()

    assert missing_amount_html =~ "Amount"

    {:ok, view, _html} = live(conn, "/transactions")

    non_positive_amount_html =
      view
      |> form("#transaction-form", %{
        "transaction" => %{
          "type" => "dividend",
          "date" => "2026-05-03",
          "currency_code" => "EUR",
          "deposit_account_id" => "#{deposit_account.id}",
          "security_id" => "#{security.id}",
          "amount" => "0.00",
          "notes" => "Non-positive amount"
        }
      })
      |> render_submit()

    assert non_positive_amount_html =~ "Amount must be greater than 0"
    assert non_positive_amount_html =~ "Non-positive amount"
  end

  test "security dropdown is portfolio-shared", %{
    conn: conn,
    security: security
  } do
    second_portfolio = create_portfolio("Secondary")
    create_deposit_account(second_portfolio, "Secondary Cash")
    secondary_security = create_security("Second synthetic ETF", "SYN2")

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(view, "#transaction-security option[value='#{security.id}']")
    assert has_element?(view, "#transaction-security option[value='#{secondary_security.id}']")
    assert select_current_portfolio(view, second_portfolio.id)
    assert has_element?(view, "#transaction-security option[value='#{security.id}']")
    assert has_element?(view, "#transaction-security option[value='#{secondary_security.id}']")
  end

  test "created transactions appear newest first", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account
  } do
    {:ok, _oldest} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "deposit",
        date: ~D[2026-04-01],
        currency_code: "EUR",
        amount: Decimal.new("100.00"),
        notes: "Oldest transaction"
      })

    {:ok, _newest} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "withdrawal",
        date: ~D[2026-04-04],
        currency_code: "EUR",
        amount: Decimal.new("20.00"),
        notes: "Newest transaction"
      })

    {:ok, _view, html} = live(conn, "/transactions")

    assert html =~ "Oldest transaction"
    assert html =~ "Newest transaction"
    assert html =~ ~r/Newest transaction.*Oldest transaction/s
  end

  test "shows derived positions after buy and sell", %{
    conn: conn,
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
        date: ~D[2026-04-01],
        currency_code: "EUR",
        quantity: Decimal.new("10.00"),
        price: Decimal.new("50.00"),
        amount: Decimal.new("500.00")
      })

    {:ok, _sell} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2026-04-02],
        currency_code: "EUR",
        quantity: Decimal.new("4.25"),
        price: Decimal.new("55.00"),
        amount: Decimal.new("233.75")
      })

    {:ok, view, html} = live(conn, "/transactions")

    assert has_element?(view, "#positions")
    assert html =~ "Main Depot"
    assert html =~ "Synthetic ETF"
    assert html =~ "5.75"
  end

  test "German portfolio selector and transaction terminology remain visible", %{
    conn: conn,
    portfolio: portfolio
  } do
    _second_portfolio = create_portfolio("Zweite")

    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, view, html} = live(conn, "/transactions")

    assert has_element?(
             view,
             "#current-portfolio-select option[value='#{portfolio.id}'][selected]"
           )

    assert html =~ "Aktuelles Portfolio"
    assert html =~ "Portfolio auswählen"
    assert html =~ "Buchungsverlauf"
    assert html =~ "Buchung anlegen"

    assert html =~
             "Das aktuelle Portfolio steuert, welche Buchungen und Bestände angezeigt werden."

    assert html =~ "Buchungen"
    assert html =~ "Stückzahl"
    assert html =~ "Betrag"
    assert html =~ "Verrechnungskonto"
    assert html =~ "Depot"
    assert html =~ "Wertpapier"
    assert html =~ "Gebühren"
    assert html =~ "Steuern"
  end

  defp create_portfolio(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{
        name: name,
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp create_deposit_account(portfolio, name) do
    {:ok, account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    account
  end

  defp create_security(name, symbol) do
    {:ok, security} =
      Catalog.create_security(%{
        name: name,
        symbol: symbol,
        currency_code: "EUR"
      })

    security
  end

  defp create_securities_account(portfolio, deposit_account, name) do
    {:ok, account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        reference_deposit_account_id: deposit_account.id,
        name: name,
        currency_code: "EUR"
      })

    account
  end

  defp select_current_portfolio(view, portfolio_id) do
    view
    |> form("#current-portfolio-form", %{"portfolio_id" => "#{portfolio_id}"})
    |> render_change()
  end
end
