defmodule PortfolixirWeb.PortfolioAccountsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Portfolios

  # User story:
  # As a local portfolio maintainer with overdraft/reserve accounts,
  # I want a per-account liquidity-role selector on the cash-account page,
  # so that I can classify an account (free cash, credit line, reserve) without
  # the API.
  #
  # Acceptance criteria:
  # - Each listed cash account shows a liquidity-role selector defaulting to
  #   free_cash.
  # - Changing the selector stores the new role and updates the rendered state.
  # - The selector renders compact and inline with the account name instead of
  #   inheriting the full-width form-input styling.
  test "sets a cash account's liquidity role", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Mein Depot", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Business Account",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/portfolios")

    selector = "#liquidity-role-#{cash.id}"

    assert Portfolios.get_cash_account(cash.id).liquidity_role == "free_cash"

    view
    |> element(selector)
    |> render_change(%{"id" => cash.id, "liquidity_role" => "reserve"})

    assert Portfolios.get_cash_account(cash.id).liquidity_role == "reserve"
    assert view |> element(selector) |> render() =~ ~r/value="reserve" selected/

    view
    |> element(selector)
    |> render_change(%{"id" => cash.id, "liquidity_role" => "credit_line"})

    assert Portfolios.get_cash_account(cash.id).liquidity_role == "credit_line"
  end

  test "renders the cash-quote toggle compact instead of as a full-width form input" do
    app_css = File.read!("priv/static/app.css")

    # Inline next to the account name, not stacked by the global label grid...
    assert app_css =~ ~r/\.cash-quote-toggle\s*\{[^}]*display:\s*inline-flex/s

    # ...and the checkbox must not inherit the 100%-width / 34px form sizing.
    assert app_css =~ ~r/\.cash-quote-toggle input\[type="checkbox"\]\s*\{[^}]*width:\s*14px/s
    assert app_css =~ ~r/\.cash-quote-toggle input\[type="checkbox"\]\s*\{[^}]*min-height:\s*0/s
  end
end
