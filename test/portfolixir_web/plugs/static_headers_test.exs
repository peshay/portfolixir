defmodule PortfolixirWeb.StaticHeadersTest do
  # Issue #763: Plug.Static runs ahead of the router, so the browser pipeline's
  # secure headers never reached a stored logo or the stylesheet.
  use PortfolixirWeb.ConnCase

  # User story:
  # As an operator,
  # I want stored logo bytes and static assets served with nosniff,
  # so that a browser never re-interprets a stored file as something else.
  #
  # Acceptance criteria:
  # - A static asset response carries x-content-type-options: nosniff.
  test "static assets are served with nosniff", %{conn: conn} do
    conn = get(conn, "/app.css")

    assert conn.status == 200
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end
end
