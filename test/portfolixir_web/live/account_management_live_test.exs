defmodule PortfolixirWeb.AccountManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
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
    assert has_element?(view, "#deposit-accounts")
    assert has_element?(view, "#securities-accounts")
  end

  test "renders an empty state when there is no portfolio", %{conn: conn} do
    {:ok, view, html} = live(conn, "/accounts")

    assert html =~ "No portfolio yet"
    assert html =~ "Create a portfolio first."
    assert has_element?(view, "#portfolio-form")
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
end
