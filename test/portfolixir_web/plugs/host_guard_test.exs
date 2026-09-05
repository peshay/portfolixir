defmodule PortfolixirWeb.HostGuardTest do
  # Issue #758 (ADR-0045 §2): the request's Host is validated ahead of the
  # router. `check_origin` guards the WebSocket handshake only; a page rendered
  # over plain HTTP was reachable under any Host, which is what a rebinding
  # page exploits. The guard is the invariant the closing act verifies.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.HostGuard

  # User story:
  # As an operator running Portfolixir on a home network,
  # I want a request whose Host is not one of my instance's names refused,
  # so that a page my browser opens elsewhere cannot read my dashboard through DNS rebinding.
  #
  # Acceptance criteria:
  # - A request with a foreign Host is answered 421 and never reaches the router.
  # - A request with an allowed Host is served as before.
  # - The LiveView still mounts on an allowed Host.
  test "refuses a foreign Host with 421 before the router", %{conn: conn} do
    conn = %{conn | host: "evil.example"} |> get("/health")

    assert conn.status == 421
    assert conn.halted
    assert conn.resp_body =~ "misdirected"
  end

  test "serves an allowed Host as before", %{conn: conn} do
    conn = get(conn, "/health")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "matches the Host case-insensitively", %{conn: conn} do
    conn = %{conn | host: "WWW.EXAMPLE.COM"} |> get("/health")

    assert conn.status == 200
  end

  test "the LiveView mounts on an allowed Host", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Portfolixir"
  end

  test "an empty allow-list refuses every Host rather than accepting every Host" do
    conn = Phoenix.ConnTest.build_conn()

    refute HostGuard.allowed?(conn.host, [])
    assert HostGuard.allowed?("localhost", ["localhost"])
    assert HostGuard.allowed?("LocalHost", ["localhost"])
    refute HostGuard.allowed?("localhost.evil", ["localhost"])
    refute HostGuard.allowed?(nil, ["localhost"])
  end
end
