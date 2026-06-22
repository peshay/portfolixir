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
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Mein Depot",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Business Account",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/portfolios")

    selector = "#liquidity-role-#{cash.id}"
    form = "#liquidity-role-form-#{cash.id}"

    assert Portfolios.get_cash_account(cash.id).liquidity_role == "free_cash"

    # Drive the form the way the browser does: the account id is carried by the
    # form's hidden input, not hand-fed here. A form-less select did not
    # serialize this, so the role silently failed to persist (#433).
    view
    |> element(form)
    |> render_change(%{"liquidity_role" => "reserve"})

    assert Portfolios.get_cash_account(cash.id).liquidity_role == "reserve"
    assert view |> element(selector) |> render() =~ ~r/value="reserve" selected/

    view
    |> element(form)
    |> render_change(%{"liquidity_role" => "credit_line"})

    assert Portfolios.get_cash_account(cash.id).liquidity_role == "credit_line"
  end

  # User story:
  # As a maintainer with more than one portfolio, I want to choose which
  # portfolio a new cash account (or depot) is added to, so that accounts never
  # silently land on whichever portfolio happens to be first in the list (#490).
  #
  # Acceptance criteria:
  # - With multiple portfolios, a target-portfolio selector is shown.
  # - The chosen target is visible ("Adding to: <name>").
  # - A created cash account lands on the selected portfolio, not the first one.
  test "creates a cash account on the explicitly selected portfolio (#490)", %{conn: conn} do
    {:ok, _a} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Alpha",
        base_currency_code: "EUR"
      })

    {:ok, _b} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Beta",
        base_currency_code: "EUR"
      })

    [first | _] = Portfolios.list_portfolios()
    target = Enum.find(Portfolios.list_portfolios(), &(&1.id != first.id))

    {:ok, view, _html} = live(conn, "/portfolios")

    view
    |> element("#target-portfolio-form")
    |> render_change(%{"portfolio_id" => to_string(target.id)})

    assert render(view) =~ "Adding to: #{target.name}"

    view
    |> element("#cash-account-form")
    |> render_submit(%{"cash_account" => %{"name" => "Target Cash", "currency_code" => "EUR"}})

    target_cash = Portfolios.list_cash_accounts_for_portfolio(target.id)
    first_cash = Portfolios.list_cash_accounts_for_portfolio(first.id)

    assert Enum.any?(target_cash, &(&1.name == "Target Cash"))
    assert first_cash == []
  end

  # User story:
  # As a German-locale maintainer with more than one portfolio,
  # I want the "add to portfolio" target picker and its hint translated,
  # so that the portfolios page is fully German.
  #
  # Acceptance criteria:
  # - With ?locale=de the target-portfolio label and the "Adding to" hint
  #   render in German and not in English.
  test "translates the target-portfolio picker for the German locale", %{conn: conn} do
    {:ok, _a} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Alpha",
        base_currency_code: "EUR"
      })

    {:ok, _b} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Beta",
        base_currency_code: "EUR"
      })

    {:ok, _view, html} = live(conn, "/portfolios?locale=de")

    assert html =~ "Zum Portfolio hinzufügen"
    assert html =~ "Hinzufügen zu:"
    refute html =~ "Add to portfolio"
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
