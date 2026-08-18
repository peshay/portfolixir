defmodule PortfolixirWeb.RedirectController do
  @moduledoc """
  Permanent redirects for routes that were renamed.

  `/income` became `/cashflow` when Income was promoted to the Cash-flow area
  (#672, UX-DR4). The old route is not deleted: bookmarks, older links and
  anything the operator wrote down still resolve. It is a plain HTTP redirect
  rather than a LiveView that navigates on mount, so it also works for a client
  that never opens a socket, and it is one line of behaviour instead of a
  LiveView whose `render/1` can never run.
  """
  use PortfolixirWeb, :controller

  def cashflow(conn, _params), do: redirect(conn, to: "/cashflow")
end
