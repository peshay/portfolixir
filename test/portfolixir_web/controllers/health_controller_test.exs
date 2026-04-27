defmodule PortfolixirWeb.HealthControllerTest do
  use PortfolixirWeb.ConnCase

  test "GET /health returns ok", %{conn: conn} do
    conn = get(conn, "/health")

    assert %{"status" => "ok"} = json_response(conn, 200)
    assert response_content_type(conn, :json)
  end
end
