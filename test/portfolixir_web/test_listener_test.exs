defmodule PortfolixirWeb.TestListenerTest do
  # #1425: a listener a test starts is stopped by the test supervisor when
  # the test ends. ThousandIsland stops its listening socket first and its
  # acceptors after it, so an acceptor still starting up asks the stopped
  # listener for its socket and crashes into the console log. Under load
  # that failed full runs on the log-noise check (#927).
  use ExUnit.Case, async: true

  alias PortfolixirWeb.TestListener

  @listener {Bandit,
             plug: PortfolixirWeb.Endpoint,
             ip: :loopback,
             port: 0,
             startup_log: false,
             thousand_island_options: [num_acceptors: 4]}

  defp child(supervisor, id) do
    Enum.find_value(Supervisor.which_children(supervisor), fn
      {^id, pid, _type, _modules} when is_pid(pid) -> pid
      _other -> nil
    end)
  end

  # The listener process and the acceptor processes of a ThousandIsland
  # server, read from its supervision tree.
  defp listener_and_acceptors(server) do
    pool = child(server, :acceptor_pool_supervisor)

    acceptors =
      for {_id, acceptor_supervisor, _type, _modules} <- Supervisor.which_children(pool),
          do: child(acceptor_supervisor, :acceptor)

    {child(server, :listener), acceptors}
  end

  # Stops the test supervisor's children the way the test supervisor does
  # when the test ends: newest first (ExUnit.Callbacks, "start_supervised/2").
  defp stop_as_the_test_ends do
    {:ok, supervisor} = ExUnit.fetch_test_supervisor()

    for {id, _pid, _type, _modules} <- Supervisor.which_children(supervisor),
        do: :ok = Supervisor.terminate_child(supervisor, id)
  end

  # The processes in the order their monitors reported them down.
  defp down_order(watched) do
    for _pid <- watched do
      receive do
        {:DOWN, _ref, :process, pid, _reason} -> pid
      after
        5_000 -> flunk("a listener process did not stop")
      end
    end
  end

  # User story (#1425):
  # As the maintainer whose full test run fails on log noise (#927),
  # I want a listener a test starts to stop its acceptors before its
  # listening socket when the test ends,
  # so that no acceptor still starting up crashes into the console log under
  # load, and a red run names a real failure.
  #
  # Acceptance criteria:
  # - Stopped as the test supervisor stops it, a listener started with
  #   `TestListener.start!/1` has every acceptor down before its listener.
  test "a listener the helper started stops its acceptors before its listener" do
    server = TestListener.start!(@listener)
    {listener, acceptors} = listener_and_acceptors(server)
    assert length(acceptors) == 4
    watched = [listener | acceptors]
    for pid <- watched, do: Process.monitor(pid)

    stop_as_the_test_ends()

    order = down_order(watched)

    assert List.last(order) == listener,
           "the listener stopped before #{length(order) - 1 - Enum.find_index(order, &(&1 == listener))} of its acceptors"
  end

  # Acceptance criteria:
  # - No test starts a listener other than through `TestListener.start!/1`.
  test "every listener a test starts goes through the helper" do
    starts_a_listener = ~r/\{Bandit,|Bandit\.PhoenixAdapter\.child_specs\(/
    starts_it_directly = ~r/start_supervised!?\(\s*(\{\s*Bandit\b|spec\))/

    offenders =
      for path <- Path.wildcard("test/**/*.exs"),
          path != "test/portfolixir_web/test_listener_test.exs",
          source = File.read!(path),
          source =~ starts_a_listener,
          source =~ starts_it_directly or not (source =~ "TestListener.start!("),
          do: path

    assert offenders == []
  end
end
