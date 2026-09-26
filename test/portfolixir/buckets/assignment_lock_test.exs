defmodule Portfolixir.Buckets.AssignmentLockTest do
  # E25 S6 (#891), G10: the four bucket-assignment writers replace a set by
  # deleting the owner's rows and inserting the new ones. Without a lock on
  # the owner, two writers interleave and leave the union of both sets, and
  # an override can end up holding the explicit-empty marker next to bucket
  # rows, which every view-scoped read used to raise on. Each writer now
  # locks the owning depot or cash-account row as its first step, and a
  # mixed override is logged and read as explicit-empty.
  use Portfolixir.DataCase, async: true

  import ExUnit.CaptureLog

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.PositionBucketOverride
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios
  alias Portfolixir.WorldFixtures

  defp owner, do: Actor.owner_ui()

  defp bucket!(label) do
    {:ok, bucket} =
      Buckets.create_bucket(owner(), %{
        name: "#{label} #{System.unique_integer([:positive])}",
        dimension: "tag"
      })

    bucket
  end

  # User story:
  # As the operator and the agent tagging the same account at the same time,
  # I want each assignment write to hold the account while it replaces the
  # set,
  # so that two writes end with exactly one request's set and never the
  # union of both.
  #
  # Acceptance criteria:
  # - Each of the four assignment writers (depot default set, cash-account
  #   set, position override, override clear) locks the owning depot or cash
  #   account row before it touches the assignment rows, and that lock is
  #   the transaction's first read.
  test "each assignment writer locks its owning account before it replaces the set" do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!(name: "Lockstep Fund", ticker: "LSF")
    bucket = bucket!("Lock")

    writes = [
      {"securities_accounts", "securities_account_buckets",
       fn -> Buckets.set_depot_default_buckets(owner(), world.depot, [bucket.id]) end},
      {"cash_accounts", "cash_account_buckets",
       fn -> Buckets.set_cash_account_buckets(owner(), world.cash, [bucket.id]) end},
      {"securities_accounts", "position_bucket_overrides",
       fn -> Buckets.set_position_override(owner(), world.depot, security, [bucket.id]) end},
      {"securities_accounts", "position_bucket_overrides",
       fn -> Buckets.clear_position_override(owner(), world.depot, security) end}
    ]

    for {owner_table, set_table, write} <- writes do
      queries = capture_queries(fn -> assert :ok = write.() end)

      lock = Enum.find_index(queries, &(&1 =~ ~r/FROM "#{owner_table}".*FOR (NO KEY )?UPDATE/s))
      clear = Enum.find_index(queries, &(&1 =~ ~r/^DELETE FROM "#{set_table}"/))

      assert lock, "no lock on #{owner_table} before writing #{set_table}"
      assert clear, "no delete of #{set_table}"
      assert lock < clear

      # Between the transaction's begin and the lock only the journal's
      # actor setting runs: no row is read before the owner is held.
      preamble =
        queries
        |> Enum.take(lock)
        |> Enum.reverse()
        |> Enum.take_while(&(&1 != "begin"))

      assert Enum.all?(preamble, &(&1 =~ ~r/^SELECT set_config/)),
             "the lock on #{owner_table} is not the first read of the #{set_table} write"
    end
  end

  # User story:
  # As the agent writing an account's bucket set while the operator deletes
  # that account,
  # I want the write to answer that the account is gone,
  # so that it neither crashes nor journals a set for an account that no
  # longer exists.
  #
  # Acceptance criteria:
  # - Each assignment writer answers not found for a deleted owner and
  #   journals nothing.
  test "an assignment write to an account deleted in the meantime answers not found" do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!(name: "Gone Fund", ticker: "GNF")
    bucket = bucket!("Gone")

    {:ok, depot} =
      Portfolios.create_securities_account(owner(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        name: "Spare Depot"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(owner(), %{
        portfolio_id: world.portfolio.id,
        name: "Spare Cash",
        currency_code: "EUR",
        liquidity_role: "free_cash"
      })

    assert {:ok, _} = Portfolios.delete_securities_account(owner(), depot)
    assert {:ok, _} = Portfolios.delete_cash_account(owner(), cash)

    before = length(Journal.list_entries())

    assert Buckets.set_depot_default_buckets(owner(), depot, [bucket.id]) == {:error, :not_found}
    assert Buckets.set_cash_account_buckets(owner(), cash, []) == {:error, :not_found}

    assert Buckets.set_position_override(owner(), depot, security, [bucket.id]) ==
             {:error, :not_found}

    assert Buckets.clear_position_override(owner(), depot, security) == {:error, :not_found}

    assert length(Journal.list_entries()) == before
  end

  # User story:
  # As the operator opening a view-scoped page,
  # I want a position whose stored override is inconsistent to be logged and
  # kept out of the views its buckets would reach,
  # so that one damaged row neither crashes every scoped read nor widens a
  # view.
  #
  # Acceptance criteria:
  # - An override holding the explicit-empty marker next to a bucket row is
  #   read as explicit-empty, with a warning in the log.
  # - The portfolio scope and the instance scope load without raising, and
  #   the position is outside a view that includes its bucket.
  test "a mixed override is logged and read as explicit-empty instead of raising" do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!(name: "Mixed Fund", ticker: "MXF")
    bucket = bucket!("Mixed")

    {:ok, view} =
      Buckets.create_view(owner(), %{name: "Mixed view #{bucket.id}", include_all: false})

    :ok = Buckets.set_view_buckets(owner(), view, [bucket.id], [])

    Repo.insert_all(PositionBucketOverride, [
      %{securities_account_id: world.depot.id, security_id: security.id, bucket_id: nil},
      %{securities_account_id: world.depot.id, security_id: security.id, bucket_id: bucket.id}
    ])

    log =
      capture_log(fn ->
        assert Buckets.position_override(world.depot.id, security.id) == :explicit_empty

        scope = Buckets.load_scope(world.portfolio.id, view.id)
        refute Buckets.position_in_scope?(scope, world.depot.id, security.id)

        global = Buckets.load_global_scope(view.id)
        refute Buckets.position_in_scope?(global, world.depot.id, security.id)

        assert %{overrides: overrides} = Buckets.global_assignments()
        assert overrides[{world.depot.id, security.id}] == :explicit_empty
      end)

    assert log =~ "position_bucket_overrides"
    assert log =~ "explicit-empty"
  end

  defp capture_queries(fun) do
    test_pid = self()
    handler = "buckets-assignment-lock-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if self() == test_pid, do: send(test_pid, {:query, query})
        end,
        nil
      )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    collect_queries([])
  end

  defp collect_queries(acc) do
    receive do
      {:query, query} -> collect_queries([query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
