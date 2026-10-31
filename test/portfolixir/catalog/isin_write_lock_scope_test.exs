defmodule Portfolixir.Catalog.IsinWriteLockScopeTest do
  # #1018: every ISIN writer takes the ISIN write lock, a transaction-scoped
  # advisory lock, so two concurrent ISIN writes serialize (ADR-0029 §3). A
  # sandboxed test never commits: its transaction, and the lock with it, lasts
  # until the test ends. With one lock for the whole database, every async
  # test that wrote an ISIN waited for the one before it to end -- the class
  # of hazard #947 removed for bucket names. The test sandbox therefore scopes
  # the lock to its own transaction; outside the sandbox it stays the one lock
  # of the database. Real two-connection serialization is pinned by the
  # lock-order harness (`Portfolixir.LockRace`), which runs outside the
  # sandbox. Since the security review of 2026-10-12 (H53) the lock is one per
  # normalized ISIN: its second key folds the scope and the ISIN together.
  use Portfolixir.DataCase, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.IdentifierAliases

  # User story:
  # As the maintainer running the suite,
  # I want a sandboxed test's ISIN writes to take an ISIN write lock of their
  # own,
  # so that an async test writing an ISIN never waits for another to end.
  #
  # Acceptance criteria:
  # - After an ISIN write in the sandbox, the test's transaction holds the
  #   ISIN write lock of that ISIN under its own scope (its connection's
  #   backend pid), and not under the database-wide scope 0.
  test "a sandboxed ISIN write holds the lock of its own transaction" do
    # An ISIN of this test's own: ISINs are unique instance-wide.
    isin = "XS" <> String.pad_leading("#{System.unique_integer([:positive])}", 10, "0")

    {:ok, _security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Lock Scope AG",
        isin: isin,
        currency_code: "EUR"
      })

    %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")

    assert held_isin_scopes(Repo) == [unsigned(lock_key(Repo, "#{backend}", isin))]
  end

  # User story (security review 2026-10-12, H53):
  # As the operator whose agent and import write ISINs at the same time,
  # I want every writer of one ISIN to take the one same lock, and writers
  # of other ISINs another,
  # so that two writes of one ISIN can never both pass the uniqueness check,
  # and a long write of some ISINs never holds up the writers of the rest.
  #
  # Acceptance criteria:
  # - Outside the sandbox, an ISIN writer's transaction holds one ISIN write
  #   lock per ISIN it writes, under scope 0, whatever an earlier transaction
  #   on the same connection set: the same key for the same ISIN in any
  #   letter case or padding, another key for another ISIN.
  # - Its locks are taken in ascending key order.
  test "outside the sandbox the ISIN write lock is one lock per ISIN" do
    {held, taken, expected} =
      fn ->
        Sandbox.unboxed_run(Repo, fn ->
          {:ok, outcome} =
            Repo.transaction(fn ->
              taken =
                observe_locks(fn ->
                  {:ok, :locked} =
                    IdentifierAliases.lock_isin_writes(Repo, [
                      "DE000EXMPL17",
                      " de000exmpl17 ",
                      "XS0000000165",
                      nil
                    ])
                end)

              expected =
                Enum.sort([
                  lock_key(Repo, "0", "DE000EXMPL17"),
                  lock_key(Repo, "0", "XS0000000165")
                ])

              {held_isin_scopes(Repo), taken, expected}
            end)

          outcome
        end)
      end
      |> Task.async()
      |> Task.await()

    assert held == Enum.sort(Enum.map(expected, &unsigned/1))
    assert taken == expected
  end

  # The second key of the ISIN write lock of `isin` under `scope`.
  defp lock_key(_repo, scope, isin), do: IdentifierAliases.lock_key_for(scope, isin)

  # pg_locks shows a two-key advisory lock's second key as an unsigned oid.
  defp unsigned(key) when key < 0, do: key + 4_294_967_296
  defp unsigned(key), do: key

  # The second keys of the ISIN write locks `fun` takes, in the order taken.
  defp observe_locks(fun) do
    handler = "isin-lock-order-#{System.unique_integer([:positive])}"
    me = self()

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _m, meta, _config ->
          with true <- self() == me,
               query when is_binary(query) <- meta[:query],
               true <- String.contains?(query, "pg_advisory_xact_lock("),
               [key, second] <- meta[:params],
               true <- key == IdentifierAliases.isin_write_lock_key() do
            Process.put(:isin_locks_taken, [second | Process.get(:isin_locks_taken, [])])
          end
        end,
        nil
      )

    try do
      fun.()
      Enum.reverse(Process.get(:isin_locks_taken, []))
    after
      :telemetry.detach(handler)
    end
  end

  # The second keys of the ISIN write locks the calling connection holds, as
  # stored: the two-key form of a transaction advisory lock stores its keys in
  # classid and objid, and marks itself with objsubid 2.
  defp held_isin_scopes(repo) do
    %{rows: rows} =
      repo.query!(
        """
        SELECT objid::bigint FROM pg_locks
        WHERE locktype = 'advisory' AND pid = pg_backend_pid() AND granted
          AND classid::bigint = $1 AND objsubid = 2
        ORDER BY objid
        """,
        [IdentifierAliases.isin_write_lock_key()]
      )

    Enum.map(rows, fn [scope] -> scope end)
  end
end
