defmodule PortfolixirWeb.ApiV1SettingsTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Settings

  @auth {"authorization", "Bearer test-api-token"}

  defp authed(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want to read and set the default view preference,
  # so that the daily-check-in scope is scriptable and visible outside the UI
  # (ADR-0024: the default view steers the Wealth page and dashboard).
  #
  # Acceptance criteria:
  # - GET returns the current default: view_id null when unset (Everything),
  #   otherwise the id plus the view's id/name echo.
  # - PUT with a live view id persists it; PUT with view_id null clears back
  #   to Everything. No financial decimals are involved (n/a).
  # - PUT with an unknown view id returns 404 and changes nothing.
  # - PUT with a malformed view_id returns 422.
  # - Both routes require the bearer token.
  test "reads and sets the default view preference", %{conn: conn} do
    assert %{"data" => %{"view_id" => nil, "view" => nil}} =
             conn |> authed() |> get("/api/v1/settings/default_view") |> json_response(200)

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Mine"})

    assert %{"data" => %{"view_id" => view_id, "view" => %{"name" => "Mine"}}} =
             conn
             |> authed()
             |> put("/api/v1/settings/default_view", %{"view_id" => view.id})
             |> json_response(200)

    assert view_id == view.id
    assert Settings.default_view_id() == view.id

    assert %{"data" => %{"view_id" => nil, "view" => nil}} =
             conn
             |> authed()
             |> put("/api/v1/settings/default_view", %{"view_id" => nil})
             |> json_response(200)

    assert Settings.default_view_id() == nil
  end

  test "rejects unknown and malformed view ids", %{conn: conn} do
    assert conn
           |> authed()
           |> put("/api/v1/settings/default_view", %{"view_id" => 999_999})
           |> json_response(404)

    assert Settings.default_view_id() == nil

    assert conn
           |> authed()
           |> put("/api/v1/settings/default_view", %{"view_id" => "not-a-number"})
           |> json_response(422)
  end

  test "requires the bearer token", %{conn: conn} do
    assert conn
           |> put_req_header("accept", "application/json")
           |> get("/api/v1/settings/default_view")
           |> json_response(401)
  end
end
