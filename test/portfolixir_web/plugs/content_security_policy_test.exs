defmodule PortfolixirWeb.ContentSecurityPolicyTest do
  use PortfolixirWeb.ConnCase, async: true

  alias PortfolixirWeb.ContentSecurityPolicy

  # User story (#382 — Sprint 11 Lane C):
  # As the operator of a self-hosted instance,
  # I want every browser page to carry a Content-Security-Policy that allows
  # only the instance's own scripts plus the root layout's inline scripts
  # through a per-request nonce,
  # so that a script injected into a page cannot run even where some
  # rendering escaped, and the Sobelow gate runs with no ignore.
  #
  # Acceptance criteria:
  # - A browser response carries a CSP whose script-src names 'self' and a
  #   nonce, with no 'unsafe-inline' and no 'unsafe-eval' among the sources.
  # - The three inline scripts of the root layout carry that request's nonce.
  # - Two requests never share a nonce.
  # - The socket origin of the request's own host is allowed for connect-src.
  # - Phoenix's other secure headers stay.
  test "browser pages carry a nonce-bearing policy and the inline scripts use it",
       %{conn: conn} do
    response = get(conn, "/")
    [policy] = get_resp_header(response, "content-security-policy")

    assert [_, nonce] = Regex.run(~r{script-src 'self' 'nonce-([A-Za-z0-9+/=]+)'}, policy)
    refute policy =~ "unsafe-eval"
    refute Regex.match?(~r/script-src[^;]*unsafe-inline/, policy)
    assert policy =~ "default-src 'self'"
    assert policy =~ "object-src 'none'"
    assert policy =~ "base-uri 'self'"
    assert policy =~ "frame-ancestors 'self'"
    assert policy =~ "form-action 'self'"
    assert policy =~ "connect-src 'self' ws://www.example.com wss://www.example.com"

    html = html_response(response, 200)

    for id <- ~w(theme-boot live-view-client-script theme-control-script) do
      assert html =~ ~s(<script id="#{id}" nonce="#{nonce}">),
             "#{id} does not carry the request's nonce"
    end

    [other] = conn |> get("/") |> get_resp_header("content-security-policy")
    refute other == policy

    assert get_resp_header(response, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(response, "referrer-policy") == ["strict-origin-when-cross-origin"]
  end

  # User story:
  # As the operator,
  # I want the login page and the logout page to carry the same policy,
  # so that the open half of the browser surface is not the unprotected half.
  test "the open browser pipeline carries the policy too", %{conn: conn} do
    for path <- ["/login", "/logout"] do
      [policy] = conn |> get(path) |> get_resp_header("content-security-policy")
      assert policy =~ "'nonce-", path
    end
  end

  test "the JSON API is unchanged: no browser policy on a JSON response", %{conn: conn} do
    response =
      conn
      |> put_req_header("authorization", "Bearer test-api-token")
      |> get("/api/v1/portfolios")

    assert json_response(response, 200)
    assert get_resp_header(response, "content-security-policy") == []
  end

  # The pipelines' static header (what Sobelow reads) and the per-request
  # policy are the same text apart from the nonce and the socket origin, so
  # the two cannot drift.
  test "the static policy is the per-request policy without its nonce and socket origin" do
    static = ContentSecurityPolicy.static_policy()
    dynamic = ContentSecurityPolicy.policy("n0nce+/=", "example.test:4000")

    assert dynamic
           |> String.replace(" 'nonce-n0nce+/='", "")
           |> String.replace(" ws://example.test:4000 wss://example.test:4000", "") == static

    assert static =~ "script-src 'self';"
    refute static =~ "nonce"
  end

  test "a nonce is fresh, base64 and long enough per request" do
    nonces = for _ <- 1..20, do: ContentSecurityPolicy.generate_nonce()
    assert length(Enum.uniq(nonces)) == 20

    for nonce <- nonces do
      assert {:ok, bytes} = Base.decode64(nonce)
      assert byte_size(bytes) >= 16
    end
  end
end
