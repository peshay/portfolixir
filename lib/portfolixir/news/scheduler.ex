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
  `Portfolixir.News.Tasks`, with a time of its own (2 minutes): a fetch
  that raises is recorded on its feed as `fetch_failed`, one that outlives
  its time is killed and recorded as `timeout`, and neither stops another
  feed's fetch. One run at a time: a tick that finds the last run still
  going skips.

  **Retention** (§12, N6). The first tick of each server day
  (`Portfolixir.Clock.local_date/1`) also runs the retention
  (`Portfolixir.News.Retention.run/1`), after that tick's fetches and in
  the same task, so it runs exactly where the fetcher runs and never beside
  one of this scheduler's runs. A retention that raises is logged and
  stops nothing; the next server day runs it again.

  `run_due/2` and `run_one/2` are the on-demand entries
  (`Portfolixir.News.fetch_due/2`, `fetch_now/2`).
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias Portfolixir.Clock
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Fetcher
  alias Portfolixir.News.Retention
  alias Portfolixir.Repo

  @default_tick_ms 60_000
  @task_timeout_ms 120_000
  @max_concurrency 8

  @type result :: {:ok, map()} | {:error, String.t()}

  @doc "The time between two ticks: one minute."
  @spec default_tick_ms() :: pos_integer()
  def default_tick_ms, do: @default_tick_ms

  @doc """
  Starts the scheduler. Options: `:enabled?` (default false), `:tick_ms`,
  `:fetch_opts` (passed to every fetch), `:name` (nil for an unnamed one).
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

  # A raise inside one feed's fetch stays that feed's.
  defp guarded(fetch, feed, opts) do
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
      running: nil,
      retained_on: nil
    }

    if state.enabled?, do: schedule_tick(state.tick_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, %{running: nil} = state) do
    fetch_opts = state.fetch_opts
    now = DateTime.utc_now()
    today = Clock.local_date(now)
    retain? = state.retained_on != today

    task =
      Task.Supervisor.async_nolink(Portfolixir.News.Tasks, fn ->
        results = run_due(now, fetch_opts)
        if retain?, do: retain(now)
        results
      end)

    schedule_tick(state.tick_ms)
    {:noreply, %{state | running: task.ref, retained_on: today}}
  end

  # The last run is still going: this tick skips.
  def handle_info(:tick, state) do
    schedule_tick(state.tick_ms)
    {:noreply, state}
  end

  def handle_info({ref, _results}, %{running: ref} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | running: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{running: ref} = state) do
    Logger.warning("news scheduler run ended: #{inspect(reason)}")
    {:noreply, %{state | running: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp retain(now) do
    Retention.run(now)
  rescue
    exception -> Logger.warning("news retention failed: #{Exception.message(exception)}")
  end

  defp schedule_tick(tick_ms), do: Process.send_after(self(), :tick, tick_ms)
end
