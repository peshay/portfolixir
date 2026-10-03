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
  # sandbox.
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
  #   ISIN write lock under its own scope (its connection's backend pid), and
  #   not under the database-wide scope 0.
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

    assert held_isin_scopes(Repo) == [backend]
  end

  # User story:
  # As the operator whose agent and import write ISINs at the same time,
  # I want every ISIN writer of the instance to take the one same lock,
  # so that two writes of one ISIN can never both pass the uniqueness check.
  #
  # Acceptance criteria:
  # - Outside the sandbox, an ISIN writer's transaction holds the ISIN write
  #   lock under scope 0: one lock for the whole database, whatever an
  #   earlier transaction on the same connection set.
  test "outside the sandbox the ISIN write lock is the one lock of the database" do
    scopes =
      fn ->
        Sandbox.unboxed_run(Repo, fn ->
          {:ok, scopes} =
            Repo.transaction(fn ->
              {:ok, :locked} = IdentifierAliases.lock_isin_writes(Repo, %{})
              held_isin_scopes(Repo)
            end)

          scopes
        end)
      end
      |> Task.async()
      |> Task.await()

    assert scopes == [0]
  end

  # The scopes (second keys) of the ISIN write locks the calling connection
  # holds: the two-key form of a transaction advisory lock stores its keys in
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
