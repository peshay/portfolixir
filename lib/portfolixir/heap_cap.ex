defmodule Portfolixir.HeapCap do
  @moduledoc """
  The per-process heap cap (E25 S4, G05) and the one way to run a piece of
  work under it in a process of its own (#1204, K08).

  `cap!/0` caps the calling process: past `max_heap_bytes` under this
  module's configuration (512 MiB by default, counting the off-heap binaries
  the process references) the runtime kills it and logs the kill.
  `PortfolixirWeb.HeapCap` caps every request and page process with it, and
  `PortfolixirWeb.CappedAsync` every task a page starts.

  `run/1` runs a function in a worker under `Portfolixir.CappedTasks` that
  caps itself first, and answers as if the caller had run the function: its
  value is returned, a raise, throw or exit inside it is raised in the
  caller again with its own stacktrace, and a worker killed past the cap
  becomes the caller's exit with the worker's reason. The caller stays
  uncapped and only watches, so it outlives the kill: a page's load task
  reports the failure to its page, and the performance warm-up and the
  derived refresher (K08) log the skipped scope and go on. A caller that
  traps exits and receives one (its page went away, or cancelled the load)
  stops the worker and exits the same way.

  Defence in depth, not the bound itself: the inputs, lists, memo and walks
  are bounded where they arrive.
  """

  @supervisor Portfolixir.CappedTasks
  @default_max_heap_bytes 512 * 1024 * 1024

  @doc "The cap in machine words, as `:max_heap_size` takes it."
  @spec max_heap_words() :: pos_integer()
  def max_heap_words do
    bytes =
      :portfolixir
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:max_heap_bytes, @default_max_heap_bytes)

    div(bytes, :erlang.system_info(:wordsize))
  end

  @doc "Caps the calling process's heap."
  @spec cap!() :: :ok
  def cap! do
    Process.flag(:max_heap_size, %{
      size: max_heap_words(),
      kill: true,
      error_logger: true,
      include_shared_binaries: true
    })

    :ok
  end

  @doc """
  Runs `fun` in a capped, supervised worker the caller watches, and answers
  as if the caller had run it (see the moduledoc).
  """
  @spec run((-> result)) :: result when result: term()
  def run(fun) when is_function(fun, 0) do
    caller = self()
    tag = make_ref()

    # The worker waits for the caller's monitor before it runs, so even a
    # worker killed at once is reported with its own reason; a caller gone
    # before that leaves nothing to run for.
    {:ok, worker} =
      Task.Supervisor.start_child(@supervisor, fn ->
        caller_watch = Process.monitor(caller)

        receive do
          ^tag ->
            Process.demonitor(caller_watch, [:flush])
            cap!()
            send(caller, {tag, outcome(fun)})

          {:DOWN, ^caller_watch, :process, ^caller, _reason} ->
            :ok
        end
      end)

    watch = Process.monitor(worker)
    send(worker, tag)
    await(worker, watch, tag)
  end

  defp outcome(fun) do
    {:ok, fun.()}
  catch
    kind, reason -> {:caught, kind, reason, __STACKTRACE__}
  end

  @spec await(pid(), reference(), reference()) :: term()
  defp await(worker, watch, tag) do
    receive do
      {^tag, {:ok, result}} ->
        Process.demonitor(watch, [:flush])
        result

      {^tag, {:caught, kind, reason, stacktrace}} ->
        Process.demonitor(watch, [:flush])
        :erlang.raise(kind, reason, stacktrace)

      {:DOWN, ^watch, :process, ^worker, reason} ->
        exit(reason)

      # Only a caller that traps exits receives one: the worker goes with it.
      {:EXIT, _from, reason} ->
        Process.exit(worker, :kill)
        exit(reason)
    end
  end
end
