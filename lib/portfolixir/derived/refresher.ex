defmodule Portfolixir.Derived.Refresher do
  @moduledoc """
  Re-materializes derived values from the **write that invalidated them**,
  instead of leaving the bill for the next reader
  ([ADR-0039](../../../docs/decisions/0039-durable-derived-values.md),
  amendment of 2026-08-15 §§1-3, issue #710).

  Before this, `Warmup` had two triggers — boot and day rollover — and neither
  was a write. So after any booking the first person to open a page paid the
  recomputation synchronously and watched the "computing" cue. That is the pull
  behaviour the B3.2 gate was opened to remove.

  ## The three rules, and where each lives

  **1. Scheduled by the invalidation.** `Portfolixir.Derived.DataVersion.bump/2`
  announces the bases it bumped here (`notify/1`), and this process
  re-materializes them **through the same request path `Warmup` uses** — the
  `:refresh` function the application wires to `Warmup.warm_basis/1`. There is
  no second computation path that could disagree with a request. A reader
  arriving before the refresh lands is served the superseded value through
  `Portfolixir.Derived.peek/3`, labelled, exactly as §6 already prescribes.

  **2. Coalesced, and this is the load-bearing part.** A naive "recompute on
  every bump" is worse than the pull it replaces: a Portfolio Performance
  import bumps per booking and `BlastRadius` widens most resource types to
  `:all`, so one import would queue thousands of full recomputations.
  Therefore:

  - bumps are collected into a **set of bases** and drained after a quiet
    period, so a burst of writes produces one refresh per basis. The quiet
    timer restarts on each bump — up to `:max_delay_ms` after the first one, so
    an import that writes without pause still gets drained rather than starved;
  - a refresh already running is not duplicated: the drain runs **inside this
    process**, so bumps arriving during it queue in the mailbox, mark their
    bases dirty afterwards, and re-queue exactly once;
  - the queued unit is a basis, never a write, so the work does not grow with
    the size of the import. The set is bounded by the number of portfolios plus
    the global basis, because that is the widest thing a bump can name.

  **3. Never a correctness dependency.** This is an optimisation of *when* work
  happens. `Portfolixir.Derived.fetch/4` keeps its contract — a stale entry is
  recomputed on read — so a failed, slow or disabled refresher costs latency
  and never freshness. Concretely: `notify/1` is a fire-and-forget cast that is
  a no-op when this process is not running, and a refresh that raises is logged
  and skipped, never fatal. It is disabled by the same switch as the rest of
  the layer.

  A refresh triggered by a bump inside a transaction that later rolls back is
  possible and harmless: it re-materializes the state that is actually
  committed, and the rolled-back bump rolls back with its transaction.
  """

  use GenServer

  require Logger

  alias Portfolixir.Derived

  # Long enough that the per-row bumps of an import collapse into one drain,
  # short enough that a single booking is refreshed while the operator is still
  # looking at the confirmation.
  @quiet_ms 500
  @max_delay_ms 10_000

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Announces that `bases` were invalidated. Fire-and-forget: never blocks the
  writing transaction, and a no-op when the refresher is not running (rule 3).
  """
  @spec notify([String.t()]) :: :ok
  def notify(bases) when is_list(bases) do
    if pid = Process.whereis(__MODULE__), do: GenServer.cast(pid, {:notify, bases})
    :ok
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :enabled?, true) and Derived.enabled?() do
      {:ok,
       %{
         dirty: MapSet.new(),
         timer: nil,
         first_dirty_at: nil,
         quiet_ms: Keyword.get(opts, :quiet_ms, @quiet_ms),
         max_delay_ms: Keyword.get(opts, :max_delay_ms, @max_delay_ms),
         refresh: Keyword.fetch!(opts, :refresh)
       }}
    else
      :ignore
    end
  end

  @impl true
  def handle_cast({:notify, bases}, state) do
    now = System.monotonic_time(:millisecond)

    {:noreply,
     %{
       state
       | dirty: Enum.into(bases, state.dirty),
         first_dirty_at: state.first_dirty_at || now
     }
     |> schedule(now)}
  end

  @impl true
  def handle_info(:drain, state) do
    bases = Enum.sort(state.dirty)

    # Drained to empty, so the next round refreshes only what the next writes
    # invalidate. A bump arriving while the refreshes below run waits in the
    # mailbox — a GenServer dispatches messages between callbacks, never
    # during one — so it re-arms the timer afterwards and buys exactly one
    # more round, however many bumps it was.
    state = %{state | dirty: MapSet.new(), timer: nil, first_dirty_at: nil}

    Enum.each(bases, &refresh(&1, state.refresh))
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp schedule(%{timer: nil} = state, _now), do: arm(state)

  defp schedule(state, now) do
    # The quiet timer restarts on each bump, but never past `max_delay_ms` from
    # the first one: a write stream that never pauses must still be drained.
    if now - state.first_dirty_at >= state.max_delay_ms do
      state
    else
      cancel(state.timer)
      arm(state)
    end
  end

  defp arm(state),
    do: %{state | timer: Process.send_after(self(), :drain, state.quiet_ms)}

  defp cancel(timer) do
    unless Process.cancel_timer(timer) do
      receive do
        :drain -> :ok
      after
        0 -> :ok
      end
    end
  end

  defp refresh(basis, refresh) do
    refresh.(basis)
  rescue
    error ->
      Logger.warning("derived refresh skipped basis #{basis}: #{Exception.message(error)}")

      :ok
  end
end
