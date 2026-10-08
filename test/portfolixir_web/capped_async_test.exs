defmodule PortfolixirWeb.CappedAsyncTest do
  # #941: the one way a page hands work to a task. Every task caps its heap
  # first, as the page's own process does (E25 S4, G05).
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.HeapCap

  # A page that starts each kind of task and reports what the task saw.
  defmodule Probe do
    use PortfolixirWeb, :live_view

    alias PortfolixirWeb.CappedAsync
    require CappedAsync

    @impl true
    def mount(_params, %{"test" => test, "supervisor" => supervisor}, socket),
      do: {:ok, assign(socket, test: test, supervisor: supervisor)}

    @impl true
    def render(assigns), do: ~H|<p>probe</p>|

    @impl true
    def handle_event("async", _params, socket) do
      test = socket.assigns.test
      {:noreply, CappedAsync.start_async(socket, :once, fn -> report(test, :async) end)}
    end

    def handle_event("task", _params, socket) do
      test = socket.assigns.test
      {:ok, _pid} = CappedAsync.start(fn -> report(test, :task) end)
      {:noreply, socket}
    end

    def handle_event("child", _params, socket) do
      test = socket.assigns.test

      {:ok, _pid} =
        CappedAsync.start_child(socket.assigns.supervisor, fn -> report(test, :child) end)

      {:noreply, socket}
    end

    @impl true
    def handle_async(:once, _result, socket), do: {:noreply, socket}

    defp report(test, kind), do: send(test, {:capped, kind, Process.info(self(), :max_heap_size)})
  end

  defp probe(conn) do
    supervisor = start_supervised!(Task.Supervisor)

    {:ok, view, _html} =
      live_isolated(conn, Probe, session: %{"test" => self(), "supervisor" => supervisor})

    view
  end

  # User story (#941):
  # As the operator whose pages hand their heaviest work to tasks,
  # I want each such task to run under the heap cap its page runs under,
  # so that a runaway load fails alone instead of exhausting the machine.
  #
  # Acceptance criteria:
  # - A task started by `start_async`, by `start` and under a supervisor by
  #   `start_child` each carries the cap, counting shared binaries and
  #   killing the task past it, before it runs anything else.
  test "every task a page starts caps its own heap first", %{conn: conn} do
    view = probe(conn)

    for kind <- ~w(async task child) do
      render_click(view, kind)
      assert_receive {:capped, _kind, {:max_heap_size, cap}}, 2_000

      assert cap.size == HeapCap.max_heap_words(), kind
      assert cap.kill == true, kind
      assert cap.include_shared_binaries == true, kind
    end
  end
end
