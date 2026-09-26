defmodule PortfolixirWeb.StaticHeadersTest do
  # Issue #763: Plug.Static runs ahead of the router, so the browser pipeline's
  # secure headers never reached a stored logo or the stylesheet.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog.LogoStore

  # A 1x1 PNG, the smallest body the logo route serves.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
       )

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

  # User story (E25 S7, F07):
  # As an operator with the UI open in one tab,
  # I want my stored logos and the app's own assets to refuse being embedded
  # by another site,
  # so that a page elsewhere cannot probe which companies I hold by loading
  # their logos from my instance.
  #
  # Acceptance criteria:
  # - Every static asset (the stylesheet, the icons, the vendored scripts)
  #   carries cross-origin-resource-policy: same-origin.
  # - A stored logo, served by the route behind the UI login, carries it too,
  #   as does every page the browser pipeline answers.
  test "static assets, stored logos and pages carry cross-origin-resource-policy: same-origin",
       %{conn: conn} do
    assets = ~w(/app.css /favicon.svg /vendor/phoenix.min.js /vendor/phoenix_live_view.min.js)

    for path <- assets do
      response = get(conn, path)
      assert response.status == 200, path
      assert get_resp_header(response, "cross-origin-resource-policy") == ["same-origin"], path
    end

    file = write_logo!()
    logo = get(conn, "/security_logos/#{file}")
    assert logo.status == 200
    assert get_resp_header(logo, "cross-origin-resource-policy") == ["same-origin"]

    page = get(conn, "/login")
    assert get_resp_header(page, "cross-origin-resource-policy") == ["same-origin"]
  end

  # User story (E25 S7, F07; closing-act finding SR-1):
  # As an operator relying on SECURITY.md's word that every browser response
  # carries a Content-Security-Policy and Cross-Origin-Resource-Policy,
  # I want the responses the router never builds — the error page of an
  # unknown path, the refusal of a foreign Host, the answer to a body the
  # parser refuses — to carry them too,
  # so that the claim holds for every response rather than every routed one.
  #
  # Acceptance criteria:
  # - An unknown path answers 404 with cross-origin-resource-policy
  #   same-origin and the static content-security-policy.
  # - A request under a foreign Host answers 421 with both.
  # - A malformed JSON body answers 400 with both; asked for JSON, with the
  #   resource policy and no browser policy, as every JSON answer.
  # - A page keeps its per-request policy: the nonce, not the static text.
  test "every response carries the resource policy and a content-security-policy",
       %{conn: conn} do
    static = PortfolixirWeb.ContentSecurityPolicy.static_policy()

    unknown = conn |> put_req_header("accept", "text/html") |> get("/no/such/page")
    assert unknown.status == 404
    assert_default_headers(unknown.resp_headers, static)

    foreign = get(%{conn | host: "foreign.example"}, "/login")
    assert foreign.status == 421
    assert_default_headers(foreign.resp_headers, static)

    {400, headers, _body} =
      assert_error_sent(400, fn ->
        conn
        |> put_req_header("accept", "text/html")
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/portfolios", "{not json")
      end)

    assert_default_headers(headers, static)

    # The JSON API keeps no browser policy, its error answers included; the
    # resource policy it carries too.
    {400, headers, _body} =
      assert_error_sent(400, fn ->
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/portfolios", "{not json")
      end)

    assert {"cross-origin-resource-policy", "same-origin"} in headers
    refute List.keymember?(headers, "content-security-policy", 0)

    [page_policy] = conn |> get("/login") |> get_resp_header("content-security-policy")
    assert page_policy =~ "'nonce-"
  end

  defp assert_default_headers(headers, static) do
    assert {"cross-origin-resource-policy", "same-origin"} in headers
    assert {"content-security-policy", static} in headers
  end

  defp write_logo! do
    dir = LogoStore.storage_dir()
    File.mkdir_p!(dir)
    file = "#{System.unique_integer([:positive])}.png"
    path = Path.join(dir, file)
    File.write!(path, @png)
    on_exit(fn -> File.rm(path) end)
    file
  end
end
