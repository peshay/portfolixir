defmodule PortfolixirWeb.TransactionEditLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3]

  alias Portfolixir.Ledger

  # User story (#809; review C6 variant C; AGENTS.md → "API And MCP Coverage",
  # the two-way rule):
  # As a local portfolio maintainer who mis-booked a transaction,
  # I want to correct it from the history,
  # so that a correction does not require the API or the agent — the update
  # capability has existed since before the coverage rule and had no human
  # view.
  #
  # Acceptance criteria:
  # - Every history row's menu carries "Edit"; it opens the #803 booking
  #   drawer pre-filled with that booking.
  # - Saving carries `Ledger.update_transaction/3`: the row changes in place
  #   (no second row) and the derived holdings follow.
  # - A refused edit keeps the drawer open with the entered values and the
  #   field errors, exactly as creation does.
  # - No new API or MCP surface: this is the view for a capability that
  #   already exists.

  setup do
    world = base_world(name: "Edit World", cash_name: "EW Cash", depot_name: "EW Depot")
    security = create_security!(name: "Edit Co", ticker: "EDT")
    deposit!(world, "10000", ~D[2026-01-01])
    tx = buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])

    %{world: world, security: security, transaction: tx}
  end

  defp held_quantity(world, security) do
    world.portfolio.id
    |> Ledger.holdings_for_portfolio()
    |> Enum.find(&(&1.security_id == security.id))
    |> case do
      nil -> nil
      holding -> holding.quantity
    end
  end

  test "the row menu opens the booking drawer pre-filled and the save updates in place",
       %{conn: conn, world: world, security: security, transaction: tx} do
    {:ok, view, _html} = live(conn, "/transactions")

    refute has_element?(view, "#booking-drawer")

    view |> element("#tx-kebab-#{tx.id}") |> render_click()
    assert has_element?(view, "#tx-row-menu-#{tx.id}")

    view |> element("#tx-edit-#{tx.id}") |> render_click()

    assert has_element?(view, "dialog#booking-drawer")
    drawer = view |> element("#booking-drawer") |> render()
    assert drawer =~ "Edit transaction"
    assert drawer =~ ~s(value="10")
    assert drawer =~ ~s(value="2026-01-05")

    view
    |> form("#transaction-form", %{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-01-05",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "12",
        "price" => "100"
      }
    })
    |> render_submit()

    refute has_element?(view, "#booking-drawer")
    assert Ledger.count_transactions() == 2
    assert Decimal.equal?(Ledger.get_transaction(tx.id).quantity, Decimal.new("12"))
    assert Decimal.equal?(held_quantity(world, security), Decimal.new("12"))
  end

  test "a refused edit keeps the drawer open with the values and the errors",
       %{conn: conn, world: world, security: security, transaction: tx} do
    {:ok, view, _html} = live(conn, "/transactions")

    view |> element("#tx-kebab-#{tx.id}") |> render_click()
    view |> element("#tx-edit-#{tx.id}") |> render_click()

    view
    |> form("#transaction-form", %{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-01-05",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "-1",
        "price" => "100"
      }
    })
    |> render_submit()

    assert has_element?(view, "#booking-drawer")
    assert Decimal.equal?(Ledger.get_transaction(tx.id).quantity, Decimal.new("10"))
  end

  test "closing the drawer returns it to recording a new transaction",
       %{conn: conn, transaction: tx} do
    {:ok, view, _html} = live(conn, "/transactions")

    view |> element("#tx-kebab-#{tx.id}") |> render_click()
    view |> element("#tx-edit-#{tx.id}") |> render_click()
    assert view |> element("#booking-drawer") |> render() =~ "Edit transaction"

    view |> element("#booking-cancel") |> render_click()
    refute has_element?(view, "#booking-drawer")

    view |> element("#open-booking") |> render_click()
    drawer = view |> element("#booking-drawer") |> render()
    assert drawer =~ "Record transaction"
    refute drawer =~ ~s(value="2026-01-05")
  end
end
