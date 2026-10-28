defmodule Portfolixir.Ledger.SettlementBackfillLockCycleTest do
  # #1214: the settlement backfill's answer to a booking whose update lost a
  # lock cycle with a concurrent write (40P01). The database's answer is
  # raised for one marked note by a trigger installed inside the test's
  # sandbox transaction (`Portfolixir.LostLockCycle`), whose DDL locks the
  # table for the test's duration, hence async: false.
  #
  # Every name, figure and date is synthetic. The booking and rate day,
  # 2026-01-19, is this module's own (#1018).
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Mix.Tasks.Portfolixir.BackfillSettlementLegs
  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.SettlementBackfill
  alias Portfolixir.LostLockCycle

  @marker "a lost lock cycle"

  setup do
    :ok = LostLockCycle.install!(@marker)

    w = base_world(name: "Backfill Cycle", cash_name: "BC Cash", depot_name: "BC Depot")
    security = create_security!(name: "Backfill Cycle US Equity", ticker: "BCU", currency: "USD")

    # An imported cross-currency buy before ADR-0033, carrying the marked
    # note, so every update of it is aborted with 40P01.
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-19],
        quantity: "10",
        price: "80.00",
        currency_code: "EUR",
        notes: @marker
      })

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-01-19],
          rate: "1.25",
          source: "manual"
        }
      ])

    %{tx: tx}
  end

  # User story (#1214; ADR-0033):
  # As the maintainer running the settlement backfill while the app writes,
  # I want a booking whose update lost a lock cycle to be named, with the
  # advice to re-run,
  # so that the task stops cleanly instead of crashing on its own report.
  #
  # Acceptance criteria:
  # - `SettlementBackfill.run/1` answers `{:error, {transaction_id, :raced}}`
  #   and the booking keeps no settlement leg.
  # - The mix task stops with a `Mix.raise` naming the booking, saying it
  #   lost a lock cycle with a concurrent write and nothing was written for
  #   it, and to re-run the task.
  test "a booking whose update lost a lock cycle is reported with the advice to re-run",
       %{tx: tx} do
    assert {:error, {id, :raced}} =
             SettlementBackfill.run(Actor.system_job("settlement_backfill"))

    assert id == tx.id
    assert Ledger.get_transaction(tx.id).security_amount == nil

    Mix.shell(Mix.Shell.Process)

    try do
      error = assert_raise Mix.Error, fn -> BackfillSettlementLegs.run([]) end

      assert error.message ==
               "Backfill stopped at transaction ##{tx.id}: its update lost a lock cycle with " <>
                 "a concurrent write and nothing was written for it. Re-run the task."
    after
      Mix.shell(Mix.Shell.IO)
    end
  end
end
