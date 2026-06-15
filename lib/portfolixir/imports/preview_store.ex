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

  ## Client API

  @doc "Starts the store, normally called from `Portfolixir.Application`."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Stores `preview` and `mapping` for the given `session_token`.

  If an entry already exists it is replaced.
  """
  @spec put(String.t(), term(), term()) :: :ok
  def put(session_token, preview, mapping) do
    :ets.insert(@table, {session_token, preview, mapping, now()})
    :ok
  end

  @doc """
  Returns `{preview, mapping}` for `session_token`, or `nil` when absent or
  expired.
  """
  @spec get(String.t()) :: {term(), term()} | nil
  def get(session_token) do
    case :ets.lookup(@table, session_token) do
      [{^session_token, preview, mapping, _touched_at}] ->
        :ets.update_element(@table, session_token, {4, now()})
        {preview, mapping}

      [] ->
        nil
    end
  end

  @doc "Removes the entry for `session_token` (e.g. after a confirmed or discarded import)."
  @spec delete(String.t()) :: :ok
  def delete(session_token) do
    :ets.delete(@table, session_token)
    :ok
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
