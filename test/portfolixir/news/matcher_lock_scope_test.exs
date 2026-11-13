defmodule Portfolixir.News.MatcherLockScopeTest do
  # Closing act (flaky): the news matcher's lock (ORD5, `Portfolixir.News`)
  # is one transaction-scoped advisory lock for the whole database. A
  # sandboxed test never commits, so a test that matched an aggregator item,
  # re-rated one (S29 N1) or changed a news identity held it until it ended,
  # and the scheduler test's fetch waited for that whole test on the one
  # connection its fetch tasks share: a sibling task queued behind it was
  # dropped and logged `fetch_failed`. The test sandbox therefore scopes the
  # lock to its own transaction, as it does the ISIN write lock (#1018);
  # outside the sandbox it stays the one lock of the database, and the real
  # two-connection serialization is pinned by the lock-order harness
  # (`test/portfolixir/lock_race/news_retier_order_test.exs`).
  use Portfolixir.DataCase, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.News
  alias Portfolixir.Repo

  @matcher_lock 727_227_006

  # The matcher locks the calling transaction holds, as {first key, second
  # key}: an advisory lock of the two-key form reads classid and objid.
  defp held_matcher_locks do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT classid::bigint, objid::bigint, objsubid
          FROM pg_locks
         WHERE locktype = 'advisory' AND pid = pg_backend_pid() AND granted
           AND ((objsubid = 2 AND classid::bigint = $1) OR (objsubid = 1 AND objid::bigint = $1))
        """,
        [@matcher_lock]
      )

    Enum.map(rows, fn
      [first, second, 2] -> {first, second}
      [_high, low, 1] -> {low, :single}
    end)
  end

  # User story:
  # As the maintainer running the suite,
  # I want a sandboxed test's matcher lock to be its own,
  # so that an async test's fetch never waits for another test to end.
  #
  # Acceptance criteria:
  # - In the sandbox, the matcher lock a test takes is keyed by its own
  #   connection's backend pid, not by the database-wide 0.
  # - Another test's sandbox holding its matcher lock does not make this
  #   test's matcher wait.
  # - Outside the sandbox it is the one lock of the database (second key 0).
  describe "the matcher's lock" do
    test "in the sandbox is the test's own" do
      %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
      {:ok, held} = Repo.transaction(fn -> :ok = News.lock_matcher() end)
      assert held == :ok
      assert held_matcher_locks() == [{@matcher_lock, backend}]
    end

    test "another test holding it is not waited for" do
      parent = self()

      holder =
        spawn(fn ->
          owner = Sandbox.start_owner!(Repo, shared: false)

          Repo.query!(
            "SELECT set_config('portfolixir.matcher_lock_scope', pg_backend_pid()::text, true)"
          )

          {:ok, :ok} = Repo.transaction(fn -> News.lock_matcher() end)
          send(parent, :held)

          receive do
            :release -> Sandbox.stop_owner(owner)
          end
        end)

      assert_receive :held, 5_000

      try do
        assert {:ok, :ok} =
                 Repo.transaction(fn ->
                   Repo.query!("SET LOCAL lock_timeout = '1s'")
                   News.lock_matcher()
                 end)
      after
        send(holder, :release)
      end
    end

    test "outside the sandbox is one lock for the whole database" do
      held =
        fn ->
          Sandbox.unboxed_run(Repo, fn ->
            {:ok, held} =
              Repo.transaction(fn ->
                :ok = News.lock_matcher()
                held_matcher_locks()
              end)

            held
          end)
        end
        |> Task.async()
        |> Task.await()

      assert held == [{@matcher_lock, 0}]
    end
  end
end
