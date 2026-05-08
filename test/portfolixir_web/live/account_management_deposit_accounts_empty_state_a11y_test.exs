defmodule PortfolixirWeb.AccountManagementDepositAccountsEmptyStateA11yTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Portfolios

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "deposit-accounts empty state keeps deterministic title and description relationships", %{
    conn: conn
  } do
    create_portfolio("Primary portfolio")

    {:ok, view, _html} = live(conn, "/accounts")

    assert has_element?(view, "#no-deposit-accounts[role='status'][aria-live='polite']")

    empty_state_html =
      view
      |> element("#no-deposit-accounts")
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

    assert labelledby == "no-deposit-accounts-title"
    assert describedby == "no-deposit-accounts-description"

    assert has_element?(view, "##{labelledby}", "No deposit accounts yet")
    assert has_element?(view, "##{describedby}", "Add a cash or settlement account.")
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
