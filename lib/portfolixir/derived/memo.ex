defmodule Portfolixir.Derived.Memo do
  @moduledoc """
  The `:request` lifetime of the derived-value axis (ADR-0039 §1): ADR-0032's
  volatile memo, absorbed. It stops existing as separate machinery — this ETS
  table is the one in-memory tier every registered analytic shares, and the
  durable tier promotes its hits through it so a decoded payload is decoded
  once per version, not once per read.

  Still a **memo, not a store**: it lives in ETS owned by this process, is
  empty after every restart, and is never read as a source of truth — dropping
  the table at any moment changes latency and nothing else, which is what
  leaves ADR-0004 (holdings are never stored) intact.

  Entries are keyed `{analytic_id, basis, entry_key, data_version,
  computation_version}` — the full ADR-0039 key. Versions live in
  `Portfolixir.Derived.DataVersion` (the durable counter), so invalidation
  never touches this table: a bump simply makes old entries unreachable as
  current. Versions are strictly monotonic but not gapless, so the superseded
  generation (`previous/1`) is the entry with the **highest version below
  current**, and it stays reachable until a fresh computation replaces it —
  the same until-replaced shape the durable tier's stale row has (ADR-0032 §6
  carried forward: the superseded series a surface renders, labelled, while a
  fresh one computes). The sweep on insert keeps one previous generation per
  entry key and age-bounds the rest.
  """

  use GenServer

  @table __MODULE__
  # Entries a surface will never ask for again (day-rollover keys) leave on
  # the next insert for their basis once they are this old.
  @max_age_seconds 7 * 86_400
  @generations_kept 2

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  The memoised value at exactly this key, as `{:hit, value, as_of}`, or
  `:miss`. The caller composes the current data version into `key`, so an
  entry of a superseded version can never be read as current.
  """
  @spec get(tuple()) :: {:hit, term(), DateTime.t()} | :miss
  def get(key) do
    if table?() do
      case :ets.lookup(@table, key) do
        [{_key, value, as_of, _stored_at}] -> {:hit, value, as_of}
        [] -> :miss
      end
    else
      :miss
    end
  end

  @doc """
  The superseded generation for a key: the entry with the highest data version
  **below** the key's current one, as `{:hit, value, as_of}`, or `:miss`.
  """
  @spec previous(tuple()) :: {:hit, term(), DateTime.t()} | :miss
  def previous({analytic, basis, entry_key, version, comp}) do
    if table?() do
      @table
      |> :ets.select([
        {{{analytic, basis, entry_key, :"$1", comp}, :"$2", :"$3", :_}, [{:<, :"$1", version}],
         [{{:"$1", :"$2", :"$3"}}]}
      ])
      |> case do
        [] ->
          :miss

        entries ->
          entries
          |> Enum.max_by(&elem(&1, 0))
          |> then(fn {_v, value, as_of} -> {:hit, value, as_of} end)
      end
    else
      :miss
    end
  end

  @doc """
  Remembers `value` under `key`, then sweeps: the entry key keeps its newest
  #{@generations_kept} generations, and entries of the same basis older than
  #{div(@max_age_seconds, 86_400)} days leave regardless of key.
  """
  @spec put(tuple(), term(), DateTime.t()) :: :ok
  def put({analytic, basis, entry_key, _version, comp} = key, value, %DateTime{} = as_of) do
    if table?() do
      :ets.insert(@table, {key, value, as_of, System.system_time(:second)})
      sweep_generations(analytic, basis, entry_key, comp)
      sweep_age(analytic, basis)
    end

    :ok
  end

  @doc "Empties the memo. For tests and for the restart-equivalence proof."
  @spec reset() :: :ok
  def reset do
    if table?(), do: GenServer.call(__MODULE__, :reset), else: :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  defp sweep_generations(analytic, basis, entry_key, comp) do
    versions =
      :ets.select(@table, [
        {{{analytic, basis, entry_key, :"$1", comp}, :_, :_, :_}, [], [:"$1"]}
      ])

    versions
    |> Enum.sort(:desc)
    |> Enum.drop(@generations_kept)
    |> Enum.each(&:ets.delete(@table, {analytic, basis, entry_key, &1, comp}))
  end

  defp sweep_age(analytic, basis) do
    cutoff = System.system_time(:second) - @max_age_seconds

    :ets.select_delete(@table, [
      {{{analytic, basis, :_, :_, :_}, :_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}
    ])
  end

  defp table?, do: :ets.whereis(@table) != :undefined
end
