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
  """

  alias Phoenix.LiveView.Socket
  alias PortfolixirWeb.HeapCap

  require Phoenix.LiveView

  # `socket.private` key: `%{name => :running | {:pending, fun}}`.
  @flights :portfolixir_capped_async

  @doc """
  `Phoenix.LiveView.start_async/3`, its task capping its heap first. A macro,
  so LiveView still checks the function at compile time for a captured
  socket or assigns.
  """
  defmacro start_async(socket, name, fun) do
    quote do
      Phoenix.LiveView.start_async(unquote(socket), unquote(name), fn ->
        PortfolixirWeb.HeapCap.cap!()
        unquote(fun).()
      end)
    end
  end

  @doc """
  `start_async/3` for a load asked again before the last one answered
  (#1058): one task under `name` at a time, the latest ask waiting for it.
  The page's `handle_async/3` for `name` calls `landed/2` first.
  """
  @spec start_latest(Socket.t(), atom(), (-> term())) :: Socket.t()
  def start_latest(%Socket{} = socket, name, fun) when is_atom(name) and is_function(fun, 0) do
    cond do
      not Phoenix.LiveView.connected?(socket) -> socket
      Map.has_key?(flights(socket), name) -> put_flight(socket, name, {:pending, fun})
      true -> run(socket, name, fun)
    end
  end

  @doc """
  What a result under a `start_latest/3` name is: `{:superseded, socket}`
  when a later ask waited for it, which is started now and whose result is
  the one to land, or `{:current, socket}`.
  """
  @spec landed(Socket.t(), atom()) :: {:superseded | :current, Socket.t()}
  def landed(%Socket{} = socket, name) when is_atom(name) do
    case Map.get(flights(socket), name) do
      {:pending, fun} ->
        {:superseded, run(socket, name, fun)}

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

  defp run(socket, name, fun) do
    socket
    |> put_flight(name, :running)
    |> Phoenix.LiveView.start_async(name, capped(fun))
  end

  defp capped(fun) do
    fn ->
      HeapCap.cap!()
      fun.()
    end
  end

  defp flights(socket), do: Map.get(socket.private, @flights, %{})

  defp put_flight(socket, name, flight),
    do: Phoenix.LiveView.put_private(socket, @flights, Map.put(flights(socket), name, flight))
end
