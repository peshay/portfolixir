defmodule Portfolixir.Derived.VersionLogCompactionTest do
  use Portfolixir.DataCase, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Derived.PostCommit
  alias Portfolixir.DerivedConfig

  @table "derived_data_version_events"

  setup do
    DerivedConfig.enable!()
    :ok
  end

  defp basis, do: "portfolio:#{-System.unique_integer([:positive])}"

  defp event!(basis, pending) do
    {1, [%{id: id}]} =
      Repo.insert_all(@table, [%{basis: basis, pending: pending}], returning: [:id])

    id
  end

  defp rows(basis),
    do:
      Repo.all(
        from(e in @table, where: e.basis == ^basis, order_by: e.id, select: {e.id, e.pending})
      )

  defp eventually(check, attempts \\ 100) do
    cond do
      check.() -> true
      attempts == 0 -> false
      true -> Process.sleep(20) && eventually(check, attempts - 1)
    end
  end

  # User story (security review 2026-10-12, H10):
  # As the operator of a small home server,
  # I want the derived layer's version log compacted on a schedule,
  # so that it stops growing with every quote sync while every derived
  # value's version stays exactly what it was.
  #
  # Acceptance criteria:
  # - After many bumps of one basis, the running post-commit process leaves
  #   one row for that basis, its newest, so DataVersion.current/1 answers
  #   the same value before and after; another basis keeps its version too.
  test "the running post-commit process compacts the log to the newest row per basis" do
    busy = basis()
    other = basis()

    for _ <- 1..6, do: event!(busy, false)
    for _ <- 1..3, do: event!(other, false)

    busy_version = DataVersion.current(busy)
    other_version = DataVersion.current(other)

    pid =
      start_supervised!(
        Supervisor.child_spec({PostCommit, interval_ms: 20, settle_delay_ms: 0},
          restart: :temporary
        )
      )

    Sandbox.allow(Repo, self(), pid)

    assert eventually(fn -> length(rows(busy)) == 1 and length(rows(other)) == 1 end),
           "the version log kept #{length(rows(busy))} rows for one basis"

    # Stopped between two messages, never inside a query (#927).
    GenServer.stop(pid)

    assert rows(busy) == [{busy_version, false}]
    assert DataVersion.current(busy) == busy_version
    assert DataVersion.current(other) == other_version
  end

  # User story (security review 2026-10-12, H10):
  # As the operator,
  # I want the compaction to leave every pending event alone,
  # so that a write whose second bump is still due keeps the mark that
  # makes it happen.
  #
  # Acceptance criteria:
  # - Only settled events below a basis's newest settled event are removed;
  #   a pending event, older or newer, stays with its mark.
  test "compaction removes settled events below the newest settled one and keeps pending ones" do
    b = basis()
    _old = event!(b, false)
    _older_settled = event!(b, false)
    pending_low = event!(b, true)
    newest_settled = event!(b, false)
    pending_high = event!(b, true)
    version = DataVersion.current(b)

    :ok = DataVersion.compact_settled(Repo)

    assert rows(b) == [{pending_low, true}, {newest_settled, false}, {pending_high, true}]
    assert DataVersion.current(b) == version
  end
end
