defmodule Portfolixir.Fx.RateSync do
  @moduledoc """
  Background scheduler + on-demand entry point for exchange-rate sync.

  The GenServer ticks every `interval_ms` (default 12 h) and calls `sync/1`,
  which fetches EUR-hub rates from the configured provider
  (`Portfolixir.Fx.RateSync.Provider`) and upserts them via `Portfolixir.Fx`.

  Hard rule: no real HTTP in tests. The test environment registers
  `Portfolixir.Fx.RateSync.Fake` instead of the ECB adapter.

  The scheduler is opt-in (`enabled?: true` in prod/dev, `false` in tests).
  Use `sync_now/0` from the UI, API, or REPL to trigger an immediate sync.
  """

  use GenServer
  require Logger

  alias Portfolixir.Fx

  @default_interval :timer.hours(12)
  @default_provider Portfolixir.Fx.RateSync.Ecb

  # -- public API ------------------------------------------------------------

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc "Trigger an immediate background sync (returns :ok)."
  def sync_now(name \\ __MODULE__) do
    send(name, :tick)
    :ok
  end

  @doc """
  Synchronously fetch and persist the latest rates.

  Returns `{:ok, %{provider: atom, status: :ok, upserted: integer}}` or
  `{:error, reason}`.

  Options:
    * `:provider` – adapter module, overrides config.
  """
  def sync(opts \\ []) do
    provider = Keyword.get(opts, :provider, runtime_provider())

    case safe_fetch(provider, opts) do
      {:ok, rows} when is_list(rows) ->
        persist(provider, rows)

      {:error, reason} ->
        Logger.warning("fx rate fetch failed via #{inspect(provider)}: #{inspect(reason)}")
        {:error, reason}

      other ->
        Logger.warning("fx rate fetch returned unexpected value: #{inspect(other)}")
        {:error, {:unexpected_response, other}}
    end
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval),
      enabled?: Keyword.get(opts, :enabled?, false),
      provider: Keyword.get(opts, :provider, @default_provider)
    }

    if state.enabled?, do: schedule_tick(state.interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    Task.start(fn ->
      try do
        sync(provider: state.provider)
      rescue
        exception ->
          Logger.error("fx rate sync tick crashed: #{Exception.message(exception)}")
      end
    end)

    if state.enabled?, do: schedule_tick(state.interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_tick(interval_ms) do
    Process.send_after(self(), :tick, interval_ms)
  end

  # -- internals -------------------------------------------------------------

  defp safe_fetch(provider, opts) do
    provider.fetch(opts)
  rescue
    exception ->
      {:error, {:adapter_exception, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {:adapter_exit, {kind, reason}}}
  end

  defp persist(provider, rows) do
    case Fx.upsert_many(rows) do
      {:ok, count} ->
        {:ok, %{provider: provider.id(), status: :ok, upserted: count}}

      {:error, reason} ->
        Logger.warning("fx rate upsert failed: #{inspect(reason)}")
        {:error, {:upsert_failed, reason}}
    end
  end

  defp runtime_provider do
    Application.get_env(:portfolixir, __MODULE__, [])
    |> Keyword.get(:provider, @default_provider)
  end
end
