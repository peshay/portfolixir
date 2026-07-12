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

  # User story (ADR-0024):
  # As a local portfolio maintainer,
  # I want to create depots and cash accounts without ever deciding on a
  # portfolio,
  # so that grouping happens exclusively through buckets and views while the
  # compatibility record is resolved internally.
  #
  # Acceptance criteria:
  # - The page renders no portfolio create form and no target-portfolio
  #   selector.
  # - Creating a cash account on an empty database binds it to one internal
  #   default portfolio ("Default") without asking.
  # - Creating a depot binds it the same way and links the cash account.
  test "creates a cash account and depot without any portfolio decision", %{conn: conn} do
    {:ok, view, html} = live(conn, "/portfolios")

    refute html =~ "portfolio-form"
    refute html =~ "target-portfolio-form"
    refute html =~ "Add to portfolio"
    refute html =~ "Create portfolio"

    view
    |> element("#cash-account-form")
    |> render_submit(%{"cash_account" => %{"name" => "Cash EUR", "currency_code" => "EUR"}})

    assert [cash] = Portfolios.list_cash_accounts()
    default = Portfolios.get_portfolio(cash.portfolio_id)
    assert default.name == "Default"

    view
    |> element("#securities-account-form")
    |> render_submit(%{
      "securities_account" => %{"name" => "Depot", "cash_account_id" => to_string(cash.id)}
    })

    assert [depot] = Portfolios.list_securities_accounts()
    assert depot.portfolio_id == default.id
    assert depot.cash_account_id == cash.id

    # Exactly one internal record was created for both writes.
    assert Portfolios.count_portfolios() == 1
  end

  # An existing installation with portfolios keeps binding new accounts to its
  # earliest portfolio — deterministic, no new "Default" record appears.
  test "existing installs bind new accounts to the earliest portfolio", %{conn: conn} do
    {:ok, first} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Alpha",
        base_currency_code: "EUR"
      })

    {:ok, _b} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Beta",
        base_currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/portfolios")

    view
    |> element("#cash-account-form")
    |> render_submit(%{"cash_account" => %{"name" => "New Cash", "currency_code" => "EUR"}})

    assert [cash] = Portfolios.list_cash_accounts()
    assert cash.portfolio_id == first.id
    assert Portfolios.count_portfolios() == 2
  end

  # User story (ADR-0024 modification 1):
  # As a local portfolio maintainer,
  # I want a minimal, read-only administration list of every portfolio record,
  # so that portfolios created over the API/MCP can never become invisible
  # writable resources.
  #
  # Acceptance criteria:
  # - A collapsed panel on the Accounts & depots page lists every portfolio
  #   record with name, creation date, source, and bound depot/account counts.
  # - API-created records appear with the API source label.
  # - The panel offers no create or edit controls.
  test "admin panel lists every portfolio record read-only", %{conn: conn} do
    {:ok, ui} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Mine",
        base_currency_code: "EUR"
      })

    {:ok, _api} =
      Portfolios.create_portfolio(Portfolixir.Actor.api_token_rw("mcp"), %{
        name: "Ghost",
        base_currency_code: "USD"
      })

    {:ok, _cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: ui.id,
        name: "Cash EUR",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/portfolios")

    panel = view |> element("#portfolio-admin") |> render()
    assert panel =~ "Mine"
    assert panel =~ "Ghost"
    assert panel =~ "API"
    assert panel =~ Date.to_iso8601(Date.utc_today())

    # Read-only: no create or edit affordance inside the panel.
    refute panel =~ "<form"
    refute panel =~ "<button"
    refute panel =~ "<input"
  end

  # User story:
  # As a German-locale maintainer,
  # I want the demoted accounts page fully translated,
  # so that the German UI carries the new no-portfolio wording.
  test "translates the demoted accounts page for the German locale", %{conn: conn} do
    {:ok, _p} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Alpha",
        base_currency_code: "EUR"
      })

    {:ok, _view, html} = live(conn, "/portfolios?locale=de")

    assert html =~ "Portfoliodatensätze"
    refute html =~ "Add to portfolio"
    refute html =~ "Create portfolio"
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
