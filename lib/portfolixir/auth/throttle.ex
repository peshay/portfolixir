defmodule Portfolixir.Auth.Throttle do
  @moduledoc """
  Per-source lockout for credential checks (#771, ADR-0045 §1), without a
  dependency.

  A `scope` (`:api` for the bearer token, `:ui` for the operator password)
  and a `key` (the source address) count failures in an ETS table owned by
  this process. From `max_failures/0` on, the source is locked for
  `base_lock_seconds/0`, doubling with every further failure up to
  `max_lock_seconds/0`. A success clears the count. Time is injectable
  (`now:` in seconds) so the arithmetic is unit-tested without sleeping.

  The table is public and written by the calling process: a lockout must not
  serialise every request through one GenServer.
  """

  use GenServer

  @table __MODULE__
  @max_failures 10
  @base_lock_seconds 2
  @max_lock_seconds 300
  @sweep_ms 10 * 60 * 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc "Failures before the first lock."
  @spec max_failures() :: pos_integer()
  def max_failures, do: @max_failures

  @doc "The first lock, in seconds; doubles per further failure."
  @spec base_lock_seconds() :: pos_integer()
  def base_lock_seconds, do: @base_lock_seconds

  @doc "The longest lock, in seconds."
  @spec max_lock_seconds() :: pos_integer()
  def max_lock_seconds, do: @max_lock_seconds

  @doc "The throttle key for a source address."
  @spec source_key(:inet.ip_address() | term()) :: String.t()
  def source_key(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  def source_key(other), do: inspect(other)

  @doc "`:ok`, or `{:locked, seconds_remaining}`."
  @spec check(atom(), String.t(), keyword()) :: :ok | {:locked, pos_integer()}
  def check(scope, key, opts \\ []) do
    now = Keyword.get(opts, :now, now())

    case :ets.lookup(@table, {scope, key}) do
      [{_, _count, locked_until, _seen}] when locked_until > now -> {:locked, locked_until - now}
      _ -> :ok
    end
  end

  @doc "Records a failed check for the source and extends its lock past the threshold."
  @spec failure(atom(), String.t(), keyword()) :: :ok
  def failure(scope, key, opts \\ []) do
    now = Keyword.get(opts, :now, now())

    # The count is bumped atomically so concurrent failures never lose one.
    count = :ets.update_counter(@table, {scope, key}, {2, 1}, {{scope, key}, 0, 0, now})
    locked_until = if count >= @max_failures, do: now + lock_seconds(count), else: 0
    :ets.update_element(@table, {scope, key}, [{3, locked_until}, {4, now}])
    :ok
  end

  @doc "Clears the source's failures after a successful check."
  @spec success(atom(), String.t()) :: :ok
  def success(scope, key) do
    :ets.delete(@table, {scope, key})
    :ok
  end

  defp lock_seconds(count) do
    exponent = count - @max_failures
    min(@base_lock_seconds * Integer.pow(2, min(exponent, 30)), @max_lock_seconds)
  end

  defp now, do: System.os_time(:second)

  @impl true
  def init(:ok) do
    :ets.new(@table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    Process.send_after(self(), :sweep, @sweep_ms)
    {:ok, :no_state}
  end

  # Forgets sources whose last failure is older than the longest lock, so the
  # table does not keep every address that ever failed once. Keyed on the last
  # failure, not the lock: a source below the threshold has no lock yet, and
  # forgetting it would hand back its remaining attempts every sweep.
  @impl true
  def handle_info(:sweep, state) do
    cutoff = now() - @max_lock_seconds
    :ets.select_delete(@table, [{{:_, :_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:noreply, state}
  end
end
