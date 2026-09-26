defmodule Portfolixir.Lifecycle.FormerNamesBackfill do
  @moduledoc """
  The one-time backfill of `former_names` from the audit journal (ADR-0050 §4
  third bullet), run by the migration `backfill_account_former_names`.

  Every journaled rename of a cash account or a depot is replayed, in journal
  order, through the rename rule of `Portfolixir.Lifecycle.AccountNames`, **at
  the moment it was made**: the journal's creates, updates and deletes of the
  kind rebuild which account carried which live name at each rename, and the
  former names replayed so far stand in for the column the rule would have
  kept. So, as the rule does:

    * a rename back to a former name consumes it;
    * the previous name is not recorded while another account of the kind in
      the portfolio still carries it as its live name — it resolved to that
      account then, and the rule records nothing, even when that account is
      renamed away later;
    * the previous name is not recorded when another account already holds it
      as a former name — one former name belongs to one account. This one is
      reported.

  An account whose journal starts with an update (created before the journal
  was armed) is taken to have carried that update's previous name from the
  start. The replayed names are then held against the name guard over the
  accounts as they are **now**:

    * a name another live account of the kind in the portfolio carries is not
      recorded — typically a zombie an import created under the old name after
      the rename, which a merge with collapse repairs (§8);
    * a name another account already has as a former name (one the column
      already holds) is not recorded either.

  Every name held back for a reason other than a live name at the rename's
  moment is **reported, never written**; the migration logs it. The former
  names of an account deleted since go with it, and a scenario (what-if) entry
  is never replayed.

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
    events = journal_events(resource_type)

    if Enum.any?(events, &rename?/1) do
      accounts = load_accounts(table)
      {replayed, held_back} = replay(kind, events, accounts)
      {accepted, refused} = hold_against_guard(kind, replayed, accounts)

      {write(actor, kind, resource_type, table, columns, accepted, accounts),
       held_back ++ refused}
    else
      {[], []}
    end
  end

  # Every real (non-scenario) create, update and delete of the kind, in
  # journal order, as `{operation, entry_id, account_id, before, after}` with
  # `before` and `after` reduced to `%{name, portfolio_id}` (nil for a side the
  # operation has none of).
  defp journal_events(resource_type) do
    from(e in "audit_journal",
      where:
        e.resource_type == ^resource_type and
          e.operation in ["create", "upsert", "update", "delete"] and is_nil(e.scenario_id),
      order_by: [asc: e.id],
      select: {e.operation, e.id, e.resource_id, e.before, e.after}
    )
    |> Repo.all()
    |> Enum.flat_map(&event/1)
  end

  defp event({operation, entry_id, resource_id, before, after_image})
       when is_binary(resource_id) do
    case Integer.parse(resource_id) do
      {account_id, ""} ->
        [{operation, entry_id, account_id, identity(before), identity(after_image)}]

      _other ->
        []
    end
  end

  defp event(_entry), do: []

  defp identity(%{"name" => name} = image) when is_binary(name),
    do: %{name: name, portfolio_id: image["portfolio_id"]}

  defp identity(_image), do: nil

  defp rename?({"update", _entry, _id, %{name: previous}, %{name: new}}), do: previous != new
  defp rename?(_event), do: false

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

  # The journal replayed through the rename rule, each rename at its moment.
  # `live` is every account alive at that point with its name and portfolio,
  # `former` the former names replayed so far, each with the journal entry
  # that appended it. Returns the former names of the accounts that exist
  # today, and the refusals of names another account already held.
  defp replay(kind, events, accounts) do
    initial = %{live: initially_live(events, accounts), former: %{}, held_back: []}

    final = Enum.reduce(events, initial, &replay_event(kind, &1, &2))
    replayed = Map.take(final.former, Map.keys(accounts))

    # A refusal outlives the replay only for an account that still exists and
    # did not come by the name later after all.
    held_back =
      Enum.filter(final.held_back, fn %{account_id: id, name: name} ->
        Map.has_key?(accounts, id) and
          not Enum.any?(Map.get(replayed, id, []), &(elem(&1, 0) == name))
      end)

    {replayed, Enum.uniq(held_back)}
  end

  # An account whose journal starts with a create did not exist before it;
  # one whose journal starts with an update or a delete (created before the
  # journal was armed) carried that entry's previous identity from the start;
  # one the journal never names carries today's.
  defp initially_live(events, accounts) do
    firsts =
      Enum.reduce(events, %{}, fn {_op, _entry, id, _before, _after} = event, acc ->
        Map.put_new(acc, id, event)
      end)

    from_journal =
      for {id, {operation, _entry, _id, %{} = before, _after}} <- firsts,
          operation in ["update", "delete"],
          into: %{},
          do: {id, before}

    untouched =
      for {id, account} <- accounts,
          not Map.has_key?(firsts, id),
          into: %{},
          do: {id, %{name: account.name, portfolio_id: account.portfolio_id}}

    Map.merge(untouched, from_journal)
  end

  defp replay_event(_kind, {op, _entry, id, _before, %{} = created}, state)
       when op in ["create", "upsert"],
       do: put_in(state, [:live, id], created)

  defp replay_event(_kind, {"delete", _entry, id, _before, _after}, state),
    do: %{state | live: Map.delete(state.live, id), former: Map.delete(state.former, id)}

  defp replay_event(kind, {"update", entry, id, %{} = before, %{} = renamed}, state) do
    state =
      if before.name != renamed.name,
        do: replay_rename(kind, entry, id, before.name, renamed, state),
        else: state

    put_in(state, [:live, id], renamed)
  end

  defp replay_event(_kind, _event, state), do: state

  # The rename rule of `AccountNames` at this entry's moment: the new name is
  # consumed from the account's former names, and the previous one appended
  # unless the account already has it, another live account of the kind in
  # the portfolio carries it (recorded nothing, silently, as the rule does),
  # or another account holds it as a former name (reported).
  defp replay_rename(kind, entry, id, previous, renamed, state) do
    names =
      state.former
      |> Map.get(id, [])
      |> Enum.reject(fn {name, _entry} -> name == renamed.name end)

    portfolio_id = renamed.portfolio_id

    others =
      for {other_id, other} <- state.live,
          other_id != id and other.portfolio_id == portfolio_id,
          do: other_id

    cond do
      Enum.any?(names, fn {name, _entry} -> name == previous end) ->
        put_in(state, [:former, id], names)

      Enum.any?(others, &(state.live[&1].name == previous)) ->
        put_in(state, [:former, id], names)

      holder = Enum.find(Enum.sort(others), &former_of?(state, &1, previous)) ->
        refusal = %{
          kind: kind,
          account_id: id,
          name: previous,
          reason: :former_name_of_another_account,
          holder_id: holder
        }

        %{
          state
          | former: Map.put(state.former, id, names),
            held_back: state.held_back ++ [refusal]
        }

      true ->
        put_in(state, [:former, id], names ++ [{previous, entry}])
    end
  end

  defp former_of?(state, id, name),
    do: state.former |> Map.get(id, []) |> Enum.any?(fn {former, _entry} -> former == name end)

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
