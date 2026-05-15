defmodule Portfolixir.Catalog.QuoteSync do
  @moduledoc """
  Background scheduler + on-demand entry point for quote history sync.

  The GenServer ticks every `interval_ms` (default 6 h) and calls
  `sync_all/1`, which fans out to one adapter per security based on
  `Security.provider`. Adapters implement
  `Portfolixir.Catalog.QuoteSync.Provider`.

  Hard rule: no real HTTP in tests. The test environment registers
  `Portfolixir.Catalog.QuoteSync.Fake` instead of CoinGecko/PortfolioPerformance.

  The scheduler is opt-in (`enabled?: true` in prod, `false` everywhere else).
  Use `sync_now/0` from the UI or REPL to trigger an immediate sync.
  """

  use GenServer
  require Logger

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security

  @default_interval :timer.hours(6)

  @default_adapter_for %{
    "coingecko" => Portfolixir.Catalog.QuoteSync.Yahoo,
    "portfolio_performance" => Portfolixir.Catalog.QuoteSync.Yahoo
  }

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
  Synchronously sync all securities. Returns
  `{:ok, %{ok: integer, skipped: integer, error: integer}}`.

  Options:
    * `:adapter_for` – `%{"provider_string" => module}` map, overrides config.
  """
  def sync_all(opts \\ []) do
    adapter_for = Keyword.get(opts, :adapter_for, runtime_adapter_for())
    securities = Catalog.list_securities()

    counts =
      Enum.reduce(securities, %{ok: 0, skipped: 0, error: 0}, fn security, acc ->
        update_counts(acc, sync_one(security, adapter_for, opts))
      end)

    {:ok, counts}
  end

  @doc "Synchronously sync one security with the configured or provided adapter map."
  def sync_security(%Security{} = security, opts \\ []) do
    adapter_for = Keyword.get(opts, :adapter_for, runtime_adapter_for())
    sync_one(security, adapter_for, opts)
  end

  # -- GenServer callbacks --------------------------------------------------

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval),
      enabled?: Keyword.get(opts, :enabled?, false),
      adapter_for: Keyword.get(opts, :adapter_for, @default_adapter_for)
    }

    if state.enabled?, do: schedule_tick(state.interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    Task.start(fn ->
      try do
        sync_all(adapter_for: state.adapter_for)
      rescue
        exception ->
          Logger.error("quote sync tick crashed: #{Exception.message(exception)}")
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

  # -- per-security sync ----------------------------------------------------

  defp sync_one(%Security{provider: provider} = security, adapter_for, opts) do
    case Map.get(adapter_for, provider) do
      nil ->
        :skipped

      adapter ->
        case adapter.fetch(security, opts) do
          {:ok, rows} when is_list(rows) ->
            persist(security, rows, provider)

          {:error, reason} ->
            Logger.warning(
              "quote fetch failed for security ##{security.id} via #{inspect(adapter)}: #{inspect(reason)}"
            )

            :error
        end
    end
  end

  defp persist(_security, [], _provider), do: :ok

  defp persist(security, rows, provider) do
    case Quotes.upsert_many(
           security.id,
           Enum.map(rows, &Map.put(&1, :source, provider))
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("quote upsert failed for security ##{security.id}: #{inspect(reason)}")
        :error
    end
  end

  defp update_counts(acc, :ok), do: Map.update!(acc, :ok, &(&1 + 1))
  defp update_counts(acc, :skipped), do: Map.update!(acc, :skipped, &(&1 + 1))
  defp update_counts(acc, :error), do: Map.update!(acc, :error, &(&1 + 1))

  defp runtime_adapter_for do
    Application.get_env(:portfolixir, __MODULE__, [])
    |> Keyword.get(:adapter_for, @default_adapter_for)
  end
end
