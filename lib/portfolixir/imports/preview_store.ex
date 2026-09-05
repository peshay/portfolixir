defmodule Portfolixir.Imports.PreviewStore do
  @moduledoc """
  Transient, session-scoped store for in-progress import previews.

  A parsed `Portfolixir.Imports.Preview` and its companion mapping live only in
  memory (ETS), keyed by the browser-session CSRF token.  The entry survives a
  LiveView remount — which happens when the user switches the UI locale — so the
  user does not need to re-upload the file.

  Entries expire after `@ttl_seconds` of inactivity and are swept by a periodic
  timer.  No database involvement; this is intentionally ephemeral state.

  ## Lifecycle

  1. After a successful parse the LiveView calls `put/3`.
  2. On every remount `get/1` is called.  If a non-nil value is returned the
     LiveView restores the preview + mapping and jumps straight to `:preview`.
  3. The user confirms or discards the import — the LiveView calls `delete/1`.
  4. A TTL sweep removes abandoned entries automatically.
  """

  use GenServer

  @table __MODULE__

  # Entries expire after 2 hours of inactivity — enough to survive a locale
  # switch (which triggers a remount within milliseconds) while preventing
  # memory accumulation from abandoned browser tabs.
  @ttl_seconds 7_200

  # At most this many parked previews (#768); the oldest-touched is evicted.
  @default_max_entries 32

  ## Client API

  @doc "Starts the store, normally called from `Portfolixir.Application`."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc "The budget: how many previews the store keeps at once (`:import_preview_max_entries`)."
  @spec max_entries() :: pos_integer()
  def max_entries,
    do: Application.get_env(:portfolixir, :import_preview_max_entries, @default_max_entries)

  @doc """
  The store key for a browser session (#768): a hash of the session token, so
  the raw CSRF secret never sits in a public table. `nil` for a missing token,
  which `put/3` refuses.
  """
  @spec key_for(String.t() | nil) :: String.t() | nil
  def key_for(token) when is_binary(token) and token != "" do
    :sha256 |> :crypto.hash(token) |> Base.encode16(case: :lower)
  end

  def key_for(_missing), do: nil

  @doc """
  Stores `preview` and `mapping` under `key`. An existing entry is replaced;
  past the budget the oldest-touched entry is evicted first. An empty key is
  refused (`:ignored`).
  """
  @spec put(String.t() | nil, term(), term(), keyword()) :: :ok | :ignored
  def put(key, preview, mapping, opts \\ [])

  def put(key, preview, mapping, opts) when is_binary(key) and key != "" do
    unless :ets.member(@table, key), do: evict_past_budget()
    :ets.insert(@table, {key, preview, mapping, Keyword.get(opts, :touched_at, now())})
    :ok
  end

  def put(_key, _preview, _mapping, _opts), do: :ignored

  @doc "Replaces only the mapping of an existing entry (#768); `:ignored` when absent."
  @spec put_mapping(String.t() | nil, term()) :: :ok | :ignored
  def put_mapping(key, mapping) when is_binary(key) and key != "" do
    if :ets.update_element(@table, key, [{3, mapping}, {4, now()}]), do: :ok, else: :ignored
  end

  def put_mapping(_key, _mapping), do: :ignored

  @doc """
  Returns `{preview, mapping}` for `session_token`, or `nil` when absent or
  expired.
  """
  @spec get(String.t() | nil) :: {term(), term()} | nil
  def get(key) when is_binary(key) and key != "" do
    case :ets.lookup(@table, key) do
      [{^key, preview, mapping, _touched_at}] ->
        :ets.update_element(@table, key, {4, now()})
        {preview, mapping}

      [] ->
        nil
    end
  end

  def get(_key), do: nil

  @doc "Empties the store. For tests that reason about the budget on the shared table."
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc "Removes the entry for `key` (e.g. after a confirmed or discarded import)."
  @spec delete(String.t() | nil) :: :ok
  def delete(key) when is_binary(key) do
    :ets.delete(@table, key)
    :ok
  end

  def delete(_key), do: :ok

  # Drops the oldest-touched entries until one slot is free.
  defp evict_past_budget do
    overflow = :ets.info(@table, :size) - max_entries() + 1

    if overflow > 0 do
      @table
      |> :ets.tab2list()
      |> Enum.sort_by(&elem(&1, 3))
      |> Enum.take(overflow)
      |> Enum.each(fn {key, _preview, _mapping, _touched} -> :ets.delete(@table, key) end)
    end
  end

  ## GenServer callbacks

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    schedule_sweep()
    {:ok, :no_state}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = now() - @ttl_seconds
    :ets.select_delete(@table, [{{:_, :_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  ## Private helpers

  defp now, do: System.os_time(:second)

  defp schedule_sweep do
    # Sweep every 15 minutes.
    Process.send_after(self(), :sweep, 15 * 60 * 1_000)
  end
end
