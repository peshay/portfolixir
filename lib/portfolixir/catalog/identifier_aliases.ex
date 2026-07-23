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
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  # All cross-table ISIN uniqueness checks take this advisory transaction lock
  # first, so two concurrent security-ISIN writes serialize instead of both
  # passing the check before either commits (ADR-0029 §3 "serialized check").
  @isin_write_lock_key 727_202_907

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
    changed_on = Keyword.get(opts, :changed_on) || Date.utc_today()
    note = Keyword.get(opts, :note)

    Repo.transaction(fn ->
      acquire_isin_write_lock(Repo)

      with {:ok, normalized} <- validate_new_isin(security, new_isin),
           :ok <- consume_own_alias(actor, security, normalized),
           {:ok, alias_row} <- insert_alias(actor, security, changed_on, note),
           {:ok, updated} <- write_new_isin(actor, security, normalized) do
        %{security: updated, alias: alias_row}
      else
        {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
      end
    end)
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
    end
  end

  @doc """
  Updates (reassigns/corrects) an alias on behalf of `actor`, journaled. A
  changed `former_isin` re-runs the serialized live-ISIN collision check;
  alias-alias collisions are held by the unique index.
  """
  def update_alias(%Actor{} = actor, %IdentifierAlias{} = alias_row, attrs) when is_map(attrs) do
    changeset = IdentifierAlias.changeset(alias_row, attrs)

    Repo.transaction(fn ->
      acquire_isin_write_lock(Repo)

      with :ok <- ensure_changed_former_isin_not_live(changeset),
           {:ok, updated} <- journaled_alias_update(actor, alias_row, changeset) do
        updated
      else
        {:error, %Changeset{} = error_changeset} -> Repo.rollback(error_changeset)
      end
    end)
  end

  @doc """
  Deletes all alias rows of a security, journaled per row — used by the
  security delete path so the FK cascade stays a silent backstop only.
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
        acquire_isin_write_lock(repo)
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
        {:error, Changeset.add_error(changeset, :isin, aliased_isin_message(aliased))}
    end
  end

  defp aliased_isin_message(%Security{} = aliased) do
    "is recorded as a former ISIN of \"#{aliased.name}\" (security ##{aliased.id}); " <>
      "delete that alias or record an ISIN change instead"
  end

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
           "is already the current ISIN of \"#{other.name}\" (security ##{other.id})"
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
           "is recorded as a former ISIN of \"#{other.name}\" (security ##{other.id})"
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

  defp insert_alias(%Actor{} = actor, %Security{} = security, changed_on, note) do
    changeset =
      IdentifierAlias.changeset(%IdentifierAlias{}, %{
        security_id: security.id,
        former_isin: security.isin,
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
    end
  end

  defp journaled_alias_update(%Actor{} = actor, %IdentifierAlias{} = before, changeset) do
    multi =
      Multi.new()
      |> Multi.update(:alias, changeset)
      |> Journal.record(actor,
        resource_type: "security_identifier_alias",
        operation: :update,
        source: :alias,
        before: before
      )

    case Repo.transaction(multi) do
      {:ok, %{alias: updated}} -> {:ok, updated}
      {:error, :alias, %Changeset{} = error, _changes} -> {:error, error}
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
               "is already the current ISIN of \"#{other.name}\" (security ##{other.id})"
             )}
        end
    end
  end

  defp acquire_isin_write_lock(repo) do
    repo.query!("SELECT pg_advisory_xact_lock($1)", [@isin_write_lock_key])
    :ok
  end

  defp error_changeset(field, message) do
    %IdentifierAlias{}
    |> Changeset.change()
    |> Changeset.add_error(field, message)
  end
end
