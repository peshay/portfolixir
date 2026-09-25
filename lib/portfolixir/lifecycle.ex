defmodule Portfolixir.Lifecycle do
  @moduledoc """
  The lifecycle of cash accounts, depots and securities: rename, merge and
  delete under a post-merge re-import contract (ADR-0050).

  This module holds the record every merge leaves behind, and its writer: a
  **merge record** (`Portfolixir.Lifecycle.MergeRecord`, §12) — one per merge,
  append-only, `UNIQUE (kind, source_id)`.

  The writer is actor-first and journaled (ADR-0017, resource code
  `merge_record`); the table is append-only and journal-armed from the
  migration that creates it. The writer runs in its own transaction, which
  joins the caller's when a merge calls it inside one.
  """

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Repo

  @doc """
  Writes the record of a merge on behalf of `actor`, journaled as a
  `merge_record` create. The actor is recorded from `actor`, never from
  `attrs`. A source already merged under the same kind answers a changeset
  error on `source_id`.
  """
  @spec record_merge(Actor.t(), map()) :: {:ok, MergeRecord.t()} | {:error, Ecto.Changeset.t()}
  def record_merge(%Actor{} = actor, attrs) when is_map(attrs) do
    attrs
    |> MergeRecord.create_changeset(actor)
    |> journaled_insert(actor, "merge_record")
  end

  defp journaled_insert(changeset, actor, resource_type) do
    Multi.new()
    |> Multi.insert(:record, changeset)
    |> Journal.record(actor, resource_type: resource_type, operation: :create, source: :record)
    |> Repo.transaction()
    |> case do
      {:ok, %{record: record}} -> {:ok, record}
      {:error, :record, %Ecto.Changeset{} = error, _changes} -> {:error, error}
    end
  end
end
