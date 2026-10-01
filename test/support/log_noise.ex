defmodule Portfolixir.LogNoise do
  @moduledoc """
  Fails a test run whose console log carries a warning or an error no test
  captured (#927).

  A full run used to pass with its log full of stack traces: LiveViews and
  tasks that outlived their test, and warnings tests provoke on purpose but
  did not capture. That noise sits in the log window CI keeps (#654, #682)
  and hides a real failure in it (#653).

  **What counts.** While any `ExUnit.CaptureLog` capture is active, ExUnit
  removes the console handler (`:default`) and afterwards adds it back with
  the configuration it had, filters included. A filter on that handler
  therefore sees exactly the events the console prints, and never one a test
  captured. Every event at `:warning` or above that reaches it is recorded,
  together with the database tests that were running or had just finished
  (`track/1`, called by the sandbox setup), since a process that outlives its
  test logs after the test is gone.

  **What happens then.** After the suite, if any event was recorded, the
  events are listed with those tests and the run exits non-zero the way
  `mix test` itself marks failed tests (an at-exit `{:shutdown, 1}`), so the
  coverage report is still written first.

  **What it cannot see.** A capture is global: an uncaptured event logged
  while another async test captures goes into that capture, not to the
  console. The check can therefore miss an event, but it never reports one
  the console did not print.

  An expected warning is captured around exactly the call that provokes it,
  and the test asserts on the captured message. Raising the log level or a
  blanket capture would silence real failures with the noise.
  """

  @table __MODULE__
  @tests __MODULE__.Tests
  @kept 50
  @levels [:emergency, :alert, :critical, :error, :warning]
  # A test counts as "around" an event while it runs and this long after.
  @after_ms 2_000

  @doc "Attaches the filter to the console handler and the verdict to the end of the suite."
  @spec install() :: :ok
  def install do
    :ets.new(@table, [:named_table, :public, :ordered_set, write_concurrency: true])
    :ets.new(@tests, [:named_table, :public, :set, write_concurrency: true])
    :ok = attach(:default, @table)
    ExUnit.after_suite(fn _result -> verdict(@table) end)
    :ok
  end

  @doc "Attaches the recording filter to `handler`, recording into `table`."
  @spec attach(:logger.handler_id(), :ets.table()) :: :ok | {:error, term()}
  def attach(handler, table),
    do: :logger.add_handler_filter(handler, __MODULE__, {&__MODULE__.record/2, table})

  @doc """
  Notes the test running in the calling process (its setup's `tags`), until
  its `on_exit` callbacks run, so an event can name the tests around it. A
  no-op when the check is not installed.
  """
  @spec track(map()) :: :ok
  def track(%{module: module, test: test}) do
    pid = self()
    :ets.insert(@tests, {pid, "#{inspect(module)}: #{test}", now(), nil})
    ExUnit.Callbacks.on_exit(fn -> :ets.update_element(@tests, pid, {4, now()}) end)
    :ok
  rescue
    ArgumentError -> :ok
  end

  def track(_tags), do: :ok

  @doc """
  The handler filter: records a `:warning`-or-above event into `table`, with
  the tracked tests around it, and never changes what the handler does with
  the event.
  """
  @spec record(:logger.log_event(), :ets.table()) :: :ignore
  def record(%{level: level} = event, table) when level in @levels do
    count = :ets.update_counter(table, :count, 1, {:count, 0})
    if count <= @kept, do: :ets.insert(table, {count, event, around(now())})
    :ignore
  rescue
    # A filter that raises is removed by :logger; the table being gone
    # (the run is over) is no reason to lose the console line.
    ArgumentError -> :ignore
  end

  def record(_event, _table), do: :ignore

  @doc """
  The events recorded in `table`: `{count, [{event, tests_around}]}`, at most
  #{@kept} kept.
  """
  @spec recorded(:ets.table()) :: {non_neg_integer(), [{:logger.log_event(), [String.t()]}]}
  def recorded(table) do
    count =
      case :ets.lookup(table, :count) do
        [{:count, count}] -> count
        [] -> 0
      end

    events =
      for {key, event, around} <- :ets.tab2list(table), is_integer(key), do: {event, around}

    {count, events}
  end

  @doc "The report for `count` recorded events, listing the first of them."
  @spec report(non_neg_integer(), [{:logger.log_event(), [String.t()]}]) :: String.t()
  def report(count, events) do
    formatter = Logger.Formatter.new(format: "[$level] $message", colors: [enabled: false])

    entries =
      Enum.map(events, fn {event, around} ->
        message =
          event
          |> formatter_format(formatter)
          |> String.split("\n", trim: true)
          |> Enum.take(3)
          |> Enum.map_join("\n", &("    " <> String.slice(&1, 0, 200)))

        message <> "\n      around: " <> around_text(around)
      end)

    """

    Log noise (#927): #{count} warning or error event(s) reached the console log \
    without a test capturing them, so the run fails. Make the process that logs \
    finish inside its test, or capture the log around exactly the call that \
    provokes an expected warning and assert on it. The first #{length(events)}, \
    each with the database tests running or just finished when it was logged:

    #{Enum.join(entries, "\n\n")}
    """
  end

  defp around(at) do
    for {_pid, name, _started, ended} <- :ets.tab2list(@tests),
        ended == nil or at - ended <= @after_ms,
        do: name
  rescue
    ArgumentError -> []
  end

  defp around_text([]), do: "(no database test)"
  defp around_text(names), do: names |> Enum.sort() |> Enum.join("; ")

  defp now, do: System.monotonic_time(:millisecond)

  defp formatter_format(event, {module, config}),
    do: event |> module.format(config) |> IO.chardata_to_string()

  defp verdict(table) do
    case recorded(table) do
      {0, _events} ->
        :ok

      {count, events} ->
        IO.puts(:stderr, report(count, events))
        System.at_exit(fn _status -> exit({:shutdown, 1}) end)
    end
  end
end
