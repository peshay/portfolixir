defmodule PortfolixirWeb.CappedAsync do
  @moduledoc """
  The one way the web layer hands work to another process (#941).

  `PortfolixirWeb.HeapCap` caps every request and LiveView process (E25 S4,
  G05), but a process flag is not inherited, so the tasks a page starts —
  the performance walk, the valuations, the import apply, the classification
  loads, the quote syncs — ran with no limit. Each starts here instead, and
  its first act is `HeapCap.cap!/0`. `test/invariants/web_tasks_capped_test.exs`
  fails on a task the web layer starts any other way. Call the functions
  qualified (`CappedAsync.start_async(...)`) after `require`.
  """

  alias PortfolixirWeb.HeapCap

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

  @doc "`Task.start/1`, the task capping its heap first."
  @spec start((-> term())) :: {:ok, pid()}
  def start(fun) when is_function(fun, 0), do: Task.start(capped(fun))

  @doc "`Task.Supervisor.start_child/2`, the task capping its heap first."
  @spec start_child(Supervisor.supervisor(), (-> term())) :: DynamicSupervisor.on_start_child()
  def start_child(supervisor, fun) when is_function(fun, 0),
    do: Task.Supervisor.start_child(supervisor, capped(fun))

  defp capped(fun) do
    fn ->
      HeapCap.cap!()
      fun.()
    end
  end
end
