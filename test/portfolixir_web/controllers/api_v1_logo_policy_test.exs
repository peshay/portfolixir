defmodule PortfolixirWeb.ApiV1LogoPolicyTest do
  # Issue #762 over the API: the manual logo endpoint is the one place a
  # caller hands the server a URL, so its refusal is generic — no address,
  # no transport error, no struct — and its policy is the store's.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog

  setup %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Synthetic Corp.",
        currency_code: "EUR",
        provider: "manual",
        asset_class: "equity"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn, security: security}
  end

  # User story:
  # As an operator whose agent can call the logo endpoint,
  # I want a URL inside my network refused with a generic message,
  # so that the endpoint is neither a way in nor an oracle for what is there.
  #
  # Acceptance criteria:
  # - A private-address or plain-http URL returns 422 with a fixed message.
  # - The message carries no host, address, status or inspected term.
  test "refuses a non-public logo URL with a generic message", %{conn: conn, security: security} do
    for url <- [
          "https://internal.test/logo.png",
          "http://example.test/logo.png",
          "https://meta.test/x"
        ] do
      conn = put(conn, "/api/v1/securities/#{security.id}/logo", %{"url" => url})

      assert %{"errors" => %{"logo" => [message]}} = json_response(conn, 422)
      assert message == "image URL not allowed: use a public https address"
    end
  end

  test "a transport failure is reported without the internal reason", %{
    conn: conn,
    security: security
  } do
    previous = Application.get_env(:portfolixir, :logo_discovery_opts, [])

    Application.put_env(:portfolixir, :logo_discovery_opts,
      req: [plug: fn conn -> Req.Test.transport_error(conn, :econnrefused) end]
    )

    on_exit(fn -> Application.put_env(:portfolixir, :logo_discovery_opts, previous) end)

    conn =
      put(conn, "/api/v1/securities/#{security.id}/logo", %{
        "url" => "https://example.test/logo.png"
      })

    assert %{"errors" => %{"logo" => [message]}} = json_response(conn, 422)
    assert message == "could not download the image"
    refute message =~ "econnrefused"
  end
end
