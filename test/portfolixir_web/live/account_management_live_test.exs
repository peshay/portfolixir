defmodule PortfolixirWeb.AccountManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  setup do
    {:ok, _currency} = Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})
    :ok
  end

  test "visiting /accounts renders the accounts workspace", %{conn: conn} do
    create_portfolio("Primary portfolio")

    {:ok, view, html} = live(conn, "/accounts")

    assert html =~ "Accounts"
    assert has_element?(view, "a[href=\"/accounts\"]")
    assert has_element?(view, "#account-workspace.app-shell-workspace-grid")
    assert has_element?(view, "#account-overview")
    assert has_element?(view, "#account-kpis .app-shell-stat-card", "Deposit accounts")
    assert has_element?(view, "#account-kpis .app-shell-stat-card", "Securities accounts")
    assert has_element?(view, "#account-kpis .app-shell-stat-card", "Cash balances")
    assert has_element?(view, "#account-kpis .app-shell-stat-card", "Cash impact warnings")
    assert has_element?(view, "#deposit-accounts")
    assert has_element?(view, "#securities-accounts")
  end

  test "accounts workspace provides responsive sections and secondary forms", %{conn: conn} do
    portfolio = create_portfolio("Primary portfolio")
    deposit_account = create_deposit_account(portfolio, "Settlement Cash")

    {:ok, _deposit} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "deposit",
        date: ~D[2026-04-01],
        currency_code: "EUR",
        amount: Decimal.new("1000.00")
      })

    {:ok, view, _html} = live(conn, "/accounts")

    assert has_element?(view, "#current-portfolio.app-shell-summary-strip")
    assert has_element?(view, "#account-kpis.app-shell-stat-grid")
    assert has_element?(view, "#deposit-accounts .app-shell-table-wrapper")
    assert has_element?(view, "#cash-balances .app-shell-table-wrapper")
    assert has_element?(view, "#securities-accounts[data-priority='primary']")
    assert has_element?(view, "#account-forms[data-priority='secondary']")
    assert has_element?(view, "#deposit-account-form.app-shell-form-grid")
    assert has_element?(view, "#securities-account-form.app-shell-form-grid")
    assert has_element?(view, ".app-shell-warning-note")
  end

  test "renders an empty state when there is no portfolio", %{conn: conn} do
    {:ok, view, html} = live(conn, "/accounts")

    assert has_element?(view, "#portfolio-onboarding.app-shell-onboarding")
    assert has_element?(view, "#portfolio-onboarding h2", "Create your first portfolio")
    assert html =~ "A portfolio is the container for accounts, transactions and derived reports."
    assert html =~ "No portfolio yet"

    assert html =~
             "Create this portfolio to unlock account setup, cash balances and ledger workflows."

    assert has_element?(view, "#portfolio-form")
    refute has_element?(view, "#account-kpis")
    refute has_element?(view, "#deposit-account-form")
    refute has_element?(view, "#securities-account-form")
  end

  test "creates a minimal portfolio", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/accounts")

    html =
      view
      |> form("#portfolio-form", %{
        "portfolio" => %{
          "name" => "Long Term",
          "base_currency_code" => "EUR",
          "description" => "Synthetic planning portfolio"
        }
      })
      |> render_submit()

    assert html =~ "Portfolio created."
    assert html =~ "Long Term"
    assert html =~ "Deposit accounts"
    assert html =~ "Securities accounts"
  end

  test "portfolio validation errors render as alerts", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/accounts")

    html =
      view
      |> form("#portfolio-form", %{
        "portfolio" => %{
          "name" => "",
          "base_currency_code" => "",
          "description" => "Missing required fields"
        }
      })
      |> render_submit()

    assert html =~ "id=\"portfolio-form-error\""
    assert has_element?(view, "#portfolio-form-error[role='alert']")
  end

  test "creates a deposit account for the current portfolio", %{conn: conn} do
    create_portfolio("Primary portfolio")

    {:ok, view, _html} = live(conn, "/accounts")

    html =
      view
      |> form("#deposit-account-form", %{
        "deposit_account" => %{
          "name" => "Settlement Cash",
          "currency_code" => "EUR",
          "notes" => "Synthetic fixture account"
        }
      })
      |> render_submit()

    assert html =~ "Deposit account created."
    assert html =~ "Settlement Cash"
    assert html =~ "EUR"
  end

  test "creates a securities account linked to a deposit account", %{conn: conn} do
    portfolio = create_portfolio("Primary portfolio")
    deposit_account = create_deposit_account(portfolio, "Reference Cash")

    {:ok, view, _html} = live(conn, "/accounts")

    html =
      view
      |> form("#securities-account-form", %{
        "securities_account" => %{
          "name" => "Main Depot",
          "currency_code" => "EUR",
          "reference_deposit_account_id" => "#{deposit_account.id}",
          "notes" => "Synthetic fixture account"
        }
      })
      |> render_submit()

    assert html =~ "Securities account created."
    assert html =~ "Main Depot"
    assert html =~ "Reference Cash"
  end

  test "securities account from another portfolio cannot link to wrong deposit account", %{
    conn: conn
  } do
    current_portfolio = create_portfolio("Current portfolio")
    create_deposit_account(current_portfolio, "Current Cash")
    other_portfolio = create_portfolio("Other portfolio")
    other_deposit_account = create_deposit_account(other_portfolio, "Other Cash")

    {:ok, view, _html} = live(conn, "/accounts")

    refute has_element?(
             view,
             "#securities-account-reference-deposit-account option[value='#{other_deposit_account.id}']"
           )

    html =
      render_submit(view, "create_securities_account", %{
        "securities_account" => %{
          "name" => "Broken Depot",
          "currency_code" => "EUR",
          "reference_deposit_account_id" => "#{other_deposit_account.id}"
        }
      })

    assert html =~ "id=\"securities-account-form-error\""
    assert html =~ "Reference deposit account"
    refute html =~ "<td>Broken Depot</td>"
  end

  test "lists only accounts for the current portfolio", %{conn: conn} do
    current_portfolio = create_portfolio("Current portfolio")
    other_portfolio = create_portfolio("Other portfolio")

    create_deposit_account(current_portfolio, "Current Cash")
    create_deposit_account(other_portfolio, "Other Cash")

    {:ok, _current_securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: current_portfolio.id,
        name: "Current Depot",
        currency_code: "EUR"
      })

    {:ok, _other_securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: other_portfolio.id,
        name: "Other Depot",
        currency_code: "EUR"
      })

    {:ok, _view, html} = live(conn, "/accounts")

    assert html =~ "Current Cash"
    assert html =~ "Current Depot"
    refute html =~ "Other Cash"
    refute html =~ "Other Depot"
  end

  test "shows derived cash balances after deposit and buy", %{conn: conn} do
    portfolio = create_portfolio("Primary portfolio")
    deposit_account = create_deposit_account(portfolio, "Settlement Cash")
    securities_account = create_securities_account(portfolio, deposit_account, "Main Depot")
    security = create_security("Synthetic ETF", "SYN")

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

    {:ok, view, html} = live(conn, "/accounts")

    assert has_element?(view, "#cash-balances")
    assert html =~ "Settlement Cash"
    assert html =~ "750.00"
    assert html =~ "EUR"
  end

  test "shows a warning for missing cash impact", %{conn: conn} do
    portfolio = create_portfolio("Primary portfolio")
    securities_account = create_unlinked_securities_account(portfolio, "Unlinked Depot")
    security = create_security("Synthetic ETF", "SYN")

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

    {:ok, view, html} = live(conn, "/accounts")

    assert has_element?(view, "#missing-cash-impacts")
    assert html =~ "Missing cash impact"
    assert html =~ "Unlinked Depot"
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
    {:ok, deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    deposit_account
  end

  defp create_securities_account(portfolio, deposit_account, name) do
    {:ok, securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        reference_deposit_account_id: deposit_account.id,
        name: name,
        currency_code: "EUR"
      })

    securities_account
  end

  defp create_unlinked_securities_account(portfolio, name) do
    {:ok, securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    securities_account
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
end
