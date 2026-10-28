defmodule Portfolixir.Ledger.UpdateLockCycleTest do
  # #1214: a booking edit that loses a lock cycle answers a retryable
  # refusal, never a crash. The edits that close a cycle with a merge are
  # raced on two real connections by the lock-order harness
  # (test/portfolixir/lock_race/same_currency_test.exs); this module pins the
  # answer the edit gives when PostgreSQL aborts it all the same (40P01).
  #
  # The database's answer is raised for one marked note by a trigger the test
  # installs inside its sandbox transaction (`Portfolixir.LostLockCycle`),
  # whose DDL locks the table for the test's duration, hence async: false.
  #
  # Every name, figure and date is synthetic.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures, only: [base_world: 1, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.LostLockCycle

  @marker "a lost lock cycle"

  setup do
    :ok = LostLockCycle.install!(@marker)

    world = base_world(name: "Lock Cycle", cash_name: "Lock Cycle Cash")
    %{booking: deposit!(world, "250.00", ~D[2026-09-03])}
  end

  defp update_entries(booking) do
    Journal.list_entries(
      resource_type: "transaction",
      resource_id: to_string(booking.id),
      operation: :update
    )
  end

  # User story (#1214; ADR-0050 §10; ADR-0036, risk-tier):
  # As the operator or the agent editing a booking while a concurrent write
  # takes the same rows in another order,
  # I want an edit the database aborted to answer "changed while saving,
  # try again",
  # so that I retry the edit instead of meeting a server error.
  #
  # Acceptance criteria:
  # - An update aborted with 40P01 answers `{:error, :raced}`; the booking is
  #   stored as before and nothing is journaled.
  # - The same edit, retried, saves.
  # - Inside a caller's own transaction the error is raised on, so that the
  #   caller's whole write rolls back (the import correction's confirm).
  test "an edit the database aborts in a lock cycle answers a retryable refusal",
       %{booking: booking} do
    assert {:error, :raced} =
             Ledger.update_transaction(Actor.owner_ui(), booking, %{notes: @marker})

    stored = Ledger.get_transaction(booking.id)
    assert stored.notes == nil
    assert stored.gross_amount == Decimal.new("250.000000")
    assert update_entries(booking) == []

    assert {:ok, %{notes: "retried"}} =
             Ledger.update_transaction(Actor.owner_ui(), booking, %{notes: "retried"})

    assert [_one] = update_entries(booking)

    assert_raise Postgrex.Error, fn ->
      Repo.transaction(fn ->
        Ledger.update_transaction(Actor.owner_ui(), booking, %{notes: @marker})
      end)
    end
  end
end
