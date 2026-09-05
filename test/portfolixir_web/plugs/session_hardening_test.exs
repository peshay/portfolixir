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
    assert RuntimeConfig.force_ssl_opts(nil) == false
    assert RuntimeConfig.force_ssl_opts("false") == false

    assert [rewrite_on: [:x_forwarded_proto], hsts: true] = RuntimeConfig.force_ssl_opts("true")
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
