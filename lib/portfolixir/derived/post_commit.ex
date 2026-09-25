defmodule Portfolixir.Derived.PostCommit do
  @moduledoc """
  The post-commit bump (E25 S6, F47).

  A basis's data version is the highest event id recorded for it
  (`Portfolixir.Derived.DataVersion`), and a writer takes its event ids inside
  its own transaction — before it commits. Ids are therefore not
  commit-ordered: writer A takes a lower id, writer B a higher one and commits
  first, a reader computes a value from B's data and files it under B's
  version, then A commits. The version is still B's, so the value computed
  without A's data stays current until some later write.

  Every bump made inside a transaction marks its events `pending`. `settle/1`
  takes the pending events that have become visible — visible means
  committed; an in-flight writer's rows are not, and wait for a later settle —
  clears their mark and bumps each of their bases once more with a fresh id,
  taken now, after those commits. The version then passes every id taken
  before them, and the value read in between is superseded.

  This process runs `settle/1` shortly after it is told a pending bump
  happened (`notify/0`, which `DataVersion` calls, fire-and-forget), on a
  fixed interval for writers whose transaction outlasts that delay, and once
  at start, so a restart between a commit and its second bump loses nothing:
  the mark lives in the table, not here. It is an optimisation of *when*, like
  the refresher, and never a condition for a write: a failed settle is logged
  and retried on the next tick. Disabled with the rest of the derived layer.
  """

  use GenServer

  require Logger

  alias Portfolixir.Derived
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Repo

  @settle_delay_ms 100
  @interval_ms 5_000

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Announces that a bump inside a transaction marked events pending.
  Fire-and-forget, and a no-op when this process is not running.
  """
  @spec notify() :: :ok
  def notify do
    if pid = Process.whereis(__MODULE__), do: send(pid, :notified)
    :ok
  end

  @doc """
  Settles every committed pending event through
  `DataVersion.settle_pending/1`: clears the mark and bumps each basis once
  more, in one statement, outside any writer's transaction. Returns the bases
  bumped.
  """
  @spec settle(Ecto.Repo.t()) :: {:ok, [String.t()]}
  def settle(repo \\ Repo), do: {:ok, DataVersion.settle_pending(repo)}

  @impl true
  def init(opts) do
    if Keyword.get(opts, :enabled?, true) and Derived.enabled?() do
      interval = Keyword.get(opts, :interval_ms, @interval_ms)
      send(self(), :tick)
      delay = Keyword.get(opts, :settle_delay_ms, @settle_delay_ms)
      {:ok, %{interval: interval, delay: delay, scheduled?: false}}
    else
      :ignore
    end
  end

  # A burst of bumps (an import books row by row) schedules one settle.
  @impl true
  def handle_info(:notified, %{scheduled?: true} = state), do: {:noreply, state}

  def handle_info(:notified, state) do
    Process.send_after(self(), :settle, state.delay)
    {:noreply, %{state | scheduled?: true}}
  end

  def handle_info(:settle, state) do
    safe_settle()
    {:noreply, %{state | scheduled?: false}}
  end

  def handle_info(:tick, state) do
    safe_settle()
    Process.send_after(self(), :tick, state.interval)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp safe_settle do
    settle()
  rescue
    error ->
      Logger.warning("post-commit bump deferred: #{Exception.message(error)}")
      :ok
  end
end
