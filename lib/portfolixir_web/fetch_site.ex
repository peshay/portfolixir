defmodule PortfolixirWeb.FetchSite do
  @moduledoc """
  Whether a request may change what the browser remembers (E25 S7, F18).

  The view, benchmark and locale choices arrive as query parameters on a
  plain GET (`?view=`, `?benchmark[]=`, `?locale=`), which any site can link
  the operator's browser to. A choice is **remembered** — written to its
  long-lived cookie — only when the browser's `Sec-Fetch-Site` header says the
  request came from this origin (`same-origin`) or from the operator directly
  (`none`: the address bar, a bookmark). Any other value (`cross-site`,
  `same-site`) applies the choice to that request only, so another site can
  change at most the page it opens, never what the next page shows.

  An absent header means something only where browsers send one (security
  review 2026-10-12, H41). They send it to an HTTPS origin and to loopback
  (`localhost`, `127.0.0.0/8`, `::1`), so an unlabelled request there is an
  older browser or a script, and it is remembered as before. To plain HTTP at
  any other name or address a browser sends no `Sec-Fetch-Site` at all,
  whatever site the request came from; there a choice is remembered only when
  the `Referer` names the request's own origin (scheme, host and port), and a
  foreign or missing one applies it to that request alone.

  Such a choice is not written into the session either (E25 S7 review round,
  S7E-4): a LiveView mounts from the session at every live navigation, so a
  choice kept there would reach every page opened from that one without a
  full load. The page it opened reads it from its own address instead
  (`PortfolixirWeb.LiveViewScope`, `PortfolixirWeb.LiveBenchmarkScope`,
  `PortfolixirWeb.LiveLocale`), on its first render and once its socket is
  connected.
  """

  import Plug.Conn

  @remembering ["same-origin", "none"]

  @doc "Whether `conn` may write a remembered UI preference."
  @spec remember?(Plug.Conn.t()) :: boolean()
  def remember?(%Plug.Conn{} = conn) do
    case get_req_header(conn, "sec-fetch-site") do
      [] -> labelled_origin?(conn) or own_referer?(conn)
      [site | _] -> String.downcase(String.trim(site)) in @remembering
    end
  end

  # An origin browsers send Fetch Metadata to: HTTPS, or a loopback name or
  # address. Off those, an absent header says nothing about the request.
  defp labelled_origin?(%Plug.Conn{scheme: :https}), do: true
  defp labelled_origin?(%Plug.Conn{host: host}), do: loopback?(bare_host(host))

  defp loopback?("localhost"), do: true

  defp loopback?(host) do
    if String.ends_with?(host, ".localhost") do
      true
    else
      case :inet.parse_address(String.to_charlist(host)) do
        {:ok, {127, _, _, _}} -> true
        {:ok, {0, 0, 0, 0, 0, 0, 0, 1}} -> true
        _other -> false
      end
    end
  end

  # The Referer names this request's own origin: the same scheme, host and
  # port. A missing, foreign or unreadable one fails closed.
  defp own_referer?(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         {:ok, %URI{scheme: scheme, host: host, port: port}} when is_binary(host) <-
           URI.new(String.trim(referer)) do
      scheme == Atom.to_string(conn.scheme) and bare_host(host) == bare_host(conn.host) and
        port == conn.port
    else
      _none_or_unreadable -> false
    end
  end

  # Both callers hand it a binary: `Plug.Conn`'s host is one by type, and the
  # Referer's is matched as one above.
  defp bare_host(host),
    do: host |> String.downcase() |> String.trim_leading("[") |> String.trim_trailing("]")
end
