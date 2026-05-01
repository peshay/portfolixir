defmodule PortfolixirWeb.SecurityDetailLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  setup do
    Catalog.ensure_mvp_currencies!()

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{
        name: "Primary",
        base_currency_code: "EUR"
      })

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

    %{
      portfolio: portfolio,
      deposit_account: deposit_account,
      securities_account: securities_account
    }
  end

  test "shows security master data with name, symbol, and identifiers", %{conn: conn} do
    security =
      create_security(%{
        name: "Synthetic ETF",
        symbol: "SYN",
        currency_code: "EUR",
        isin: "US0000000001",
        wkn: "A1B2C3",
        provider_symbol: "SYN.X"
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-detail-title", "Synthetic ETF (SYN)")
    assert has_element?(view, "#security-master-data", "Synthetic ETF")
    assert has_element?(view, "#security-master-data", "SYN")
    assert has_element?(view, "#security-master-data", "US0000000001")
    assert has_element?(view, "#security-master-data", "A1B2C3")
    assert has_element?(view, "#security-master-data", "EUR")
    assert has_element?(view, "#security-master-data", "SYN.X")
  end

  test "shows buy transactions for the selected security", %{
    conn: conn,
    securities_account: securities_account,
    portfolio: portfolio
  } do
    security = create_security(%{name: "Buy Security", symbol: "BUY", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-04-01],
        currency_code: "EUR",
        quantity: Decimal.new("10.00"),
        price: Decimal.new("12.50"),
        amount: Decimal.new("125.00"),
        notes: "Initial buy"
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-transactions", "Buy")
    assert has_element?(view, "#security-transactions", "Main Depot")
    assert has_element?(view, "#security-transactions", "10")
    assert has_element?(view, "#security-transactions", "12.5")
    assert has_element?(view, "#security-transactions", "125")
    assert has_element?(view, "#security-transactions", "Initial buy")
  end

  test "shows sell transactions for the selected security", %{
    conn: conn,
    securities_account: securities_account,
    portfolio: portfolio
  } do
    security = create_security(%{name: "Sell Security", symbol: "SELL", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2026-04-02],
        currency_code: "EUR",
        quantity: Decimal.new("3.00"),
        price: Decimal.new("15.00"),
        amount: Decimal.new("45.00"),
        notes: "Partial sale"
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-transactions", "Sell")
    assert has_element?(view, "#security-transactions", "Partial sale")
    assert has_element?(view, "#security-transactions", "45")
  end

  test "shows dividend transactions for the selected security", %{
    conn: conn,
    deposit_account: deposit_account,
    portfolio: portfolio
  } do
    security = create_security(%{name: "Dividend Security", symbol: "DIV", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        security_id: security.id,
        type: "dividend",
        date: ~D[2026-04-03],
        currency_code: "EUR",
        amount: Decimal.new("11.00"),
        notes: "Dividend payment"
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-transactions", "Dividend")
    assert has_element?(view, "#security-transactions", "Dividend payment")
    assert has_element?(view, "#security-transactions", "11")
  end

  test "shows an empty state when no transactions exist", %{conn: conn} do
    security =
      create_security(%{name: "Empty Security", symbol: "EMPTY", currency_code: "EUR"})

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#no-security-transactions")
    assert has_element?(view, "#no-security-transactions", "No transactions are recorded")
  end

  test "shows current derived positions per securities account", %{
    conn: conn,
    deposit_account: deposit_account,
    securities_account: securities_account,
    portfolio: portfolio
  } do
    second_deposit =
      create_deposit_account(%{
        portfolio_id: deposit_account.portfolio_id,
        name: "Secondary cash"
      })

    second_securities_account =
      create_securities_account(%{
        portfolio_id: deposit_account.portfolio_id,
        reference_deposit_account_id: second_deposit.id,
        name: "Secondary depot"
      })

    security = create_security(%{name: "Position Security", symbol: "POS", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-04-04],
        currency_code: "EUR",
        quantity: Decimal.new("8.00"),
        price: Decimal.new("10.00"),
        amount: Decimal.new("80.00")
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: second_securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-04-05],
        currency_code: "EUR",
        quantity: Decimal.new("5.00"),
        price: Decimal.new("10.00"),
        amount: Decimal.new("50.00")
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-position-list")
    assert has_element?(view, "#security-position-list", "Main Depot")
    assert has_element?(view, "#security-position-list", "Secondary depot")
    assert has_element?(view, "#security-position-list", "8")
    assert has_element?(view, "#security-position-list", "5")
  end

  test "does not include transactions from other securities", %{
    conn: conn,
    securities_account: securities_account,
    deposit_account: _deposit_account,
    portfolio: portfolio
  } do
    security = create_security(%{name: "Target Security", symbol: "TGT", currency_code: "EUR"})

    other_security =
      create_security(%{name: "Other Security", symbol: "OTH", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-04-06],
        currency_code: "EUR",
        quantity: Decimal.new("3.00"),
        price: Decimal.new("10.00"),
        amount: Decimal.new("30.00"),
        notes: "Target note"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: other_security.id,
        type: "buy",
        date: ~D[2026-04-07],
        currency_code: "EUR",
        quantity: Decimal.new("1.00"),
        price: Decimal.new("20.00"),
        amount: Decimal.new("20.00"),
        notes: "Other note"
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-transactions", "Target note")
    refute has_element?(view, "#security-transactions", "Other note")
  end

  test "returns a clear not found message for unknown security id", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities/999999")

    assert has_element?(view, "#security-detail-not-found")
    assert has_element?(view, "#security-detail-not-found", "Security not found")
  end

  test "links security list rows to their detail pages", %{conn: conn} do
    security = create_security(%{name: "Linked Security", symbol: "LNK", currency_code: "EUR"})

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(
             view,
             "#security-detail-link-#{security.id}[href=\"/securities/#{security.id}\"]"
           )

    expected_path = "/securities/#{security.id}"

    assert {:error, {:redirect, %{to: ^expected_path}}} =
             element(view, "#security-detail-link-#{security.id}") |> render_click()
  end

  defp create_security(attrs) do
    {:ok, security} = Catalog.create_security(attrs)
    security
  end

  defp create_deposit_account(attrs) do
    {:ok, account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: attrs[:portfolio_id],
        name: attrs[:name],
        currency_code: "EUR"
      })

    account
  end

  defp create_securities_account(attrs) do
    {:ok, account} =
      Portfolios.create_securities_account(%{
        portfolio_id: attrs[:portfolio_id],
        reference_deposit_account_id: attrs[:reference_deposit_account_id],
        name: attrs[:name],
        currency_code: "EUR"
      })

    account
  end
end
