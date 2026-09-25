defmodule Portfolixir.Lifecycle.Delete do
  @moduledoc """
  The hardened delete of a cash account, a depot or a security (ADR-0050 §11,
  §16 invariant 11).

  `delete/2` runs in one database transaction:

    1. the row is read `FOR UPDATE`, so a booking onto it waits for the
       delete instead of slipping in between the check and the delete; a row
       that has vanished answers `{:error, :not_found}`;
    2. the **reference check**: every foreign key whose delete disposition is
       `:restrict` in `Portfolixir.Lifecycle.ForeignKeys` is counted, per
       referencing table — a transaction once, whichever leg references the
       row. Any reference answers `{:error, {:referenced, referenced_by}}` and
       writes nothing; `remedy/2` names what to do instead;
    3. `remove/2`: every **membership** (a `:remove_journaled` disposition —
       bucket links, position overrides, category assignments, position
       targets, identifier aliases) is removed through its journaled context
       function, one entry per account or position as that function already
       writes — the rows removed one by one are locked `FOR UPDATE` first, so
       a concurrent removal waits instead of making a per-row delete stale;
       then the row is deleted and its delete journaled with the full
       before-image.

  No cascade removes a membership: the database refuses the delete of a row
  that still carries one (the foreign keys restrict). The delete declares
  every foreign key onto its table, so a reference that appears after the
  check is refused as `{:error, {:referenced, referenced_by}}`, counted after
  the rollback, never raised as a constraint error.

  `remove/2` is the step after the check, for a caller that holds the row's
  lock and has found it unreferenced (a merge deletes its source through it,
  ADR-0050 §7 step 7). Inside the caller's transaction a refusal is
  `{:error, :raced}`, and the caller rolls back.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.PositionBucketOverride
  alias Portfolixir.Catalog.IdentifierAliases
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Assignment
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle.ForeignKeys
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Repo

  @type record :: %CashAccount{} | %SecuritiesAccount{} | Security.t()

  # The referencing columns as atoms, fixed when this module compiles, from
  # the static disposition map and never from input — so counting references
  # does not depend on a schema naming the column having been loaded first
  # (`String.to_existing_atom/1` failed on a fresh node until one was).
  @column_fields for %{columns: columns} <- ForeignKeys.dispositions(),
                     column <- columns,
                     into: %{},
                     do: {column, String.to_atom(column)}

  @typedoc "Referencing table => number of referencing rows; only tables that reference."
  @type referenced_by :: %{optional(String.t()) => pos_integer()}

  @type remedy :: :merge | :retire

  @tables %{
    CashAccount => "cash_accounts",
    SecuritiesAccount => "securities_accounts",
    Security => "securities"
  }

  @resource_types %{
    CashAccount => "cash_account",
    SecuritiesAccount => "securities_account",
    Security => "security"
  }

  # Each `:remove_journaled` foreign key of the disposition map, and the
  # journaled writer that removes its rows before the delete.
  @removers %{
    "cash_account_buckets_cash_account_id_fkey" => :cash_account_buckets,
    "securities_account_buckets_securities_account_id_fkey" => :depot_default_buckets,
    "position_bucket_overrides_securities_account_id_fkey" => :depot_position_overrides,
    "position_bucket_overrides_security_id_fkey" => :security_position_overrides,
    "security_category_assignments_security_id_fkey" => :category_assignments,
    "portfolio_targets_security_id_fkey" => :position_targets,
    "security_identifier_aliases_security_id_fkey" => :identifier_aliases
  }

  @doc """
  Deletes `record` on behalf of `actor` when nothing references it, removing
  its memberships through their journaled writers first. See the moduledoc
  for the steps. Called outside any transaction.
  """
  @spec delete(Actor.t(), record()) ::
          {:ok, record()}
          | {:error, :not_found | :raced | {:referenced, referenced_by()} | term()}
  def delete(%Actor{} = actor, %schema{id: id} = record) when is_map_key(@tables, schema) do
    fn ->
      with {:ok, locked} <- lock_row(schema, id),
           :ok <- unreferenced(locked),
           {:ok, deleted} <- remove_locked(actor, locked) do
        deleted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> count_after_refusal(record)
  end

  @doc """
  The step after the reference check: removes `record`'s memberships through
  their journaled writers, then deletes the row, journaled. For a caller that
  holds the row's lock and has found it unreferenced; a reference the check
  did not see is refused by the declared constraints — counted as
  `{:error, {:referenced, referenced_by}}` when this ran as its own
  transaction, `{:error, :raced}` inside the caller's, which rolls back.
  """
  @spec remove(Actor.t(), record()) ::
          {:ok, record()}
          | {:error, :not_found | :raced | {:referenced, referenced_by()} | term()}
  def remove(%Actor{} = actor, %schema{} = record) when is_map_key(@tables, schema) do
    fn ->
      case remove_locked(actor, record) do
        {:ok, deleted} -> deleted
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> count_after_refusal(record)
  end

  @doc """
  What references `record`, counted per referencing table (only the tables
  that do): every `:restrict` foreign key of the disposition map, a
  transaction counted once whichever leg references the row.
  """
  @spec referenced_by(record()) :: referenced_by()
  def referenced_by(%schema{id: id}) when is_map_key(@tables, schema) do
    @tables
    |> Map.fetch!(schema)
    |> restricting_columns()
    |> Enum.reduce(%{}, fn {table, columns}, acc ->
      case count_referencing(table, columns, id) do
        0 -> acc
        count -> Map.put(acc, table, count)
      end
    end)
  end

  @doc """
  What to do instead of deleting a referenced `record`: `:merge` it into the
  row to keep (ADR-0050 §7, §9), unless a reference a merge refuses to carry
  holds it — research notes and policy-rule versions on a security (§9) —
  when the remedy is to `:retire` it.
  """
  @spec remedy(record(), referenced_by()) :: remedy()
  def remedy(%schema{}, referenced_by) when is_map_key(@tables, schema) do
    unmergeable = unmergeable_tables(Map.fetch!(@tables, schema))

    if Enum.any?(Map.keys(referenced_by), &(&1 in unmergeable)), do: :retire, else: :merge
  end

  @doc """
  The delete changeset of `record`: it declares every foreign key of the
  disposition map onto the record's table, so a refusal by any of them is a
  changeset error, never an `Ecto.ConstraintError`.
  """
  @spec delete_changeset(record()) :: Changeset.t()
  def delete_changeset(%schema{} = record) when is_map_key(@tables, schema) do
    table = Map.fetch!(@tables, schema)

    for %{references: ^table, constraint: name} <- ForeignKeys.dispositions(),
        reduce: Changeset.change(record) do
      changeset ->
        Changeset.foreign_key_constraint(changeset, :id,
          name: name,
          message: "is referenced by existing records"
        )
    end
  end

  @doc "The `:remove_journaled` foreign keys this path has a journaled remover for."
  @spec removers() :: [String.t()]
  def removers, do: Map.keys(@removers)

  # -- the steps -------------------------------------------------------------

  defp lock_row(schema, id) do
    case Repo.one(from(r in schema, where: r.id == ^id, lock: "FOR UPDATE")) do
      nil -> {:error, :not_found}
      locked -> {:ok, locked}
    end
  end

  defp unreferenced(record) do
    case referenced_by(record) do
      references when map_size(references) == 0 -> :ok
      references -> {:error, {:referenced, references}}
    end
  end

  defp remove_locked(actor, record) do
    with :ok <- remove_memberships(actor, record) do
      delete_row(actor, record)
    end
  end

  defp remove_memberships(actor, %schema{} = record) do
    table = Map.fetch!(@tables, schema)

    ForeignKeys.dispositions()
    |> Enum.filter(&(&1.references == table and &1.delete == :remove_journaled))
    |> Enum.reduce_while(:ok, fn %{constraint: name}, :ok ->
      case remove_membership(Map.fetch!(@removers, name), actor, record) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp delete_row(actor, %schema{} = record) do
    Multi.new()
    |> Multi.delete(:record, delete_changeset(record), stale_error_field: :id)
    |> Journal.record(actor,
      resource_type: Map.fetch!(@resource_types, schema),
      operation: :delete,
      source: :record,
      before: record
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{record: deleted}} -> {:ok, deleted}
      {:error, :record, %Changeset{} = changeset, _changes} -> {:error, refusal(changeset)}
    end
  end

  defp refusal(%Changeset{errors: errors} = changeset) do
    cond do
      Enum.any?(errors, fn {_field, {_message, opts}} -> opts[:constraint] == :foreign end) ->
        :raced

      Enum.any?(errors, fn {_field, {_message, opts}} -> opts[:stale] == true end) ->
        :not_found

      true ->
        changeset
    end
  end

  # A refusal by a declared constraint aborts the transaction, so the
  # references are counted once it has rolled back. Inside a caller's
  # transaction nothing can be read any more: the caller gets `:raced`.
  defp count_after_refusal({:error, :raced}, record) do
    if Repo.in_transaction?(),
      do: {:error, :raced},
      else: {:error, {:referenced, referenced_by(record)}}
  end

  defp count_after_refusal(result, _record), do: result

  # -- the journaled membership removals --------------------------------------

  defp remove_membership(:cash_account_buckets, actor, %CashAccount{} = account) do
    case Buckets.cash_account_bucket_ids(account.id) do
      [] -> :ok
      _bucket_ids -> Buckets.set_cash_account_buckets(actor, account, [])
    end
  end

  defp remove_membership(:depot_default_buckets, actor, %SecuritiesAccount{} = depot) do
    case Buckets.depot_default_bucket_ids(depot.id) do
      [] -> :ok
      _bucket_ids -> Buckets.set_depot_default_buckets(actor, depot, [])
    end
  end

  defp remove_membership(:depot_position_overrides, actor, %SecuritiesAccount{} = depot) do
    from(o in PositionBucketOverride,
      where: o.securities_account_id == ^depot.id,
      distinct: true,
      order_by: o.security_id,
      select: o.security_id
    )
    |> Repo.all()
    |> each_removed(&Buckets.clear_position_override(actor, depot, %Security{id: &1}))
  end

  defp remove_membership(:security_position_overrides, actor, %Security{} = security) do
    from(o in PositionBucketOverride,
      where: o.security_id == ^security.id,
      distinct: true,
      order_by: o.securities_account_id,
      select: o.securities_account_id
    )
    |> Repo.all()
    |> each_removed(&Buckets.clear_position_override(actor, %SecuritiesAccount{id: &1}, security))
  end

  # The per-row removers below read a row, then delete it; its rows are
  # locked FOR UPDATE first, in this transaction, so a writer removing one of
  # them concurrently waits for the delete instead of leaving the per-row
  # delete stale (Ecto.StaleEntryError, a 500).
  defp remove_membership(:category_assignments, actor, %Security{} = security) do
    from(a in Assignment,
      where: a.security_id == ^security.id,
      order_by: a.classification_id,
      lock: "FOR UPDATE",
      select: a.classification_id
    )
    |> Repo.all()
    |> each_removed(&Classifications.unassign_security(actor, security.id, &1))
  end

  defp remove_membership(:position_targets, actor, %Security{} = security) do
    lock_memberships("portfolio_targets", security.id)
    actor |> Targets.delete_position_targets_for_security(security.id) |> removed()
  end

  defp remove_membership(:identifier_aliases, actor, %Security{} = security) do
    lock_memberships("security_identifier_aliases", security.id)
    actor |> IdentifierAliases.delete_all_for_security(security.id) |> removed()
  end

  defp lock_memberships(table, security_id) do
    from(m in table,
      where: m.security_id == ^security_id,
      order_by: m.id,
      lock: "FOR UPDATE",
      select: m.id
    )
    |> Repo.all()
  end

  defp each_removed(keys, remover) do
    Enum.reduce_while(keys, :ok, fn key, :ok ->
      case removed(remover.(key)) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp removed(:ok), do: :ok
  defp removed({:ok, _result}), do: :ok
  defp removed({:error, reason}), do: {:error, reason}

  # -- the disposition map, read -------------------------------------------

  # The single-column `:restrict` keys onto `table`, grouped by referencing
  # table; a composite key follows its single-column twin and is not counted
  # twice.
  defp restricting_columns(table) do
    ForeignKeys.dispositions()
    |> Enum.filter(&(&1.references == table and &1.delete == :restrict))
    |> Enum.filter(&match?([_column], &1.columns))
    |> Enum.group_by(& &1.table, fn %{columns: [column]} -> column end)
    |> Enum.sort()
  end

  defp count_referencing(table, columns, id) do
    condition =
      Enum.reduce(columns, dynamic(false), fn column, acc ->
        column = Map.fetch!(@column_fields, column)
        dynamic([r], field(r, ^column) == ^id or ^acc)
      end)

    Repo.one(from(r in table, where: ^condition, select: count()))
  end

  defp unmergeable_tables(table) do
    for %{references: ^table, merge: :refuse, table: referencing} <- ForeignKeys.dispositions(),
        uniq: true,
        do: referencing
  end
end
