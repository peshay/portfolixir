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

  Two bounds that per-source counting alone lacks (E25 S1, F04): a source's
  count is kept for `retention_seconds/0` after its last failure, well past the
  longest lock, so waiting for the sweep does not reset its escalation; and a
  scope may carry a rolling ceiling over all sources together
  (`scope_ceiling/1`), so failures spread over many addresses cannot multiply
  the attempts. The UI password has one; the API token, whose length the boot
  check enforces, does not.

  Bounded in count as well as in time (security review 2026-10-12, H03): an
  IPv6 source is keyed by its /64, the table holds at most `max_rows/0`
  rows (past it a new source is not recorded), and a scope may carry a
  rolling ceiling on first failures from sources it does not remember
  (`new_source_ceiling/1`): past it, every such source is told to wait and is
  not recorded. The API token has one.

  The table is public and written by the calling process: a lockout must not
  serialise every request through one GenServer.
  """

  use GenServer

  @table __MODULE__
  @max_failures 10
  @base_lock_seconds 2
  @max_lock_seconds 300
  @retention_seconds 60 * 60
  @sweep_ms 10 * 60 * 1_000

  # Failed checks per scope over a rolling window, counted in one-minute
  # buckets so every write is an atomic counter bump.
  @scope_ceilings %{ui: {100, 60 * 60}}
  @bucket_seconds 60

  # The most rows the table holds.
  @max_rows 50_000
  # First failures from sources the scope does not remember, over a rolling
  # window, in the same one-minute buckets.
  @new_source_ceilings %{api: {1_000, 60 * 60}}

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

  @doc "How long a source's failures are remembered after its last one."
  @spec retention_seconds() :: pos_integer()
  def retention_seconds, do: @retention_seconds

  @doc "The scope-wide rolling ceiling, as `{failures, window_seconds}`, or `nil`."
  @spec scope_ceiling(atom()) :: {pos_integer(), pos_integer()} | nil
  def scope_ceiling(scope), do: Map.get(@scope_ceilings, scope)

  @doc "The most rows the table holds."
  @spec max_rows() :: pos_integer()
  def max_rows, do: @max_rows

  @doc """
  The rolling ceiling on first failures from sources the scope does not
  remember, as `{failures, window_seconds}`, or `nil`.
  """
  @spec new_source_ceiling(atom()) :: {pos_integer(), pos_integer()} | nil
  def new_source_ceiling(scope), do: Map.get(@new_source_ceilings, scope)

  @doc """
  The throttle key for a source address: an IPv4 address as text, an IPv6
  address as the text of its /64 (one client's prefix is one source), an
  IPv4-mapped IPv6 address as its IPv4 text.
  """
  @spec source_key(:inet.ip_address() | term()) :: String.t()
  def source_key({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: source_key({div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)})

  def source_key({a, b, c, d, _, _, _, _}),
    do: {a, b, c, d, 0, 0, 0, 0} |> :inet.ntoa() |> to_string()

  def source_key(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  def source_key(other), do: inspect(other)

  @doc "`:ok`, or `{:locked, seconds_remaining}` for the source or, past its ceiling, the scope."
  @spec check(atom(), String.t(), keyword()) :: :ok | {:locked, pos_integer()}
  def check(scope, key, opts \\ []) do
    now = Keyword.get(opts, :now, now())

    case :ets.lookup(@table, {scope, key}) do
      [{_, _count, locked_until, _seen}] when locked_until > now -> {:locked, locked_until - now}
      [_known] -> check_scope(scope, now)
      [] -> with :ok <- check_new_sources(scope, now), do: check_scope(scope, now)
    end
  end

  @doc """
  Records a failed check for the source and extends its lock past the
  threshold. A source the table does not remember is recorded only below
  `max_rows/0` and the scope's `new_source_ceiling/1`.
  """
  @spec failure(atom(), String.t(), keyword()) :: :ok
  def failure(scope, key, opts \\ []) do
    now = Keyword.get(opts, :now, now())

    if :ets.member(@table, {scope, key}) or record_new_source?(scope, now) do
      # The count is bumped atomically so concurrent failures never lose one.
      count = :ets.update_counter(@table, {scope, key}, {2, 1}, {{scope, key}, 0, 0, now})
      locked_until = if count >= @max_failures, do: now + lock_seconds(count), else: 0
      :ets.update_element(@table, {scope, key}, [{3, locked_until}, {4, now}])
    end

    count_for_scope(scope, now)
  end

  @doc "Clears the source's failures after a successful check."
  @spec success(atom(), String.t()) :: :ok
  def success(scope, key) do
    :ets.delete(@table, {scope, key})
    :ok
  end

  defp count_for_scope(scope, now) do
    if scope_ceiling(scope), do: bump_bucket(scope, :scope_failures, now)
    :ok
  end

  # A new source is recorded while the table has room and the scope's
  # first-failure ceiling is not reached; its first failure is then counted.
  # The ceiling buckets count towards the room; they are a bounded handful.
  defp record_new_source?(scope, now) do
    cond do
      :ets.info(@table, :size) >= @max_rows -> false
      new_source_ceiling(scope) == nil -> true
      check_new_sources(scope, now) == :ok -> bump_bucket(scope, :new_sources, now) > 0
      true -> false
    end
  end

  defp bump_bucket(scope, tag, now) do
    bucket = div(now, @bucket_seconds)
    key = {scope, {tag, bucket}}
    # The fourth field is the bucket's start, so the sweep ages it like a source.
    :ets.update_counter(@table, key, {2, 1}, {key, 0, 0, bucket * @bucket_seconds})
  end

  # Past the ceiling every source waits until enough failures have aged out of
  # the window for the rest to sit below it again.
  defp check_scope(scope, now) do
    case scope_ceiling(scope) do
      nil ->
        :ok

      {ceiling, window} ->
        check_ceiling({scope, :scope_failures}, now, ceiling, div(window, @bucket_seconds))
    end
  end

  # Past the first-failure ceiling every source the scope does not remember
  # waits the same way; the sources it remembers keep their own counts.
  defp check_new_sources(scope, now) do
    case new_source_ceiling(scope) do
      nil ->
        :ok

      {ceiling, window} ->
        check_ceiling({scope, :new_sources}, now, ceiling, div(window, @bucket_seconds))
    end
  end

  # The window's buckets are read by their keys, oldest first: a bounded number
  # of hash lookups, never a scan of every source the table remembers.
  defp check_ceiling({scope, tag}, now, ceiling, window_buckets) do
    current = div(now, @bucket_seconds)

    buckets =
      for bucket <- (current - window_buckets + 1)..current//1,
          {_key, count, _, _} <- :ets.lookup(@table, {scope, {tag, bucket}}),
          do: {bucket, count}

    total = buckets |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total < ceiling,
      do: :ok,
      else: {:locked, max(unlocks_at(buckets, total, ceiling, window_buckets) - now, 1)}
  end

  # Oldest bucket first: the lock ends when the bucket whose expiry brings the
  # count below the ceiling leaves the window.
  defp unlocks_at([{bucket, count} | older], left, ceiling, window_buckets) do
    if left - count < ceiling or older == [],
      do: (bucket + window_buckets) * @bucket_seconds,
      else: unlocks_at(older, left - count, ceiling, window_buckets)
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

  # Forgets sources whose last failure is older than the retention, so the
  # table does not keep every address that ever failed once. Keyed on the last
  # failure, not the lock: a source below the threshold has no lock yet, and
  # forgetting it would hand back its remaining attempts every sweep. The
  # retention is well past the longest lock (F04), so a source that waits out
  # its lock is still escalated when it fails again.
  @impl true
  def handle_info(:sweep, state) do
    cutoff = now() - @retention_seconds
    :ets.select_delete(@table, [{{:_, :_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:noreply, state}
  end
end
