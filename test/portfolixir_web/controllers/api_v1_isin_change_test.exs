defmodule PortfolixirWeb.ApiV1IsinChangeTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp post_json(conn, path, body) do
    conn |> api_conn() |> post(path, Jason.encode!(body))
  end

  defp create_security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: "Example AG", currency_code: "EUR"}, attrs)
      )

    security
  end

  # User story:
  # As an API/MCP operator whose security got a new ISIN through a corporate
  # action,
  # I want to record the ISIN change over the JSON API (AR-11 parity),
  # so that future imports keep matching the security via its former ISIN.
  #
  # Acceptance criteria:
  # - POST /api/v1/securities/:id/isin-change records the change and returns
  #   the updated security including its identifier aliases.
  # - Guard violations (A->A, collisions) return 422 with named errors.
  # - The write is journaled under the API-token actor.
  test "records an ISIN change over the API", %{conn: conn} do
    security = create_security!(%{isin: "DE0001234567"})

    response =
      conn
      |> post_json("/api/v1/securities/#{security.id}/isin-change", %{
        "isin_change" => %{
          "new_isin" => "de0007654321",
          "changed_on" => "2026-07-01",
          "note" => "merger rename"
        }
      })
      |> json_response(200)

    assert response["data"]["isin"] == "DE0007654321"

    assert [alias_row] = response["data"]["identifier_aliases"]
    assert alias_row["former_isin"] == "DE0001234567"
    assert alias_row["changed_on"] == "2026-07-01"
    assert alias_row["note"] == "merger rename"

    assert [entry] =
             Journal.list_entries(
               resource_type: "security_identifier_alias",
               operation: :create
             )

    assert entry.actor_type == :api_token_rw
  end

  test "rejects an A->A change with 422", %{conn: conn} do
    security = create_security!(%{isin: "DE0001234567"})

    response =
      conn
      |> post_json("/api/v1/securities/#{security.id}/isin-change", %{
        "isin_change" => %{"new_isin" => "DE0001234567"}
      })
      |> json_response(422)

    assert %{"new_isin" => [_ | _]} = response["errors"]
  end

  test "rejects a collision with another security's live ISIN, naming it", %{conn: conn} do
    _other = create_security!(%{name: "Other AG", isin: "DE0009999999"})
    security = create_security!(%{isin: "DE0001234567"})

    response =
      conn
      |> post_json("/api/v1/securities/#{security.id}/isin-change", %{
        "isin_change" => %{"new_isin" => "DE0009999999"}
      })
      |> json_response(422)

    assert [message | _] = response["errors"]["new_isin"]
    assert message =~ "Other AG"
  end

  test "rejects an invalid changed_on date with 422", %{conn: conn} do
    security = create_security!(%{isin: "DE0001234567"})

    response =
      conn
      |> post_json("/api/v1/securities/#{security.id}/isin-change", %{
        "isin_change" => %{"new_isin" => "DE0007654321", "changed_on" => "not-a-date"}
      })
      |> json_response(422)

    assert %{"changed_on" => [_ | _]} = response["errors"]
  end

  test "returns 404 for an unknown security", %{conn: conn} do
    response =
      conn
      |> post_json("/api/v1/securities/999999/isin-change", %{
        "isin_change" => %{"new_isin" => "DE0007654321"}
      })
      |> json_response(404)

    assert response["errors"]["detail"] == "not found"
  end

  # User story:
  # As an API/MCP operator,
  # I want the security detail to list its identifier aliases and a journaled
  # alias delete endpoint (AR-11 parity, ADR-0029 §3 correctability),
  # so that recorded ISIN changes stay visible and correctable over the API.
  #
  # Acceptance criteria:
  # - GET /api/v1/securities/:id carries the identifier_aliases list.
  # - DELETE /api/v1/securities/:security_id/identifier_aliases/:id removes
  #   the alias, journaled, and returns 204.
  test "lists aliases on the security detail and deletes one", %{conn: conn} do
    security = create_security!(%{isin: "DE0001234567"})

    {:ok, %{alias: alias_row}} =
      Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654321")

    detail =
      conn
      |> api_conn()
      |> get("/api/v1/securities/#{security.id}")
      |> json_response(200)

    assert [listed] = detail["data"]["identifier_aliases"]
    assert listed["id"] == alias_row.id
    assert listed["former_isin"] == "DE0001234567"

    conn =
      build_conn()
      |> api_conn()
      |> delete("/api/v1/securities/#{security.id}/identifier_aliases/#{alias_row.id}")

    assert response(conn, 204)
    assert Catalog.list_identifier_aliases(security) == []

    assert [entry] =
             Journal.list_entries(
               resource_type: "security_identifier_alias",
               operation: :delete
             )

    assert entry.actor_type == :api_token_rw
  end

  test "alias delete returns 404 for an alias of another security", %{conn: conn} do
    security = create_security!(%{isin: "DE0001234567"})
    other = create_security!(%{name: "Other AG", isin: "DE0009999999"})

    {:ok, %{alias: alias_row}} =
      Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654321")

    response =
      conn
      |> api_conn()
      |> delete("/api/v1/securities/#{other.id}/identifier_aliases/#{alias_row.id}")
      |> json_response(404)

    assert response["errors"]["detail"] == "not found"
  end
end
