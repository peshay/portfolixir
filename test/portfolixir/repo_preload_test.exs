defmodule Portfolixir.RepoPreloadTest do
  # #1018: Ecto runs the preloads of a read outside a transaction in tasks
  # of their own, each checking out a connection. Under the SQL sandbox every
  # query of a test runs on the test's one connection, so those tasks could
  # only queue for it, and under load the queue dropped one of them: the read
  # failed with "connection not available and request was dropped from
  # queue" (seen in the security merge preview, an API id-range sweep and a
  # LiveView mount). The test configuration preloads on the calling process.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  # User story:
  # As the maintainer whose suite runs under load,
  # I want a test's preloads to run on the test's own process,
  # so that none of them queues for the test's single sandbox connection and
  # is dropped from that queue.
  #
  # Acceptance criteria:
  # - Preloading two associations outside a transaction, with
  #   `Repo.preload/2` and through a query's `preload:`, sends every query
  #   from the calling process: no preload task runs.
  test "preloads run on the calling process, never in tasks of their own" do
    world = base_world(name: "Preload #{System.unique_integer([:positive])}")
    security = create_security!(name: "Preload Co.", ticker: "PRLD")
    buy!(world, security, quantity: "1", price: "10")

    test_pid = self()
    handler = "repo-preload-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, _metadata, _config ->
          if test_pid in Process.get(:"$callers", []), do: send(test_pid, :query_in_a_task)
        end,
        nil
      )

    try do
      refute Repo.in_transaction?()

      [tx] =
        security.id
        |> Ledger.list_transactions_for_security()
        |> Repo.preload([:security, :cash_account], force: true)

      assert tx.security.id == security.id

      [queried] =
        Repo.all(
          from(t in Transaction,
            where: t.security_id == ^security.id,
            preload: [:security, :cash_account]
          )
        )

      assert queried.cash_account.id == world.cash.id
    after
      :telemetry.detach(handler)
    end

    refute_received :query_in_a_task
  end
end
