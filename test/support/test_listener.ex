defmodule PortfolixirWeb.TestListener do
  @moduledoc """
  Starts an HTTP listener (Bandit on ThousandIsland) under the test
  supervisor so that it stops its acceptors before its listening socket
  (#1425).

  The test supervisor stops a listener when the test ends. ThousandIsland
  then closes its listening socket first and stops its acceptors after it,
  so an acceptor still starting up -- a listener has ten or a hundred, and
  under load a short test ends before all of them asked the listener for
  its socket -- asks a listener that is gone, and crashes with "no process"
  into the console log. The log-noise check (#927) fails the run on it.

  `start!/1` therefore starts a second child after the listener, which the
  test supervisor stops first (it stops its children newest first). That
  child suspends the server as it stops: `ThousandIsland.suspend/1` stops
  every acceptor and only then the listening socket. The server itself is
  stopped right after, as before.
  """

  use GenServer

  @doc "Starts the listener `spec` under the test supervisor and returns its server pid."
  @spec start!(Supervisor.child_spec() | {module(), term()}) :: pid()
  def start!(spec) do
    server = ExUnit.Callbacks.start_supervised!(spec)
    ExUnit.Callbacks.start_supervised!({__MODULE__, server}, id: {__MODULE__, server})
    server
  end

  @doc false
  def start_link(server), do: GenServer.start_link(__MODULE__, server)

  @impl GenServer
  def init(server) do
    # Trapped, so the test supervisor's shutdown runs `terminate/2`.
    Process.flag(:trap_exit, true)
    {:ok, server}
  end

  @impl GenServer
  def terminate(_reason, server) do
    if Process.alive?(server), do: ThousandIsland.suspend(server)
    :ok
  end
end
