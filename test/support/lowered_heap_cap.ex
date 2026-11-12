defmodule Portfolixir.LoweredHeapCap do
  @moduledoc """
  The one way a test lowers the heap cap (#1440): for the call that provokes
  the kill only, and returning only once the runtime has logged every kill
  the lowered cap caused.

  The cap is `max_heap_bytes` in the application environment, which every
  capped process reads as its first act (`Portfolixir.HeapCap.cap!/0`), so a
  lowered cap reaches any process that caps itself while it is lowered. And
  the runtime hands a kill's report to its logger asynchronously, after the
  killed process is gone: a test whose `capture_log` closed as soon as the
  page showed the failure let the report reach the console under load, and
  the log-noise check (#927) failed a run with no test failed.

  `run/3` lowers the cap, runs `fun`, restores the cap however `fun` ends,
  and then returns only once every process that took the lowered cap while
  `fun` ran (a return trace of `Portfolixir.HeapCap.max_heap_words/0`, whose
  answer is the cap the process sets) has ended, and the runtime's report of
  each one the cap killed has been logged, so into the caller's capture. A
  process that took it and is still alive, or was killed without a report,
  after `:timeout` (5 s by default) fails the call, named: the lowered cap
  reached a process the test does not end, which would be killed later,
  outside the capture.

  Call it inside the `capture_log` that takes the reports, in a test that is
  not async, since the cap is global.
  """

  import ExUnit.Assertions, only: [flunk: 1]

  alias Portfolixir.HeapCap

  @default_timeout 5_000
  @traced {HeapCap, :max_heap_words, 0}

  defmodule Reports do
    @moduledoc false
    # A :logger handler, for the call only: tells the collector which
    # process the runtime reported killed at the lowered cap.

    @spec log(:logger.log_event(), :logger.handler_config()) :: :ok
    def log(%{meta: %{pid: pid}, msg: {format, [pid, words | _]}}, %{
          config: %{collector: collector, words: words}
        })
        when is_list(format) do
      if :string.find(format, ~c"maximum heap size reached") != :nomatch,
        do: send(collector, {:reported, pid})

      :ok
    end

    def log(_event, _config), do: :ok
  end

  @doc "Runs `fun` under a heap cap of `bytes`, as the moduledoc describes."
  @spec run(pos_integer(), (-> result), keyword()) :: result when result: term()
  def run(bytes, fun, opts \\ []) when is_integer(bytes) and is_function(fun, 0) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    words = div(bytes, :erlang.system_info(:wordsize))
    prior = Application.get_env(:portfolixir, HeapCap, [])
    {collector, session} = watch(words)

    Application.put_env(:portfolixir, HeapCap, Keyword.put(prior, :max_heap_bytes, bytes))

    outcome =
      try do
        {:ok, fun.()}
      catch
        kind, reason -> {:caught, kind, reason, __STACKTRACE__}
      after
        Application.put_env(:portfolixir, HeapCap, prior)
      end

    left = settle(collector, session, timeout)
    unwatch(collector, session)

    case outcome do
      # A failure inside `fun` is the one to report.
      {:caught, kind, reason, stacktrace} ->
        :erlang.raise(kind, reason, stacktrace)

      {:ok, _result} when left != [] ->
        flunk(
          "The lowered heap cap reached processes the call did not end with a " <>
            "logged kill: #{inspect(left)}. Each would be killed, or reported, " <>
            "after the capture."
        )

      {:ok, result} ->
        result
    end
  end

  defp watch(words) do
    collector = spawn(fn -> collect(words, %{}, MapSet.new()) end)
    session = :trace.session_create(__MODULE__, collector, [])
    # A module not loaded yet has no function to trace.
    Code.ensure_loaded!(HeapCap)
    1 = :trace.function(session, @traced, [{:_, [], [{:return_trace}]}], [:local])
    :trace.process(session, :all, true, [:call, :procs])

    :ok =
      :logger.add_handler(Reports, Reports, %{
        level: :all,
        config: %{collector: collector, words: words}
      })

    {collector, session}
  end

  defp unwatch(collector, session) do
    :logger.remove_handler(Reports)
    :trace.session_destroy(session)
    Process.exit(collector, :kill)
  end

  # Every trace message sent before the cap was restored reaches the
  # collector first, so it knows every process that took the lowered cap.
  defp settle(collector, session, timeout) do
    delivered = :trace.delivered(session, :all)

    receive do
      {:trace_delivered, :all, ^delivered} -> :ok
    end

    reply = make_ref()
    send(collector, {:settle, self(), reply, System.monotonic_time(:millisecond) + timeout})

    left =
      receive do
        {^reply, left} -> left
      end

    # The handler that told the collector of a report may run before the
    # capture's own: the proxy answers a system call only once it has
    # handled the report in full, every handler included.
    _state = :sys.get_state(:logger_proxy)
    left
  end

  # `takers`: pid => :alive | {:exited, reason}, for each process that took
  # the lowered cap; `reported`: the pids the runtime reported killed at it.
  defp collect(words, takers, reported) do
    receive do
      {:trace, pid, :return_from, @traced, ^words} ->
        collect(words, Map.put_new(takers, pid, :alive), reported)

      {:trace, pid, :exit, reason} when is_map_key(takers, pid) ->
        collect(words, Map.put(takers, pid, {:exited, reason}), reported)

      {:reported, pid} ->
        collect(words, takers, MapSet.put(reported, pid))

      {:settle, from, reply, deadline} ->
        settle_loop(words, takers, reported, from, reply, deadline)

      _other ->
        collect(words, takers, reported)
    end
  end

  defp settle_loop(words, takers, reported, from, reply, deadline) do
    case unsettled(takers, reported) do
      [] ->
        send(from, {reply, []})

      left ->
        wait = max(deadline - System.monotonic_time(:millisecond), 0)

        receive do
          {:trace, pid, :exit, reason} when is_map_key(takers, pid) ->
            takers = Map.put(takers, pid, {:exited, reason})
            settle_loop(words, takers, reported, from, reply, deadline)

          {:reported, pid} ->
            settle_loop(words, takers, MapSet.put(reported, pid), from, reply, deadline)
        after
          wait -> send(from, {reply, left})
        end
    end
  end

  # A taker still alive, or killed with its report not yet logged. One that
  # ended any other way was not killed by the cap and has no report coming.
  defp unsettled(takers, reported) do
    for {pid, state} <- takers,
        state == :alive or (state == {:exited, :killed} and pid not in reported),
        do: {pid, state}
  end
end
