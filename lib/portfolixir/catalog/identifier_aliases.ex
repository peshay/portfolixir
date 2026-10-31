defmodule Portfolixir.Catalog.IdentifierAliases do
  @moduledoc """
  Journaled ISIN-change aliases for securities (ADR-0029 §3).

  `record_isin_change/4` moves a security's current ISIN into a
  `security_identifier_aliases` row and writes the new ISIN onto the security,
  both in one journaled transaction (ADR-0017). Guards, all inside that
  transaction and serialized through an advisory lock:

    * the new ISIN must differ from the current one (A->A is rejected);
    * the new ISIN must not be live on another security, nor aliased to
      another security — the error names the conflicting security;
    * a new ISIN equal to one of the SAME security's own aliases consumes
      (deletes, journaled) that alias row, so a B->A revert works.

  The bidirectional half of the guard lives in `guard_isin_not_aliased/2`,
  which every security-ISIN write path (create/update, including the import
  applier's create path) runs inside its write transaction: an ISIN present in
  the alias table is rejected with an error naming the aliased security. The
  cross-table invariant cannot live in one index (ADR-0029 §3).

  Aliases are correctable master data, not write-once: `delete_alias/2` and
  `update_alias/3` (reassign/correct) are journaled at API/MCP parity.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.IdentifierAlias
  alias Portfolixir.Catalog.Isin
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  # All cross-table ISIN uniqueness checks take this advisory transaction lock
  # first, so two concurrent writes of one ISIN serialize instead of both
  # passing the check before either commits (ADR-0029 §3 "serialized check").
  #
  # The lock is the two-key form (key, ISIN): one lock per normalized ISIN
  # (security review 2026-10-12, H53), so a long transaction serializes only
  # the writers of its own ISINs, never every identifier writer of the
  # instance. A writer takes the lock of every ISIN it writes into either
  # column (a security's ISIN, a former ISIN), in ascending key order, so two
  # writers of the same two ISINs never wait on each other crosswise; two
  # ISINs that share a key only serialize more than they must. A writer of a
  # stored security's ISIN (an edit, an ISIN change, a merge) takes the
  # security's own key of this lock first, in ascending id order, and the
  # ISIN keys after it, the stored ISIN among them, read under that key: two
  # writers of one security queue there, and the ISIN its write replaces or
  # moves into the alias table is the one it locked.
  #
  # The key folds in a scope, '0' for the whole database, unless the
  # transaction has set `portfolixir.isin_write_lock_scope`, which only the
  # test sandbox does (#1018): a sandboxed test never commits, so it held its
  # locks until it ended and every other async test writing the same ISIN
  # waited for it. Each test's transaction scopes the locks to itself; its own
  # writers still serialize. A session that once set the value reads it back
  # as '' afterwards, hence the nullif.
  @isin_write_lock_key 727_202_907
  # The scope a transaction's locks fold in: '0' for the whole database.
  @isin_write_lock_scope_sql """
  SELECT coalesce(nullif(current_setting('portfolixir.isin_write_lock_scope', true), ''), '0')
  """

  @doc """
  Records an ISIN change on behalf of `actor` (ADR-0029 §3): the security's
  current ISIN becomes an alias row (`changed_on` defaults to today, optional
  `:note`), and `new_isin` (normalized to catalog normal form) is written onto
  the security — one journaled transaction.

  Returns `{:ok, %{security: updated, alias: alias_row}}` or
  `{:error, changeset}` with the guard violation on `:new_isin`.
  """
  def record_isin_change(actor, security, new_isin, opts \\ [])

  def record_isin_change(%Actor{} = actor, %Security{} = security, new_isin, opts)
      when is_list(opts) do
    changed_on = Keyword.get(opts, :changed_on) || Clock.today()
    note = Keyword.get(opts, :note)

    Repo.transaction(fn ->
      # The security's key, then the ISIN that becomes the alias (the stored
      # one) and the one that becomes the security's.
      acquire_security_isin_write_lock(Repo, [security.id], [new_isin])

      # The ISIN that becomes the alias is the stored one, read under the
      # row's lock, not the caller's copy (E25 S6, F49).
      with {:ok, security} <- lock_security(security),
           {:ok, normalized} <- validate_new_isin(security, new_isin),
           :ok <- consume_own_alias(actor, security, normalized),
           {:ok, alias_row} <- insert_alias(actor, security, security.isin, changed_on, note),
           {:ok, updated} <- write_new_isin(actor, security, normalized) do
        %{security: updated, alias: alias_row}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp lock_security(%Security{id: id}) do
    case Repo.one(from(s in Security, where: s.id == ^id, lock: "FOR UPDATE")) do
      nil -> {:error, :not_found}
      stored -> {:ok, stored}
    end
  end

  @doc """
  Records `former_isin` — the ISIN of a security a merge takes away — as a
  former ISIN of `security` on behalf of `actor` (ADR-0050 §9, the identity
  choice `keep_target_isin`): one journaled alias row (`changed_on` defaults
  to today, optional `:note`), so an export still carrying that ISIN resolves
  to `security` through the ladder's alias tier. `security`'s own ISIN is
  unchanged.

  The same guards as `record_isin_change/4`, under the same ISIN write lock:
  the ISIN must not be live on any security — the merge clears the source's
  first — nor recorded as a former ISIN already (the unique index). Returns
  `{:ok, alias_row}` or `{:error, changeset}` with the violation on
  `:former_isin`.
  """
  @spec record_merged_isin(Actor.t(), Security.t(), String.t(), keyword()) ::
          {:ok, IdentifierAlias.t()} | {:error, Changeset.t()}
  def record_merged_isin(%Actor{} = actor, %Security{} = security, former_isin, opts \\ [])
      when is_binary(former_isin) and is_list(opts) do
    changed_on = Keyword.get(opts, :changed_on) || Clock.today()
    normalized = IdentifierAlias.normalize_isin(former_isin)

    Repo.transaction(fn ->
      acquire_isin_write_lock(Repo, [normalized])

      with :ok <- ensure_merged_isin_not_live(normalized),
           {:ok, alias_row} <-
             insert_alias(actor, security, normalized, changed_on, Keyword.get(opts, :note)) do
        alias_row
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp ensure_merged_isin_not_live(isin) do
    case Repo.get_by(Security, isin: isin) do
      nil ->
        :ok

      %Security{} = other ->
        {:error,
         error_changeset(
           :former_isin,
           "is still the current ISIN of security #%{security_id}",
           named(other)
         )}
    end
  end

  @doc "Lists a security's identifier aliases, newest change first."
  def list_for_security(%Security{id: id}), do: list_for_security(id)

  def list_for_security(security_id) when is_integer(security_id) do
    Repo.all(
      from(a in IdentifierAlias,
        where: a.security_id == ^security_id,
        order_by: [desc: a.changed_on, desc: a.id]
      )
    )
  end

  @doc "Fetches one alias scoped to its security (nil when not found there)."
  def get_for_security(security_id, alias_id)
      when is_integer(security_id) and is_integer(alias_id) do
    Repo.get_by(IdentifierAlias, id: alias_id, security_id: security_id)
  end

  @doc """
  Deletes an alias on behalf of `actor`, journaled with the full `before`
  snapshot (ADR-0029 §3 correctability).
  """
  def delete_alias(%Actor{} = actor, %IdentifierAlias{} = alias_row) do
    multi =
      Multi.new()
      |> Multi.delete(:alias, alias_row)
      |> Journal.record(actor,
        resource_type: "security_identifier_alias",
        operation: :delete,
        source: :alias,
        before: alias_row
      )

    case Repo.transaction(multi) do
      {:ok, %{alias: deleted}} -> {:ok, deleted}
      {:error, :alias, %Changeset{} = changeset, _changes} -> {:error, changeset}
      # The row was deleted before the write took its lock (E25 S6, F49).
      {:error, {:journal_lock, _}, :not_found, _changes} -> {:error, :not_found}
    end
  end

  @doc """
  Updates (reassigns/corrects) an alias on behalf of `actor`, journaled. A
  changed `former_isin` re-runs the serialized live-ISIN collision check;
  alias-alias collisions are held by the unique index.
  """
  def update_alias(%Actor{} = actor, %IdentifierAlias{} = alias_row, attrs) when is_map(attrs) do
    # Built on the row as stored, re-read under its lock by the journal step
    # (E25 S6 review round, M5): an edit from a stale read that sets a field
    # back to the value it read is a change, never dropped as none. The ISIN
    # write lock comes first, as in every ISIN writer.
    changeset = &IdentifierAlias.changeset(Journal.locked_row(&1), attrs)

    Multi.new()
    |> Multi.run(:former_isin_guard, fn _repo, changes ->
      case ensure_changed_former_isin_not_live(changeset.(changes)) do
        :ok -> {:ok, :clear}
        {:error, _changeset} = refused -> refused
      end
    end)
    |> Multi.update(:alias, changeset)
    |> Journal.record(actor,
      resource_type: "security_identifier_alias",
      operation: :update,
      source: :alias,
      before: alias_row
    )
    |> Multi.prepend(
      Multi.run(Multi.new(), :isin_write_lock, fn repo, _changes ->
        lock_isin_writes(repo, [alias_row.former_isin, attr(attrs, :former_isin)])
      end)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{alias: updated}} -> {:ok, updated}
      {:error, :former_isin_guard, %Changeset{} = error, _changes} -> {:error, error}
      {:error, :alias, %Changeset{} = error, _changes} -> {:error, error}
      {:error, {:journal_lock, _}, :not_found, _changes} -> {:error, :not_found}
    end
  end

  @doc """
  Deletes all alias rows of a security, journaled per row — used by the
  hardened security delete path (`Portfolixir.Lifecycle.Delete`, ADR-0050
  §11). The foreign key restricts, so no cascade removes an alias silently.
  """
  def delete_all_for_security(%Actor{} = actor, security_id) when is_integer(security_id) do
    Repo.transaction(fn ->
      security_id
      |> list_for_security()
      |> Enum.each(fn alias_row ->
        case delete_alias(actor, alias_row) do
          {:ok, _} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

      :ok
    end)
  end

  @doc """
  The bidirectional guard (ADR-0029 §3), run as an `Ecto.Multi` step inside
  every security-ISIN write transaction: rejects a changeset whose (normalized)
  `:isin` change is present in the alias table, naming the aliased security.
  A changeset that does not change the ISIN passes untouched.
  """
  def guard_isin_not_aliased(repo, %Changeset{} = changeset) do
    case Changeset.get_change(changeset, :isin) do
      nil ->
        {:ok, :not_applicable}

      isin ->
        acquire_isin_write_lock(repo, [isin])
        check_isin_against_aliases(repo, changeset, isin)
    end
  end

  @doc "Map of `former_isin => security_id` for the import ladder's ISIN tier."
  def by_former_isin do
    Repo.all(from(a in IdentifierAlias, select: {a.former_isin, a.security_id}))
    |> Map.new()
  end

  defp check_isin_against_aliases(repo, changeset, isin) do
    case repo.one(alias_with_security_query(isin)) do
      nil ->
        {:ok, :clear}

      %IdentifierAlias{security: aliased} ->
        {:error,
         Changeset.add_error(
           changeset,
           :isin,
           "is recorded as a former ISIN of security #%{security_id}; delete that alias or " <>
             "record an ISIN change instead",
           named(aliased)
         )}
    end
  end

  # #965 (F75's rule): a refusal names the security it collides with by its
  # id, so a stored name that reads like an instruction never sits inside a
  # sentence an agent reads; the name travels as data, for the operator's
  # screen, which keeps its sentence (`PortfolixirWeb.NamedRecordRefusal`).
  defp named(%Security{} = other), do: [security_id: other.id, security_name: other.name]

  defp alias_with_security_query(isin) do
    from(a in IdentifierAlias, where: a.former_isin == ^isin, preload: :security)
  end

  defp validate_new_isin(%Security{} = security, new_isin) do
    normalized = IdentifierAlias.normalize_isin(new_isin)

    cond do
      is_nil(security.isin) ->
        {:error,
         error_changeset(:new_isin, "cannot be recorded: the security has no current ISIN")}

      is_nil(normalized) ->
        {:error, error_changeset(:new_isin, "can't be blank")}

      # E25 S4 (G17) and S5 (G23): twelve characters of the ISIN shape with a
      # check digit that agrees, before anything is looked up or moved into
      # the alias table.
      not Isin.valid?(normalized) ->
        {:error,
         error_changeset(
           :new_isin,
           "is not an ISIN (two letters, nine letters or digits and a check digit)"
         )}

      normalized == security.isin ->
        {:error, error_changeset(:new_isin, "must differ from the current ISIN")}

      true ->
        check_new_isin_collisions(security, normalized)
    end
  end

  defp check_new_isin_collisions(%Security{} = security, normalized) do
    with :ok <- ensure_not_live_elsewhere(normalized),
         :ok <- ensure_not_foreign_alias(security, normalized) do
      {:ok, normalized}
    end
  end

  defp ensure_not_live_elsewhere(normalized) do
    case Repo.get_by(Security, isin: normalized) do
      nil ->
        :ok

      %Security{} = other ->
        {:error,
         error_changeset(
           :new_isin,
           "is already the current ISIN of security #%{security_id}",
           named(other)
         )}
    end
  end

  defp ensure_not_foreign_alias(%Security{id: security_id}, normalized) do
    case Repo.one(alias_with_security_query(normalized)) do
      nil ->
        :ok

      %IdentifierAlias{security_id: ^security_id} ->
        # The security's own alias: consumed by `consume_own_alias/3` (B->A).
        :ok

      %IdentifierAlias{security: other} ->
        {:error,
         error_changeset(
           :new_isin,
           "is recorded as a former ISIN of security #%{security_id}",
           named(other)
         )}
    end
  end

  defp consume_own_alias(%Actor{} = actor, %Security{id: security_id}, normalized) do
    case Repo.get_by(IdentifierAlias, security_id: security_id, former_isin: normalized) do
      nil ->
        :ok

      %IdentifierAlias{} = own_alias ->
        case delete_alias(actor, own_alias) do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp insert_alias(%Actor{} = actor, %Security{} = security, former_isin, changed_on, note) do
    changeset =
      IdentifierAlias.changeset(%IdentifierAlias{}, %{
        security_id: security.id,
        former_isin: former_isin,
        changed_on: changed_on,
        note: note
      })

    multi =
      Multi.new()
      |> Multi.insert(:alias, changeset)
      |> Journal.record(actor,
        resource_type: "security_identifier_alias",
        operation: :create,
        source: :alias
      )

    case Repo.transaction(multi) do
      {:ok, %{alias: alias_row}} -> {:ok, alias_row}
      {:error, :alias, %Changeset{} = error, _changes} -> {:error, error}
    end
  end

  defp write_new_isin(%Actor{} = actor, %Security{} = security, normalized) do
    multi =
      Multi.new()
      |> Multi.update(:security, Security.changeset(security, %{isin: normalized}))
      |> Journal.record(actor,
        resource_type: "security",
        operation: :update,
        source: :security,
        before: security
      )

    case Repo.transaction(multi) do
      {:ok, %{security: updated}} -> {:ok, updated}
      {:error, :security, %Changeset{} = error, _changes} -> {:error, error}
      {:error, {:journal_lock, _}, :not_found, _changes} -> {:error, :not_found}
    end
  end

  defp ensure_changed_former_isin_not_live(changeset) do
    case Changeset.get_change(changeset, :former_isin) do
      nil ->
        :ok

      isin ->
        case Repo.get_by(Security, isin: isin) do
          nil ->
            :ok

          %Security{} = other ->
            {:error,
             Changeset.add_error(
               changeset,
               :former_isin,
               "is already the current ISIN of security #%{security_id}",
               named(other)
             )}
        end
    end
  end

  @doc """
  Takes the ISIN write lock of each of `isins` (normalized; blanks and
  repeats taken once) for the rest of the transaction, in ascending key
  order, answered as an `Ecto.Multi` step result, for a writer that must
  hold them before the journal's row lock (E25 S6 review round, F49): the
  locks every ISIN writer takes first. The lock is one per ISIN (security
  review 2026-10-12, H53).
  """
  @spec lock_isin_writes(Ecto.Repo.t(), [String.t() | nil]) :: {:ok, :locked}
  def lock_isin_writes(repo, isins) when is_list(isins) do
    :ok = acquire_isin_write_lock(repo, isins)
    {:ok, :locked}
  end

  @doc """
  The ISIN write locks of a writer of stored securities' ISINs (an edit, an
  ISIN change, a merge): the key of each of `security_ids` first, in
  ascending id order, then the ISIN keys of `isins` and of each security's
  stored ISIN, read under its key, in ascending key order (security review
  2026-10-12, H53). Answered as an `Ecto.Multi` step result.
  """
  @spec lock_security_isin_writes(Ecto.Repo.t(), [integer()], [String.t() | nil]) ::
          {:ok, :locked}
  def lock_security_isin_writes(repo, security_ids, isins)
      when is_list(security_ids) and is_list(isins) do
    :ok = acquire_security_isin_write_lock(repo, security_ids, isins)
    {:ok, :locked}
  end

  defp acquire_security_isin_write_lock(repo, security_ids, isins) do
    ids = security_ids |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
    scope = lock_scope(repo)

    Enum.each(ids, &take_lock(repo, lock_key_for(scope, "security:#{&1}")))

    stored = repo.all(from(s in Security, where: s.id in ^ids, select: s.isin))
    acquire_isin_write_lock(repo, isins ++ stored, scope)
  end

  @doc """
  The second key of the ISIN write lock of `name` (a normalized ISIN, or
  "security:<id>" for a security's own key) under `scope` ("0" for the whole
  database): the first four bytes of its SHA-256, signed. Computed here, so
  no input reaches the lock statement but an integer.
  """
  @spec lock_key_for(String.t(), String.t()) :: integer()
  def lock_key_for(scope, name) when is_binary(scope) and is_binary(name) do
    <<key::signed-32, _rest::binary>> = :crypto.hash(:sha256, scope <> ":" <> name)
    key
  end

  @doc "The first key of the ISIN write lock (`pg_advisory_xact_lock(int, int)`)."
  @spec isin_write_lock_key() :: integer()
  def isin_write_lock_key, do: @isin_write_lock_key

  defp lock_scope(repo) do
    %{rows: [[scope]]} = repo.query!(@isin_write_lock_scope_sql, [])
    scope
  end

  defp acquire_isin_write_lock(repo, isins, scope \\ nil) do
    case isins |> Enum.map(&IdentifierAlias.normalize_isin/1) |> Enum.reject(&is_nil/1) do
      [] ->
        :ok

      normalized ->
        scope = scope || lock_scope(repo)

        normalized
        |> Enum.map(&lock_key_for(scope, &1))
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.each(&take_lock(repo, &1))
    end
  end

  defp take_lock(repo, key),
    do: repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@isin_write_lock_key, key])

  defp attr(attrs, field), do: Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))

  defp error_changeset(field, message, keys \\ []) do
    %IdentifierAlias{}
    |> Changeset.change()
    |> Changeset.add_error(field, message, keys)
  end
end
