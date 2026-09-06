defmodule PortfolixirWeb.TrustedProxyTest do
  # Issue #771 (ADR-0045 §2): behind the documented reverse proxy every client
  # arrives from the proxy's address, so the throttle would lock the operator
  # out together with a guesser. A named proxy's x-forwarded-for fixes that;
  # an unnamed one is never believed.
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias PortfolixirWeb.TrustedProxy

  setup do
    previous = Application.get_env(:portfolixir, :trusted_proxies)
    on_exit(fn -> Application.put_env(:portfolixir, :trusted_proxies, previous) end)
    :ok
  end

  defp request(remote_ip, forwarded) do
    conn = %{conn(:get, "/") | remote_ip: remote_ip}
    if forwarded, do: put_req_header(conn, "x-forwarded-for", forwarded), else: conn
  end

  # User story:
  # As an operator running the instance behind a reverse proxy,
  # I want the throttle to count the client the proxy vouches for,
  # so that a guesser locks out itself, not everyone behind the proxy.
  #
  # Acceptance criteria:
  # - With no trusted proxies, x-forwarded-for is ignored.
  # - From a trusted address, the last untrusted hop of the header becomes remote_ip.
  # - From an untrusted address, the header is ignored even when proxies are named.
  # - A header without a parsable address leaves remote_ip as it was.
  test "believes x-forwarded-for only from a trusted proxy" do
    Application.put_env(:portfolixir, :trusted_proxies, [])

    assert TrustedProxy.call(request({172, 18, 0, 1}, "203.0.113.5"), []).remote_ip ==
             {172, 18, 0, 1}

    Application.put_env(:portfolixir, :trusted_proxies, [
      {{172, 16, 0, 0}, 12},
      {{0, 0, 0, 0, 0, 0, 0, 1}, 128}
    ])

    assert TrustedProxy.call(request({172, 18, 0, 1}, "203.0.113.5"), []).remote_ip ==
             {203, 0, 113, 5}

    # The chain: client, then a second trusted hop appended by the proxy.
    assert TrustedProxy.call(request({172, 18, 0, 1}, "198.51.100.7, 172.20.0.2"), []).remote_ip ==
             {198, 51, 100, 7}

    assert TrustedProxy.call(request({0, 0, 0, 0, 0, 0, 0, 1}, "2001:db8::9"), []).remote_ip ==
             {0x2001, 0xDB8, 0, 0, 0, 0, 0, 9}

    assert TrustedProxy.call(request({10, 0, 0, 9}, "203.0.113.5"), []).remote_ip == {10, 0, 0, 9}

    assert TrustedProxy.call(request({172, 18, 0, 1}, "not-an-address"), []).remote_ip ==
             {172, 18, 0, 1}

    assert TrustedProxy.call(request({172, 18, 0, 1}, nil), []).remote_ip == {172, 18, 0, 1}
  end
end
