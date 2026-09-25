defmodule Portfolixir.Catalog.QuoteEnrichment do
  @moduledoc """
  The one worker that backfills quote history for new securities (E25 S3,
  G04): every created security, one at a time, whichever path created it.

  A security created over the API or the page used to start its own
  unbounded provider task; an import started one task per batch. Both now
  enqueue here: the worker keeps one queue, runs one sync at a time in a
  supervised task (a crash is that security's, never the queue's), and does
  not queue an id that is already waiting or running. It schedules no wake-up
  of its own: it works only when something is enqueued.

  Options: `:name` (default this module), and `:sync`, the function run per
  security id (default: load the security and sync it through
  `Portfolixir.Catalog.QuoteSync`). The `:sync` in this module's application
  config, when present, wins at run time — the test suite's seam.
  """

  use GenServer
  require Logger

  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Repo

  @doc false
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc "Queues the ids for enrichment; an id already queued or running is not added again."
  @spec enqueue([integer()], GenServer.server()) :: :ok
  def enqueue(ids, name \\ __MODULE__) when is_list(ids) do
    case Enum.filter(ids, &is_integer/1) do
      [] -> :ok
      valid -> GenServer.cast(name, {:enqueue, valid})
    end
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       queue: :queue.new(),
       queued: MapSet.new(),
       running: nil,
       sync: Keyword.get(opts, :sync, &sync_security/1)
     }}
  end

  @impl true
  def handle_cast({:enqueue, ids}, state) do
    state = ids |> Enum.uniq() |> Enum.reduce(state, &put_queued/2)
    {:noreply, maybe_start_next(state)}
  end

  @impl true
  def handle_info({ref, _result}, %{running: {ref, _id}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, maybe_start_next(%{state | running: nil})}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{running: {ref, id}} = state) do
    Logger.warning("quote enrichment for security ##{id} stopped: #{inspect(reason)}")
    {:noreply, maybe_start_next(%{state | running: nil})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp put_queued(id, state) do
    if MapSet.member?(state.queued, id) or match?({_, ^id}, state.running) do
      state
    else
      %{state | queue: :queue.in(id, state.queue), queued: MapSet.put(state.queued, id)}
    end
  end

  defp maybe_start_next(%{running: {_ref, _id}} = state), do: state

  defp maybe_start_next(state) do
    case :queue.out(state.queue) do
      {{:value, id}, queue} ->
        sync = configured_sync() || state.sync
        task = Task.Supervisor.async_nolink(Portfolixir.LogoSupervisor, fn -> sync.(id) end)

        %{state | queue: queue, queued: MapSet.delete(state.queued, id), running: {task.ref, id}}

      {:empty, _queue} ->
        state
    end
  end

  defp configured_sync do
    :portfolixir |> Application.get_env(__MODULE__, []) |> Keyword.get(:sync)
  end

  defp sync_security(id) do
    case Repo.get(Security, id) do
      %Security{} = security -> QuoteSync.sync_security(security)
      nil -> :ok
    end
  end
end
