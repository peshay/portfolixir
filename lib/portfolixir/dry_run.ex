defmodule Portfolixir.DryRun do
  @moduledoc """
  A delete's dry run (Sprint 25 X1, #894, idea F21; the plan's D-4).

  The real delete runs inside a transaction that **always rolls back**, so
  the answer is exactly what the delete does, refusals included: never a
  count computed beside it, which could drift from the delete and say less
  than it does. ADR-0050's probe reads the import's dry run the same way
  (`Portfolixir.Imports.Applier`, amended 2026-10-09).

  What the delete removed is read inside the same transaction: for each
  kind of row the delete reaches, the ids its table held before the delete
  ran and no longer holds after it, so a row the database's own cascade
  took is named as well as a row a journaled writer took. Every row the
  delete wrote — the journal's entries, the derived layer's version events —
  rolls back with the rest.

  The transaction is REPEATABLE READ (Sprint 25 closing act): at READ
  COMMITTED each read took a fresh snapshot, so a row a concurrent
  transaction deleted between the read before the delete and the read after
  it was named as one the delete removes. Both reads now see one snapshot
  plus the transaction's own deletes. A delete that then meets a row a
  concurrent transaction changed fails with a serialization failure, and
  the dry run answers `{:error, :concurrent_change}`: nothing was deleted
  either way, and a retry decides. Under the SQL sandbox the dry run's
  transaction is a savepoint inside the test's, where PostgreSQL refuses an
  isolation level, so the level is set only where `Repo.transaction/1`
  opens a transaction of its own; the scratch-database tests
  (`Portfolixir.LockRace.DryRunDeleteTest`) pin it on real connections.

  Nothing outside the transaction hears of a dry run: while one runs,
  `active?/0` is true in its process, and the derived layer's version bump
  (`Portfolixir.Derived.DataVersion`) then tells neither the refresher nor
  the post-commit process, whose events would be rolled back before they
  could read them.
  """

  import Ecto.Query, only: [select: 3]

  alias Portfolixir.Repo

  @flag {__MODULE__, :active}

  @typedoc "A kind of row the delete reaches, and the schema of its table."
  @type kinds :: [{atom(), module()}]

  @typedoc "Per kind, the count and the ids (ascending) the delete removed."
  @type removed :: %{atom() => %{count: non_neg_integer(), ids: [integer()]}}

  @doc """
  Runs `delete` (a function answering `{:ok, _}` or `{:error, reason}`, the
  real delete) in a transaction that always rolls back. Answers
  `{:ok, removed}` with, per kind of `kinds`, the count and the ids of the
  rows the delete removed (every kind listed, a count of 0 where it removed
  none), the delete's own `{:error, reason}`, or `{:error,
  :concurrent_change}` when a concurrent transaction changed a row the
  delete reached after the dry run's snapshot.
  """
  @spec run(kinds(), (-> {:ok, term()} | {:error, term()})) :: {:ok, removed()} | {:error, term()}
  def run(kinds, delete) when is_list(kinds) and is_function(delete, 0) do
    previous = Process.put(@flag, true)
    own_transaction? = own_transaction?()

    try do
      fn ->
        if own_transaction?, do: Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
        before = ids(kinds)

        case delete.() do
          {:ok, _deleted} -> Repo.rollback({__MODULE__, {:ok, removed(kinds, before)}})
          {:error, reason} -> Repo.rollback({__MODULE__, {:error, reason}})
        end
      end
      |> Repo.transaction()
      |> case do
        {:error, {__MODULE__, answer}} -> answer
      end
    rescue
      error in Postgrex.Error ->
        case error do
          %Postgrex.Error{postgres: %{code: :serialization_failure}} ->
            {:error, :concurrent_change}

          _other ->
            reraise error, __STACKTRACE__
        end
    after
      if previous, do: Process.put(@flag, previous), else: Process.delete(@flag)
    end
  end

  @doc "Whether a dry run is running in this process."
  @spec active?() :: boolean()
  def active?, do: Process.get(@flag, false)

  # Whether `Repo.transaction/1` opens a transaction of its own here, whose
  # isolation level can still be set: not inside another transaction, and
  # not on the SQL sandbox's ownership pool, whose every transaction is a
  # savepoint inside the test's.
  defp own_transaction? do
    not Repo.in_transaction?() and
      Ecto.Adapter.lookup_meta(Repo.get_dynamic_repo()).opts[:pool] != DBConnection.Ownership
  end

  defp ids(kinds) do
    Map.new(kinds, fn {kind, schema} ->
      {kind, schema |> select([r], r.id) |> Repo.all() |> MapSet.new()}
    end)
  end

  defp removed(kinds, before) do
    after_delete = ids(kinds)

    Map.new(kinds, fn {kind, _schema} ->
      ids = before |> Map.fetch!(kind) |> MapSet.difference(after_delete[kind]) |> Enum.sort()
      {kind, %{count: length(ids), ids: ids}}
    end)
  end
end
