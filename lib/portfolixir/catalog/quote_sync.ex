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

  @skip_reasons [:missing_ticker, :missing_currency]

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
  Synchronously sync all securities. Returns aggregate counts plus the
  per-security result list:
  `{:ok, %{ok: integer, skipped: integer, error: integer, results: list}}`.

  Options:
    * `:adapter_for` – `%{"provider_string" => module}` map, overrides config.
  """
  def sync_all(opts \\ []) do
    adapter_for = Keyword.get(opts, :adapter_for, runtime_adapter_for())
    securities = Catalog.list_securities()

    results = Enum.map(securities, &sync_one(&1, adapter_for, opts))
    counts = Enum.reduce(results, %{ok: 0, skipped: 0, error: 0}, &update_counts/2)

    {:ok, Map.put(counts, :results, results)}
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
        result(security, :skipped, :no_provider_adapter)

      adapter ->
        case safe_fetch(adapter, security, opts) do
          {:ok, rows} when is_list(rows) ->
            persist(security, rows, provider)

          {:error, reason} when reason in @skip_reasons ->
            result(security, :skipped, reason)

          {:error, reason} ->
            Logger.warning(
              "quote fetch failed for security ##{security.id} via #{inspect(adapter)}: #{inspect(reason)}"
            )

            result(security, :error, reason)

          other ->
            Logger.warning(
              "quote fetch returned unexpected value for security ##{security.id} via #{inspect(adapter)}: #{inspect(other)}"
            )

            result(security, :error, {:unexpected_response, other})
        end
    end
  end

  defp safe_fetch(adapter, security, opts) do
    adapter.fetch(security, opts)
  rescue
    exception ->
      {:error, {:adapter_exception, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {:adapter_exit, {kind, reason}}}
  end

  defp persist(security, [], _provider), do: result(security, :ok, nil, 0)

  defp persist(security, rows, provider) do
    case Quotes.upsert_many(
           security.id,
           Enum.map(rows, &Map.put(&1, :source, provider))
         ) do
      {:ok, count} ->
        result(security, :ok, nil, count)

      {:error, reason} ->
        Logger.warning("quote upsert failed for security ##{security.id}: #{inspect(reason)}")
        result(security, :error, {:upsert_failed, reason})
    end
  end

  defp result(security, status, reason, upserted \\ nil) do
    %{
      security_id: security.id,
      provider: security.provider,
      status: status,
      reason: reason,
      upserted: upserted
    }
  end

  defp update_counts(%{status: :ok}, acc), do: Map.update!(acc, :ok, &(&1 + 1))
  defp update_counts(%{status: :skipped}, acc), do: Map.update!(acc, :skipped, &(&1 + 1))
  defp update_counts(%{status: :error}, acc), do: Map.update!(acc, :error, &(&1 + 1))

  defp runtime_adapter_for do
    Application.get_env(:portfolixir, __MODULE__, [])
    |> Keyword.get(:adapter_for, @default_adapter_for)
  end
end
