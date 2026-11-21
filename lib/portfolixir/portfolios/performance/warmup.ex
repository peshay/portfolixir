defmodule Portfolixir.Portfolios.Performance.Warmup do
  @moduledoc """
  Warms the performance memo at boot and on each day rollover (ADR-0032 §5).

  The derived-value layer (`Portfolixir.Derived`, ADR-0039) removes the
  repeat wait; this removes the first wait after a restart, so the first page
  of the day opens warm — and for the durable lifetime it re-materializes the
  operative entries after any invalidating write landed while the app was
  down.

  Rules from the ADR, all load-bearing:

  - it runs **after** the supervision tree is up and never blocks it — the
    work happens in `handle_continue`, and every scope is warmed inside a
    `try/rescue`, so a failing portfolio cannot take the process (or the app)
    down with it;
  - it warms **through the same API a request uses** (`Performance.analysis/2`)
    — there is no second computation path that could disagree with a request;
  - it is **bounded**: every portfolio at the `:unscoped` scope plus the
    default view where one is set — the scopes the dashboard and Wealth page
    actually open. Periods cost nothing (`summarise/2` re-chains);
  - it is disabled by the **same switch** as the derived layer, so "off" is
    one testable state, not two;
  - each scope's walk runs **under the heap cap** a request runs under, in a
    supervised worker of its own (`Portfolixir.HeapCap.run/1`, K08): a walk
    grown past the cap is killed and logged, the scope is skipped, and this
    process goes on. `Portfolixir.Derived.Refresher` walks through
    `warm_basis/1`, so its walks run the same way.

  Day rollover: `today` is part of the memo key, so yesterday's entries simply
  stop matching at midnight. This process re-warms shortly after local
  midnight so the first visit of the new day is warm too.

  ## The default period (I34 step 2, Sprint 31 P1, plan D-12)

  The full walks re-chain to every period for free, but the two reads a
  screen waits on beside them do not: the stacked chart's bands and the
  contribution table under it each run a windowed walk of their own per
  period (ADR-0051 §5). After every warm above — boot, rollover, and the
  refresher's re-warm of the global basis after a write — this process
  therefore also warms **the default period's** (`"1y"`) bands at
  „Kategorien €“ (the value series' default, and the axis „ab 0“ reads) and
  its contribution table, for the Everything scope and for every view, in
  the first portfolio's base currency: the reads a screen opens with,
  through the same functions a request calls (`Bands.for_view/2`,
  `Contribution.for_view/2`), so a warmed entry is the entry the request
  would have stored. Only those two per scope: M6 measured one scope warmed
  for every period and request at 29 MiB of the memo's 128, the two at
  about 0.7 MiB.

  It never stands between a request and its figure:

  - it runs in a task of its own, at low priority, each scope's reads in a
    worker under the heap cap (`HeapCap.run/1`, K08); a request never waits
    for it, and one arriving first computes and stores the entry itself;
  - it is **cancellable**: an ask while a warm runs cancels that warm after
    its current scope — a walk is never killed mid-query, as
    `PortfolixirWeb.CappedAsync` keeps none — and starts one fresh warm
    after it, so a burst of writes never runs two warms at once;
  - it is **bounded by the memo's budget**: it stops before a scope once the
    memo holds half its entries or bytes, so warming never empties the
    table a request filled (`Derived.memo_below_half_budget?/0`);
  - it is off with the derived layer, as the rest of this module is.

  Each warm ends with a `#{inspect([:portfolixir, :performance, :warmup, :default_period])}`
  telemetry event: `duration_ms`, and the `outcome` (`:done`, `:cancelled`
  or `:over_budget`) with the number of `scopes` read.
  """

  use GenServer

  require Logger

  alias Portfolixir.Buckets
  alias Portfolixir.Derived
  alias Portfolixir.HeapCap
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Bands
  alias Portfolixir.Portfolios.Performance.Contribution
  alias Portfolixir.Settings

  # A minute past local midnight: comfortably on the new day without assuming
  # anything about clock precision at the boundary.
  @rollover_slack_ms 60_000

  # The period every screen opens with (`PortfolixirWeb.PortfolioLive`'s
  # default, the dashboard's), and the event each of its warms ends with.
  @default_period "1y"
  @default_period_event [:portfolixir, :performance, :warmup, :default_period]
  # Under the 5 s a supervisor gives a worker to shut down.
  @terminate_wait_ms 4_000

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Warms every portfolio's unscoped analysis plus the default view's, through
  the request path. Returns `:ok` always — a scope that raises is logged and
  skipped, never fatal (§5: a failing warm-up must not prevent serving).
  """
  @spec warm() :: :ok
  def warm do
    if Derived.enabled?() do
      default_view_id = default_view_id()

      Enum.each(Portfolios.list_portfolios(), &warm_portfolio(&1.id, default_view_id))
      warm_global(default_view_id)
      warm_default_period()
    end

    :ok
  end

  @doc """
  Asks this process to warm the default period's bands and contribution
  table for every scope a screen opens with (see the moduledoc). Returns at
  once: the warm runs in the background, and an ask while one runs cancels
  it after its current scope and starts a fresh one. A no-op when the
  process is not running (the derived layer off, the test default).
  """
  @spec warm_default_period() :: :ok
  def warm_default_period do
    if pid = Process.whereis(__MODULE__), do: GenServer.cast(pid, :warm_default_period)
    :ok
  end

  @doc """
  Warms the operative scopes of **one** data-version basis, through the same
  request path `warm/0` uses.

  This is what `Portfolixir.Derived.Refresher` calls when a write invalidates a
  basis (ADR-0039 amendment §1, issue #710): the refresher schedules, this
  module stays the single place that knows which scopes are operative, and
  there is still no second computation path. An unrecognised basis is a no-op —
  a basis naming something this module cannot warm is not an error, it simply
  has nothing here to re-materialize.
  """
  @spec warm_basis(String.t()) :: :ok
  def warm_basis(basis) when is_binary(basis) do
    if Derived.enabled?(), do: do_warm_basis(basis)
    :ok
  end

  defp do_warm_basis("global") do
    warm_global(default_view_id())
    # Every bump bumps the global basis the default period's entries are
    # kept under, so its re-warm is the one that re-warms them.
    warm_default_period()
  end

  defp do_warm_basis("portfolio:" <> portfolio_id) do
    case Integer.parse(portfolio_id) do
      {id, ""} -> warm_portfolio(id, default_view_id())
      _not_an_id -> :ok
    end
  end

  defp do_warm_basis(_other), do: :ok

  defp warm_portfolio(portfolio_id, default_view_id) do
    warm_scope(portfolio_id, nil)
    if default_view_id, do: warm_scope(portfolio_id, default_view_id)
    :ok
  end

  # The cross-portfolio view walk (#577) is what the Wealth page and the
  # dashboard card open: the Everything scope plus the default view, in the
  # base currency those surfaces request (the first portfolio's).
  defp warm_global(default_view_id) do
    warm_view_scope(nil)
    if default_view_id, do: warm_view_scope(default_view_id)
    :ok
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :enabled?, true) and Derived.enabled?() do
      # A shutdown reaches `terminate/2`, which lets a running default
      # period warm end its current read rather than leave it running.
      Process.flag(:trap_exit, true)

      {:ok,
       %{
         period_task: nil,
         period_pending: false,
         period_reads: Keyword.get(opts, :period_reads, &default_period_reads/2)
       }, {:continue, :warm}}
    else
      :ignore
    end
  end

  @impl true
  def handle_continue(:warm, state) do
    warm()
    schedule_rollover()
    {:noreply, state}
  end

  @impl true
  def handle_cast(:warm_default_period, %{period_task: nil} = state),
    do: {:noreply, start_period_warm(state)}

  # One warm at a time: the running one is told to stop after its current
  # scope, and the fresh one starts when it has answered.
  def handle_cast(:warm_default_period, %{period_task: task} = state) do
    send(task.pid, :cancel)
    {:noreply, %{state | period_pending: true}}
  end

  @impl true
  def handle_info(:rollover, state) do
    warm()
    schedule_rollover()
    {:noreply, state}
  end

  def handle_info({ref, _outcome}, %{period_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, period_warm_ended(state)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{period_task: %Task{ref: ref}} = state) do
    skipped("the default period", exited(reason))
    {:noreply, period_warm_ended(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # A warm running at shutdown stops after its current read, never in the
  # middle of a query; one that does not answer within the shutdown's
  # margin is stopped.
  @impl true
  def terminate(_reason, %{period_task: %Task{} = task}) do
    send(task.pid, :cancel)
    Task.yield(task, @terminate_wait_ms) || Task.shutdown(task, :brutal_kill)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp period_warm_ended(%{period_pending: true} = state),
    do: start_period_warm(%{state | period_task: nil, period_pending: false})

  defp period_warm_ended(state), do: %{state | period_task: nil}

  defp start_period_warm(state) do
    reads = state.period_reads
    owner = self()

    task =
      Task.Supervisor.async_nolink(Portfolixir.CappedTasks, fn -> warm_period(reads, owner) end)

    %{state | period_task: task}
  end

  # The task's body, unlinked from this process so a failure is its own. It
  # watches this process and traps exits, so this process going away, or a
  # shutdown, reaches it as a message: between reads `go_on?/1` exits, and
  # inside a read `HeapCap.run/1` stops the worker on a shutdown.
  defp warm_period(reads, owner) do
    Process.flag(:trap_exit, true)
    Process.flag(:priority, :low)
    owner_watch = Process.monitor(owner)
    started = System.monotonic_time(:millisecond)
    {outcome, scopes} = warm_period_scopes(reads, owner_watch, period_scopes())

    :telemetry.execute(
      @default_period_event,
      %{duration_ms: System.monotonic_time(:millisecond) - started},
      %{outcome: outcome, scopes: scopes}
    )

    outcome
  end

  defp warm_period_scopes(reads, owner_watch, {base_currency, view_ids}) do
    Enum.reduce_while(view_ids, {:done, 0}, fn view_id, {:done, read} ->
      cond do
        not go_on?(owner_watch) -> {:halt, {:cancelled, read}}
        not Derived.memo_below_half_budget?() -> {:halt, {:over_budget, read}}
        true -> {:cont, {:done, read + warm_period_scope(reads, view_id, base_currency)}}
      end
    end)
  end

  # The scopes a screen opens with: Everything and every view, in the base
  # currency Wealth and the dashboard read them in (the first portfolio's).
  defp period_scopes do
    case Portfolios.first_portfolio() do
      %{base_currency_code: base_currency} ->
        {base_currency, [nil | Enum.map(Buckets.list_views(), & &1.id)]}

      _no_portfolio ->
        {nil, []}
    end
  end

  defp go_on?(owner_watch) do
    receive do
      :cancel -> false
      {:EXIT, _from, reason} -> exit(reason)
      {:DOWN, ^owner_watch, :process, _owner, _reason} -> exit(:shutdown)
    after
      0 -> true
    end
  end

  defp warm_period_scope(reads, view_id, base_currency) do
    HeapCap.run(fn ->
      Process.flag(:priority, :low)
      reads.(view_id, base_currency)
    end)

    1
  rescue
    error ->
      skipped("the default period of view scope #{inspect(view_id)}", Exception.message(error))
      1
  catch
    :exit, reason ->
      shut_down_on(reason)
      skipped("the default period of view scope #{inspect(view_id)}", exited(reason))
      1
  end

  # What a screen opens with, read as it reads it: the stack at „Kategorien
  # €“ (`PortfolixirWeb.PortfolioLive`'s `start_bands/1` and
  # `start_stack_axis/1` send no sort, scale, filter or tree by default) and
  # the table.
  defp default_period_reads(view_id, base_currency) do
    {:ok, _table} =
      Contribution.for_view(view_id, period: @default_period, base_currency: base_currency)

    {:ok, _bands} =
      Bands.for_view(view_id,
        period: @default_period,
        base_currency: base_currency,
        level: :category
      )

    :ok
  end

  defp warm_scope(portfolio_id, view_id) do
    HeapCap.run(fn -> Performance.analysis(portfolio_id, view: view_id) end)
  rescue
    error ->
      skipped("portfolio #{portfolio_id} (view #{inspect(view_id)})", Exception.message(error))
  catch
    :exit, reason ->
      shut_down_on(reason)
      skipped("portfolio #{portfolio_id} (view #{inspect(view_id)})", exited(reason))
  end

  defp warm_view_scope(view_id) do
    case Portfolios.first_portfolio() do
      %{base_currency_code: base_currency} ->
        HeapCap.run(fn -> Performance.view_analysis(view_id, base_currency: base_currency) end)

      _no_portfolio ->
        :ok
    end
  rescue
    error -> skipped("view scope #{inspect(view_id)}", Exception.message(error))
  catch
    :exit, reason ->
      shut_down_on(reason)
      skipped("view scope #{inspect(view_id)}", exited(reason))
  end

  # This process and the default period's task trap exits, so a shutdown
  # arriving during a walk reaches `HeapCap.run/1`, which stops the worker
  # and exits with the shutdown's reason: that exit goes on, never skipped
  # as a failed scope.
  defp shut_down_on(:shutdown), do: exit(:shutdown)
  defp shut_down_on({:shutdown, _detail} = reason), do: exit(reason)

  defp shut_down_on(_reason), do: :ok

  defp skipped(scope, why) do
    Logger.warning("performance warm-up skipped #{scope}: #{why}")
    :ok
  end

  # A walk killed past the heap cap, or one that exited otherwise.
  defp exited(:killed), do: "its walk was killed at the heap cap"
  defp exited(reason), do: "its walk exited (#{inspect(reason, limit: 5)})"

  defp default_view_id do
    Settings.default_view_id() && Buckets.get_view(Settings.default_view_id()) &&
      Settings.default_view_id()
  rescue
    _error -> nil
  end

  defp schedule_rollover do
    Process.send_after(self(), :rollover, ms_until_next_local_day())
  end

  defp ms_until_next_local_day do
    {_date, {hours, minutes, seconds}} = :calendar.local_time()
    elapsed_ms = ((hours * 60 + minutes) * 60 + seconds) * 1000
    max(:timer.hours(24) - elapsed_ms + @rollover_slack_ms, @rollover_slack_ms)
  end
end
