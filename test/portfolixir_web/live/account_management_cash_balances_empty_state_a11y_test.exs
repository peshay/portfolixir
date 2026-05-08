defmodule PortfolixirWeb.AccountManagementCashBalancesEmptyStateA11yTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Portfolios

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "cash-balances empty state keeps deterministic title and description relationships", %{
    conn: conn
  } do
    create_portfolio("Primary portfolio")

    {:ok, view, _html} = live(conn, "/accounts")

    assert has_element?(view, "#no-cash-balances[role='status'][aria-live='polite']")

    empty_state_html =
      view
      |> element("#no-cash-balances")
      |> render()

    {:ok, [status_region]} = Floki.parse_fragment(empty_state_html)

    labelledby =
      status_region
      |> Floki.attribute("aria-labelledby")
      |> List.first()

    describedby =
      status_region
      |> Floki.attribute("aria-describedby")
      |> List.first()

    assert labelledby == "no-cash-balances-title"
    assert describedby == "no-cash-balances-description"

    assert has_element?(view, "##{labelledby}", "No cash balances yet")

    assert has_element?(
             view,
             "##{describedby}",
             "Balances appear after deposit, withdrawal and trade transactions."
           )
  end

  defp create_portfolio(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{
        name: name,
        base_currency_code: "EUR"
      })

    portfolio
  end
end
