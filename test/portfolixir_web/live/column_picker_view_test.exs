defmodule PortfolixirWeb.ColumnPickerViewTest do
  # Issue #732: `fields=` (FR-37) gives the agent a sparse fieldset on the
  # transactions and holdings reads, but neither surface had the operator's
  # counterpart — a column picker. These tests pin the human half: the same
  # projections the API serves, chosen column by column on the page.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

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

    # #850: the picker is a popover on its toggle.
    view |> element("#tx-column-toggle") |> render_click()

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
    view |> element("#tx-column-toggle") |> render_click()

    refute has_element?(view, "#tx-column-form input[value='balance']")

    view |> element("#tx-column-form") |> render_change(%{"columns" => ["date", "type"]})

    view
    |> element("#transaction-chips button[phx-value-option='#{world.cash.id}']")
    |> render_click()

    assert view |> element("#transaction-list thead") |> render() =~ "Balance"
  end

  # User story (issue #732):
  # As a local portfolio maintainer,
  # I want my column choices to survive a reload,
  # so that a table I shaped once stays shaped.
  #
  # Acceptance criteria:
  # - The history table carries the ColumnPrefs hook with its own storage key
  #   and restore event (the holdings table left the route with #803).
  # - The hook's restore event applies a stored selection.
  test "column choices persist through the ColumnPrefs hook wiring", %{conn: conn} do
    seed_history()

    {:ok, view, html} = live(conn, "/transactions")

    assert html =~ ~s(data-storage-key="transactions.columns")
    assert html =~ ~s(data-restore-event="set_tx_columns")

    view
    |> element("[data-storage-key='transactions.columns']")
    |> render_hook("set_tx_columns", %{"columns" => ["date", "type", "fees"]})

    head = view |> element("#transaction-list thead") |> render()
    assert head =~ "Fees"
    refute head =~ "Quantity"
  end
end
