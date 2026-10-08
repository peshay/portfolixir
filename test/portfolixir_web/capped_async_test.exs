defmodule PortfolixirWeb.CappedAsyncTest do
  # #941 and #1058: the one way a page hands work to a task. Every task caps
  # its heap first, as the page's own process does (E25 S4, G05), and a load
  # the page asks for again before the last one answered waits for it as the
  # latest request instead of running beside it.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.HeapCap

  # A page that starts each kind of task and reports what the task saw. A
  # walk blocks until the test lets it go, so "while one runs" is a state the
  # test holds, not a race it hopes to win.
  defmodule Probe do
    use PortfolixirWeb, :live_view

    alias PortfolixirWeb.CappedAsync
    require CappedAsync

    @impl true
    def mount(_params, %{"test" => test, "supervisor" => supervisor}, socket),
      do: {:ok, assign(socket, test: test, supervisor: supervisor, landed: [])}

    @impl true
    def render(assigns), do: ~H|<p id="landed"><%= inspect(@landed) %></p>|

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

    def handle_event("walk", %{"n" => n}, socket) do
      test = socket.assigns.test

      {:noreply,
       CappedAsync.start_latest(socket, :walk, fn ->
         send(test, {:walking, n, self()})

         receive do
           :go -> n
         end
       end)}
    end

    @impl true
    def handle_async(:once, _result, socket), do: {:noreply, socket}

    def handle_async(:walk, result, socket) do
      case CappedAsync.landed(socket, :walk) do
        {:superseded, socket} -> {:noreply, socket}
        {:current, socket} -> {:noreply, update(socket, :landed, &(&1 ++ [result]))}
      end
    end

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

  # User story (#1058):
  # As the operator switching Wealth's period several times in a row,
  # I want one contribution walk at a time, and the walk for the period I
  # stopped on to be the one that answers,
  # so that rapid switches do not run a full walk for every period I passed.
  #
  # Acceptance criteria:
  # - A load asked for while one runs starts no second task; a later ask
  #   replaces it, so of three asks only the first and the last ever run.
  # - The running task is never killed: it ends, its result is dropped as
  #   superseded, and the latest ask starts then and is the one that lands.
  # - A load asked for when none runs starts at once.
  test "a load asked again while one runs waits as the latest, and only it lands",
       %{conn: conn} do
    view = probe(conn)

    render_click(view, "walk", %{"n" => "1"})
    assert_receive {:walking, "1", first}

    render_click(view, "walk", %{"n" => "2"})
    render_click(view, "walk", %{"n" => "3"})
    refute_receive {:walking, _n, _pid}, 100

    send(first, :go)
    assert_receive {:walking, "3", last}, 2_000
    refute_received {:walking, "2", _pid}

    send(last, :go)
    render_async(view)
    assert view |> element("#landed") |> render() == ~s(<p id="landed">[ok: &quot;3&quot;]</p>)

    render_click(view, "walk", %{"n" => "4"})
    assert_receive {:walking, "4", next}
    send(next, :go)
    render_async(view)

    assert view |> element("#landed") |> render() ==
             ~s(<p id="landed">[ok: &quot;3&quot;, ok: &quot;4&quot;]</p>)
  end
end
