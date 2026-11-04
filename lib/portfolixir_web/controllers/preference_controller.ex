defmodule PortfolixirWeb.PreferenceController do
  @moduledoc """
  The address the sidebar rail's toggle asks to remember its state at
  (Sprint 24 P2): `GET /preferences/rail?rail=collapsed|expanded`.

  `PortfolixirWeb.RailScope`, in the browser pipeline, writes or deletes the
  cookie, as `PortfolixirWeb.BenchmarkScope` does for a benchmark choice on
  any page; this action only answers, with no content, so the toggle's
  request renders no page.
  """
  use PortfolixirWeb, :controller

  def rail(conn, _params), do: send_resp(conn, 204, "")
end
