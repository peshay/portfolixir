defmodule Portfolixir.LockRace.Sprint18Test do
  # A split event's whole delete (U1, #912) against a re-book of the same
  # split, raced on two real connections by the lock-order harness (#996).
  # The closing act of Sprint 18's PR γ found the re-book could slip a row
  # into a portfolio between the delete's lock and its commit, leaving a
  # split the operator had just deleted alive in one portfolio. Both writers
  # now take one advisory lock per security first, so one waits for the
  # other and each reads what the other committed.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits, and need no other test's load on the cores.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.LockRace
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @moduletag :lock_race

  @bought_on ~D[2026-08-03]
  @split_on ~D[2026-09-15]

  setup_all do
    %{db: LockRace.database!()}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  defp owner, do: Actor.owner_ui()

  # A portfolio holding 10 units of `security`, bought before the split day.
  defp holder!(name, security) do
    world =
      WorldFixtures.base_world(name: name, cash_name: "#{name} Cash", depot_name: "#{name} Depot")

    WorldFixtures.deposit!(world, "1000", @bought_on)
    WorldFixtures.buy!(world, security, quantity: "10", price: "50", date: @bought_on)
    world
  end

  defp split_attrs(security),
    do: %{security_id: security.id, date: @split_on, ratio_numerator: 2, ratio_denominator: 1}

  defp split_portfolios(security) do
    Repo.all(
      from(t in Transaction,
        where: t.type == "split" and t.security_id == ^security.id,
        select: t.portfolio_id,
        order_by: t.portfolio_id
      )
    )
  end

  # Two portfolios carry the split; a third is positioned before the split
  # day only afterwards (a backdated buy), so an identical re-book extends
  # the event to it.
  defp world(name) do
    security = WorldFixtures.create_security!(name: "#{name} AG", ticker: nil)
    a = holder!("#{name} A", security)
    b = holder!("#{name} B", security)
    {:ok, [row_a, _row_b]} = Splits.book_split(owner(), split_attrs(security))
    c = holder!("#{name} C", security)

    %{
      security: security,
      row_a: row_a,
      ids: Enum.sort([a.portfolio.id, b.portfolio.id, c.portfolio.id])
    }
  end

  # User story (#912 review round):
  # As the operator deleting a split booked with the wrong ratio while the
  # agent books the same split again,
  # I want the two to take turns,
  # so that the split ends up booked everywhere or nowhere, never in one
  # portfolio of the three.
  #
  # Acceptance criteria:
  # - With the whole-split delete held after its first lock, the re-book
  #   waits for it; neither deadlocks.
  # - The delete removes both rows it found; the re-book then books the
  #   event anew in all three positioned portfolios.
  test "a re-book waits for the whole-split delete and books the event everywhere", %{db: db} do
    w = world("Race Delete First")

    {deleted, rebooked} =
      LockRace.race!(
        db,
        {fn -> Splits.delete_split(owner(), w.row_a) end, &LockRace.lock?/1},
        fn -> Splits.book_split(owner(), split_attrs(w.security)) end
      )

    assert {:ok, [_a, _b]} = deleted
    assert {:ok, [_, _, _]} = rebooked
    assert split_portfolios(w.security) == w.ids
  end

  # Acceptance criteria:
  # - With the re-book held after its first lock, the whole-split delete
  #   waits for it; neither deadlocks.
  # - The re-book extends the event to the third portfolio; the delete then
  #   removes all three rows, so no portfolio keeps the split.
  test "a whole-split delete waits for a re-book and deletes the row it added", %{db: db} do
    w = world("Race Book First")

    {rebooked, deleted} =
      LockRace.race!(
        db,
        {fn -> Splits.book_split(owner(), split_attrs(w.security)) end, &LockRace.lock?/1},
        fn -> Splits.delete_split(owner(), w.row_a) end
      )

    assert {:ok, [_c]} = rebooked
    assert {:ok, [_, _, _]} = deleted
    assert split_portfolios(w.security) == []
  end
end
