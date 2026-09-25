defmodule Portfolixir.Lifecycle do
  @moduledoc """
  The lifecycle of cash accounts, depots and securities: rename, merge and
  delete under a post-merge re-import contract (ADR-0050).

  This module holds the two records every merge leaves behind, and their
  writers:

    * a **merge record** (`Portfolixir.Lifecycle.MergeRecord`, §12) — one per
      merge, append-only, `UNIQUE (kind, source_id)`;
    * a **retired import hash** (`Portfolixir.Lifecycle.RetiredImportHash`,
      §3) — one per row a merge removes, so the held-or-retired hash set only
      grows (obligation O1) and the database refuses the hash on
      `transactions` from then on.

  Both writers are actor-first and journaled (ADR-0017, resource codes
  `merge_record` and `retired_import_hash`); both tables are append-only and
  journal-armed from the migrations that create them. Each writer runs in its
  own transaction, which joins the caller's when a merge calls it inside one.

  The foreign-key disposition map every merge and delete is held against is
  `Portfolixir.Lifecycle.ForeignKeys` (§14).
  """

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Lifecycle.RetiredImportHash
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

  @doc """
  Retires the content hash of a row a merge removed, on behalf of `actor`,
  journaled as a `retired_import_hash` create. The retirement names its merge
  record by `merge_record_id`; that foreign key is checked when the merge's
  transaction commits, so a merge may retire before it writes its record.
  """
  @spec retire_import_hash(Actor.t(), map()) ::
          {:ok, RetiredImportHash.t()} | {:error, Ecto.Changeset.t()}
  def retire_import_hash(%Actor{} = actor, attrs) when is_map(attrs) do
    attrs
    |> RetiredImportHash.changeset()
    |> journaled_insert(actor, "retired_import_hash")
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
