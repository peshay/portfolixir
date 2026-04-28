defmodule PortfolixirWeb.TransactionManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  setup do
    {:ok, _currency} = Catalog.create_currency(%{code: "EUR", name: "Euro", minor_units: 2})
    {:ok, portfolio} = Portfolios.create_portfolio(%{name: "Primary", base_currency_code: "EUR"})

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

  test "visiting /transactions renders the transactions workspace", %{conn: conn} do
    {:ok, view, html} = live(conn, "/transactions")

    assert html =~ "Transactions"
    assert has_element?(view, "a[href=\"/transactions\"]")
    assert has_element?(view, "#transaction-form")
  end

  test "renders an empty state when there are no transactions", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/transactions")

    assert html =~ "No transactions yet"
    assert html =~ "Record the first ledger transaction."
  end

  test "creates a deposit transaction", %{conn: conn, deposit_account: deposit_account} do
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
    assert html =~ "deposit"
    assert html =~ "1000.00"
    assert html =~ "Settlement Cash"
    refute html =~ "Synthetic opening deposit\""
  end

  test "creates a buy transaction using linked securities account and security", %{
    conn: conn,
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
    assert html =~ "buy"
    assert html =~ "Synthetic ETF"
    assert html =~ "5.00"
    assert html =~ "50.00"
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
    assert html =~ "Amount must be greater than 0"
    assert html =~ "value=\"0.00\""
    assert html =~ "Keep this value"
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
end
