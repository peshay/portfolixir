defmodule Portfolixir.Invariants.WebTasksCappedTest do
  use ExUnit.Case, async: true

  # User story (#941, E25 S4's G05 follow-up):
  # As the operator whose pages hand their heaviest reads and writes to
  # background tasks,
  # I want every task the web layer starts to run under the heap cap its page
  # runs under, and a new one unable to start any other way,
  # so that one runaway load fails alone instead of taking the node's memory,
  # whichever process it runs in.
  #
  # Acceptance criteria:
  # - No module under lib/portfolixir_web/ starts a process itself:
  #   LiveView's start_async/assign_async/stream_async, Task's and
  #   Task.Supervisor's starts and the spawn family are called only inside
  #   `PortfolixirWeb.CappedAsync`, whose functions cap the task's heap as
  #   its first act.
  # - The scan sees the call sites it polices (the pages' CappedAsync calls),
  #   and catches a synthetic module that starts tasks directly, so a clean
  #   tree cannot pass vacuously.
  @helper "lib/portfolixir_web/capped_async.ex"

  @live_starts ~w(start_async assign_async stream_async)a
  @task_starts ~w(start start_link async async_nolink async_stream async_stream_nolink start_child)a
  @spawns ~w(spawn spawn_link spawn_monitor spawn_opt)a

  test "no task in the web layer starts past the capped helper" do
    sources =
      for path <- Path.wildcard("lib/portfolixir_web/**/*.ex"), path != @helper do
        {path, File.read!(path)}
      end

    offenders = Enum.flat_map(sources, fn {path, source} -> uncapped_starts(source, path) end)

    assert offenders == [],
           "Tasks started past PortfolixirWeb.CappedAsync, which caps their heap (#941):\n" <>
             Enum.join(offenders, "\n")

    helper_calls =
      Enum.sum(
        for {_path, source} <- sources,
            do:
              length(
                Regex.scan(
                  ~r/CappedAsync\.(start_async|start_latest|start|start_child)\(/,
                  source
                )
              )
      )

    assert helper_calls >= 15, "the scan saw #{helper_calls} capped starts; the pages have more"
  end

  test "a synthetic module that starts tasks itself is caught" do
    source = """
    defmodule PortfolixirWeb.SyntheticLive do
      def a(socket), do: start_async(socket, :a, fn -> :a end)
      def b(socket), do: Phoenix.LiveView.assign_async(socket, :b, fn -> {:ok, %{b: 1}} end)
      def c, do: Task.start(fn -> :c end)
      def d, do: Task.Supervisor.start_child(SomeSupervisor, fn -> :d end)
      def e, do: spawn(fn -> :e end)
      def f, do: Process.spawn(fn -> :f end, [])
      def ok(socket), do: CappedAsync.start_async(socket, :ok, fn -> :ok end)
      def ok_too, do: CappedAsync.start(fn -> :ok end)
    end
    """

    offenders = uncapped_starts(source, "synthetic.ex")

    assert length(offenders) == 6, Enum.join(offenders, "\n")
    refute Enum.any?(offenders, &(&1 =~ "CappedAsync"))
  end

  defp uncapped_starts(source, path) do
    {_ast, offenders} =
      source
      |> Code.string_to_quoted!(columns: false)
      |> Macro.prewalk([], fn node, acc -> {node, acc ++ offender(node, path)} end)

    offenders
  end

  defp offender({fun, meta, args}, path) when fun in @live_starts and is_list(args),
    do: ["#{path}:#{meta[:line]}: #{fun}/#{length(args)}"]

  defp offender({fun, meta, args}, path) when fun in @spawns and is_list(args),
    do: ["#{path}:#{meta[:line]}: #{fun}/#{length(args)}"]

  defp offender({{:., _, [{:__aliases__, _, segments}, fun]}, meta, args}, path)
       when is_list(args) do
    if uncapped_remote?(segments, fun),
      do: ["#{path}:#{meta[:line]}: #{Enum.join(segments, ".")}.#{fun}/#{length(args)}"],
      else: []
  end

  defp offender(_node, _path), do: []

  defp uncapped_remote?([:Phoenix, :LiveView], fun), do: fun in @live_starts
  defp uncapped_remote?([:Task], fun), do: fun in @task_starts
  defp uncapped_remote?([:Task, :Supervisor], fun), do: fun in @task_starts
  defp uncapped_remote?([:Process], fun), do: fun in @spawns
  defp uncapped_remote?(_segments, _fun), do: false
end
