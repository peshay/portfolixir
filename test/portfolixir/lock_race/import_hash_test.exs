defmodule Portfolixir.LockRace.ImportHashTest do
  # The two import-hash triggers raced on two real connections by the
  # lock-order harness (#996): a booking of hash H and a retirement of H
  # (#917, ADR-0050 §16, the 2026-10-06 note to invariant 4). Each trigger
  # checks the other table, and under READ COMMITTED neither sees the other's
  # uncommitted row, so without a lock both could commit and the live and
  # retired sets would meet. Both triggers take the import-hash lock first,
  # one key for every hash, shared by a booking and exclusive to a
  # retirement, so the second writer waits for the first, reads what it
  # committed, and is refused.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits, and need no other test's load on the cores.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.RetiredImportHash
  alias Portfolixir.LockRace
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @moduletag :lock_race

  setup_all do
    %{db: LockRace.database!()}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  defp world(name) do
    world = WorldFixtures.base_world(name: name, cash_name: "#{name} Cash")

    {:ok, record} =
      Lifecycle.record_merge(Actor.owner_ui(), %{
        kind: "cash_account",
        source_id: world.cash.id + 1_000_000,
        target_id: world.cash.id,
        portfolio_id: world.portfolio.id,
        source_snapshot: %{"name" => "#{name} (old)"},
        manifest: %{},
        plan_digest: "sha256:synthetic-plan"
      })

    Map.put(world, :record, record)
  end

  defp book(world, hash) do
    Ledger.create_transaction(
      Actor.import_session(),
      %{
        type: "deposit",
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        currency_code: "EUR",
        date: ~D[2026-01-05],
        gross_amount: Decimal.new("10")
      },
      import_hash: hash
    )
  end

  defp retire(world, hash) do
    Lifecycle.retire_import_hash(Actor.owner_ui(), %{
      import_hash: hash,
      former_transaction_id: 9_000_001,
      merge_record_id: world.record.id,
      reason: "internal_transfer"
    })
  end

  defp held?(hash), do: Repo.exists?(from(t in Transaction, where: t.import_hash == ^hash))

  defp retired?(hash),
    do: Repo.exists?(from(r in RetiredImportHash, where: r.import_hash == ^hash))

  # User story (#917):
  # As the maintainer of the post-merge re-import contract,
  # I want a booking and a retirement of one hash, run at the same time, to
  # take turns,
  # so that the hash ends up live or retired, never both.
  #
  # Acceptance criteria:
  # - With the booking held after its insert, the retirement waits for it,
  #   then is refused as a hash a transaction still holds.
  # - The hash is live and not retired; neither writer deadlocks.
  test "a retirement waits for a booking of the same hash and is refused", %{db: db} do
    w = world("Race Book First")

    {booked, retired} =
      LockRace.race!(
        db,
        {fn -> book(w, "synthetic-race-book-first") end,
         LockRace.query?(~s(INSERT INTO "transactions"))},
        fn -> retire(w, "synthetic-race-book-first") end
      )

    assert {:ok, %Transaction{}} = booked
    assert {:error, changeset} = retired
    assert {"is still held by a transaction", _} = changeset.errors[:import_hash]
    assert held?("synthetic-race-book-first")
    refute retired?("synthetic-race-book-first")
  end

  # Acceptance criteria:
  # - With the retirement held after its insert, the booking waits for it,
  #   then is refused as a hash a merge retired.
  # - The hash is retired and not live; neither writer deadlocks.
  test "a booking waits for a retirement of the same hash and is refused", %{db: db} do
    w = world("Race Retire First")

    {retired, booked} =
      LockRace.race!(
        db,
        {fn -> retire(w, "synthetic-race-retire-first") end,
         LockRace.query?(~s(INSERT INTO "retired_import_hashes"))},
        fn -> book(w, "synthetic-race-retire-first") end
      )

    assert {:ok, %RetiredImportHash{}} = retired
    assert {:error, changeset} = booked

    assert {"was retired by a merge and cannot be booked again", _} =
             changeset.errors[:import_hash]

    assert retired?("synthetic-race-retire-first")
    refute held?("synthetic-race-retire-first")
  end
end
