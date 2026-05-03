defmodule PortfolixirWeb.PaymentsReportLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  setup do
    Catalog.ensure_mvp_currencies!()

    {:ok, portfolio} = Portfolios.create_portfolio(%{name: "Primary", base_currency_code: "EUR"})

    {:ok, deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio.id,
        name: "Settlement Cash",
        currency_code: "EUR"
      })

    {:ok, security} =
      Catalog.create_security(%{
        name: "Synthetic ETF",
        symbol: "SYN",
        currency_code: "EUR"
      })

    %{portfolio: portfolio, deposit_account: deposit_account, security: security}
  end

  test "renders payments report route", %{conn: conn} do
    {:ok, view, html} = live(conn, "/reports/payments")

    assert html =~ "Payments report"
    assert has_element?(view, "#payments-group-form")
  end

  test "shows empty state when no dividends exist", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/reports/payments")

    assert has_element?(view, "#payments-empty-state", "No dividend payments yet")
  end

  test "shows only dividend transactions in list mode", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account,
    security: security
  } do
    {:ok, _deposit} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "deposit",
        date: ~D[2026-01-01],
        currency_code: "EUR",
        amount: Decimal.new("100.00"),
        notes: "Deposit note"
      })

    {:ok, _dividend} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        security_id: security.id,
        type: "dividend",
        date: ~D[2026-01-02],
        currency_code: "EUR",
        amount: Decimal.new("12.50"),
        notes: "Dividend note"
      })

    {:ok, view, _html} = live(conn, "/reports/payments")

    assert has_element?(view, "#payments-list", "Dividend note")
    refute has_element?(view, "#payments-list", "Deposit note")
  end

  test "groups by month quarter year and security", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account,
    security: security
  } do
    {:ok, second_security} =
      Catalog.create_security(%{
        name: "Growth Fund",
        symbol: "GRW",
        currency_code: "EUR"
      })

    create_dividend(portfolio, deposit_account, security, ~D[2026-01-15], "10.00", "Jan dividend")
    create_dividend(portfolio, deposit_account, security, ~D[2026-03-03], "20.00", "Mar dividend")

    create_dividend(
      portfolio,
      deposit_account,
      second_security,
      ~D[2026-04-02],
      "30.00",
      "Apr dividend"
    )

    {:ok, view, _html} = live(conn, "/reports/payments")

    render_change(element(view, "#payments-group-form"), %{group_mode: "month"})
    assert has_element?(view, "#payments-group-2026-04")
    assert has_element?(view, "#payments-group-2026-03")
    assert has_element?(view, "#payments-group-2026-01")

    render_change(element(view, "#payments-group-form"), %{group_mode: "quarter"})
    assert has_element?(view, "#payments-group-2026-q2")
    assert has_element?(view, "#payments-group-2026-q1")

    render_change(element(view, "#payments-group-form"), %{group_mode: "year"})
    assert has_element?(view, "#payments-group-2026")

    render_change(element(view, "#payments-group-form"), %{group_mode: "security"})
    assert has_element?(view, "#payments-group-synthetic-etf", "Synthetic ETF")
    assert has_element?(view, "#payments-group-growth-fund", "Growth Fund")
  end

  test "viewing payments report does not create transactions", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account,
    security: security
  } do
    create_dividend(portfolio, deposit_account, security, ~D[2026-01-15], "10.00", "Dividend")

    transactions_before = Repo.aggregate(Transaction, :count, :id)

    {:ok, _view, _html} = live(conn, "/reports/payments")

    assert Repo.aggregate(Transaction, :count, :id) == transactions_before
  end

  defp create_dividend(portfolio, deposit_account, security, date, amount, notes) do
    {:ok, _transaction} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        security_id: security.id,
        type: "dividend",
        date: date,
        currency_code: "EUR",
        amount: Decimal.new(amount),
        notes: notes
      })
  end
end
