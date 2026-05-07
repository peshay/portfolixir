defmodule PortfolixirWeb.AccountManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "visiting /accounts renders the accounts workspace", %{conn: conn} do
    create_portfolio("Primary portfolio")

    {:ok, view, html} = live(conn, "/accounts")

    assert has_element?(view, "#account-setup-onboarding")
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

    assert html =~ "Portfolio"
    assert html =~ "Deposit account"
    assert html =~ "Securities account"
    assert html =~ "Reference deposit account"
  end

  test "shows a current portfolio selector and selects the first portfolio by default", %{
    conn: conn
  } do
    first_portfolio = create_portfolio("Primary portfolio")
    create_portfolio("Secondary portfolio")

    {:ok, view, html} = live(conn, "/accounts")

    assert has_element?(view, "#current-portfolio-selector")

    assert has_element?(
             view,
             "#current-portfolio-select option[value='#{first_portfolio.id}'][selected]"
           )

    assert has_element?(
             view,
             "#current-portfolio-select option[value='#{first_portfolio.id}']",
             "Primary portfolio"
           )

    assert html =~ "Select portfolio"
  end

  test "switching current portfolio updates portfolio-scoped account data", %{conn: conn} do
    first_portfolio = create_portfolio("Primary portfolio")
    second_portfolio = create_portfolio("Secondary portfolio")

    first_cash = create_deposit_account(first_portfolio, "Primary Cash")
    second_cash = create_deposit_account(second_portfolio, "Secondary Cash")

    create_securities_account(first_portfolio, first_cash, "Primary Depot")
    create_securities_account(second_portfolio, second_cash, "Secondary Depot")

    {:ok, _deposit} =
      Ledger.create_transaction(%{
        portfolio_id: first_portfolio.id,
        deposit_account_id: first_cash.id,
        type: "deposit",
        date: ~D[2026-04-01],
        currency_code: "EUR",
        amount: Decimal.new("1000.00")
      })

    {:ok, _deposit} =
      Ledger.create_transaction(%{
        portfolio_id: second_portfolio.id,
        deposit_account_id: second_cash.id,
        type: "deposit",
        date: ~D[2026-04-02],
        currency_code: "EUR",
        amount: Decimal.new("1000.00")
      })

    {:ok, view, _html} = live(conn, "/accounts")

    assert has_element?(view, "#deposit-account-list", "Primary Cash")
    assert has_element?(view, "#securities-account-list", "Primary Depot")
    assert has_element?(view, "#cash-balance-list", "Primary Cash")
    refute has_element?(view, "#deposit-account-list", "Secondary Cash")
    refute has_element?(view, "#securities-account-list", "Secondary Depot")

    html = select_current_portfolio(view, second_portfolio.id)

    assert has_element?(view, "#deposit-account-list", "Secondary Cash")
    assert has_element?(view, "#securities-account-list", "Secondary Depot")
    assert has_element?(view, "#cash-balance-list", "Secondary Cash")
    refute has_element?(view, "#deposit-account-list", "Primary Cash")
    refute has_element?(view, "#securities-account-list", "Primary Depot")
    assert has_element?(view, "option[value='#{second_portfolio.id}'][selected]")
    assert html =~ "Secondary portfolio"
  end

  test "creates a deposit account for the selected current portfolio", %{conn: conn} do
    first_portfolio = create_portfolio("Primary portfolio")
    second_portfolio = create_portfolio("Secondary portfolio")

    create_deposit_account(first_portfolio, "Primary Cash")

    {:ok, view, _html} = live(conn, "/accounts")

    assert select_current_portfolio(view, second_portfolio.id) =~ "The current portfolio controls"

    html =
      view
      |> form("#deposit-account-form", %{
        "deposit_account" => %{
          "name" => "Secondary Cash",
          "currency_code" => "EUR",
          "notes" => "Synthetic fixture account"
        }
      })
      |> render_submit()

    assert html =~ "Deposit account created."
    assert has_element?(view, "#deposit-account-list", "Secondary Cash")

    refute Enum.any?(
             Portfolios.list_deposit_accounts_for_portfolio(first_portfolio.id),
             &(&1.name == "Secondary Cash")
           )

    assert Enum.any?(
             Portfolios.list_deposit_accounts_for_portfolio(second_portfolio.id),
             &(&1.name == "Secondary Cash")
           )
  end

  test "creates a securities account for the selected current portfolio", %{conn: conn} do
    first_portfolio = create_portfolio("Primary portfolio")
    second_portfolio = create_portfolio("Secondary portfolio")

    first_cash = create_deposit_account(first_portfolio, "Primary Cash")
    second_cash = create_deposit_account(second_portfolio, "Secondary Cash")

    {:ok, view, _html} = live(conn, "/accounts")

    assert select_current_portfolio(view, second_portfolio.id) =~ "The current portfolio controls"

    assert has_element?(
             view,
             "#securities-account-reference-deposit-account option[value='#{second_cash.id}']"
           )

    refute has_element?(
             view,
             "#securities-account-reference-deposit-account option[value='#{first_cash.id}']"
           )

    html =
      view
      |> form("#securities-account-form", %{
        "securities_account" => %{
          "name" => "Secondary Depot",
          "currency_code" => "EUR",
          "reference_deposit_account_id" => "#{second_cash.id}",
          "notes" => "Synthetic fixture account"
        }
      })
      |> render_submit()

    assert html =~ "Securities account created."
    assert has_element?(view, "#securities-account-list", "Secondary Depot")

    refute Enum.any?(
             Portfolios.list_securities_accounts_for_portfolio(first_portfolio.id),
             &(&1.name == "Secondary Depot")
           )
  end

  test "invalid current portfolio selection keeps the previous current portfolio", %{conn: conn} do
    first_portfolio = create_portfolio("Primary portfolio")
    create_portfolio("Secondary portfolio")

    {:ok, view, _html} = live(conn, "/accounts")

    assert has_element?(
             view,
             "#current-portfolio-select option[value='#{first_portfolio.id}'][selected]"
           )

    html =
      render_change(view, "select_current_portfolio", %{"portfolio_id" => "123456"})

    assert has_element?(
             view,
             "#current-portfolio-select option[value='#{first_portfolio.id}'][selected]"
           )

    assert html =~ "Primary portfolio"
  end

  test "invalid current portfolio selection does not expose data from other portfolio", %{
    conn: conn
  } do
    first_portfolio = create_portfolio("Primary portfolio")
    second_portfolio = create_portfolio("Secondary portfolio")

    create_deposit_account(first_portfolio, "Primary Cash")
    create_deposit_account(second_portfolio, "Secondary Cash")

    {:ok, _} =
      Portfolios.create_securities_account(%{
        portfolio_id: first_portfolio.id,
        name: "Primary Depot",
        currency_code: "EUR"
      })

    {:ok, _} =
      Portfolios.create_securities_account(%{
        portfolio_id: second_portfolio.id,
        name: "Secondary Depot",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/accounts")

    assert has_element?(view, "#deposit-account-list", "Primary Cash")
    assert has_element?(view, "#securities-account-list", "Primary Depot")
    refute has_element?(view, "#deposit-account-list", "Secondary Cash")
    refute has_element?(view, "#securities-account-list", "Secondary Depot")

    html =
      render_change(view, "select_current_portfolio", %{"portfolio_id" => "invalid-portfolio-id"})

    assert has_element?(
             view,
             "#current-portfolio-select option[value='#{first_portfolio.id}'][selected]"
           )

    assert has_element?(view, "#deposit-account-list", "Primary Cash")
    assert has_element?(view, "#securities-account-list", "Primary Depot")
    refute has_element?(view, "#deposit-account-list", "Secondary Cash")
    refute has_element?(view, "#securities-account-list", "Secondary Depot")
    assert html =~ "Primary portfolio"
  end

  test "accounts page explains setup flow in English terms", %{conn: conn} do
    create_portfolio("Primary portfolio")

    {:ok, view, html} = live(conn, "/accounts")

    assert has_element?(view, "#account-setup-onboarding.app-shell-section-card")
    assert has_element?(view, "#account-setup-onboarding h2", "How account setup works")

    assert html =~ "Create portfolio"
    assert html =~ "Create deposit account"
    assert html =~ "Create securities account"
    assert html =~ "Reference deposit account"
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

  test "account list tables include hidden captions", %{conn: conn} do
    portfolio = create_portfolio("Primary portfolio")
    deposit_account = create_deposit_account(portfolio, "Settlement Cash")
    create_securities_account(portfolio, deposit_account, "Primary Depot")

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

    assert has_element?(
             view,
             "#deposit-account-list-caption.app-shell-visually-hidden",
             "Deposit accounts with name, currency, and notes."
           )

    assert has_element?(
             view,
             "#cash-balance-list-caption.app-shell-visually-hidden",
             "Cash balances by deposit account and currency."
           )

    assert has_element?(
             view,
             "#securities-account-list-caption.app-shell-visually-hidden",
             "Securities accounts with reference deposit account and notes."
           )

    assert has_element?(view, "#deposit-account-list", "Settlement Cash")
  end

  test "renders an empty state when there is no portfolio", %{conn: conn} do
    {:ok, view, html} = live(conn, "/accounts")

    assert has_element?(view, "#portfolio-onboarding.app-shell-onboarding")
    assert has_element?(view, "#portfolio-onboarding h2", "Create your first portfolio")

    assert html =~ "Create this portfolio first so account setup appears next."

    assert html =~ "No portfolio yet"

    assert html =~
             "After you create this portfolio, you can set up a deposit account and then a securities account."

    assert has_element?(view, "#portfolio-form")
    refute has_element?(view, "#account-kpis")
    refute has_element?(view, "#deposit-account-form")
    refute has_element?(view, "#securities-account-form")
  end

  test "walks through the first-run account setup flow", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/accounts")

    refute has_element?(view, "#deposit-account-form")
    refute has_element?(view, "#securities-account-form")

    html =
      render_submit(view, "create_portfolio", %{
        "portfolio" => %{
          "name" => "Starter Portfolio",
          "base_currency_code" => "EUR",
          "description" => "Bootstrap setup portfolio"
        }
      })

    assert html =~ "Portfolio created."
    assert has_element?(view, "#deposit-account-form")
    assert has_element?(view, "#securities-account-form")

    html =
      view
      |> form("#deposit-account-form", %{
        "deposit_account" => %{
          "name" => "Starter Verrechnung",
          "currency_code" => "EUR",
          "notes" => "Synthetic fixture"
        }
      })
      |> render_submit()

    assert html =~ "Deposit account created."
    assert html =~ "Starter Verrechnung"

    portfolio = Portfolios.first_portfolio()
    [reference_account] = Portfolios.list_deposit_accounts_for_portfolio(portfolio.id)

    html =
      view
      |> form("#securities-account-form", %{
        "securities_account" => %{
          "name" => "Main Depot",
          "currency_code" => "EUR",
          "reference_deposit_account_id" => "#{reference_account.id}",
          "notes" => "Synthetic fixture"
        }
      })
      |> render_submit()

    assert html =~ "Securities account created."
    assert has_element?(view, "#securities-account-list")
    assert has_element?(view, "#securities-account-list", "Main Depot")
    assert has_element?(view, "#securities-account-list", "Starter Verrechnung")
  end

  test "fresh seeded setup offers EUR defaults for portfolio and account currency selects", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/accounts")

    assert has_element?(
             view,
             "select#portfolio-base-currency[name='portfolio[base_currency_code]'] option[value='EUR'][selected]"
           )

    html =
      view
      |> form("#portfolio-form", %{
        "portfolio" => %{
          "name" => "First Run Portfolio",
          "base_currency_code" => "EUR"
        }
      })
      |> render_submit()

    assert html =~ "Portfolio created."
    assert html =~ "First Run Portfolio"

    assert has_element?(
             view,
             "select#deposit-account-currency[name='deposit_account[currency_code]'] option[value='EUR'][selected]"
           )

    assert has_element?(
             view,
             "select#securities-account-currency[name='securities_account[currency_code]'] option[value='EUR'][selected]"
           )
  end

  test "German account terminology renders for currency and account forms", %{conn: conn} do
    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")
    create_portfolio("Primäres Portfolio")

    {:ok, view, html} = live(conn, "/accounts")

    assert html =~ "Kontenübersicht"
    assert html =~ "Portfolio anlegen"
    assert html =~ "Konten einrichten"
    assert html =~ "Währung"
    assert html =~ "Verrechnungskonto"
    assert html =~ "Depot"
    assert html =~ "Kontenübersicht"
    assert html =~ "Referenz-Verrechnungskonto"
    assert html =~ "Aktuelles Portfolio"

    assert html =~
             "Das aktuelle Portfolio steuert, welche Konten und späteren Buchungen angezeigt werden."

    assert has_element?(view, "#deposit-account-form")
    assert has_element?(view, "#securities-account-form")
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

    assert has_element?(
             view,
             "#missing-cash-impacts-table-caption.app-shell-visually-hidden",
             "Transactions missing a reference deposit account cash impact."
           )

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

  defp select_current_portfolio(view, portfolio_id) do
    view
    |> form("#current-portfolio-form", %{"portfolio_id" => "#{portfolio_id}"})
    |> render_change()
  end
end
