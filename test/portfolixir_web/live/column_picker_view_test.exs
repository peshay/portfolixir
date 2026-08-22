defmodule PortfolixirWeb.ColumnPickerViewTest do
  # Issue #732: `fields=` (FR-37) gives the agent a sparse fieldset on the
  # transactions and holdings reads, but neither surface had the operator's
  # counterpart — a column picker. These tests pin the human half: the same
  # projections the API serves, chosen column by column on the page.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  defp seed_history do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!(name: "Pick Co", ticker: "PCK")

    buy =
      WorldFixtures.buy!(world, security,
        quantity: "10",
        price: "100",
        fees: "1.50",
        taxes: "0.75",
        date: ~D[2026-01-02]
      )

    WorldFixtures.put_quote!(security, ~D[2026-01-10], "120")
    %{world: world, security: security, buy: buy}
  end

  # User story (issue #732):
  # As a local portfolio maintainer,
  # I want to choose which columns the transaction history shows,
  # so that the fields the agent can select with `fields=` are equally
  # reachable for me — fees and taxes included, which the table never showed.
  #
  # Acceptance criteria:
  # - The default column set matches what the table showed before the picker.
  # - Adding a column (fees) renders its header and the booked value.
  # - Removing columns narrows the table; an empty selection falls back to
  #   the defaults rather than rendering a table of nothing.
  test "the transaction history's column picker adds and removes columns", %{conn: conn} do
    seed_history()

    {:ok, view, html} = live(conn, "/transactions")

    assert html =~ ~s(id="transaction-list")
    refute view |> element("#transaction-list thead") |> render() =~ "Fees"

    view
    |> element("#tx-column-form")
    |> render_change(%{
      "columns" => ["date", "type", "security", "quantity", "price", "currency", "fees"]
    })

    assert view |> element("#transaction-list thead") |> render() =~ "Fees"
    assert view |> element("#transaction-list tbody") |> render() =~ "1.5"

    view |> element("#tx-column-form") |> render_change(%{"columns" => ["date", "type"]})
    refute view |> element("#transaction-list thead") |> render() =~ "Quantity"

    # An empty selection is a broken table, not a preference: fall back.
    view |> element("#tx-column-form") |> render_change(%{"columns" => [""]})
    assert view |> element("#transaction-list thead") |> render() =~ "Quantity"
  end

  # User story (issue #732):
  # As a local portfolio maintainer,
  # I want the Balance column to stay governed by its own rule,
  # so that the picker never fakes a running balance outside the one-account
  # narrowing that makes it meaningful.
  #
  # Acceptance criteria:
  # - The picker offers no "balance" checkbox.
  # - Narrowing to one account still adds the Balance column, whatever the
  #   picker selection says.
  test "the balance column stays rule-bound, not pickable", %{conn: conn} do
    %{world: world} = seed_history()

    {:ok, view, _html} = live(conn, "/transactions")

    refute has_element?(view, "#tx-column-form input[value='balance']")

    view |> element("#tx-column-form") |> render_change(%{"columns" => ["date", "type"]})

    view
    |> element("#transaction-chips button[phx-value-option='#{world.cash.id}']")
    |> render_click()

    assert view |> element("#transaction-list thead") |> render() =~ "Balance"
  end

  # User story (issue #732):
  # As a local portfolio maintainer,
  # I want the holdings panel to offer the valuation columns the agent reads
  # over the holdings API — cost, latest price, market value, P&L —
  # so that the holdings list is the human view of the same projection, not a
  # poorer cousin of it.
  #
  # Acceptance criteria:
  # - The default column set stays Depot / Security / Quantity.
  # - Picking market value and average cost renders the figures of the API's
  #   own holdings projection (`Ledger.holdings_for_portfolio/1`).
  test "the holdings panel's picker surfaces the API projection's columns", %{conn: conn} do
    %{world: world} = seed_history()

    {:ok, view, _html} = live(conn, "/transactions")

    head = view |> element("#holdings-table thead") |> render()
    assert head =~ "Depot"
    assert head =~ "Security"
    assert head =~ "Quantity"
    refute head =~ "Market value"

    view
    |> element("#holdings-column-form")
    |> render_change(%{
      "columns" => ["depot", "security", "quantity", "avg_cost", "market_value"]
    })

    assert view |> element("#holdings-table thead") |> render() =~ "Market value"

    [holding] = Ledger.holdings_for_portfolio(world.portfolio.id)
    body = view |> element("#holdings-table tbody") |> render()
    assert body =~ Decimal.to_string(Decimal.normalize(holding.market_value), :normal)
    assert body =~ Decimal.to_string(Decimal.normalize(holding.avg_cost), :normal)
  end

  # User story (issue #732):
  # As a local portfolio maintainer,
  # I want my column choices to survive a reload,
  # so that a table I shaped once stays shaped.
  #
  # Acceptance criteria:
  # - Both tables carry the ColumnPrefs hook with distinct storage keys and
  #   their own restore events, so the stored sets cannot cross-write.
  # - The hook's restore event applies a stored selection.
  test "column choices persist through the ColumnPrefs hook wiring", %{conn: conn} do
    seed_history()

    {:ok, view, html} = live(conn, "/transactions")

    assert html =~ ~s(data-storage-key="transactions.columns")
    assert html =~ ~s(data-storage-key="transactions.holdings.columns")
    assert html =~ ~s(data-restore-event="set_tx_columns")
    assert html =~ ~s(data-restore-event="set_holdings_columns")

    view
    |> element("[data-storage-key='transactions.columns']")
    |> render_hook("set_tx_columns", %{"columns" => ["date", "type", "fees"]})

    head = view |> element("#transaction-list thead") |> render()
    assert head =~ "Fees"
    refute head =~ "Quantity"
  end
end
