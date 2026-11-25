defmodule Portfolixir.Periods do
  @moduledoc """
  The period vocabulary (ADR-0062's amendment of 2026-11-25, point 6; I59;
  Sprint 32 T1): every key the dashboards, the widgets and the performance
  family's routes take, resolved against a day into the term the reads
  already take (`Portfolixir.Portfolios.Performance.summarise/2`): one of
  the read's own keys, `{:year, year}` or `{:range, from, to}`.

    * **Rolling**, to today: `1d 1w 1m 3m 6m` are ranges ending today,
      ADR-0061 §3's money window `S + 1` to `T` (`1d` today alone, `1w` the
      seven days after `T − 7`, `1m`, `3m` and `6m` the days after the date
      one, three or six months back), as the dashboard read its short
      periods since Sprint 31; `1y 3y 5y max` are the read's own keys.
    * **Calendar**: `mtd` (this month to today), `prev_month`, `qtd` (this
      quarter to today), `prev_quarter` (both whole, across a year's turn),
      `q1` to `q4` of the current year (a quarter not yet begun is refused,
      not read as empty), `ytd` (the read's own key) and `prev_year`.
    * **Keyed**: `year:YYYY`, one calendar year from 1970 (a year not yet
      begun is refused), and `saved:<id>`, a stored period by reference
      (Sprint 32 T2): its `from` to its `to`, or to today for one stored
      "until today"; one deleted no longer resolves.

  **The stored periods** (`Portfolixir.Periods.SavedPeriod`): a name, `from`
  and `to` or none, a `lock_version`; at most `max_saved/0`; every write
  journaled under its actor (resource type `"period"`, ADR-0017). A period
  holds no figure: no derived value reads it, so a write moves none
  (`Portfolixir.Derived.BlastRadius`).

  A range may end after today (`q4` in November); the reads clamp it to
  today, as they clamp `?to=`. `ytd`, `1y`, `3y`, `5y` and `max` resolve
  to themselves, so no figure a key returned before the vocabulary moves.

  Keys are matched as strings against a closed set and parsed with fixed
  patterns; no atom is ever made from one.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Journal
  alias Portfolixir.Periods.SavedPeriod
  alias Portfolixir.Repo

  @rolling ~w(1d 1w 1m 3m 6m 1y 3y 5y max)
  @calendar ~w(mtd prev_month qtd prev_quarter q1 q2 q3 q4 ytd prev_year)
  @keys @rolling ++ @calendar

  # The read's own keys (`Performance.periods/0`), passed through as they are.
  @read_keys ~w(ytd 1y 3y 5y max)

  @first_year 1970
  @year_key ~r/\Ayear:([0-9]{4})\z/
  @saved_key ~r/\Asaved:([1-9][0-9]{0,18})\z/

  @max_saved 50
  @max_id 9_223_372_036_854_775_807
  @resource_type "period"
  # The transaction advisory lock a create takes before it counts
  # (`Portfolixir.LockTable` row 31).
  @count_lock "periods|count"

  @typedoc "A term the performance family's reads take."
  @type read_term :: String.t() | {:year, pos_integer()} | {:range, Date.t(), Date.t()}

  @typedoc "Why a key does not resolve: none, not yet begun, or a stored period no longer there."
  @type refusal :: :unknown_period | :not_begun | :not_found

  @typedoc """
  A refused write: the changeset, a key the write does not take or one it
  needs, an unknown id, or the 51st period.
  """
  @type write_refusal ::
          Ecto.Changeset.t()
          | {:unknown_fields, %{String.t() => [String.t()]}}
          | {:missing_fields, %{String.t() => [String.t()]}}
          | :not_found
          | :too_many_periods

  @doc "The rolling keys, shortest first."
  @spec rolling() :: [String.t()]
  def rolling, do: @rolling

  @doc "The calendar keys, in the menu's order."
  @spec calendar() :: [String.t()]
  def calendar, do: @calendar

  @doc "Every fixed key: the rolling ones, then the calendar ones."
  @spec keys() :: [String.t()]
  def keys, do: @keys

  @doc "Whether `key` is a key of the vocabulary, by its form (not whether it resolves today)."
  @spec key?(term()) :: boolean()
  def key?(key) when key in @keys, do: true

  def key?(key) when is_binary(key),
    do: match?({:ok, _year}, year_key(key)) or match?({:ok, _id}, saved_id(key))

  def key?(_key), do: false

  @doc """
  The id a `saved:<id>` key names, `{:ok, id}`, or `:error` for any other
  key.
  """
  @spec saved_id(term()) :: {:ok, pos_integer()} | :error
  def saved_id(key) when is_binary(key) do
    case Regex.run(@saved_key, key) do
      [_key, digits] ->
        id = String.to_integer(digits)
        if id <= @max_id, do: {:ok, id}, else: :error

      nil ->
        :error
    end
  end

  def saved_id(_key), do: :error

  @doc """
  The term the reads take for `key` on `today`: `{:ok, term}`,
  `{:error, :not_begun}` for a quarter or a year that has not begun,
  `{:error, :not_found}` for a stored period no longer there, or
  `{:error, :unknown_period}` for anything that is no key.

  `saved` is where a `saved:<id>` key is looked up: `:stored` (the
  default) reads the row, a list of `Portfolixir.Periods.SavedPeriod`
  looks it up there (a page that read them once).
  """
  @spec resolve(term(), Date.t(), :stored | [SavedPeriod.t()]) ::
          {:ok, read_term()} | {:error, refusal()}
  def resolve(key, today \\ Clock.today(), saved \\ :stored)

  def resolve(key, %Date{}, _saved) when key in @read_keys, do: {:ok, key}

  def resolve("1d", %Date{} = today, _saved), do: {:ok, {:range, today, today}}
  def resolve("1w", %Date{} = today, _saved), do: {:ok, {:range, Date.add(today, -6), today}}
  def resolve("1m", %Date{} = today, _saved), do: {:ok, {:range, months_back(today, 1), today}}
  def resolve("3m", %Date{} = today, _saved), do: {:ok, {:range, months_back(today, 3), today}}
  def resolve("6m", %Date{} = today, _saved), do: {:ok, {:range, months_back(today, 6), today}}

  def resolve("mtd", %Date{} = today, _saved),
    do: {:ok, {:range, Date.beginning_of_month(today), today}}

  def resolve("prev_month", %Date{} = today, _saved) do
    last = today |> Date.beginning_of_month() |> Date.add(-1)
    {:ok, {:range, Date.beginning_of_month(last), last}}
  end

  def resolve("qtd", %Date{} = today, _saved), do: {:ok, {:range, quarter_start(today), today}}

  def resolve("prev_quarter", %Date{} = today, _saved) do
    start = today |> quarter_start() |> Date.add(-1) |> quarter_start()
    {:ok, {:range, start, quarter_end(start)}}
  end

  def resolve("q" <> n, %Date{} = today, _saved) when n in ~w(1 2 3 4) do
    start = Date.new!(today.year, (String.to_integer(n) - 1) * 3 + 1, 1)

    if Date.after?(start, today),
      do: {:error, :not_begun},
      else: {:ok, {:range, start, quarter_end(start)}}
  end

  def resolve("prev_year", %Date{} = today, _saved), do: {:ok, {:year, today.year - 1}}

  def resolve(key, %Date{} = today, saved) when is_binary(key) do
    case {year_key(key), saved_id(key)} do
      {{:ok, year}, _none} when year > today.year -> {:error, :not_begun}
      {{:ok, year}, _none} -> {:ok, {:year, year}}
      {:error, {:ok, id}} -> saved_span(lookup(id, saved), today)
      {:error, :error} -> {:error, :unknown_period}
    end
  end

  def resolve(_key, _today, _saved), do: {:error, :unknown_period}

  defp lookup(id, :stored), do: get_saved(id)
  defp lookup(id, saved) when is_list(saved), do: Enum.find(saved, &(&1.id == id))

  defp saved_span(%SavedPeriod{from: from, to: to}, today), do: {:ok, {:range, from, to || today}}
  defp saved_span(nil, _today), do: {:error, :not_found}

  # --- the stored periods: reads ----------------------------------------------

  @doc "The most periods an instance stores."
  @spec max_saved() :: pos_integer()
  def max_saved, do: @max_saved

  @doc "The longest period name, in characters."
  @spec name_max() :: pos_integer()
  def name_max, do: SavedPeriod.name_max()

  @doc "The stored periods in the order they were made."
  @spec list_saved() :: [SavedPeriod.t()]
  def list_saved, do: Repo.all(from(p in SavedPeriod, order_by: [asc: p.id]))

  @doc "The stored period `id`, or `nil` (also for an id no row can carry)."
  @spec get_saved(term()) :: SavedPeriod.t() | nil
  def get_saved(id) when is_integer(id) and id >= 1 and id <= @max_id,
    do: Repo.get(SavedPeriod, id)

  def get_saved(_id), do: nil

  # --- the stored periods: writes ---------------------------------------------
  #
  # Every stored write is one journal entry under its actor (ADR-0017),
  # resource type "period"; the table's guard refuses one that is not.

  @doc """
  Stores a period on behalf of `actor` from `attrs`, which take only
  `name`, `from` and `to` (string or atom keys; `to` absent or `nil` is
  "until today"), lock_version 1, journaled as a create.

  `{:error, :too_many_periods}` when `max_saved/0` are stored: the count is
  read under a transaction advisory lock every create takes, so two
  creates cannot both pass it. Nothing is written on a refusal.
  """
  @spec create_saved(Actor.t(), map()) :: {:ok, SavedPeriod.t()} | {:error, write_refusal()}
  def create_saved(%Actor{} = actor, attrs) when is_map(attrs) do
    with :ok <- closed(attrs, ~w(name from to), "a period's create") do
      changeset = SavedPeriod.changeset(%SavedPeriod{}, string_attrs(attrs))

      if changeset.valid?,
        do: insert(actor, changeset),
        else: {:error, Map.put(changeset, :action, :insert)}
    end
  end

  @doc """
  Replaces the name and the span of the period `id` on behalf of `actor`.
  `attrs` take exactly `name`, `from`, `to` (`nil`: until today) and
  `lock_version`, the one the caller read: under the row's lock, a stored
  lock_version that differs answers `{:error, :stale, stored}` and nothing
  is written. Otherwise lock_version rises by one and the replace is
  journaled as an update with its before-image; one that changes nothing
  writes and journals nothing.
  """
  @spec replace_saved(Actor.t(), term(), map()) ::
          {:ok, SavedPeriod.t()} | {:error, :stale, SavedPeriod.t()} | {:error, write_refusal()}
  def replace_saved(%Actor{} = actor, id, attrs) when is_map(attrs) do
    fields = ~w(name from to lock_version)

    with :ok <- closed(attrs, fields, "a period's replace"),
         attrs = string_attrs(attrs),
         :ok <- required(attrs, fields, "a period's replace"),
         {:ok, read_version} <- lock_version(attrs),
         {:ok, prior} <- fetch(id) do
      Multi.new()
      |> Multi.run(:current, fn _repo, changes ->
        current = Journal.locked_row(changes)

        if current.lock_version == read_version,
          do: {:ok, current},
          else: {:error, current}
      end)
      |> Multi.update(:period, fn %{current: current} ->
        SavedPeriod.changeset(current, Map.take(attrs, ~w(name from to)))
      end)
      |> journal(actor, :update, prior)
      |> Repo.transaction()
      |> case do
        {:error, :current, %SavedPeriod{} = stored, _changes} -> {:error, :stale, stored}
        result -> written(result)
      end
    end
  end

  @doc """
  Deletes the period `id` on behalf of `actor`, journaled as a delete with
  its before-image. Nothing else changes: a pin that names it dangles and
  reads the dashboard's period (ADR-0062's amendment, point 6).
  """
  @spec delete_saved(Actor.t(), term()) :: {:ok, SavedPeriod.t()} | {:error, :not_found}
  def delete_saved(%Actor{} = actor, id) do
    with {:ok, prior} <- fetch(id) do
      Multi.new()
      |> Multi.delete(:period, &Journal.locked_row/1)
      |> journal(actor, :delete, prior)
      |> Repo.transaction()
      |> written()
    end
  end

  defp insert(actor, changeset) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [@count_lock])

      if Repo.aggregate(SavedPeriod, :count) >= @max_saved,
        do: Repo.rollback(:too_many_periods)

      Multi.new()
      |> Multi.insert(:period, changeset)
      |> journal(actor, :create, nil)
      |> Repo.transaction()
      |> written()
      |> case do
        {:ok, period} -> period
        {:error, refusal} -> Repo.rollback(refusal)
      end
    end)
  end

  defp journal(multi, actor, operation, prior) do
    Journal.record(multi, actor,
      resource_type: @resource_type,
      operation: operation,
      source: :period,
      before: prior
    )
  end

  defp written({:ok, %{period: period}}), do: {:ok, period}
  defp written({:error, :period, %Ecto.Changeset{} = invalid, _changes}), do: {:error, invalid}
  defp written({:error, {:journal_lock, _step}, :not_found, _changes}), do: {:error, :not_found}

  defp fetch(id) do
    case get_saved(id) do
      %SavedPeriod{} = period -> {:ok, period}
      nil -> {:error, :not_found}
    end
  end

  # The keys a write takes, read as strings (an atom key from code as its
  # name); a key it does not take is refused by name, never made an atom.
  defp closed(attrs, fields, write) do
    attrs
    |> Map.keys()
    |> Enum.map(&key_name/1)
    |> Enum.reject(&(&1 in fields))
    |> case do
      [] ->
        :ok

      unknown ->
        message = "is unknown: #{write} takes only #{Enum.join(fields, ", ")}"
        {:error, {:unknown_fields, Map.new(unknown, &{&1, [message]})}}
    end
  end

  defp required(attrs, fields, write) do
    case Enum.reject(fields, &Map.has_key?(attrs, &1)) do
      [] ->
        :ok

      missing ->
        message = "is required: #{write} takes #{Enum.join(fields, ", ")}"
        {:error, {:missing_fields, Map.new(missing, &{&1, [message]})}}
    end
  end

  defp lock_version(%{"lock_version" => version})
       when is_integer(version) and version >= 1 and version <= @max_id,
       do: {:ok, version}

  defp lock_version(_attrs) do
    {:error,
     %SavedPeriod{}
     |> Ecto.Changeset.change()
     |> Ecto.Changeset.add_error(
       :lock_version,
       dgettext_noop("errors", "must be the whole number the period was read with"),
       validation: :lock_version
     )
     |> Map.put(:action, :update)}
  end

  defp string_attrs(attrs), do: Map.new(attrs, fn {key, value} -> {key_name(key), value} end)

  defp key_name(key) when is_binary(key), do: key
  defp key_name(key) when is_atom(key), do: Atom.to_string(key)
  defp key_name(key), do: inspect(key)

  # ADR-0061 §3's money window: the day after the date `months` back.
  defp months_back(today, months), do: today |> Date.shift(month: -months) |> Date.add(1)

  defp quarter_start(%Date{year: year, month: month}),
    do: Date.new!(year, div(month - 1, 3) * 3 + 1, 1)

  defp quarter_end(start), do: start |> Date.shift(month: 2) |> Date.end_of_month()

  defp year_key(key) do
    case Regex.run(@year_key, key) do
      [_key, digits] ->
        year = String.to_integer(digits)
        if year >= @first_year, do: {:ok, year}, else: :error

      nil ->
        :error
    end
  end
end
