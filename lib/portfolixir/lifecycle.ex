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
  `Portfolixir.Lifecycle.ForeignKeys` (§14); the hardened delete of a cash
  account, a depot or a security that reads it is
  `Portfolixir.Lifecycle.Delete` (§11).

  The merges themselves: a cash account into another
  (`preview_cash_merge/2`, `merge_cash_account/4`, implemented by
  `Portfolixir.Lifecycle.CashMerge`, §7, §8, §10), a depot into another
  (`preview_depot_merge/2`, `merge_depot/4`, implemented by
  `Portfolixir.Lifecycle.DepotMerge`) and a security into another
  (`preview_security_merge/2`, `merge_security/4`, implemented by
  `Portfolixir.Lifecycle.SecurityMerge`, §9), each writing row by row through
  `Portfolixir.Lifecycle.MergeWriter` under a digest from
  `Portfolixir.Lifecycle.PlanDigest`, with the consent rules they share in
  `Portfolixir.Lifecycle.MergeFlow`.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle.CashMerge
  alias Portfolixir.Lifecycle.DepotMerge
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Lifecycle.RetiredImportHash
  alias Portfolixir.Lifecycle.SecurityMerge
  alias Portfolixir.Repo

  # Ids are never reused, so a merge chain cannot cycle; the bound only keeps
  # a corrupted record set from looping.
  @max_chain 1_000

  @doc """
  Writes the record of a merge on behalf of `actor`, journaled as a
  `merge_record` create. The actor is recorded from `actor`, never from
  `attrs`. A source already merged under the same kind answers a changeset
  error on `source_id`.

  `id:` in `opts` writes the record under an id reserved with
  `reserve_merge_record_id/0`: a merge retires the hashes of the rows it
  removes under its record's id before it writes the record last (§7 step 7),
  and the deferred foreign key checks the pair when the merge commits.
  """
  @spec record_merge(Actor.t(), map(), keyword()) ::
          {:ok, MergeRecord.t()} | {:error, Ecto.Changeset.t()}
  def record_merge(%Actor{} = actor, attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    attrs
    |> MergeRecord.create_changeset(actor)
    |> put_reserved_id(Keyword.get(opts, :id))
    |> journaled_insert(actor, "merge_record")
  end

  @doc """
  Reserves the id the record of a merge in progress will carry, from the
  table's own sequence, so the retirements that name it can be written
  first. A merge that rolls back leaves a gap in the ids, never a record.
  """
  @spec reserve_merge_record_id() :: pos_integer()
  def reserve_merge_record_id do
    %{rows: [[id]]} = Repo.query!("SELECT nextval('merge_records_id_seq')")
    id
  end

  @doc """
  The preview of a merge of the cash account `source_id` into `target_id`
  (ADR-0050 §7, §8, §10): a read. See `Portfolixir.Lifecycle.CashMerge`.
  """
  defdelegate preview_cash_merge(source_id, target_id), to: CashMerge, as: :preview

  @doc """
  Merges the cash account `source_id` into `target_id` on behalf of `actor`
  under the approved `plan_digest` and the operator's `collapse_key_equal`
  choice (ADR-0050 §7, §8, §10, §12). See `Portfolixir.Lifecycle.CashMerge`.
  """
  defdelegate merge_cash_account(actor, source_id, target_id, params), to: CashMerge, as: :apply

  @doc """
  The preview of a merge of the depot `source_id` into `target_id` (ADR-0050
  §7, §8, §10): a read. See `Portfolixir.Lifecycle.DepotMerge`.
  """
  defdelegate preview_depot_merge(source_id, target_id), to: DepotMerge, as: :preview

  @doc """
  Merges the depot `source_id` into `target_id` on behalf of `actor` under
  the approved `plan_digest` and the operator's `collapse_key_equal` choice
  (ADR-0050 §7, §8, §10, §12). See `Portfolixir.Lifecycle.DepotMerge`.
  """
  defdelegate merge_depot(actor, source_id, target_id, params), to: DepotMerge, as: :apply

  @doc """
  The preview of a merge of the security `source_id` into `target_id`
  (ADR-0050 §8, §9, §10): a read. See `Portfolixir.Lifecycle.SecurityMerge`.
  """
  defdelegate preview_security_merge(source_id, target_id), to: SecurityMerge, as: :preview

  @doc """
  Merges the security `source_id` into `target_id` on behalf of `actor` under
  the approved `plan_digest`, the operator's `collapse_key_equal` choice and,
  when both carry an ISIN, the operator's `identity_choice` (ADR-0050 §8, §9,
  §10, §12). See `Portfolixir.Lifecycle.SecurityMerge`.
  """
  defdelegate merge_security(actor, source_id, target_id, params),
    to: SecurityMerge,
    as: :apply

  @doc """
  The record of the merge that took `source_id` away under `kind`, or `nil`.
  """
  @spec merge_of(:cash_account | :securities_account | :security, integer()) ::
          MergeRecord.t() | nil
  def merge_of(kind, source_id)
      when kind in [:cash_account, :securities_account, :security] and is_integer(source_id) do
    Repo.one(from(m in MergeRecord, where: m.kind == ^kind and m.source_id == ^source_id))
  end

  @typedoc "One merge record as the audit read lists it, with the names a reader needs (§12)."
  @type listed_merge :: %{
          record: MergeRecord.t(),
          source_name: String.t() | nil,
          target_name: String.t() | nil,
          target_merged_into: integer() | nil
        }

  @doc """
  The merge records, newest first (`inserted_at`, then `id`, descending), at
  most `limit` — the audit read of a destructive write (ADR-0050 §12). Each
  carries the source's name as its snapshot recorded it, the target's live
  name, and — for a target a later merge took away — the name that merge
  recorded and the live end of the chain in `target_merged_into` (`nil`
  while the target is live).
  """
  @spec list_merges(pos_integer()) :: [listed_merge()]
  def list_merges(limit) when is_integer(limit) and limit > 0 do
    records =
      Repo.all(from(m in MergeRecord, order_by: [desc: m.inserted_at, desc: m.id], limit: ^limit))

    live = live_names(Enum.map(records, &{&1.kind, &1.target_id}))

    Enum.map(records, fn record ->
      key = {record.kind, record.target_id}

      {target_name, merged_into} =
        case Map.fetch(live, key) do
          {:ok, name} -> {name, nil}
          :error -> {recorded_name(record.kind, record.target_id), survivor(key)}
        end

      %{
        record: record,
        source_name: snapshot_name(record),
        target_name: target_name,
        target_merged_into: merged_into
      }
    end)
  end

  @doc """
  The merges into each of `target_ids` under `kind`, oldest first, as
  `%{target_id => [%{source_id, source_name, source_isin, merged_on}]}` —
  what a survivor shows as "merged from …" (ADR-0050 §12). `source_isin` is
  the ISIN a security's snapshot recorded (`nil` for an account, or a
  security without one). `merged_on` is the host's
  calendar date of the merge (`Portfolixir.Clock.local_date/1`). Direct
  merges only: a source that was itself a survivor keeps its own sources.
  """
  @spec merged_from(:cash_account | :securities_account | :security, [integer()]) :: %{
          optional(integer()) => [
            %{
              source_id: integer(),
              source_name: String.t() | nil,
              source_isin: String.t() | nil,
              merged_on: Date.t()
            }
          ]
        }
  def merged_from(kind, target_ids)
      when kind in [:cash_account, :securities_account, :security] and is_list(target_ids) do
    from(m in MergeRecord,
      where: m.kind == ^kind and m.target_id in ^target_ids,
      order_by: [asc: m.inserted_at, asc: m.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.target_id, fn record ->
      %{
        source_id: record.source_id,
        source_name: snapshot_name(record),
        source_isin: snapshot_isin(record),
        merged_on: Portfolixir.Clock.local_date(record.inserted_at)
      }
    end)
  end

  @live_schemas %{
    cash_account: Portfolixir.Portfolios.CashAccount,
    securities_account: Portfolixir.Portfolios.SecuritiesAccount,
    security: Portfolixir.Catalog.Security
  }

  defp live_names(keys) do
    keys
    |> Enum.uniq()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {kind, ids} ->
      from(r in Map.fetch!(@live_schemas, kind), where: r.id in ^ids, select: {r.id, r.name})
      |> Repo.all()
      |> Enum.map(fn {id, name} -> {{kind, id}, name} end)
    end)
    |> Map.new()
  end

  # A target no row carries any more was taken away by a later merge, whose
  # snapshot recorded its name — or deleted once it held nothing, which
  # leaves no merge record to name it (nil).
  defp recorded_name(kind, id) do
    case merge_of(kind, id) do
      %MergeRecord{} = record -> snapshot_name(record)
      nil -> nil
    end
  end

  defp survivor({kind, id}), do: merged_into(kind, id)

  defp snapshot_name(%MergeRecord{source_snapshot: %{"name" => name}}) when is_binary(name),
    do: name

  defp snapshot_name(_record), do: nil

  defp snapshot_isin(%MergeRecord{source_snapshot: %{"isin" => isin}}) when is_binary(isin),
    do: isin

  defp snapshot_isin(_record), do: nil

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

  @doc """
  The survivor of a merged-away row: the target of the merge record whose
  source is `id` under `kind`, followed through every later merge of that
  target to the live end of the chain (ADR-0050 §10, §12). `nil` when no merge
  record names `id` as its source.
  """
  @spec merged_into(:cash_account | :securities_account | :security, integer()) ::
          integer() | nil
  def merged_into(kind, id)
      when kind in [:cash_account, :securities_account, :security] and is_integer(id),
      do: follow(kind, id, nil, @max_chain)

  defp follow(_kind, _id, found, 0), do: found

  defp follow(kind, id, found, hops) do
    case Repo.one(
           from(m in MergeRecord,
             where: m.kind == ^kind and m.source_id == ^id,
             select: m.target_id
           )
         ) do
      nil -> found
      target -> follow(kind, target, target, hops - 1)
    end
  end

  defp put_reserved_id(changeset, nil), do: changeset

  defp put_reserved_id(changeset, id) when is_integer(id),
    do: Ecto.Changeset.put_change(changeset, :id, id)

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
