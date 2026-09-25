defmodule Portfolixir.Lifecycle.AccountNames do
  @moduledoc """
  The identity of a cash account or a depot by name (ADR-0050 §4): its live
  `name` and its `former_names`, one resolution over both, one name guard on
  every writer, and one advisory lock that serializes the guard.

  **Resolution** (`index/2`, `resolve/2`) is the one function the import
  preview's prefill and the applier share: an exact live name of the kind in
  the portfolio first, then a former name. A tier that names more than one
  account resolves to `{:ambiguous, tier, ids}`, never to one of them — the
  preview prefills nothing and the apply refuses the name unmapped. That
  replaces the last-wins map the importer used to build.

  **The name guard**, attached to both schemas' `changeset/2` by
  `validate/1`, so every writer that builds its write there is covered (the
  API, MCP and UI creates and renames, the importer's lazy creation, any
  seed):

    * a live name may equal neither another live name nor a former name of
      the same kind in the portfolio;
    * a former name may equal neither a live name nor another account's
      former name.

  There is no unique index behind it (a former name sits in an array that no
  plain index keeps distinct across rows or from another row's live name, and
  duplicate names from before the guard are not migrated), so the guard runs
  under a transaction-scoped **advisory lock** for account identity, taken
  before any row lock. Names only ever conflict inside one portfolio, so the
  lock is one per portfolio (`lock_identity/2`, keyed `{lock_key/0, portfolio}`): two
  writers of one portfolio's account names serialize, writers of different
  portfolios do not wait on each other. A merge (L3) takes the same lock
  first. An update that leaves the name and the portfolio alone is not
  checked, so a duplicate from before the guard stays editable.

  **The writers of former names:**

    * the **rename rule** (in `validate/1`): a rename appends the previous
      name, and renaming back to a former name consumes it — except when
      another account of the kind in the portfolio still carries the previous
      name as its live name: then nothing is recorded, because that name
      already resolves to the other account;
    * the **remembered remap** (`remember/4`): a Portfolio Performance name
      the operator mapped onto a differently named account in the import
      preview becomes a former name of that account; a former name of another
      account moves; a live name of another account is not remembered
      (`remember_outcome/3` says which before the import is applied);
    * the **removal** (`remove_former_name/3`);
    * the merge, which appends the source's names (L3).

  Every write of `former_names` is journaled with its before and after.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  # The first key of the account-identity advisory lock
  # (pg_advisory_xact_lock(int, int)); the second is the portfolio. Distinct
  # from the ISIN write lock of `Portfolixir.Catalog.IdentifierAliases`.
  @lock_key 727_205_004
  @int4_max 2_147_483_647

  @schemas [CashAccount, SecuritiesAccount]

  @resource_types %{CashAccount => "cash_account", SecuritiesAccount => "securities_account"}
  @nouns %{CashAccount => "cash account", SecuritiesAccount => "securities account"}

  @type schema :: CashAccount | SecuritiesAccount
  @type account :: %CashAccount{} | %SecuritiesAccount{}

  @type resolution ::
          {:ok, integer(), :live | :former} | :none | {:ambiguous, :live | :former, [integer()]}

  @typedoc "Every live and former name of one kind in one portfolio, with the ids carrying it."
  @type index :: %{live: %{String.t() => [integer()]}, former: %{String.t() => [integer()]}}

  @type remember_outcome ::
          :same_name | :already | :append | {:move, integer()} | {:not_offered, integer()}

  @doc "The first key of the account-identity advisory lock."
  @spec lock_key() :: integer()
  def lock_key, do: @lock_key

  @doc """
  The second key of the account-identity advisory lock for `portfolio_id`
  (the portfolio id folded into the lock's 32-bit key; two portfolios that
  share a key only serialize more than they must).
  """
  @spec lock_portfolio_key(integer()) :: integer()
  def lock_portfolio_key(portfolio_id) when is_integer(portfolio_id),
    do: rem(portfolio_id, @int4_max)

  @doc """
  Takes the account-identity advisory lock of each of `portfolio_ids` for the
  rest of the current transaction, in ascending order so two writers never
  wait on each other crosswise. Re-entrant: a transaction that holds a lock
  takes it again at once. A `nil` portfolio takes nothing.
  """
  @spec lock_identity([integer() | nil] | integer() | nil, Ecto.Repo.t()) :: :ok
  def lock_identity(portfolio_ids, repo \\ Repo)

  def lock_identity(portfolio_ids, repo) when is_list(portfolio_ids) do
    portfolio_ids
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&lock_portfolio_key/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(&repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@lock_key, &1]))
  end

  def lock_identity(portfolio_id, repo), do: lock_identity([portfolio_id], repo)

  # --- resolution --------------------------------------------------------------

  @doc """
  Every live and former name of `schema`'s accounts in `portfolio_id`, for
  `resolve/2`. A `nil` portfolio (no import target yet) has no names.
  """
  @spec index(schema(), integer() | nil) :: index()
  def index(schema, nil) when schema in @schemas, do: %{live: %{}, former: %{}}

  def index(schema, portfolio_id) when schema in @schemas and is_integer(portfolio_id) do
    rows =
      Repo.all(
        from(a in schema,
          where: a.portfolio_id == ^portfolio_id,
          order_by: [asc: a.id],
          select: {a.id, a.name, a.former_names}
        )
      )

    %{
      live: Enum.group_by(rows, fn {_id, name, _former} -> name end, &elem(&1, 0)),
      former:
        rows
        |> Enum.flat_map(fn {id, _name, former} -> Enum.map(former, &{&1, id}) end)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    }
  end

  @doc """
  Resolves `name` in `index`: the exact live name first, then the former name.
  A tier naming more than one account is `{:ambiguous, tier, ids}` and stops
  there; nothing found is `:none`.
  """
  @spec resolve(index(), String.t()) :: resolution()
  def resolve(%{live: live, former: former}, name) when is_binary(name) do
    case tier(live, name, :live) do
      :none -> tier(former, name, :former)
      found -> found
    end
  end

  defp tier(names, name, tier) do
    case names |> Map.get(name, []) |> Enum.uniq() |> Enum.sort() do
      [] -> :none
      [id] -> {:ok, id, tier}
      ids -> {:ambiguous, tier, ids}
    end
  end

  # --- the guard and the rename rule --------------------------------------------

  @doc """
  Attaches the name guard, and for a rename the rename rule, to `changeset`.
  A new row is always checked; a stored row only when its `name` or its
  `portfolio_id` changes. The check runs when the row is written, inside the
  write's transaction and under the account-identity lock
  (`prepare_changes`); a refusal is a field error on `name`
  (`validation: :name_taken`), which the API answers as 422.
  """
  @spec validate(Changeset.t()) :: Changeset.t()
  def validate(%Changeset{data: %schema{} = data} = changeset) when schema in @schemas do
    cond do
      Ecto.get_meta(data, :state) == :built ->
        Changeset.prepare_changes(changeset, &guard_new/1)

      Map.has_key?(changeset.changes, :name) or Map.has_key?(changeset.changes, :portfolio_id) ->
        Changeset.prepare_changes(changeset, &guard_stored/1)

      true ->
        changeset
    end
  end

  defp guard_new(%Changeset{data: %schema{}} = changeset) do
    portfolio_id = Changeset.get_field(changeset, :portfolio_id)
    lock_identity(portfolio_id, changeset.repo)
    name = Changeset.get_field(changeset, :name)

    case name_conflict(schema, portfolio_id, name, nil) do
      nil -> changeset
      conflict -> refuse(changeset, schema, conflict)
    end
  end

  # A rename: the previous name is appended unless another live account
  # carries it (or, which the guard never lets arise, another account's former
  # names hold it), and the new name is consumed from the account's own former
  # names. The row is re-read under its lock, so the rule reads the stored
  # former names, not the caller's copy.
  defp guard_stored(%Changeset{data: %schema{id: id} = data} = changeset) do
    lock_identity(
      [data.portfolio_id, Changeset.get_field(changeset, :portfolio_id)],
      changeset.repo
    )

    case changeset.repo.one(
           from(a in schema,
             where: a.id == ^id,
             lock: "FOR UPDATE",
             select: %{name: a.name, former_names: a.former_names}
           )
         ) do
      nil -> changeset
      stored -> guard_rename(changeset, schema, id, stored)
    end
  end

  defp guard_rename(changeset, schema, id, stored) do
    portfolio_id = Changeset.get_field(changeset, :portfolio_id)
    name = Changeset.get_field(changeset, :name)
    former = renamed_former_names(schema, portfolio_id, id, stored, name)

    conflicts =
      [name_conflict(schema, portfolio_id, name, id)] ++
        Enum.map(former, &former_conflict(schema, portfolio_id, &1, id))

    case Enum.reject(conflicts, &is_nil/1) do
      [] -> Changeset.force_change(changeset, :former_names, former)
      [conflict | _] -> refuse(changeset, schema, conflict)
    end
  end

  defp renamed_former_names(_schema, _portfolio_id, _id, %{name: name} = stored, name),
    do: stored.former_names

  defp renamed_former_names(schema, portfolio_id, id, stored, name) do
    former = List.delete(stored.former_names, name)
    previous = stored.name

    cond do
      previous in former -> former
      live_holder(schema, portfolio_id, previous, id) != nil -> former
      former_holder(schema, portfolio_id, previous, id) != nil -> former
      true -> former ++ [previous]
    end
  end

  # A live name of another account of the kind in the portfolio, or a former
  # name of any other account — the account's own former names are its own.
  defp name_conflict(schema, portfolio_id, name, id) do
    case live_holder(schema, portfolio_id, name, id) do
      nil ->
        case former_holder(schema, portfolio_id, name, id) do
          nil -> nil
          holder -> {:former, holder}
        end

      holder ->
        {:live, holder}
    end
  end

  # One of the account's former names against the other accounts of the kind
  # in the (possibly new) portfolio: only a move to another portfolio, or a
  # state from before the guard, can make one clash.
  defp former_conflict(schema, portfolio_id, name, id) do
    case live_holder(schema, portfolio_id, name, id) do
      nil ->
        case former_holder(schema, portfolio_id, name, id) do
          nil -> nil
          holder -> {:former_names, holder, name, "a former name"}
        end

      holder ->
        {:former_names, holder, name, "the name"}
    end
  end

  @doc """
  What the name guard would answer for a new account of `schema` named `name`
  in `portfolio_id`: the field error's message, or `nil` when the name is
  free. Read-only and unlocked — for a form that must refuse a taken name
  before it writes anything else; the write itself is still guarded.
  """
  @spec name_error(schema(), integer() | nil, String.t()) :: String.t() | nil
  def name_error(schema, portfolio_id, name) when schema in @schemas and is_binary(name) do
    case name_conflict(schema, portfolio_id, name, nil) do
      nil -> nil
      conflict -> conflict_message(schema, conflict)
    end
  end

  defp refuse(changeset, schema, {kind, _holder} = conflict) when kind in [:live, :former] do
    Changeset.add_error(changeset, :name, conflict_message(schema, conflict),
      validation: :name_taken
    )
  end

  defp refuse(changeset, schema, {:former_names, holder, name, what}) do
    Changeset.add_error(
      changeset,
      :former_names,
      "include \"#{name}\", #{what} of #{noun(schema)} ##{holder.id} in this portfolio",
      validation: :name_taken
    )
  end

  defp conflict_message(schema, {:live, holder}),
    do: "is already the name of #{noun(schema)} ##{holder.id} in this portfolio"

  defp conflict_message(schema, {:former, holder}) do
    "is a former name of #{noun(schema)} ##{holder.id} (\"#{holder.name}\"): an import " <>
      "naming it books there. Remove it from that account's former names first"
  end

  defp live_holder(_schema, nil, _name, _id), do: nil

  defp live_holder(schema, portfolio_id, name, id) do
    schema
    |> where([a], a.portfolio_id == ^portfolio_id and a.name == ^name)
    |> other_than(id)
    |> first_holder()
  end

  defp former_holder(_schema, nil, _name, _id), do: nil

  defp former_holder(schema, portfolio_id, name, id) do
    schema
    |> where([a], a.portfolio_id == ^portfolio_id and ^name in a.former_names)
    |> other_than(id)
    |> first_holder()
  end

  defp other_than(query, nil), do: query
  defp other_than(query, id), do: where(query, [a], a.id != ^id)

  defp first_holder(query) do
    query
    |> order_by([a], asc: a.id)
    |> limit(1)
    |> select([a], %{id: a.id, name: a.name})
    |> Repo.one()
  end

  # --- the remembered remap ------------------------------------------------------

  @doc """
  What remembering `name` on the account `account_id` of `schema` would do,
  read-only, for the import preview:

    * `:same_name` — it is the account's live name; nothing to remember;
    * `:already` — it is already a former name of the account;
    * `:append` — it becomes a former name of the account;
    * `{:move, id}` — it is a former name of account `id` and moves;
    * `{:not_offered, id}` — it is the live name of account `id` of the kind
      in the portfolio, which the guard refuses as a former name: the choice
      holds for this import only (remedy: merge or rename that account);
    * `:not_found` — the account does not exist.
  """
  @spec remember_outcome(schema(), integer(), String.t()) :: remember_outcome() | :not_found
  def remember_outcome(schema, account_id, name)
      when schema in @schemas and is_integer(account_id) and is_binary(name) do
    case Repo.get(schema, account_id) do
      nil -> :not_found
      account -> outcome(account, name)
    end
  end

  defp outcome(%schema{} = account, name) do
    cond do
      account.name == name ->
        :same_name

      name in account.former_names ->
        :already

      holder = live_holder(schema, account.portfolio_id, name, account.id) ->
        {:not_offered, holder.id}

      holder = former_holder(schema, account.portfolio_id, name, account.id) ->
        {:move, holder.id}

      true ->
        :append
    end
  end

  @doc """
  Remembers `name` as a former name of the account `account_id` of `schema`
  on behalf of `actor`, under the account-identity lock, in one transaction
  (which joins the caller's): `:appended`, `{:moved, from_id}` (removed from
  that account and appended here, each journaled), or — writing nothing —
  `:same_name`, `:already` and `{:not_offered, live_on_id}`.
  """
  @spec remember(Actor.t(), schema(), integer(), String.t()) ::
          {:ok,
           :same_name | :already | :appended | {:moved, integer()} | {:not_offered, integer()}}
          | {:error, :not_found | Changeset.t()}
  def remember(%Actor{} = actor, schema, account_id, name)
      when schema in @schemas and is_integer(account_id) and is_binary(name) do
    Repo.transaction(fn ->
      with {:ok, account} <- locked(schema, account_id),
           {:ok, result} <- remember_locked(actor, account, name) do
        result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp remember_locked(actor, %schema{} = account, name) do
    case outcome(account, name) do
      :append ->
        with {:ok, _} <- write_former_names(actor, account, account.former_names ++ [name]),
             do: {:ok, :appended}

      {:move, from_id} ->
        with {:ok, from} <- locked(schema, from_id),
             {:ok, _} <- write_former_names(actor, from, List.delete(from.former_names, name)),
             {:ok, _} <- write_former_names(actor, account, account.former_names ++ [name]),
             do: {:ok, {:moved, from_id}}

      other ->
        {:ok, other}
    end
  end

  # --- the removal -----------------------------------------------------------------

  @doc """
  Removes `name` from `account`'s former names on behalf of `actor`,
  journaled. An import that still names it resolves to no account from then
  on, and creates a new one. A name the account does not carry answers
  `{:error, :not_a_former_name}`; a vanished account `{:error, :not_found}`.
  """
  @spec remove_former_name(Actor.t(), account(), String.t()) ::
          {:ok, account()} | {:error, :not_a_former_name | :not_found | Changeset.t()}
  def remove_former_name(%Actor{} = actor, %schema{id: id}, name)
      when schema in @schemas and is_binary(name) do
    Repo.transaction(fn ->
      with {:ok, account} <- locked(schema, id),
           true <- name in account.former_names || {:error, :not_a_former_name},
           {:ok, updated} <-
             write_former_names(actor, account, List.delete(account.former_names, name)) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # --- shared ---------------------------------------------------------------------

  # The account's portfolio lock first, then its row: the order every writer
  # of account names takes them in.
  defp locked(schema, id) do
    case Repo.one(from(a in schema, where: a.id == ^id, select: a.portfolio_id)) do
      nil ->
        {:error, :not_found}

      portfolio_id ->
        lock_identity(portfolio_id)

        case Repo.one(from(a in schema, where: a.id == ^id, lock: "FOR UPDATE")) do
          nil -> {:error, :not_found}
          account -> {:ok, account}
        end
    end
  end

  defp write_former_names(actor, %schema{} = account, former_names) do
    Multi.new()
    |> Multi.update(:account, former_names_changeset(account, former_names))
    |> Journal.record(actor,
      resource_type: Map.fetch!(@resource_types, schema),
      operation: :update,
      source: :account,
      before: account
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{account: updated}} -> {:ok, updated}
      {:error, :account, %Changeset{} = changeset, _changes} -> {:error, changeset}
    end
  end

  defp former_names_changeset(%CashAccount{} = account, former_names),
    do: CashAccount.former_names_changeset(account, former_names)

  defp former_names_changeset(%SecuritiesAccount{} = account, former_names),
    do: SecuritiesAccount.former_names_changeset(account, former_names)

  defp noun(schema), do: Map.fetch!(@nouns, schema)
end
