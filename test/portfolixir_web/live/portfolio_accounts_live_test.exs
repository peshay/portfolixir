defmodule PortfolixirWeb.PortfolioAccountsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Portfolios

  # User story:
  # As a local portfolio maintainer with a business account,
  # I want a toggle on the cash-account management page for whether an
  # account counts toward the cash quote,
  # so that I can exclude a business account without the API.
  #
  # Acceptance criteria:
  # - Each listed cash account shows a counts-toward-cash-quote toggle,
  #   checked by default.
  # - Clicking the toggle flips the stored flag and the rendered state.
  test "toggles whether a cash account counts toward the cash quote", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Mein Depot", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Business Account",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/portfolios")

    toggle = "#cash-quote-toggle-#{cash.id}"

    assert view |> element(toggle) |> render() =~ "checked"

    view |> element(toggle) |> render_click()

    assert Portfolios.get_cash_account(cash.id).counts_toward_cash_quote == false
    refute view |> element(toggle) |> render() =~ "checked"

    view |> element(toggle) |> render_click()

    assert Portfolios.get_cash_account(cash.id).counts_toward_cash_quote == true
    assert view |> element(toggle) |> render() =~ "checked"
  end
end
