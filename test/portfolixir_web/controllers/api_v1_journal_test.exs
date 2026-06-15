defmodule PortfolixirWeb.ApiV1JournalTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Actor
  alias Portfolixir.Catalog

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  # User story:
  # As an API or MCP client,
  # I want to list the append-only audit journal,
  # so that I can see who changed which financial record, when, and how — with a
  # self-describing response (FR-28, FR-13).

  test "requires authentication", %{conn: conn} do
    conn = get(conn, "/api/v1/journal")
    assert json_response(conn, 401)
  end

  test "lists journal entries newest-first with a self-describing meta envelope", %{conn: conn} do
    # A write through the API is attributed to the read-write API token.
    created =
      conn
      |> api_conn()
      |> post(
        "/api/v1/securities",
        Jason.encode!(%{security: %{name: "Journaled Co", currency_code: "EUR"}})
      )

    assert %{"data" => %{"id" => id}} = json_response(created, 201)

    body = conn |> api_conn() |> get("/api/v1/journal") |> json_response(200)

    assert %{"data" => [entry | _], "meta" => meta} = body
    assert entry["resource_type"] == "security"
    assert entry["operation"] == "create"
    assert entry["actor_type"] == "api_token_rw"
    assert entry["resource_id"] == to_string(id)
    assert entry["after"]["name"] == "Journaled Co"
    assert is_nil(entry["before"])

    # Self-describing (FR-13): as_of, ordering, count and applied filters.
    assert is_binary(meta["as_of"])
    assert meta["order"] == "inserted_at:desc,id:desc"
    assert meta["count"] == length(body["data"])
    assert meta["filters"]["include_scenarios"] == false
  end

  test "filters by resource_id and operation", %{conn: conn} do
    actor = Actor.owner_ui()
    {:ok, security} = Catalog.create_security(actor, %{name: "Filter Me", currency_code: "EUR"})
    {:ok, _} = Catalog.update_security(actor, security, %{name: "Filtered"})

    body =
      conn
      |> api_conn()
      |> get("/api/v1/journal", %{
        "resource_id" => to_string(security.id),
        "operation" => "update"
      })
      |> json_response(200)

    assert [entry] = body["data"]
    assert entry["operation"] == "update"
    assert entry["before"]["name"] == "Filter Me"
    assert entry["after"]["name"] == "Filtered"
    assert body["meta"]["filters"]["operation"] == "update"
    assert body["meta"]["filters"]["resource_id"] == to_string(security.id)
  end

  test "rejects an unknown operation filter with 422", %{conn: conn} do
    conn = conn |> api_conn() |> get("/api/v1/journal", %{"operation" => "frobnicate"})
    assert %{"errors" => %{"operation" => _}} = json_response(conn, 422)
  end

  test "applies and echoes the actor_type and limit filters", %{conn: conn} do
    # One write via the API (api_token_rw) and one via the context (owner_ui).
    conn
    |> api_conn()
    |> post(
      "/api/v1/securities",
      Jason.encode!(%{security: %{name: "Api Co", currency_code: "EUR"}})
    )

    {:ok, _} = Catalog.create_security(Actor.owner_ui(), %{name: "Ui Co", currency_code: "EUR"})

    body =
      conn
      |> api_conn()
      |> get("/api/v1/journal", %{"actor_type" => "owner_ui", "limit" => "1"})
      |> json_response(200)

    assert [entry] = body["data"]
    assert entry["actor_type"] == "owner_ui"
    assert body["meta"]["filters"]["actor_type"] == "owner_ui"
    assert body["meta"]["filters"]["limit"] == 1
  end

  test "rejects a non-integer limit with 422", %{conn: conn} do
    conn = conn |> api_conn() |> get("/api/v1/journal", %{"limit" => "lots"})
    assert %{"errors" => %{"limit" => _}} = json_response(conn, 422)
  end

  test "rejects an unknown actor_type filter with 422", %{conn: conn} do
    conn = conn |> api_conn() |> get("/api/v1/journal", %{"actor_type" => "ghost"})
    assert %{"errors" => %{"actor_type" => _}} = json_response(conn, 422)
  end
end
