defmodule Portfolixir.Fx.RateSync do
  @moduledoc """
  Background scheduler + on-demand entry point for exchange-rate sync.

  The GenServer ticks every `interval_ms` (default 12 h) and calls `sync/1`,
  which fetches EUR-hub rates from the configured provider
  (`Portfolixir.Fx.RateSync.Provider`) and upserts them via `Portfolixir.Fx`.

  Hard rule: no real HTTP in tests. The test environment registers
  `Portfolixir.Fx.RateSync.Fake` instead of the ECB adapter.

  The scheduler is opt-in (`enabled?: true` in prod/dev, `false` in tests).
  When enabled it also runs one sync shortly after startup (`startup_delay_ms`),
  so foreign-currency value is available promptly instead of `interval_ms` later,
  followed by `backfill_when_needed/1` (#1120).
  Use `sync_now/0` from the UI, API, or REPL to trigger an immediate sync.

  `backfill/1` (issue #737, Sprint 9 D-1) is the one-shot, on-demand fetch of
  the provider's **historical** series through the same upsert path — it
  fills every past date the provider publishes at once, so a dated
  conversion (a realized gain at its own close date) can find its rate. It
  does not change the rate-availability rule: a date the provider never
  published stays absent, and the consumer keeps excluding and naming it.

  `backfill_when_needed/1` (#1120, D-5 of the Sprint 20 plan, amending
  Sprint 9's D-1 to "on demand, and once by itself when needed") is that
  backfill run only when a booking predates its currency's earliest stored
  rate and no completed run has sought the currency yet
  (`Portfolixir.Fx.HistoryGaps`), under the same single-flight key. It runs
  by itself after the boot sync and after an import's apply
  (`backfill_when_needed_async/0`), in the background and only while the
  scheduler is enabled, as every background fetch is.
  """

  use GenServer
  require Logger

  alias Portfolixir.Catalog.MarketDataBounds
  alias Portfolixir.Fx
  alias Portfolixir.Fx.HistoryGaps
  alias Portfolixir.SingleFlight

  @default_interval :timer.hours(12)
  @default_startup_delay :timer.seconds(5)
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

  @doc """
  Synchronously fetch and persist the provider's **historical** series (the
  one-shot backfill, issue #737).

  Returns `{:ok, %{provider: atom, status: :ok, upserted: integer, scope: :history}}`,
  `{:error, :history_unsupported}` when the provider publishes no history, or
  `{:error, reason}`.

  Options:
    * `:provider` – adapter module, overrides config.
  """
  def backfill(opts \\ []) do
    # One backfill at a time (E25, G04): a second one while it runs is
    # {:error, :backfill_in_progress} and calls no provider.
    case SingleFlight.run(:fx_backfill, fn -> backfill_unlocked(opts) end) do
      {:ok, result} -> result
      {:error, :in_progress} -> {:error, :backfill_in_progress}
    end
  end

  @doc """
  The history backfill **when needed** (#1120, D-5 of the Sprint 20 plan):
  `backfill/1`, run only when a booking in some currency predates that
  currency's earliest stored rate and no completed run has sought that
  currency yet (`Portfolixir.Fx.HistoryGaps.due/0`).

  It holds `backfill/1`'s single-flight key for the whole check, fetch and
  record, so it never runs beside a manual backfill: while either runs, the
  other answers `{:error, :backfill_in_progress}` and asks the provider
  nothing.

  Returns `:not_needed` (nothing due; the provider is not asked),
  `{:ok, result}` (`backfill/1`'s result plus `sought`, the due currencies,
  now recorded so they are not due again), `{:error,
  :history_unsupported}`, `{:error, :backfill_in_progress}`, or `{:error,
  reason}` when the fetch or the store failed: logged by `backfill/1`'s
  path, nothing recorded, so the next trigger tries again. It never raises
  for a provider failure.

  Options: as `backfill/1`.
  """
  @spec backfill_when_needed(keyword()) :: :not_needed | {:ok, map()} | {:error, term()}
  def backfill_when_needed(opts \\ []) do
    provider = Keyword.get(opts, :provider, runtime_provider())
    opts = Keyword.put(opts, :provider, provider)

    if history?(provider) do
      case SingleFlight.run(:fx_backfill, fn -> when_needed_unlocked(opts) end) do
        {:ok, result} -> result
        {:error, :in_progress} -> {:error, :backfill_in_progress}
      end
    else
      {:error, :history_unsupported}
    end
  end

  @doc """
  Starts `backfill_when_needed/1` in a background task, the trigger after an
  import's apply (#1120): the caller never waits for it, and a failure
  never reaches it.

  It is a background fetch like the scheduled sync, so it runs only when
  the scheduler's own switch is on: the `enabled?` this module's
  configuration carries, which `PORTFOLIXIR_BACKGROUND_FETCH=off` sets to
  `false` (config/runtime.exs, config/dev.exs) and the test suite keeps
  `false`. Off, it answers `:disabled` and asks no provider; on,
  `{:ok, pid}`. The provider and the optional `notify` pid (told
  `{#{inspect(__MODULE__)}, :history, result}` when the run ends; the test
  suite's seam) come from the same configuration.
  """
  @spec backfill_when_needed_async() :: {:ok, pid()} | :disabled
  def backfill_when_needed_async do
    config = Application.get_env(:portfolixir, __MODULE__, [])

    if Keyword.get(config, :enabled?, false) do
      provider = Keyword.get(config, :provider, @default_provider)
      notify = Keyword.get(config, :notify)
      Task.start(fn -> history_quietly(provider, notify) end)
    else
      :disabled
    end
  end

  defp when_needed_unlocked(opts) do
    case HistoryGaps.due() do
      due when map_size(due) == 0 ->
        :not_needed

      due ->
        sought = due |> Map.keys() |> Enum.sort()

        case backfill_unlocked(opts) do
          {:ok, result} ->
            :ok = HistoryGaps.record_sought(sought)

            Logger.info(
              "fx history backfill ran by itself for #{Enum.join(sought, ", ")}: " <>
                "#{result.upserted} rate(s) stored"
            )

            {:ok, Map.put(result, :sought, sought)}

          {:error, _reason} = error ->
            error
        end
    end
  end

  defp backfill_unlocked(opts) do
    provider = Keyword.get(opts, :provider, runtime_provider())

    if history?(provider) do
      case safe_fetch_history(provider, opts) do
        {:ok, rows} when is_list(rows) ->
          persist(provider, rows, :history)

        {:error, reason} ->
          Logger.warning("fx history fetch failed via #{inspect(provider)}: #{inspect(reason)}")
          {:error, reason}

        other ->
          Logger.warning("fx history fetch returned unexpected value: #{inspect(other)}")
          {:error, {:unexpected_response, other}}
      end
    else
      {:error, :history_unsupported}
    end
  end

  # function_exported?/3 is false for a module not loaded yet, so the
  # provider is loaded first; otherwise the answer would depend on whether
  # anything had called the adapter before.
  defp history?(provider),
    do: Code.ensure_loaded?(provider) and function_exported?(provider, :fetch_history, 1)

  # -- GenServer callbacks ---------------------------------------------------

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval),
      startup_delay_ms: Keyword.get(opts, :startup_delay_ms, @default_startup_delay),
      enabled?: Keyword.get(opts, :enabled?, false),
      provider: Keyword.get(opts, :provider, @default_provider),
      notify: Keyword.get(opts, :notify)
    }

    # Sync once shortly after boot (issue #435): without this the first tick is
    # interval_ms (12 h) away, so foreign-currency cash is silently uncounted
    # until then. handle_info/2 reschedules subsequent ticks at interval_ms.
    # Disabled (PORTFOLIXIR_BACKGROUND_FETCH=off), there is no boot tick, so
    # no history backfill either (#1120).
    if state.enabled?, do: schedule(:boot_tick, state.startup_delay_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    Task.start(fn -> sync_quietly(state.provider) end)

    if state.enabled?, do: schedule(:tick, state.interval_ms)
    {:noreply, state}
  end

  # The boot sync, then the history backfill when a booking needs it (#1120,
  # D-5), one after the other in one background task.
  def handle_info(:boot_tick, state) do
    Task.start(fn ->
      sync_quietly(state.provider)
      history_quietly(state.provider, state.notify)
    end)

    schedule(:tick, state.interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule(message, after_ms) do
    Process.send_after(self(), message, after_ms)
  end

  defp sync_quietly(provider) do
    sync(provider: provider)
  rescue
    exception ->
      Logger.error("fx rate sync tick crashed: #{Exception.message(exception)}")
  end

  # `backfill_when_needed/1` in a background task: a provider failure is
  # already an error tuple and a warning; anything that raises is logged
  # here, so nothing reaches the import or the boot that started it. The
  # optional `notify` pid is told the result (the test suite's seam).
  defp history_quietly(provider, notify) do
    result =
      try do
        backfill_when_needed(provider: provider)
      rescue
        exception ->
          Logger.error("fx history backfill crashed: #{Exception.message(exception)}")
          {:error, :crashed}
      end

    if is_pid(notify), do: send(notify, {__MODULE__, :history, result})
    result
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

  defp safe_fetch_history(provider, opts) do
    provider.fetch_history(opts)
  rescue
    exception ->
      {:error, {:adapter_exception, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {:adapter_exit, {kind, reason}}}
  end

  defp persist(provider, rows, scope \\ :latest) do
    case safe_upsert(drop_implausible(rows)) do
      {:ok, count} ->
        {:ok, %{provider: provider.id(), status: :ok, upserted: count, scope: scope}}

      {:error, reason} ->
        Logger.warning("fx rate upsert failed: #{inspect(reason)}")
        {:error, {:upsert_failed, reason}}
    end
  end

  # Rows the database refuses are the run's error, answered like an upstream
  # failure (the API's 502), never a crash (F28).
  defp safe_upsert(rows) do
    Fx.upsert_many(rows)
  rescue
    exception ->
      Logger.warning("fx rate persistence failed: #{Exception.message(exception)}")
      {:error, :persist_failed}
  end

  # Whatever a provider returns, an implausible rate (F26) is dropped here, so
  # one bad row never fails the batch.
  defp drop_implausible(rows) do
    {plausible, dropped} =
      Enum.split_with(rows, fn row ->
        is_map(row) and
          MarketDataBounds.plausible?(
            field(row, :date),
            field(row, :rate),
            MarketDataBounds.rate_column()
          )
      end)

    if dropped != [] do
      Logger.warning("fx rate sync dropped #{length(dropped)} implausible provider rate(s)")
    end

    plausible
  end

  defp field(row, key), do: Map.get(row, key, Map.get(row, Atom.to_string(key)))

  defp runtime_provider do
    Application.get_env(:portfolixir, __MODULE__, [])
    |> Keyword.get(:provider, @default_provider)
  end
end
