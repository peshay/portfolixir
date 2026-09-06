defmodule PortfolixirWeb.HostGuard do
  @moduledoc """
  Refuses any request whose `Host` is not one of the instance's own names
  (ADR-0045 §2, #758).

  `check_origin` protects the WebSocket handshake only. A page rendered over
  plain HTTP was served under any `Host`, which is exactly what a DNS-rebinding
  page relies on to read an unauthenticated home-network service through the
  operator's own browser. The guard runs ahead of `Plug.Static` and the router,
  answers 421 (Misdirected Request) and halts.

  One request the guard does not see: the `/live` WebSocket handshake is
  dispatched by the endpoint before its plugs run. It rests on `check_origin`,
  which production builds from the same allow-list, and a browser always sends
  an `Origin` on that handshake; the LiveView it opens also needs a session
  token from a page this guard did serve.

  The allow-list comes from application config
  (`config :portfolixir, PortfolixirWeb.HostGuard, hosts: [...]`), built by
  `Portfolixir.RuntimeConfig.allowed_hosts/2` at release time. An empty or
  missing list refuses every request rather than accepting every request: a
  misconfiguration fails closed and is noticed at once.
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if allowed?(conn.host, configured_hosts()) do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(421, "misdirected request: unknown host")
      |> halt()
    end
  end

  @doc "Whether `host` (as Plug parses it, without the port) is on the allow-list."
  @spec allowed?(String.t() | nil, [String.t()]) :: boolean()
  def allowed?(host, hosts) when is_binary(host) and is_list(hosts) do
    String.downcase(host) in hosts
  end

  def allowed?(_host, _hosts), do: false

  defp configured_hosts do
    :portfolixir
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:hosts, [])
  end
end
