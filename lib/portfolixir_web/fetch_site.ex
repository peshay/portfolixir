defmodule PortfolixirWeb.FetchSite do
  @moduledoc """
  Whether a request may change what the browser remembers (E25 S7, F18).

  The view, benchmark and locale choices arrive as query parameters on a
  plain GET (`?view=`, `?benchmark[]=`, `?locale=`), which any site can link
  the operator's browser to. A choice is **remembered** — written to its
  long-lived cookie — only when the browser's `Sec-Fetch-Site` header says the
  request came from this origin (`same-origin`), from the operator directly
  (`none`: the address bar, a bookmark), or is absent (a browser that does not
  send it, a script). Any other value (`cross-site`, `same-site`) applies the
  choice to that request only, so another site can change at most the page it
  opens, never what the next page shows.
  """

  import Plug.Conn

  @remembering ["same-origin", "none"]

  @doc "Whether `conn` may write a remembered UI preference."
  @spec remember?(Plug.Conn.t()) :: boolean()
  def remember?(%Plug.Conn{} = conn) do
    case get_req_header(conn, "sec-fetch-site") do
      [] -> true
      [site | _] -> String.downcase(String.trim(site)) in @remembering
    end
  end
end
