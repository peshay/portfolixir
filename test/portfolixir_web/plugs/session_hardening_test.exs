defmodule PortfolixirWeb.SessionHardeningTest do
  # Issue #759 (ADR-0045 §2): the session cookie's attributes, the derived
  # signing salts, and the opt-in TLS posture behind a reverse proxy.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.RuntimeConfig

  # User story:
  # As an operator running Portfolixir behind a TLS-terminating reverse proxy,
  # I want the session cookie to carry SameSite, HttpOnly and — over TLS — Secure,
  # so that the session that will carry the UI login cannot be replayed cross-site or over plain HTTP.
  #
  # Acceptance criteria:
  # - Every browser response sets the session cookie with SameSite=Lax and HttpOnly.
  # - Behind a proxy that sets x-forwarded-proto: https the cookie is also Secure.
  # - Over plain HTTP (no proxy header) the cookie is not Secure, so a loopback
  #   instance without TLS keeps working.
  test "the session cookie carries SameSite=Lax and HttpOnly", %{conn: conn} do
    cookie = session_cookie(get(conn, "/"))

    assert cookie =~ ~r/samesite=lax/i
    assert cookie =~ ~r/httponly/i
    refute cookie =~ ~r/;\s*secure/i
  end

  test "the session cookie is Secure behind a proxy that forwards https", %{conn: conn} do
    cookie =
      conn
      |> put_req_header("x-forwarded-proto", "https")
      |> get("/")
      |> session_cookie()

    assert cookie =~ ~r/;\s*secure/i
  end

  # User story (E25 S1, F09):
  # As an operator behind a reverse proxy,
  # I want x-forwarded-proto believed only from loopback or from a proxy I named,
  # so that the scheme follows the same trust rule as the forwarded address.
  #
  # Acceptance criteria:
  # - An untrusted peer's forwarded-proto header leaves the scheme http: the
  #   cookie is not Secure, and with force_ssl on the request is redirected.
  # - A loopback proxy still gets Secure cookies.
  # - A named proxy is judged by the address it connects from, before the
  #   forwarded-for rewrite names the client behind it.
  test "x-forwarded-proto is believed only from loopback or a trusted proxy", %{conn: conn} do
    previous_proxies = Application.get_env(:portfolixir, :trusted_proxies)
    previous_ssl = Application.get_env(:portfolixir, :force_ssl)

    on_exit(fn ->
      Application.put_env(:portfolixir, :trusted_proxies, previous_proxies)
      Application.put_env(:portfolixir, :force_ssl, previous_ssl)
    end)

    Application.put_env(:portfolixir, :trusted_proxies, [{{172, 16, 0, 0}, 12}])

    untrusted =
      %{conn | remote_ip: {192, 168, 1, 50}}
      |> put_req_header("x-forwarded-proto", "https")
      |> get("/")

    refute session_cookie(untrusted) =~ ~r/;\s*secure/i

    loopback = conn |> put_req_header("x-forwarded-proto", "https") |> get("/")
    assert session_cookie(loopback) =~ ~r/;\s*secure/i

    proxied =
      %{conn | remote_ip: {172, 18, 0, 1}}
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-for", "203.0.113.5")
      |> get("/")

    assert session_cookie(proxied) =~ ~r/;\s*secure/i

    Application.put_env(:portfolixir, :force_ssl, RuntimeConfig.force_ssl_opts("true"))

    redirected =
      %{conn | remote_ip: {192, 168, 1, 50}}
      |> put_req_header("x-forwarded-proto", "https")
      |> get("/health")

    assert redirected.status in [301, 302]
    assert get_resp_header(redirected, "strict-transport-security") == []
  end

  # User story:
  # As an operator,
  # I want the cookie signing salts derived from my SECRET_KEY_BASE,
  # so that no two installations share a salt printed in a public repository.
  #
  # Acceptance criteria:
  # - The derived salt is deterministic per secret and purpose, differs between
  #   purposes and secrets, and is long enough for LiveView (>= 8 bytes).
  test "salts are derived from the secret key base per purpose" do
    secret = String.duplicate("s", 64)

    assert RuntimeConfig.derived_salt(secret, "session") ==
             RuntimeConfig.derived_salt(secret, "session")

    refute RuntimeConfig.derived_salt(secret, "session") ==
             RuntimeConfig.derived_salt(secret, "live_view")

    refute RuntimeConfig.derived_salt(secret, "session") ==
             RuntimeConfig.derived_salt(String.duplicate("t", 64), "session")

    assert byte_size(RuntimeConfig.derived_salt(secret, "live_view")) >= 32
  end

  test "the endpoint's session salt is derived, not the former literal" do
    salt = PortfolixirWeb.Endpoint.session_signing_salt()

    refute salt == "change_me"

    assert salt ==
             RuntimeConfig.derived_salt(
               PortfolixirWeb.Endpoint.config(:secret_key_base),
               "session"
             )
  end

  # User story:
  # As an operator whose instance terminates TLS itself or behind a proxy,
  # I want an opt-in switch that redirects plain HTTP and sets HSTS,
  # so that the posture is one variable rather than a code change.
  #
  # Acceptance criteria:
  # - PHX_FORCE_SSL unset: no redirect, no HSTS header.
  # - PHX_FORCE_SSL true: a plain-HTTP request is redirected to https; a
  #   request forwarded as https is served with strict-transport-security.
  test "force_ssl is off unless asked for" do
    assert RuntimeConfig.force_ssl_opts(nil, nil) == false
    assert RuntimeConfig.force_ssl_opts("false", "app") == false

    assert [rewrite_on: [:x_forwarded_proto], hsts: true, exclude: ["localhost"]] =
             RuntimeConfig.force_ssl_opts("true", nil)
  end

  # User story (E25 S7, F23):
  # As an operator who turned PHX_FORCE_SSL on for the Compose deployment,
  # I want the MCP companion's plain-HTTP calls on the Compose network to reach
  # the app without a redirect,
  # so that the companion never meets a redirect it would have to follow to
  # an address it was not configured for.
  #
  # Acceptance criteria:
  # - PORTFOLIXIR_FORCE_SSL_EXCLUDED_HOSTS names hosts (comma-separated, trimmed,
  #   lower-cased, a port dropped) that force_ssl leaves on plain HTTP, beside
  #   localhost, which it always leaves (the container's own health check).
  # - A plain-HTTP request under an excluded host is served, without HSTS;
  #   the public host is still redirected.
  test "force_ssl leaves the named internal hosts on plain HTTP" do
    assert [rewrite_on: [:x_forwarded_proto], hsts: true, exclude: ["localhost", "app", "mcp"]] =
             RuntimeConfig.force_ssl_opts("true", " App:4000, ,mcp,app")
  end

  test "with force_ssl on, an excluded internal host is served while the public one redirects",
       %{conn: conn} do
    previous = Application.get_env(:portfolixir, :force_ssl)
    previous_hosts = Application.get_env(:portfolixir, PortfolixirWeb.HostGuard)
    Application.put_env(:portfolixir, :force_ssl, RuntimeConfig.force_ssl_opts("true", "app"))

    Application.put_env(:portfolixir, PortfolixirWeb.HostGuard,
      hosts: ["app" | Keyword.fetch!(previous_hosts, :hosts)]
    )

    on_exit(fn ->
      Application.put_env(:portfolixir, :force_ssl, previous)
      Application.put_env(:portfolixir, PortfolixirWeb.HostGuard, previous_hosts)
    end)

    internal = get(%{conn | host: "app"}, "/health")
    assert internal.status == 200
    assert get_resp_header(internal, "strict-transport-security") == []

    public = get(conn, "/health")
    assert public.status in [301, 302]
    assert [location] = get_resp_header(public, "location")
    assert location =~ ~r{^https://www\.example\.com}
  end

  test "with force_ssl on, plain HTTP redirects and forwarded https gets HSTS", %{conn: conn} do
    previous = Application.get_env(:portfolixir, :force_ssl)
    Application.put_env(:portfolixir, :force_ssl, RuntimeConfig.force_ssl_opts("true"))
    on_exit(fn -> Application.put_env(:portfolixir, :force_ssl, previous) end)

    redirected = get(conn, "/health")
    assert redirected.status in [301, 302]
    assert [location] = get_resp_header(redirected, "location")
    assert location =~ ~r{^https://}

    served =
      conn
      |> put_req_header("x-forwarded-proto", "https")
      |> get("/health")

    assert served.status == 200
    assert [hsts] = get_resp_header(served, "strict-transport-security")
    assert hsts =~ "max-age="
  end

  test "with force_ssl off, plain HTTP is served without HSTS", %{conn: conn} do
    served = get(conn, "/health")

    assert served.status == 200
    assert get_resp_header(served, "strict-transport-security") == []
  end

  defp session_cookie(conn) do
    conn
    |> get_resp_header("set-cookie")
    |> Enum.find(&String.starts_with?(&1, "_portfolixir_key="))
    |> then(fn cookie ->
      assert cookie, "expected the session cookie to be set"
      cookie
    end)
  end
end
