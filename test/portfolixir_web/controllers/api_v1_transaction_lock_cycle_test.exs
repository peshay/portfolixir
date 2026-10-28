defmodule PortfolixirWeb.ApiV1TransactionLockCycleTest do
  # #1214: PATCH /api/v1/transactions/:id answers an edit PostgreSQL aborted
  # in a lock cycle (40P01) with a retryable 409, never a 500. The cycle
  # itself is raced on two real connections by the lock-order harness
  # (test/portfolixir/lock_race/same_currency_test.exs); here the database's
  # answer is raised for one marked note (`Portfolixir.LostLockCycle`), whose
  # DDL locks the table for the test's duration, hence async: false.
  #
  # Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase, async: false

  import Portfolixir.WorldFixtures, only: [base_world: 1, deposit!: 3]

  alias Portfolixir.Ledger
  alias Portfolixir.LostLockCycle

  @marker "a lost lock cycle"

  setup %{conn: conn} do
    :ok = LostLockCycle.install!(@marker)
    world = base_world(name: "Lock Cycle API", cash_name: "Lock Cycle API Cash")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn, booking: deposit!(world, "250.00", ~D[2026-09-03])}
  end

  # User story (#1214; ADR-0050 §10):
  # As the agent editing a booking over the API while a concurrent write
  # takes the same rows in another order,
  # I want an edit the database aborted to answer a 409 that says to read
  # the booking again and retry,
  # so that I retry instead of reporting a server error.
  #
  # Acceptance criteria:
  # - The PATCH answers 409 with `errors.detail` saying the transaction
  #   changed while it was being saved, nothing was saved, and to read it
  #   again and retry the update.
  # - The booking is stored as before.
  test "an update aborted in a lock cycle answers a retryable 409",
       %{conn: conn, booking: booking} do
    conn =
      patch(
        conn,
        "/api/v1/transactions/#{booking.id}",
        Jason.encode!(%{"transaction" => %{"notes" => @marker}})
      )

    assert json_response(conn, 409) == %{
             "errors" => %{
               "detail" =>
                 "transaction changed while it was being saved, and nothing was saved: " <>
                   "read it again and retry the update"
             }
           }

    assert Ledger.get_transaction(booking.id).notes == nil
  end
end
