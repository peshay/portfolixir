defmodule PortfolixirWeb.TransactionManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  # User story (#471):
  # As a maintainer with several portfolios,
  # I want the Transactions page to name the active portfolio and let me switch,
  # so that I never record a buy/sell into the wrong portfolio unknowingly.
  #
  # Acceptance criteria:
  # - The page renders a portfolio strip naming the active portfolio and the
  #   other portfolios as switchable chips.
  # - Switching changes which portfolio is active (its depots are offered).
  # - A transaction recorded after switching books into the switched-to
  #   portfolio, not the one that happened to be first.
  test "names the active portfolio and switches which portfolio books a transaction",
       %{conn: conn} do
    alpha =
      WorldFixtures.base_world(name: "Alpha", depot_name: "Alpha Depot", cash_name: "Alpha Cash")

    beta =
      WorldFixtures.base_world(name: "Beta", depot_name: "Beta Depot", cash_name: "Beta Cash")

    security = WorldFixtures.create_security!(name: "Switch Co", ticker: "SWC")

    {:ok, view, html} = live(conn, "/transactions")

    # The strip names both portfolios; the first-created one is active.
    assert html =~ "Alpha"
    assert html =~ "Beta"
    assert has_element?(view, "#portfolio-switch-#{alpha.portfolio.id}.is-active")
    refute has_element?(view, "#portfolio-switch-#{beta.portfolio.id}.is-active")

    # Switching to Beta exposes Beta's depot, not Alpha's.
    switched = view |> element("#portfolio-switch-#{beta.portfolio.id}") |> render_click()
    assert switched =~ "Beta Depot"
    refute switched =~ "Alpha Depot"
    assert has_element?(view, "#portfolio-switch-#{beta.portfolio.id}.is-active")

    # A transaction recorded now books into Beta, not the first portfolio.
    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-02-01",
        "securities_account_id" => to_string(beta.depot.id),
        "security_id" => to_string(WorldFixtures.security_id_for(security)),
        "quantity" => "3",
        "price" => "100",
        "currency_code" => "EUR"
      }
    })

    assert Ledger.list_transactions_for_portfolio(beta.portfolio.id) != []
    assert Ledger.list_transactions_for_portfolio(alpha.portfolio.id) == []
  end

  # A single-portfolio install still names the active portfolio (no ambiguity,
  # but the user should see which one they are booking into).
  test "names the only portfolio when there is just one", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Solo")

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(view, "#portfolio-switch-#{world.portfolio.id}.is-active")
  end

  # An unknown portfolio id (e.g. one deleted in another tab) is a no-op: the
  # active portfolio is left unchanged rather than blanking the page.
  test "selecting an unknown portfolio leaves the active one unchanged", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Solo")

    {:ok, view, _html} = live(conn, "/transactions")

    render_hook(view, "select_portfolio", %{"id" => "999999"})

    assert has_element?(view, "#portfolio-switch-#{world.portfolio.id}.is-active")
  end

  # User story (#472):
  # As a maintainer choosing a depot, I want each option to read clearly — the
  # depot name with its linked cash account as a quiet caption — instead of an
  # arrow plus a separate footnote, so the dropdown is self-explanatory.
  #
  # Acceptance criteria:
  # - The depot option shows the depot name and its linked cash account as a
  #   parenthetical caption, not via a "->" arrow.
  # - The "Linked cash account is derived…" footnote is gone.
  test "depot option shows the linked cash account as a caption, no arrow/footnote (#472)",
       %{conn: conn} do
    WorldFixtures.base_world(name: "Solo", depot_name: "Main Depot", cash_name: "Local Cash")

    {:ok, _view, html} = live(conn, "/transactions")

    assert html =~ "Main Depot (Local Cash)"
    refute html =~ "Main Depot -&gt;"
    refute html =~ "Linked cash account is derived"
  end

  # User story (#473):
  # As a maintainer recording a trade, I want the currency derived from the
  # chosen depot's cash account and the rare fees/taxes tucked behind a
  # disclosure, so the common buy/sell path stays clean.
  #
  # Acceptance criteria:
  # - No free-text Currency input in the default field set.
  # - Fees/Taxes live behind a (collapsed) disclosure.
  # - A basic buy with no costs derives currency from the depot and stores 0 costs.
  test "derives currency from the depot and hides costs behind a disclosure (#473)",
       %{conn: conn} do
    world =
      WorldFixtures.base_world(
        name: "Solo",
        currency: "USD",
        depot_name: "Main",
        cash_name: "Cash"
      )

    security = WorldFixtures.create_security!(name: "Globex", ticker: "GLB", currency: "USD")

    {:ok, view, _html} = live(conn, "/transactions")

    refute has_element?(view, "input[name='transaction[currency_code]']")
    assert has_element?(view, "details#transaction-costs")

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-02-01",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "2",
        "price" => "50"
      }
    })

    [tx] = Ledger.list_transactions_for_portfolio(world.portfolio.id)
    assert tx.currency_code == "USD"
    assert Decimal.equal?(tx.fees, Decimal.new("0"))
    assert Decimal.equal?(tx.taxes, Decimal.new("0"))
  end

  # The phx-change that drives the derived-currency caption must not blank the
  # depot select: the chosen option keeps its server-rendered `selected` state.
  test "keeps the chosen depot selected after a form change (#473)", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Solo", depot_name: "Main", cash_name: "Cash")

    {:ok, view, _html} = live(conn, "/transactions")

    html =
      view
      |> element("#transaction-form")
      |> render_change(%{
        "transaction" => %{"securities_account_id" => to_string(world.depot.id)}
      })

    assert html =~ ~r/<option[^>]*value="#{world.depot.id}"[^>]*selected/
    assert html =~ "Currency: EUR"
  end

  test "records fees entered in the costs disclosure (#473)", %{conn: conn} do
    world =
      WorldFixtures.base_world(
        name: "Solo",
        currency: "EUR",
        depot_name: "Main",
        cash_name: "Cash"
      )

    security = WorldFixtures.create_security!(name: "Globex", ticker: "GLB", currency: "EUR")

    {:ok, view, _html} = live(conn, "/transactions")

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-02-01",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "2",
        "price" => "50",
        "fees" => "3.50"
      }
    })

    [tx] = Ledger.list_transactions_for_portfolio(world.portfolio.id)
    assert Decimal.equal?(tx.fees, Decimal.new("3.50"))
  end

  # User story (#474):
  # As a maintainer, I want the input form to read as the primary task with
  # holdings and history as secondary supporting panels, and only the 6 core
  # fields up front, so the screen says "enter here, see results there".
  #
  # Acceptance criteria:
  # - The default form shows exactly the 6 core fields plus the costs disclosure.
  # - Holdings/history render as a secondary region but keep their DOM ids and
  #   still show their data after a transaction is recorded.
  test "shows the 6 core fields and keeps holdings/history panels (#474)", %{conn: conn} do
    world =
      WorldFixtures.base_world(
        name: "Solo",
        currency: "EUR",
        depot_name: "Main",
        cash_name: "Cash"
      )

    security = WorldFixtures.create_security!(name: "Globex", ticker: "GLB", currency: "EUR")

    {:ok, view, _html} = live(conn, "/transactions")

    for field <- ~w(type date securities_account_id security_id quantity price) do
      assert has_element?(view, "#transaction-form [name='transaction[#{field}]']")
    end

    assert has_element?(view, "details#transaction-costs")
    # The holdings/history panels are grouped as a secondary region.
    assert has_element?(view, ".transaction-secondary #holdings-panel")
    assert has_element?(view, ".transaction-secondary #transaction-list-panel")

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-02-01",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "2",
        "price" => "50"
      }
    })

    # The preserved ids still resolve and render their data.
    assert has_element?(view, "#holdings-panel #holdings-table")
    assert has_element?(view, "#transaction-list-panel #transaction-list")
  end

  # User story (Steve cold-start #2):
  # As a German-speaking maintainer recording a transaction,
  # I want the Type dropdown and history to read in my language,
  # so that the form does not feel half-built with raw "buy"/"sell" leaking
  # through an otherwise localized screen.
  #
  # Acceptance criteria:
  # - The Type select offers localized option labels ("Buy"/"Sell" in English),
  #   while the submitted value stays the stored enum ("buy"/"sell").
  # - The transaction history Type column shows the localized label, not the
  #   raw stored enum.
  test "localizes the transaction Type options and history labels", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Solo")
    security = WorldFixtures.create_security!(name: "Localize Co", ticker: "LOC")

    {:ok, view, _html} = live(conn, "/transactions")

    # The option keeps its machine value but renders a human, localized label.
    assert has_element?(
             view,
             "#transaction-form select[name='transaction[type]'] option[value='buy']",
             "Buy"
           )

    assert has_element?(
             view,
             "#transaction-form select[name='transaction[type]'] option[value='sell']",
             "Sell"
           )

    # A recorded buy shows the localized label in the history, not raw "buy".
    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-02-01",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "2",
        "price" => "50"
      }
    })

    assert has_element?(view, "#transaction-list tbody tr td", "Buy")
  end

  # The history lists every ledger kind, not just buy/sell (e.g. an imported
  # dividend). Such kinds have no dedicated label and fall back to their stored
  # name rather than crashing the table.
  test "history falls back to the stored name for non-buy/sell kinds", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Solo")
    security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")

    {:ok, _tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: WorldFixtures.security_id_for(security),
        type: "dividend",
        date: ~D[2026-02-01],
        gross_amount: "100",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(view, "#transaction-list tbody tr td", "dividend")
  end

  # User story (Steve cold-start #1):
  # As a new user who has set up a portfolio and a depot but no securities yet,
  # I want the transaction form to tell me a security must exist first and send
  # me to create one,
  # so that I do not fill in the whole form only to hit an empty, unselectable
  # "Wertpapier auswählen" dropdown that silently blocks submission.
  #
  # Acceptance criteria:
  # - With no securities, the Security field is replaced by an empty-state that
  #   links to /securities (the missing prerequisite is named at the point of
  #   pain), and the dead security <select> is not rendered.
  # - Once a security exists, the normal Security select is back.
  test "names the missing-security prerequisite instead of a dead empty select",
       %{conn: conn} do
    _world = WorldFixtures.base_world(name: "Solo")

    {:ok, view, _html} = live(conn, "/transactions")

    # The dead, unselectable security dropdown is gone...
    refute has_element?(view, "#transaction-form select[name='transaction[security_id]']")
    # ...replaced by a teaching empty-state that links to where you fix it.
    assert has_element?(view, "#transaction-no-securities a[href='/securities']")
  end

  test "shows the security select again once a security exists", %{conn: conn} do
    _world = WorldFixtures.base_world(name: "Solo")
    WorldFixtures.create_security!(name: "Has Sec", ticker: "HAS")

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(view, "#transaction-form select[name='transaction[security_id]']")
    refute has_element?(view, "#transaction-no-securities")
  end
end
