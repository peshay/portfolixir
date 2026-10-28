defmodule PortfolixirWeb.SessionCookieStore do
  @moduledoc """
  The session's cookie store: `Plug.Session.COOKIE`, plus one rule for a
  session cookie whose name the Cookie header carries twice (security review
  2026-10-12, K02).

  Another origin of the same host name (another port, a sibling subdomain)
  can set a cookie named like the session's with a longer `Path`, which the
  browser lists first. Plug and the LiveView socket read the first value of a
  name, so an unverifiable twin would leave every live page without its
  session. When the first value does not verify, the store reads the other
  values of the name, in order, and takes the first one this server signed;
  a value it did not sign is never taken.
  """

  @behaviour Plug.Session.Store

  alias Plug.Conn.Cookies
  alias Plug.Session.COOKIE

  @impl true
  def init(opts), do: COOKIE.init(opts)

  @impl true
  def get(conn, raw_cookie, opts) do
    case COOKIE.get(conn, raw_cookie, opts) do
      {nil, _empty} -> signed_twin(conn, raw_cookie, opts)
      found -> found
    end
  end

  @impl true
  def put(conn, sid, term, opts), do: COOKIE.put(conn, sid, term, opts)

  @impl true
  def delete(conn, sid, opts), do: COOKIE.delete(conn, sid, opts)

  defp signed_twin(conn, first, opts) do
    key = Keyword.fetch!(PortfolixirWeb.Endpoint.session_options(), :key)

    twins =
      for {"cookie", header} <- conn.req_headers,
          pair <- :binary.split(header, ";", [:global]),
          {^key, value} <- Cookies.decode(pair),
          value != first,
          do: value

    Enum.find_value(twins, {nil, %{}}, fn value ->
      case COOKIE.get(conn, value, opts) do
        {nil, _empty} -> nil
        found -> found
      end
    end)
  end
end
