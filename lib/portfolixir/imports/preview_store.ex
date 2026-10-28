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

  # Security review 2026-10-12, H07: at most this many bytes of parked
  # previews, as their terms measure (`:erts_debug.flat_size/1`), whatever
  # their number; the oldest-touched are evicted to make room. One preview
  # may take at most a quarter of it: a file at the parser's caps measures
  # about half of the budget, and is not parked (a remount shows the drop
  # zone again) rather than evicting every other session's preview.
  @default_max_bytes 256 * 1024 * 1024
  @entry_share 4

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
  The byte budget: how many bytes of parked previews the store keeps at once
  (`:import_preview_max_bytes`, H07). One entry may take a quarter of it.
  """
  @spec max_bytes() :: pos_integer()
  def max_bytes,
    do: Application.get_env(:portfolixir, :import_preview_max_bytes, @default_max_bytes)

  @doc "The most bytes one parked preview may take: a quarter of `max_bytes/0` (H07)."
  @spec max_entry_bytes() :: pos_integer()
  def max_entry_bytes, do: div(max_bytes(), @entry_share)

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
  Stores `preview` and `mapping` under `key`, with what a remount of the page
  shows from them (`summary:`, H08: computed once, on upload, rather than on
  every remount; `nil` when not given). An existing entry is replaced;
  past either budget, the number of entries or their bytes, the
  oldest-touched entries are evicted first. An empty key is refused
  (`:ignored`). A preview larger than one entry may take (`max_entry_bytes/0`)
  is not stored, and the entry `key` held before is dropped with it, so a
  remount never brings back an older file (`:too_large`, H07).
  """
  @spec put(String.t() | nil, term(), term(), keyword()) :: :ok | :ignored | :too_large
  def put(key, preview, mapping, opts \\ [])

  def put(key, preview, mapping, opts) when is_binary(key) and key != "" do
    summary = Keyword.get(opts, :summary)
    bytes = :erts_debug.flat_size({preview, mapping, summary}) * :erlang.system_info(:wordsize)

    if bytes > max_entry_bytes() do
      :ets.delete(@table, key)
      :too_large
    else
      evict_past_budget(key, bytes)
      touched_at = Keyword.get(opts, :touched_at, now())
      :ets.insert(@table, {key, preview, mapping, touched_at, bytes, summary})
      :ok
    end
  end

  def put(_key, _preview, _mapping, _opts), do: :ignored

  @doc "Replaces only the mapping of an existing entry (#768); `:ignored` when absent."
  @spec put_mapping(String.t() | nil, term()) :: :ok | :ignored
  def put_mapping(key, mapping) when is_binary(key) and key != "" do
    if :ets.update_element(@table, key, [{3, mapping}, {4, now()}]), do: :ok, else: :ignored
  end

  def put_mapping(_key, _mapping), do: :ignored

  @doc """
  Replaces only the summary of an existing entry (H08): what the page shows
  changed after the upload (a correction, a refreshed resolution), and a
  remount shows it as it is now. `:ignored` when absent. The entry's size
  stays as measured at `put/4`: a summary is small beside its preview.
  """
  @spec put_summary(String.t() | nil, term()) :: :ok | :ignored
  def put_summary(key, summary) when is_binary(key) and key != "" do
    if :ets.update_element(@table, key, [{6, summary}, {4, now()}]), do: :ok, else: :ignored
  end

  def put_summary(_key, _summary), do: :ignored

  @doc """
  The summary parked under `key`, read without the preview it belongs to and
  without renewing the lease (H08); `nil` when absent or stored without one.
  """
  @spec summary(String.t() | nil) :: term()
  def summary(key) when is_binary(key) and key != "",
    do: :ets.lookup_element(@table, key, 6, nil)

  def summary(_key), do: nil

  @doc """
  Returns `{preview, mapping}` for `session_token`, or `nil` when absent or
  expired.
  """
  @spec get(String.t() | nil) :: {term(), term()} | nil
  def get(key) do
    case restore(key) do
      {preview, mapping, _summary} -> {preview, mapping}
      nil -> nil
    end
  end

  @doc """
  Returns `{preview, mapping, summary}` for `key`, as `get/1` does, with the
  summary `put/4` or `put_summary/2` stored (`nil` when none was), or `nil`.
  """
  @spec restore(String.t() | nil) :: {term(), term(), term()} | nil
  def restore(key) when is_binary(key) and key != "" do
    case :ets.lookup(@table, key) do
      [{^key, preview, mapping, _touched_at, _bytes, summary}] ->
        :ets.update_element(@table, key, {4, now()})
        {preview, mapping, summary}

      [] ->
        nil
    end
  end

  def restore(_key), do: nil

  @doc """
  Whether a preview is parked under `key`, without copying it out of the
  store or renewing its lease (H07).
  """
  @spec parked?(String.t() | nil) :: boolean()
  def parked?(key) when is_binary(key) and key != "", do: :ets.member(@table, key)
  def parked?(_key), do: false

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

  # Drops the oldest-touched entries, other than the one `key` replaces,
  # until the new entry of `bytes` fits both budgets: a free slot and room in
  # the bytes. Only keys, timestamps and sizes leave the table (E25 S5, F41):
  # copying every parked preview into the caller's heap to find the oldest
  # cost as much as all of them.
  @keys_touched_bytes [{{:"$1", :_, :_, :"$2", :"$3", :_}, [], [{{:"$2", :"$1", :"$3"}}]}]

  defp evict_past_budget(key, bytes) do
    others =
      @table
      |> :ets.select(@keys_touched_bytes)
      |> Enum.reject(fn {_touched, other, _bytes} -> other == key end)
      |> Enum.sort()

    room = %{
      slots: max_entries() - 1,
      bytes: max_bytes() - bytes
    }

    held = %{slots: length(others), bytes: Enum.sum(Enum.map(others, &elem(&1, 2)))}

    Enum.reduce_while(others, held, fn {_touched, other, other_bytes}, held ->
      if held.slots <= room.slots and held.bytes <= room.bytes do
        {:halt, held}
      else
        :ets.delete(@table, other)
        {:cont, %{slots: held.slots - 1, bytes: held.bytes - other_bytes}}
      end
    end)
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
    :ets.select_delete(@table, [{{:_, :_, :_, :"$1", :_, :_}, [{:<, :"$1", cutoff}], [true]}])
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
