defmodule Portfolixir.Lifecycle.FormerNamesBackfill do
  @moduledoc """
  The one-time backfill of `former_names` from the audit journal (ADR-0050 §4
  third bullet), run by the migration `backfill_account_former_names`.

  Every journaled update of a cash account or a depot whose name changed is
  replayed per account, in journal order, through the rename rule of
  `Portfolixir.Lifecycle.AccountNames`: the previous name is appended, and a
  rename back to a former name consumes it. The replayed names are then held
  against the name guard over the accounts as they are **now**, oldest rename
  first:

    * a name another live account of the kind in the portfolio carries is not
      recorded — typically a zombie an import created under the old name after
      the rename, which a merge with collapse repairs (§8);
    * a name another account already has as a former name (an earlier rename's,
      or one the column already holds) is not recorded either — one former name
      belongs to one account.

  Both are **reported, never written**; the migration logs them. Renames of an
  account deleted since are skipped, and a scenario (what-if) entry is never
  replayed.

  The backfill only **adds** names, so a second run writes nothing. Each row
  it changes is written once, journaled under the caller's actor with its
  before and after. It reads and writes the two tables schemaless, naming only
  the columns they have at this migration, so the immutable migration keeps
  running when a later one adds a column the schemas then know.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  # {kind, journal resource type, table, the columns at this migration}
  @kinds [
    {:cash_account, "cash_account", "cash_accounts",
     ~w(id portfolio_id name currency_code notes liquidity_role former_names inserted_at updated_at)a},
    {:securities_account, "securities_account", "securities_accounts",
     ~w(id portfolio_id cash_account_id name notes former_names inserted_at updated_at)a}
  ]

  @nouns %{cash_account: "cash account", securities_account: "securities account"}

  @type kind :: :cash_account | :securities_account

  @type refusal :: %{
          kind: kind(),
          account_id: integer(),
          name: String.t(),
          reason:
            :live_name_of_another_account
            | :former_name_of_another_account
            | :live_name_of_the_account,
          holder_id: integer()
        }

  @type report :: %{
          written: [%{kind: kind(), account_id: integer(), former_names: [String.t()]}],
          refused: [refusal()]
        }

  @doc """
  Replays the journaled renames into `former_names` on behalf of `actor`, in
  one transaction. Returns what it wrote (the full former-name list of each
  changed row) and what it refused.
  """
  @spec run(Actor.t()) :: {:ok, report()}
  def run(%Actor{} = actor) do
    Repo.transaction(fn ->
      Enum.reduce(@kinds, %{written: [], refused: []}, fn kind, acc ->
        {written, refused} = backfill(actor, kind)
        %{written: acc.written ++ written, refused: acc.refused ++ refused}
      end)
    end)
  end

  @doc "One refusal as the sentence the migration logs."
  @spec describe(refusal()) :: String.t()
  def describe(%{kind: kind, account_id: id, name: name, reason: reason, holder_id: holder}) do
    noun = Map.fetch!(@nouns, kind)

    "#{noun} ##{id} keeps no former name \"#{name}\": " <>
      case reason do
        :live_name_of_another_account ->
          "#{noun} ##{holder} carries it as its live name, so an import naming it books there; " <>
            "if that account is a zombie the import created after the rename, merge it into " <>
            "##{id} with collapse (ADR-0050 §8)"

        :former_name_of_another_account ->
          "#{noun} ##{holder} already has it as a former name, from an earlier rename"

        :live_name_of_the_account ->
          "it is the account's own live name"
      end
  end

  defp backfill(actor, {kind, resource_type, table, columns}) do
    case journaled_renames(resource_type) do
      [] ->
        {[], []}

      renames ->
        accounts = load_accounts(table)
        replayed = replay(renames, accounts)
        {accepted, refused} = hold_against_guard(kind, replayed, accounts)
        {write(actor, kind, resource_type, table, columns, accepted, accounts), refused}
    end
  end

  # [{entry_id, account_id, previous_name, new_name}], journal order.
  defp journaled_renames(resource_type) do
    from(e in "audit_journal",
      where:
        e.resource_type == ^resource_type and e.operation == "update" and
          is_nil(e.scenario_id),
      order_by: [asc: e.id],
      select: {e.id, e.resource_id, e.before, e.after}
    )
    |> Repo.all()
    |> Enum.flat_map(&rename/1)
  end

  defp rename({entry_id, resource_id, %{"name" => previous}, %{"name" => new}})
       when is_binary(resource_id) and is_binary(previous) and is_binary(new) and
              previous != new do
    case Integer.parse(resource_id) do
      {account_id, ""} -> [{entry_id, account_id, previous, new}]
      _other -> []
    end
  end

  defp rename(_entry), do: []

  defp load_accounts(table) do
    from(a in table,
      select: %{
        id: a.id,
        portfolio_id: a.portfolio_id,
        name: a.name,
        former_names: a.former_names
      }
    )
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  # Per account, the former names the rename rule leaves, each with the
  # journal entry that appended it: the new name is consumed, the previous
  # one appended unless the account already had it.
  defp replay(renames, accounts) do
    Enum.reduce(renames, %{}, fn {entry_id, account_id, previous, new}, acc ->
      if Map.has_key?(accounts, account_id) do
        names =
          acc
          |> Map.get(account_id, [])
          |> Enum.reject(fn {name, _entry} -> name == new end)

        names =
          if Enum.any?(names, fn {name, _entry} -> name == previous end),
            do: names,
            else: names ++ [{previous, entry_id}]

        Map.put(acc, account_id, names)
      else
        acc
      end
    end)
  end

  # The guard over the accounts as they are now, oldest rename first: a
  # replayed name the account does not carry yet is recorded unless a live
  # name of the kind in the portfolio, or another account's former name,
  # already has it.
  defp hold_against_guard(kind, replayed, accounts) do
    live = group(accounts, fn account -> [account.name] end)

    held_former =
      accounts
      |> Map.values()
      |> Enum.flat_map(fn a -> Enum.map(a.former_names, &{{a.portfolio_id, &1}, a.id}) end)
      |> Map.new()

    candidates =
      for {account_id, names} <- replayed,
          {name, entry_id} <- names,
          name not in Map.fetch!(accounts, account_id).former_names,
          do: {entry_id, account_id, name}

    {accepted, refused, _former} =
      candidates
      |> Enum.sort()
      |> Enum.reduce({%{}, [], held_former}, fn {_entry, account_id, name}, {ok, no, former} ->
        key = {Map.fetch!(accounts, account_id).portfolio_id, name}

        case conflict(account_id, Map.get(live, key, []), Map.get(former, key)) do
          nil ->
            {Map.update(ok, account_id, [name], &(&1 ++ [name])), no,
             Map.put(former, key, account_id)}

          {reason, holder} ->
            refusal = %{
              kind: kind,
              account_id: account_id,
              name: name,
              reason: reason,
              holder_id: holder
            }

            {ok, no ++ [refusal], former}
        end
      end)

    {accepted, refused}
  end

  defp conflict(account_id, live_holders, former_holder) do
    cond do
      account_id in live_holders -> {:live_name_of_the_account, account_id}
      live_holders != [] -> {:live_name_of_another_account, Enum.min(live_holders)}
      former_holder not in [nil, account_id] -> {:former_name_of_another_account, former_holder}
      true -> nil
    end
  end

  defp group(accounts, names_of) do
    accounts
    |> Map.values()
    |> Enum.flat_map(fn account ->
      Enum.map(names_of.(account), &{{account.portfolio_id, &1}, account.id})
    end)
    |> Enum.group_by(fn {key, _id} -> key end, fn {_key, id} -> id end)
  end

  defp write(actor, kind, resource_type, table, columns, accepted, accounts) do
    accepted
    |> Enum.sort()
    |> Enum.map(fn {account_id, names} ->
      former_names = Map.fetch!(accounts, account_id).former_names ++ names
      :ok = write_row(actor, resource_type, table, columns, account_id, former_names)
      %{kind: kind, account_id: account_id, former_names: former_names}
    end)
  end

  defp write_row(actor, resource_type, table, columns, account_id, former_names) do
    row = from(a in table, where: a.id == ^account_id, select: map(a, ^columns))
    before = row |> lock("FOR UPDATE") |> Repo.one!()
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Multi.new()
    |> Multi.run(:account, fn repo, _changes ->
      {1, [written]} =
        repo.update_all(row, set: [former_names: former_names, updated_at: now])

      {:ok, written}
    end)
    |> Journal.record(actor,
      resource_type: resource_type,
      operation: :update,
      source: :account,
      before: before
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
    end
  end
end
