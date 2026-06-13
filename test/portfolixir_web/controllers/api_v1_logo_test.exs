defmodule PortfolixirWeb.ApiV1LogoTest do
  # User story:
  # As an API client (or the LiveView using it), I want to read a security's
  # logo status, set a manual logo from a URL, remove it, and trigger
  # re-discovery, so logo coverage can be managed without shell access.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog

  @auth {"authorization", "Bearer test-api-token"}

  # 1x1 PNG
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp png_stub do
    [
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/png")
        |> Plug.Conn.send_resp(200, @png)
      end
    ]
  end

  setup do
    prior = Application.get_env(:portfolixir, :logo_discovery_opts, [])

    tmp =
      Path.join(System.tmp_dir!(), "portfolixir-logo-api-#{System.unique_integer([:positive])}")

    Application.put_env(:portfolixir, :logo_discovery_opts, req: png_stub(), storage_dir: tmp)

    on_exit(fn ->
      Application.put_env(:portfolixir, :logo_discovery_opts, prior)
      File.rm_rf(tmp)
    end)

    {:ok, security} =
      Catalog.create_security(%{
        name: "Baozun Inc.",
        currency_code: "USD",
        provider: "manual",
        asset_class: "equity"
      })

    %{security: security}
  end

  test "GET reports an empty logo status before anything is set", %{
    conn: conn,
    security: security
  } do
    conn = conn |> api_conn() |> get("/api/v1/securities/#{security.id}/logo")

    assert %{
             "data" => %{
               "security_id" => _,
               "has_logo" => false,
               "locked" => false,
               "path" => nil,
               "source" => nil
             }
           } = json_response(conn, 200)
  end

  test "PUT with a URL sets a manual, locked logo", %{conn: conn, security: security} do
    conn =
      conn
      |> api_conn()
      |> put(
        "/api/v1/securities/#{security.id}/logo",
        Jason.encode!(%{"logo" => %{"url" => "https://example.test/logo.png"}})
      )

    assert %{
             "data" => %{
               "has_logo" => true,
               "locked" => true,
               "source" => "manual"
             }
           } = json_response(conn, 200)

    assert Catalog.get_security!(security.id).attributes["logo_source"] == "manual"
  end

  test "PUT without a URL is rejected", %{conn: conn, security: security} do
    conn =
      conn
      |> api_conn()
      |> put("/api/v1/securities/#{security.id}/logo", Jason.encode!(%{"logo" => %{}}))

    assert %{"errors" => %{"url" => _}} = json_response(conn, 422)
  end

  test "DELETE removes the logo and locks the no-logo choice", %{
    conn: conn,
    security: security
  } do
    {:ok, _} =
      Catalog.set_logo_override(
        security,
        "https://example.test/logo.png",
        Application.get_env(:portfolixir, :logo_discovery_opts, [])
      )

    conn = conn |> api_conn() |> delete("/api/v1/securities/#{security.id}/logo")

    assert %{"data" => %{"has_logo" => false, "locked" => true}} = json_response(conn, 200)
  end

  test "GET on an unknown security id is 404", %{conn: conn} do
    conn = conn |> api_conn() |> get("/api/v1/securities/0/logo")
    assert json_response(conn, 404) == %{"errors" => %{"detail" => "not found"}}
  end

  test "POST .../logo/discover runs discovery and reports a result", %{
    conn: conn,
    security: security
  } do
    conn = conn |> api_conn() |> post("/api/v1/securities/#{security.id}/logo/discover")

    assert %{"data" => %{"security_id" => _, "result" => result}} = json_response(conn, 200)
    assert result in ["updated", "no_source", "failed"]
  end

  test "PUT with an unsupported image type is rejected", %{conn: conn, security: security} do
    html_stub = [
      plug: fn c ->
        c
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<html/>")
      end
    ]

    Application.put_env(:portfolixir, :logo_discovery_opts, req: html_stub)

    conn =
      conn
      |> api_conn()
      |> put(
        "/api/v1/securities/#{security.id}/logo",
        Jason.encode!(%{"logo" => %{"url" => "https://example.test/page.html"}})
      )

    assert %{"errors" => %{"logo" => [_ | _]}} = json_response(conn, 422)
  end
end
