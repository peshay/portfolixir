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

  test "group controls expose deterministic accessible relationship for grouping selector", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/reports/payments")

    assert has_element?(
             view,
             "#payments-group-controls[role='group'][aria-labelledby='payments-group-controls-label'][aria-describedby='payments-group-controls-description']"
           )

    assert has_element?(
             view,
             "#payments-group-controls-label.app-shell-visually-hidden",
             "Payments grouping controls"
           )

    assert has_element?(
             view,
             "#payments-group-controls-description.app-shell-visually-hidden",
             "Choose how to group dividend payment rows in this report."
           )

    assert has_element?(
             view,
             "#payments-group-form[aria-labelledby='payments-group-controls-label'][aria-describedby='payments-group-controls-description']"
           )

    assert has_element?(
             view,
             "#payments-group-mode[aria-describedby='payments-group-controls-description']"
           )
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
    assert has_element?(view, "#payments-group-security-#{security.id}", "Synthetic ETF (SYN)")

    assert has_element?(
             view,
             "#payments-group-security-#{second_security.id}",
             "Growth Fund (GRW)"
           )
  end

  test "security grouping uses security identity when names collide", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account,
    security: security
  } do
    {:ok, duplicate_name_security} =
      Catalog.create_security(%{
        name: "Synthetic ETF",
        symbol: "SYNB",
        currency_code: "EUR"
      })

    create_dividend(portfolio, deposit_account, security, ~D[2026-01-10], "5.00", "First")

    create_dividend(
      portfolio,
      deposit_account,
      duplicate_name_security,
      ~D[2026-01-11],
      "7.00",
      "Second"
    )

    {:ok, view, _html} = live(conn, "/reports/payments")

    render_change(element(view, "#payments-group-form"), %{group_mode: "security"})

    assert has_element?(view, "#payments-group-security-#{security.id}", "Synthetic ETF (SYN)")

    assert has_element?(
             view,
             "#payments-group-security-#{duplicate_name_security.id}",
             "Synthetic ETF (SYNB)"
           )
  end

  test "renders accumulated dividend chart and deterministic monthly accumulation table", %{
    conn: conn,
    portfolio: portfolio,
    deposit_account: deposit_account,
    security: security
  } do
    create_dividend(portfolio, deposit_account, security, ~D[2026-01-05], "5.00", "Jan first")
    create_dividend(portfolio, deposit_account, security, ~D[2026-01-20], "7.50", "Jan second")
    create_dividend(portfolio, deposit_account, security, ~D[2026-02-01], "2.50", "Feb")

    {:ok, view, _html} = live(conn, "/reports/payments")

    assert has_element?(
             view,
             "#payments-accumulation-chart[aria-labelledby='payments-accumulation-chart-title'][aria-describedby='payments-accumulation-chart-intro']"
           )

    assert has_element?(
             view,
             "#payments-accumulation-chart-title.app-shell-section-title",
             "Accumulated dividends"
           )

    assert has_element?(
             view,
             "#payments-accumulation-chart-intro",
             "Monthly cumulative progression based on recorded dividend transactions."
           )

    assert has_element?(view, "#payments-accumulation-row-eur-2026-01", "12.5")
    assert has_element?(view, "#payments-accumulation-row-eur-2026-02", "15.0")
    assert has_element?(view, "#payments-yearly-comparison", "Yearly comparison")
    assert has_element?(view, "#payments-yearly-row-2026-1-eur", "12.5")
    assert has_element?(view, "#payments-yearly-row-2026-2-eur", "15.0")
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
