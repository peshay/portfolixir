defmodule Portfolixir.Derived.CommitOrderTest do
  # E25 S6 (#891), F47: a basis's data version is the highest event id, and
  # event ids are taken when the bump runs inside the writing transaction,
  # not when it commits. A writer that took the lower id and commits last
  # leaves the version where the other writer put it, so a value read between
  # the two commits — without the late writer's data — stays current. Every
  # in-transaction bump is therefore marked pending and bumped once more after
  # its commit.
  #
  # The two writers must really commit, so they run outside the SQL sandbox
  # on their own connections; the rows they commit are removed afterwards.
  use Portfolixir.DataCase, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Derived
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Derived.Memo
  alias Portfolixir.Derived.PostCommit
  alias Portfolixir.DerivedConfig

  @table "derived_data_version_events"

  setup do
    Memo.reset()
    DerivedConfig.enable!()

    floor = unboxed(fn -> Repo.one(from(e in @table, select: coalesce(max(e.id), 0))) end)

    on_exit(fn ->
      Memo.reset()
      unboxed(fn -> Repo.delete_all(from(e in @table, where: e.id > ^floor)) end)
    end)

    :ok
  end

  # Outside the sandbox, on a connection of its own: `unboxed_run/2` checks
  # the calling process's connection in, so it never runs in the test process.
  defp unboxed(fun), do: fn -> Sandbox.unboxed_run(Repo, fun) end |> Task.async() |> Task.await()

  # A writer on its own connection: bumps inside its transaction, tells the
  # test, and commits when told.
  defp late_writer(portfolio_id) do
    parent = self()

    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.transaction(fn ->
          DataVersion.bump([portfolio_id], Repo, [])
          send(parent, :bumped)

          receive do
            :commit -> :ok
          end
        end)
      end)
    end)
  end

  # User story:
  # As the operator reading derived figures while writes land,
  # I want a value computed without a write that commits later never to stay
  # current once that write has committed,
  # so that no figure goes stale for good because two writes committed in
  # the other order than they bumped.
  #
  # Acceptance criteria:
  # - Writer A bumps (the lower id) and holds its transaction; writer B bumps
  #   (a higher id) and commits; a value is read and remembered; A commits.
  #   After A's post-commit bump the next read recomputes instead of serving
  #   the remembered value.
  test "two connections interleaved so the lower id commits last never leave a stale value served" do
    portfolio_id = -System.unique_integer([:positive])
    basis = DataVersion.portfolio_basis(portfolio_id)

    writer_a = late_writer(portfolio_id)
    assert_receive :bumped, 5_000

    unboxed(fn -> Repo.transaction(fn -> DataVersion.bump([portfolio_id], Repo, []) end) end)

    assert {:fresh, :before_a} =
             Derived.fetch(:portfolio_metrics, basis, "f47", fn -> :before_a end)

    send(writer_a.pid, :commit)
    Task.await(writer_a)

    PostCommit.settle(Repo)

    assert {:fresh, :after_a} =
             Derived.fetch(:portfolio_metrics, basis, "f47", fn -> :after_a end)
  end

  # User story:
  # As the operator of a running instance,
  # I want the post-commit bump to happen by itself shortly after a commit,
  # so that no reader has to wait for another write to see the late one.
  #
  # Acceptance criteria:
  # - The application supervises the settling process.
  # - Told that a pending bump happened, the process settles it: the basis's
  #   version passes the committed writer's id, and the mark is cleared.
  test "the running process settles a committed pending bump after it is told" do
    assert Enum.any?(Portfolixir.Application.children(), &match?({PostCommit, _}, &1))

    portfolio_id = -System.unique_integer([:positive])
    basis = DataVersion.portfolio_basis(portfolio_id)

    unboxed(fn -> Repo.transaction(fn -> DataVersion.bump([portfolio_id], Repo, []) end) end)
    committed = DataVersion.current(basis)

    pid = start_supervised!({PostCommit, interval_ms: 60_000, settle_delay_ms: 0})
    Sandbox.allow(Repo, self(), pid)
    PostCommit.notify()

    assert eventually(fn -> DataVersion.current(basis) > committed end)

    refute Repo.exists?(from(e in @table, where: e.basis == ^basis and e.pending == true))

    # Stopped while the test still owns the connection it was allowed.
    stop_supervised!(PostCommit)
  end

  defp eventually(check, attempts \\ 50) do
    cond do
      check.() -> true
      attempts == 0 -> false
      true -> Process.sleep(20) && eventually(check, attempts - 1)
    end
  end
end
