defmodule PortfolixirWeb.TrustedProxyCatchAllTest do
  # A trusted-proxy block wide enough to cover the clients is refused and
  # named at startup (security review 2026-10-12, H04). Addresses are
  # documentation ranges (RFC 5737, RFC 3849). No network.
  use PortfolixirWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.Auth.Throttle
  alias Portfolixir.RuntimeConfig
  alias PortfolixirWeb.TrustedProxy

  @password "h04-operator-password-long-enough"
  # A client that connects to the listener directly, not a proxy.
  @peer {192, 0, 2, 77}
  # The documented setting: the one address the proxy connects from.
  @documented "172.18.0.1"

  setup do
    keys = [:force_ssl, :trusted_proxies, :ui_password, PortfolixirWeb.Endpoint]
    previous = Map.new(keys, &{&1, Application.fetch_env(:portfolixir, &1)})
    previous_var = System.get_env("PORTFOLIXIR_TRUSTED_PROXIES")

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:portfolixir, key, value)
          :error -> Application.delete_env(:portfolixir, key)
        end
      end

      if previous_var,
        do: System.put_env("PORTFOLIXIR_TRUSTED_PROXIES", previous_var),
        else: System.delete_env("PORTFOLIXIR_TRUSTED_PROXIES")
    end)

    :ok
  end

  # What config/runtime.exs does with the variable; a refusing fix may raise.
  defp boot_blocks(value) do
    System.put_env("PORTFOLIXIR_TRUSTED_PROXIES", value)
    {:ok, RuntimeConfig.trusted_proxies()}
  rescue
    error in ArgumentError -> {:refused, Exception.message(error)}
  end

  defp use_proxies(value),
    do: Application.put_env(:portfolixir, :trusted_proxies, RuntimeConfig.trusted_proxies(value))

  defp direct_request(headers) do
    Enum.reduce(headers, %{Plug.Test.conn(:get, "/") | remote_ip: @peer}, fn {name, value},
                                                                             conn ->
      put_req_header(conn, name, value)
    end)
  end

  # Wrong passwords from the one peer; forwarded(n) is the X-Forwarded-For the
  # client writes on its n-th attempt (nil: none).
  defp login_statuses(forwarded) do
    for n <- 1..(Throttle.max_failures() + 2) do
      conn = %{build_conn() | remote_ip: @peer}

      conn =
        if value = forwarded.(n), do: put_req_header(conn, "x-forwarded-for", value), else: conn

      post(conn, "/login", %{"session" => %{"password" => "wrong-#{n}"}}).status
    end
  end

  # User story (security review 2026-10-12, H04):
  # As the operator who names the reverse proxy in PORTFOLIXIR_TRUSTED_PROXIES,
  # I want an entry that would trust nearly every client refused and named
  # at startup,
  # so that a copied catch-all does not silently hand every client the
  # throttle's source and the scheme.
  #
  # Acceptance criteria:
  # - A catch-all entry, alone or for both families, is refused at boot, or
  #   the startup log names the variable and quotes the entry.
  test "boot: a catch-all PORTFOLIXIR_TRUSTED_PROXIES is refused and named in a startup warning" do
    # The Compose bind, PHX_FORCE_SSL on, a sound UI password: the exposure
    # and password warnings stay silent.
    endpoint = Application.get_env(:portfolixir, PortfolixirWeb.Endpoint, [])
    http = Keyword.put(Keyword.get(endpoint, :http, []), :ip, {0, 0, 0, 0})
    Application.put_env(:portfolixir, PortfolixirWeb.Endpoint, Keyword.put(endpoint, :http, http))
    Application.put_env(:portfolixir, :force_ssl, RuntimeConfig.force_ssl_opts("true", nil))
    Application.put_env(:portfolixir, :ui_password, @password)

    for value <- ["0.0.0.0/0", "0.0.0.0/0, ::/0"] do
      case boot_blocks(value) do
        {:refused, message} ->
          assert message =~ "PORTFOLIXIR_TRUSTED_PROXIES"

        {:ok, blocks} ->
          Application.put_env(:portfolixir, :trusted_proxies, blocks)

          log =
            capture_log([level: :warning], fn ->
              assert Portfolixir.Application.warn_if_exposed() == :ok
            end)

          refute Enum.any?(blocks, fn {_network, bits} -> bits == 0 end),
                 "#{inspect(value)} parsed to #{inspect(blocks)}"

          assert log =~ "PORTFOLIXIR_TRUSTED_PROXIES"
          assert log =~ inspect("0.0.0.0/0"), "the boot log said: " <> inspect(log)
      end
    end
  end

  # User story (security review 2026-10-12, H04):
  # As the operator,
  # I want a client that connects directly to keep its own address as the
  # throttle's source whatever catch-all the variable holds,
  # so that it cannot pick a fresh source per request.
  #
  # Acceptance criteria:
  # - Under the documented single address and under 0.0.0.0/0 alike, a
  #   directly connecting client's X-Forwarded-For is not its source.
  test "plug: under 0.0.0.0/0 a directly connecting client cannot choose its throttle source" do
    use_proxies(@documented)
    control = TrustedProxy.call(direct_request([{"x-forwarded-for", "2001:db8::1234"}]), [])
    assert control.remote_ip == @peer

    use_proxies("0.0.0.0/0")
    conn = TrustedProxy.call(direct_request([{"x-forwarded-for", "2001:db8::1234"}]), [])

    assert conn.remote_ip == @peer,
           "the client's own X-Forwarded-For became the throttle source: " <>
             Throttle.source_key(conn.remote_ip)
  end

  # User story (security review 2026-10-12, H04):
  # As the operator,
  # I want a directly connecting client unable to mark its own plain-HTTP
  # request as HTTPS, whatever catch-all the variable holds,
  # so that the scheme is believed from the named proxy only.
  #
  # Acceptance criteria:
  # - Under the documented address and under a catch-all list, the client's
  #   X-Forwarded-Proto leaves the scheme http.
  test "plug: under a catch-all list a directly connecting client cannot set the scheme" do
    use_proxies(@documented)
    control = TrustedProxy.call(direct_request([{"x-forwarded-proto", "https"}]), [])
    assert control.scheme == :http

    for value <- ["0.0.0.0/0", "0.0.0.0/0, ::/0"] do
      use_proxies(value)
      conn = TrustedProxy.call(direct_request([{"x-forwarded-proto", "https"}]), [])

      assert conn.scheme == :http,
             "under #{inspect(value)} the client's own X-Forwarded-Proto made its plain-HTTP request https"
    end
  end

  # User story (security review 2026-10-12, H04):
  # As an operator with a UI password,
  # I want one client that rotates its X-Forwarded-For still locked out of
  # the login after repeated wrong passwords, under a catch-all entry too,
  # so that the per-source lock holds.
  #
  # Acceptance criteria:
  # - Under the documented address and under 0.0.0.0/0, the last of more
  #   wrong passwords than the threshold is answered 429.
  test "endpoint: under 0.0.0.0/0 one client rotating X-Forwarded-For is still locked out of /login" do
    Application.put_env(:portfolixir, :ui_password, @password)
    peer_key = Throttle.source_key(@peer)
    rotating = fn n -> "2001:db8:4:#{Integer.to_string(n, 16)}::1" end

    use_proxies(@documented)
    Throttle.success(:ui, peer_key)
    control = login_statuses(rotating)
    assert List.last(control) == 429, "control: #{inspect(control)}"
    Throttle.success(:ui, peer_key)

    use_proxies("0.0.0.0/0")
    statuses = login_statuses(rotating)
    Throttle.success(:ui, peer_key)

    assert List.last(statuses) == 429,
           "the same peer made #{length(statuses)} wrong-password attempts and was never locked: " <>
             inspect(statuses)
  end

  # User story (security review 2026-10-12, H04):
  # As the operator who turned PHX_FORCE_SSL on,
  # I want a client's plain-HTTP request redirected whatever it claims in
  # X-Forwarded-Proto, under a catch-all entry too,
  # so that the redirect and HSTS follow the named proxy only.
  #
  # Acceptance criteria:
  # - Under the documented address and under 0.0.0.0/0, the request is
  #   answered 301.
  test "endpoint: under 0.0.0.0/0 with PHX_FORCE_SSL a client's plain-HTTP request is still redirected" do
    Application.put_env(:portfolixir, :force_ssl, RuntimeConfig.force_ssl_opts("true", nil))

    request = fn ->
      %{build_conn() | remote_ip: @peer}
      |> put_req_header("x-forwarded-proto", "https")
      |> get("/login")
    end

    use_proxies(@documented)
    control = request.()
    assert control.status == 301
    assert get_resp_header(control, "strict-transport-security") == []

    use_proxies("0.0.0.0/0")
    response = request.()

    assert response.status == 301,
           "status #{response.status}, HSTS #{inspect(get_resp_header(response, "strict-transport-security"))}: " <>
             "the client's own X-Forwarded-Proto was believed over plain HTTP"
  end

  # User story (security review 2026-10-12, H04):
  # As the operator,
  # I want a catch-all for both families never to make a forwarded hop the
  # source,
  # so that the walk over X-Forwarded-For falls back to the peer.
  #
  # Acceptance criteria:
  # - Under 0.0.0.0/0 plus ::/0, and under 0.0.0.0/0 alone for an IPv4 hop,
  #   the source stays the connecting peer.
  test "under 0.0.0.0/0 plus ::/0 no forwarded hop becomes the source" do
    use_proxies("0.0.0.0/0, ::/0")

    for forwarded <- [
          "198.51.100.9",
          "2001:db8::1234",
          "198.51.100.9, 2001:db8::99",
          "not-an-address"
        ] do
      conn = TrustedProxy.call(direct_request([{"x-forwarded-for", forwarded}]), [])
      assert conn.remote_ip == @peer, "#{inspect(forwarded)} -> #{inspect(conn.remote_ip)}"
    end

    use_proxies("0.0.0.0/0")
    conn = TrustedProxy.call(direct_request([{"x-forwarded-for", "198.51.100.9"}]), [])
    assert conn.remote_ip == @peer
  end
end
