defmodule PortfolixirWeb.TransactionLockCycleLiveTest do
  # #1214: the booking drawer answers an edit PostgreSQL aborted in a lock
  # cycle (40P01) with a message to try again, never a crash. The cycle
  # itself is raced on two real connections by the lock-order harness
  # (test/portfolixir/lock_race/same_currency_test.exs); here the database's
  # answer is raised for one marked note (`Portfolixir.LostLockCycle`), whose
  # DDL locks the table for the test's duration, hence async: false.
  #
  # Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3]

  alias Portfolixir.Ledger
  alias Portfolixir.LostLockCycle

  @marker "a lost lock cycle"

  setup do
    :ok = LostLockCycle.install!(@marker)
    world = base_world(name: "Lock Cycle Drawer", cash_name: "Lock Cycle Drawer Cash")
    security = create_security!(name: "Lock Cycle Drawer AG", ticker: "LCDA")
    booking = deposit!(world, "250.00", ~D[2026-09-03])
    buy = buy!(world, security, quantity: "2", price: "40", date: ~D[2026-09-04])
    %{booking: booking, buy: buy}
  end

  # User story (#1214; ADR-0050 §10):
  # As the operator saving a booking's note while a concurrent write takes
  # the same rows in another order,
  # I want an edit the database aborted to say that nothing was saved and
  # to try again, with what I typed kept,
  # so that I save it again instead of losing the page to an error.
  #
  # Acceptance criteria:
  # - The drawer stays open with the typed note and says the transaction
  #   changed while it was being saved, so nothing was saved, and to try
  #   again.
  # - The booking is stored as before.
  test "a note save aborted in a lock cycle says to try again", %{conn: conn, booking: booking} do
    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#tx-kebab-#{booking.id}") |> render_click()
    view |> element("#tx-edit-#{booking.id}") |> render_click()

    html =
      view
      |> form("#note-form", %{"note" => %{"notes" => @marker}})
      |> render_submit()

    assert html =~
             "That transaction changed while it was being saved, so nothing was saved. Try again."

    assert has_element?(view, "dialog#booking-drawer #note-form textarea", @marker)
    assert Ledger.get_transaction(booking.id).notes == nil
  end

  # Acceptance criteria (the buy and sell drawer):
  # - Saving an edit of a buy that the database aborted keeps the drawer
  #   open with what was typed and says to try again; the buy is stored as
  #   before.
  test "a buy edit aborted in a lock cycle says to try again", %{conn: conn, buy: buy} do
    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#tx-kebab-#{buy.id}") |> render_click()
    view |> element("#tx-edit-#{buy.id}") |> render_click()

    html =
      view
      |> form("#transaction-form", %{"transaction" => %{"notes" => @marker}})
      |> render_submit()

    assert html =~
             "That transaction changed while it was being saved, so nothing was saved. Try again."

    assert has_element?(view, "#transaction-form textarea[name='transaction[notes]']", @marker)

    stored = Ledger.get_transaction(buy.id)
    assert stored.notes == nil
    assert stored.quantity == Decimal.new("2.000000000000")
  end
end
