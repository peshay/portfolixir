defmodule PortfolixirWeb.CappedAsync do
  @moduledoc """
  The one way the web layer hands work to another process (#941, #1058).

  `PortfolixirWeb.HeapCap` caps every request and LiveView process (E25 S4,
  G05), but a process flag is not inherited, so the tasks a page starts —
  the performance walk, the valuations, the import apply, the classification
  loads, the quote syncs — ran with no limit. Each starts here instead, and
  its first act is `HeapCap.cap!/0`. `test/invariants/web_tasks_capped_test.exs`
  fails on a task the web layer starts any other way. Call the functions
  qualified (`CappedAsync.start_async(...)`) after `require`.

  `start_latest/3` (#1058) is for a load a page may ask for again before the
  last one answered, such as Wealth's contribution walk on a period switch:
  one task per name at a time. An ask while one runs starts nothing and is
  kept as the latest, replacing any older one, and `landed/2`, which the
  page's `handle_async/3` for that name calls first, starts it once the
  running task has answered. The running task is never killed: a task killed
  mid-query takes its database connection with it (under the test sandbox,
  the test's own), so a superseded walk still ends, but only the first and
  the latest of a burst of asks ever run.

  `max_in_flight: n` (Sprint 31 closing act, security lens SE1) caps how
  many of a page's `start_latest/4` loads under that option do their work
  at once. Each load's task starts at the ask, as before, so the page and
  `Phoenix.LiveViewTest.render_async/1` see it; past the cap it waits for
  a free slot before it starts its worker, and the page grants the slots
  in the order asked, one more each time a load's task ends (a monitor, so
  a task that dies frees its slot too). The cap is the page's: the first
  ask that names one attaches the gate (a `handle_info` hook).

  A page's load runs in two processes (#1204). LiveView links the task it
  starts to the page; that task is a wrapper that stays uncapped and only
  watches: the load itself runs in a worker it monitors, and the worker caps
  its heap first. A worker the cap kills is reported by the wrapper as its
  own exit, so the page's `handle_async/3` receives `{:exit, reason}` and
  shows its own failure state instead of going down with a linked task. The
  wrapper traps exits, so a page that goes away or cancels the load reaches
  it as a message; it stops the worker and exits the same way.
  """

  alias Phoenix.LiveView.Socket
  alias PortfolixirWeb.HeapCap
  alias PortfolixirWeb.PrivacyMode

  require Phoenix.LiveView

  # `socket.private` key: `%{name => :running | {:pending, fun, opts}}`.
  @flights :portfolixir_capped_async
  # `socket.private` key: the page's gate, `%{limit, running, waiting}`.
  @gate :portfolixir_capped_async_gate

  @doc """
  `Phoenix.LiveView.start_async/3`, its load running in a worker that caps
  its heap first and whose death the page receives as `{:exit, reason}`
  (#1204). A macro, so LiveView still checks the function at compile time
  for a captured socket or assigns.
  """
  defmacro start_async(socket, name, fun) do
    quote do
      privacy_mode = PortfolixirWeb.PrivacyMode.on?()

      Phoenix.LiveView.start_async(unquote(socket), unquote(name), fn ->
        PortfolixirWeb.CappedAsync.__watch__(unquote(fun), privacy_mode)
      end)
    end
  end

  @doc """
  `start_async/3` for a load asked again before the last one answered
  (#1058): one task under `name` at a time, the latest ask waiting for it.
  The page's `handle_async/3` for `name` calls `landed/2` first. The name
  is any term, as `Phoenix.LiveView.start_async/3`'s is: a page that reads
  one load per scope names each `{:movers, scope}` (Sprint 31 D3).

  Options: `max_in_flight` — at most that many of the page's loads under
  the option do their work at once, the rest waiting in the order asked
  (see the module doc).
  """
  @spec start_latest(Socket.t(), term(), (-> term()), keyword()) :: Socket.t()
  def start_latest(%Socket{} = socket, name, fun, opts \\ [])
      when is_function(fun, 0) and is_list(opts) do
    cond do
      not Phoenix.LiveView.connected?(socket) -> socket
      Map.has_key?(flights(socket), name) -> put_flight(socket, name, {:pending, fun, opts})
      true -> run(socket, name, fun, opts)
    end
  end

  @doc """
  What a result under a `start_latest/3` name is: `{:superseded, socket}`
  when a later ask waited for it, which is started now and whose result is
  the one to land, or `{:current, socket}`.
  """
  @spec landed(Socket.t(), term()) :: {:superseded | :current, Socket.t()}
  def landed(%Socket{} = socket, name) do
    case Map.get(flights(socket), name) do
      {:pending, fun, opts} ->
        {:superseded, run(socket, name, fun, opts)}

      _running ->
        {:current,
         Phoenix.LiveView.put_private(socket, @flights, Map.delete(flights(socket), name))}
    end
  end

  @doc "`Task.start/1`, the task capping its heap first."
  @spec start((-> term())) :: {:ok, pid()}
  def start(fun) when is_function(fun, 0), do: Task.start(capped(fun))

  @doc "`Task.Supervisor.start_child/2`, the task capping its heap first."
  @spec start_child(Supervisor.supervisor(), (-> term())) :: DynamicSupervisor.on_start_child()
  def start_child(supervisor, fun) when is_function(fun, 0),
    do: Task.Supervisor.start_child(supervisor, capped(fun))

  defp run(socket, name, fun, opts) do
    privacy_mode = PrivacyMode.on?()
    socket = put_flight(socket, name, :running)

    case Keyword.get(opts, :max_in_flight) do
      limit when is_integer(limit) and limit > 0 ->
        page = self()

        socket
        |> gate(limit)
        |> Phoenix.LiveView.start_async(name, fn ->
          __wait_for_slot__(page)
          __watch__(fun, privacy_mode)
        end)

      nil ->
        Phoenix.LiveView.start_async(socket, name, fn -> __watch__(fun, privacy_mode) end)
    end
  end

  # -- the page's gate (Sprint 31 closing act, SE1) ---------------------------

  defp gate(socket, limit) do
    case socket.private do
      %{@gate => _gate} ->
        socket

      _none ->
        socket
        |> Phoenix.LiveView.put_private(@gate, %{
          limit: limit,
          running: MapSet.new(),
          waiting: :queue.new()
        })
        |> Phoenix.LiveView.attach_hook(:capped_async_gate, :handle_info, &gate_info/2)
    end
  end

  @doc false
  # The first act of a load's task under `max_in_flight`: ask the page for
  # a slot and wait for it. Before it, the task runs nothing; it is linked
  # to the page, so a page that goes away takes the waiting task with it.
  @spec __wait_for_slot__(pid()) :: :ok
  def __wait_for_slot__(page) do
    tag = make_ref()
    send(page, {:capped_async_slot, self(), tag})

    receive do
      {:capped_async_go, ^tag} -> :ok
    end
  end

  defp gate_info({:capped_async_slot, task, tag}, socket) do
    gate = socket.private[@gate]
    ref = Process.monitor(task)

    gate =
      if MapSet.size(gate.running) < gate.limit,
        do: grant(gate, {task, tag, ref}),
        else: %{gate | waiting: :queue.in({task, tag, ref}, gate.waiting)}

    {:halt, Phoenix.LiveView.put_private(socket, @gate, gate)}
  end

  defp gate_info({:DOWN, ref, :process, _task, _reason}, socket) do
    gate = socket.private[@gate]

    cond do
      MapSet.member?(gate.running, ref) ->
        gate = next(%{gate | running: MapSet.delete(gate.running, ref)})
        {:halt, Phoenix.LiveView.put_private(socket, @gate, gate)}

      waiting?(gate, ref) ->
        waiting = :queue.filter(fn {_task, _tag, waiter} -> waiter != ref end, gate.waiting)
        {:halt, Phoenix.LiveView.put_private(socket, @gate, %{gate | waiting: waiting})}

      true ->
        {:cont, socket}
    end
  end

  defp gate_info(_message, socket), do: {:cont, socket}

  defp grant(gate, {task, tag, ref}) do
    send(task, {:capped_async_go, tag})
    %{gate | running: MapSet.put(gate.running, ref)}
  end

  defp next(gate) do
    case :queue.out(gate.waiting) do
      {{:value, waiter}, waiting} -> grant(%{gate | waiting: waiting}, waiter)
      {:empty, _waiting} -> gate
    end
  end

  defp waiting?(gate, ref),
    do: Enum.any?(:queue.to_list(gate.waiting), fn {_task, _tag, waiter} -> waiter == ref end)

  @doc false
  # The body of a page's load task (#1204): runs `fun` in a capped worker it
  # watches (`Portfolixir.HeapCap.run/1`) and answers as if it had run `fun`
  # itself. A value is returned, a raise, throw or exit inside `fun` is
  # raised here again with its own stacktrace, and a worker that died
  # without one (killed past the cap) becomes this task's exit with the
  # worker's reason. It traps exits, so its page going away reaches it as a
  # message and stops the worker.
  #
  # The worker formats in the privacy mode of the page that started it
  # (Sprint 26 P1): a figure a load formats there is hidden as the page's
  # own are.
  @spec __watch__((-> term()), boolean()) :: term()
  def __watch__(fun, privacy_mode \\ false) when is_function(fun, 0) do
    Process.flag(:trap_exit, true)

    Portfolixir.HeapCap.run(fn ->
      PrivacyMode.put(privacy_mode)
      fun.()
    end)
  end

  defp capped(fun) do
    fun = PrivacyMode.carry(fun)

    fn ->
      HeapCap.cap!()
      fun.()
    end
  end

  defp flights(socket), do: Map.get(socket.private, @flights, %{})

  defp put_flight(socket, name, flight),
    do: Phoenix.LiveView.put_private(socket, @flights, Map.put(flights(socket), name, flight))
end
