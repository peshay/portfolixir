defmodule Portfolixir.News.Scheduler do
  @moduledoc """
  The news scheduler (ADR-0056 §5, §14 item 4, B6): a supervised process
  that ticks every minute and fetches every feed that is due, each in its
  own task.

  **Where it runs (B6).** Exactly where the quote sync runs: the
  supervision tree hands it the quote sync's `enabled?` (production;
  development with `PORTFOLIXIR_BACKGROUND_FETCH`; never in tests), so
  there is no second switch to forget. **An enabled feed is the opt-in**:
  with no enabled feed it makes no request.

  **Which feeds are due** (`due?/2`): an enabled feed never fetched, or one
  whose `last_fetch_at` lies its interval ago (the class's default of §5 —
  `regulatory` 10, `issuer` 15, `aggregator` 60, `thematic` 180 minutes —
  unless the feed sets one), and not while its backoff's `retry_at` lies
  ahead.

  **Freshness** (§14 item 4): an item that appears in a feed at time t is
  stored by the first tick after the feed's next due time, so by t + the
  interval + the tick (one minute) + the fetch, inside the promised five
  minutes.

  **Isolation.** Each feed is fetched in its own task under
  `Portfolixir.News.Tasks`, with a time of its own (2 minutes) and under
  the heap cap every request and page process has
  (`Portfolixir.HeapCap`, N-11): a fetch that raises, or that the runtime
  kills past the cap, is recorded on its feed as `fetch_failed`, one that
  outlives its time is killed and recorded as `timeout`, and none of them
  stops another feed's fetch. One run at a time: a tick that finds the
  last run still going skips.

  **Unfiled items** (F5, ADR-0056 amendment of 2026-11-24). After its
  fetches every tick reclusters each scope that holds an assigned item in
  no story (`Portfolixir.News.Stories.recluster_unfiled/1`): an item whose
  story could not be written when it was fetched is filed within a tick,
  whether or not its feed brings anything new. A sweep in which a scope
  failed is logged and tried again by the first tick a quarter of an hour
  later (`:unfiled_retry_ms`), not at every tick.

  **Retention** (§12, N6). The first tick of each server day
  (`Portfolixir.Clock.local_date/1`) also runs the retention
  (`Portfolixir.News.Retention.run/1`), after that tick's fetches and in
  the same task, so it runs exactly where the fetcher runs and never beside
  one of this scheduler's runs. **The day counts as retained once a run
  finished** (F4, ADR-0056 amendment of 2026-11-24): a run that raised, or
  whose task ended (the run's task carries the heap cap, as a fetch's
  does), is logged, stops nothing, and is run again by the first tick an
  hour later (`:retention_retry_ms`), not at every tick and not only the
  next day.

  `run_due/2` and `run_one/2` are the on-demand entries
  (`Portfolixir.News.fetch_due/2`, `fetch_now/2`).
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias Portfolixir.Clock
  alias Portfolixir.HeapCap
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Fetcher
  alias Portfolixir.News.Retention
  alias Portfolixir.News.Stories
  alias Portfolixir.Repo

  @default_tick_ms 60_000
  @task_timeout_ms 120_000
  # How long a failed retention run waits before it is run again.
  @retention_retry_ms 60 * 60_000
  # How long the sweep of unfiled items waits after one in which a scope
  # failed.
  @unfiled_retry_ms 15 * 60_000
  @max_concurrency 8

  @type result :: {:ok, map()} | {:error, String.t()}

  @doc "The time between two ticks: one minute."
  @spec default_tick_ms() :: pos_integer()
  def default_tick_ms, do: @default_tick_ms

  @doc """
  Starts the scheduler. Options: `:enabled?` (default false), `:tick_ms`,
  `:fetch_opts` (passed to every fetch), `:name` (nil for an unnamed one),
  `:retention` (the function of the clock a retention run is, default
  `Portfolixir.News.Retention.run/1`), `:retention_retry_ms` (how long a
  failed run waits, default an hour) and `:unfiled_retry_ms` (how long the
  sweep of unfiled items waits after a scope failed, default a quarter of
  an hour).
  """
  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "Whether `feed` is due at the server's clock `now`; see the moduledoc."
  @spec due?(Feed.t(), DateTime.t()) :: boolean()
  def due?(%Feed{enabled: false}, _now), do: false

  def due?(%Feed{} = feed, %DateTime{} = now) do
    not later?(feed.retry_at, now) and
      not later?(next_fetch_at(feed), now)
  end

  defp next_fetch_at(%Feed{last_fetch_at: nil}), do: nil

  defp next_fetch_at(%Feed{last_fetch_at: at, interval_minutes: minutes}),
    do: DateTime.add(at, minutes, :minute)

  defp later?(nil, _now), do: false
  defp later?(at, now), do: DateTime.compare(at, now) == :gt

  @doc """
  Fetches every feed due at `now`, each in its own task; `[{feed_id,
  result}]` in feed id order. `now` decides which feeds are due; the fetch
  reads the server's clock once its answer arrived. Options go to the fetch
  (`Fetcher.fetch/2`, a test's `:clock` among them), plus `:fetch` (the
  fetch function) and `:timeout_ms` (a task's time).
  """
  @spec run_due(DateTime.t(), keyword()) :: [{pos_integer(), result()}]
  def run_due(%DateTime{} = now, opts \\ []) do
    from(f in Feed, where: f.enabled, order_by: f.id)
    |> Repo.all()
    |> Enum.filter(&due?(&1, now))
    |> run(Keyword.put(opts, :now, now))
  end

  @doc """
  Fetches the enabled feed `feed_id` now, due or not, in its own task.
  `{:error, :not_found}` or `{:error, :disabled}` otherwise.
  """
  @spec run_one(integer(), keyword()) :: result() | {:error, :not_found | :disabled}
  def run_one(feed_id, opts \\ []) when is_integer(feed_id) do
    case Repo.get(Feed, feed_id) do
      nil ->
        {:error, :not_found}

      %Feed{enabled: false} ->
        {:error, :disabled}

      feed ->
        [{_id, result}] = run([feed], Keyword.put_new_lazy(opts, :now, &DateTime.utc_now/0))
        result
    end
  end

  defp run([], _opts), do: []

  defp run(feeds, opts) do
    now = Keyword.fetch!(opts, :now)
    fetch = Keyword.get(opts, :fetch, &Fetcher.fetch/2)
    timeout = Keyword.get(opts, :timeout_ms, @task_timeout_ms)
    # The tick decides which feeds are due and stamps a failure the task
    # could not record; the fetch reads its own clock once the answer arrived
    # (closing act, KNOWN), so the tick is not passed on.
    fetch_opts = Keyword.drop(opts, [:fetch, :timeout_ms, :now])

    Portfolixir.News.Tasks
    |> Task.Supervisor.async_stream_nolink(feeds, &guarded(fetch, &1, fetch_opts),
      timeout: timeout,
      on_timeout: :kill_task,
      max_concurrency: @max_concurrency,
      ordered: true
    )
    |> Enum.zip(feeds)
    |> Enum.map(fn
      {{:ok, {:crashed, message}}, feed} -> {feed.id, failed(feed, now, "fetch_failed", message)}
      {{:ok, result}, feed} -> {feed.id, result}
      {{:exit, :timeout}, feed} -> {feed.id, failed(feed, now, "timeout", "killed")}
      {{:exit, reason}, feed} -> {feed.id, failed(feed, now, "fetch_failed", inspect(reason))}
    end)
  end

  # A raise inside one feed's fetch stays that feed's, and so does what
  # the fetch allocates: the task caps its own heap first (N-11), as a
  # request's process does.
  defp guarded(fetch, feed, opts) do
    HeapCap.cap!()
    fetch.(feed, opts)
  rescue
    exception -> {:crashed, Exception.message(exception)}
  end

  defp failed(feed, now, code, detail) do
    Logger.warning("news feed #{feed.id}: #{code} (#{detail})")
    Fetcher.record_failure(feed, now, code)
    {:error, code}
  end

  # -- the process ---------------------------------------------------------------

  @impl true
  def init(opts) do
    state = %{
      enabled?: Keyword.get(opts, :enabled?, false),
      tick_ms: Keyword.get(opts, :tick_ms, @default_tick_ms),
      fetch_opts: Keyword.get(opts, :fetch_opts, []),
      retention: Keyword.get(opts, :retention, &Retention.run/1),
      retention_retry_ms: Keyword.get(opts, :retention_retry_ms, @retention_retry_ms),
      unfiled_retry_ms: Keyword.get(opts, :unfiled_retry_ms, @unfiled_retry_ms),
      # Monotonic milliseconds before which the sweep is not run again.
      unfiled_retry_at: nil,
      running: nil,
      # The run under way retains this day, or nil when it does not.
      retaining: nil,
      retained_on: nil,
      # Monotonic milliseconds before which a failed run is not run again.
      retention_retry_at: nil
    }

    if state.enabled?, do: schedule_tick(state.tick_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, %{running: nil} = state) do
    fetch_opts = state.fetch_opts
    retention = state.retention
    now = DateTime.utc_now()
    today = Clock.local_date(now)
    retain? = state.retained_on != today and not waiting?(state.retention_retry_at)
    file? = not waiting?(state.unfiled_retry_at)

    task =
      Task.Supervisor.async_nolink(Portfolixir.News.Tasks, fn ->
        HeapCap.cap!()
        results = run_due(now, fetch_opts)
        filed = if(file?, do: file_unfiled(), else: :not_due)
        {results, filed, if(retain?, do: retain(retention, now), else: :not_due)}
      end)

    schedule_tick(state.tick_ms)
    {:noreply, %{state | running: task.ref, retaining: if(retain?, do: today)}}
  end

  # The last run is still going: this tick skips.
  def handle_info(:tick, state) do
    schedule_tick(state.tick_ms)
    {:noreply, state}
  end

  def handle_info({ref, {_results, filed, retention}}, %{running: ref} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | running: nil} |> filed(filed) |> retained(retention)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{running: ref} = state) do
    Logger.warning("news scheduler run ended: #{inspect(reason)}")
    # Which part of the run ended it is not known: both wait.
    {:noreply, %{state | running: nil} |> filed(:failed) |> retained(:failed)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # F5: the sweep reads its own clock, after the tick's fetches, so an item
  # it files enters its scope after every fetch of this tick.
  defp file_unfiled do
    case Stories.recluster_unfiled(DateTime.utc_now()) do
      %{failed: 0} -> :ok
      %{failed: _some} -> :failed
    end
  rescue
    exception ->
      Logger.warning("news unfiled sweep failed: #{Exception.message(exception)}")
      :failed
  end

  defp filed(state, :failed) do
    retry_at = System.monotonic_time(:millisecond) + state.unfiled_retry_ms
    %{state | unfiled_retry_at: retry_at}
  end

  defp filed(state, :ok), do: %{state | unfiled_retry_at: nil}
  defp filed(state, :not_due), do: state

  defp retain(retention, now) do
    retention.(now)
    :ok
  rescue
    exception ->
      Logger.warning("news retention failed: #{Exception.message(exception)}")
      :failed
  end

  # F4: the day is recorded once its run finished. A run that failed, or
  # whose task ended, leaves the day open and waits before the next try.
  defp retained(%{retaining: nil} = state, _retention), do: state

  defp retained(%{retaining: day} = state, :ok),
    do: %{state | retaining: nil, retained_on: day, retention_retry_at: nil}

  defp retained(state, _failed) do
    retry_at = System.monotonic_time(:millisecond) + state.retention_retry_ms
    %{state | retaining: nil, retention_retry_at: retry_at}
  end

  defp waiting?(nil), do: false
  defp waiting?(retry_at), do: System.monotonic_time(:millisecond) < retry_at

  defp schedule_tick(tick_ms), do: Process.send_after(self(), :tick, tick_ms)
end
