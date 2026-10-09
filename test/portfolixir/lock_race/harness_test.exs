defmodule Portfolixir.LockRace.HarnessTest do
  # The lock-order harness's own failure paths (Sprint 17, Lane G-2, #996),
  # run for real in CI: two writers locking two rows of a table of the
  # scratch database in opposite orders make the race fail on the 40P01 the
  # database answers -- the in-CI form of the mutation evidence the Sprint 16
  # races were verified with -- and every other way a race can go wrong
  # fails it by name.
  #
  # async: false -- the races share a scratch database.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.LockRace
  alias Portfolixir.Repo
  alias Portfolixir.ScratchDatabase

  @moduletag :lock_race

  setup_all do
    db = LockRace.database!()
    ScratchDatabase.query!(db, "CREATE TABLE lock_race_rows (id integer PRIMARY KEY)")
    ScratchDatabase.query!(db, "INSERT INTO lock_race_rows SELECT generate_series(1, 20)")
    %{db: db}
  end

  # One transaction locking `ids` FOR UPDATE, in that order.
  defp lock_rows(ids) do
    fn ->
      Repo.transaction(fn ->
        for id <- ids do
          Repo.query!("SELECT id FROM lock_race_rows WHERE id = $1 FOR UPDATE", [id])
        end

        ids
      end)
    end
  end

  defp never_ends, do: fn -> receive(do: (:never -> :ok)) end

  # User story:
  # As the maintainer relying on a lock-order case to stop two writers that
  # could deadlock,
  # I want the harness to fail the case when the database aborts a writer
  # with a deadlock, and when the race could not have tested a lock order,
  # so that a green race means the two writers really queued.
  #
  # Acceptance criteria:
  # - Two writers locking two rows in opposite orders fail the race naming
  #   the 40P01 and the query it aborted; in one order they both finish.
  # - A second writer that never waits on the first, a writer that raises, a
  #   first writer that ends before its pause point, a step not reached in
  #   time and a writer that cannot get a connection each fail the race by
  #   name.
  test "two writers locking two rows in opposite orders fail on the deadlock", %{db: db} do
    error =
      assert_raise ExUnit.AssertionError, fn ->
        LockRace.race!(db, {lock_rows([1, 2]), &LockRace.lock?/1}, lock_rows([2, 1]))
      end

    # The database aborts whichever writer's deadlock check finds the cycle:
    # the second, which waited first, unless a loaded machine delays it.
    assert error.message =~
             ~r/a deadlock \(40P01\): the database aborted the (first|second) writer at/

    assert error.message =~ "FROM lock_race_rows WHERE id = $1 FOR UPDATE"

    assert {{:ok, [3, 4]}, {:ok, [3, 4]}} =
             LockRace.race!(db, {lock_rows([3, 4]), &LockRace.lock?/1}, lock_rows([3, 4]))
  end

  test "a second writer that never waits on the first fails the race", %{db: db} do
    assert_raise ExUnit.AssertionError, ~r/so the race tested\s+no lock order/, fn ->
      LockRace.race!(db, {lock_rows([5]), &LockRace.lock?/1}, lock_rows([6]))
    end
  end

  # User story (#922 closing act):
  # As the maintainer pinning a lock a writer no longer takes,
  # I want a race in which the second writer must pass the held first one,
  # so that a lock that comes back fails the case by name.
  #
  # Acceptance criteria:
  # - With `second: :passes`, a second writer that ends while the first is
  #   held passes the race, and the first then resumes and ends.
  # - One the database reports blocked by the first fails the race.
  test "a second writer that is to pass the first passes it or fails the race", %{db: db} do
    assert {{:ok, [12]}, {:ok, [13]}} =
             LockRace.race!(db, {lock_rows([12]), &LockRace.lock?/1}, lock_rows([13]),
               second: :passes
             )

    assert_raise ExUnit.AssertionError,
                 ~r/the second writer waited on the first, which it was to pass/,
                 fn ->
                   LockRace.race!(db, {lock_rows([14]), &LockRace.lock?/1}, lock_rows([14]),
                     second: :passes
                   )
                 end
  end

  test "a writer that raises fails the race with its exception", %{db: db} do
    raising = fn ->
      lock_rows([7]).()
      raise "synthetic writer failure"
    end

    assert_raise ExUnit.AssertionError,
                 ~r/the first writer raised:\s+\*\* \(RuntimeError\) synthetic writer failure/,
                 fn -> LockRace.race!(db, {raising, &LockRace.lock?/1}, lock_rows([7])) end
  end

  test "a first writer that ends before its pause point fails the race", %{db: db} do
    assert_raise ExUnit.AssertionError,
                 ~r/the first writer ended before it reached its pause point:\s+returned :no_lock/,
                 fn ->
                   LockRace.race!(db, {fn -> :no_lock end, &LockRace.lock?/1}, lock_rows([8]))
                 end
  end

  test "a step the race does not reach in time fails it, naming the step", %{db: db} do
    assert_raise ExUnit.AssertionError,
                 ~r/the first writer did not reach its pause point within 1000 ms/,
                 fn ->
                   LockRace.race!(db, {never_ends(), &LockRace.lock?/1}, lock_rows([9]),
                     timeout: 1_000
                   )
                 end

    assert_raise ExUnit.AssertionError,
                 ~r/the second writer neither waited on the first nor ended within 1000 ms/,
                 fn ->
                   LockRace.race!(db, {lock_rows([10]), &LockRace.lock?/1}, never_ends(),
                     timeout: 1_000
                   )
                 end

    # The writers those races left paused or waiting were killed with their
    # transactions: both rows are free again.
    assert {{:ok, [9, 10]}, {:ok, [9, 10]}} =
             LockRace.race!(db, {lock_rows([9, 10]), &LockRace.lock?/1}, lock_rows([9, 10]))
  end

  test "a writer that cannot get a connection fails the race", %{db: db} do
    gone = %{db | repo: spawn(fn -> :ok end)}

    # The writer logs its crash report before it exits (#1046), so the report
    # is in this capture by the time the race has seen the exit.
    log =
      capture_log(fn ->
        assert_raise ExUnit.AssertionError,
                     ~r/the first writer exited before it got a connection/,
                     fn ->
                       LockRace.race!(gone, {lock_rows([11]), &LockRace.lock?/1}, lock_rows([11]))
                     end
      end)

    assert log =~ "the first writer raised:"
  end

  test "the pause predicates pass over a query event that carries no text" do
    assert LockRace.lock?(%{query: "SELECT id FROM t WHERE id = $1 FOR NO KEY UPDATE"})
    assert LockRace.lock?(%{query: "SELECT pg_advisory_xact_lock($1)"})
    refute LockRace.lock?(%{query: "SELECT id FROM t"})
    refute LockRace.lock?(%{})

    insert? = LockRace.query?(~s(INSERT INTO "transactions"))
    assert insert?.(%{query: ~s|INSERT INTO "transactions" ("id") VALUES ($1)|})
    refute insert?.(%{query: nil})
  end
end
