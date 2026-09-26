defmodule PortfolixirWeb.ApiV1NamedPrincipalsTest do
  # E25 S7, G26 — the architecture's FU-6, named principals: API tokens are
  # configured as name–token pairs, and the journal's actor label is the name
  # of the entry the presented token matched, never a caller's claim.
  use PortfolixirWeb.ConnCase

  @agent_token String.duplicate("a", 40)
  @scripts_token String.duplicate("s", 40)
  @default_token String.duplicate("d", 40)

  setup do
    previous = Application.get_env(:portfolixir, :api_tokens)

    Application.put_env(:portfolixir, :api_tokens, [
      {"mcp", @agent_token},
      {"scripts", @scripts_token},
      {nil, @default_token}
    ])

    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)
    :ok
  end

  defp api_conn(conn, token) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> token)
  end

  defp create_security(conn, token, name) do
    conn
    |> api_conn(token)
    |> post("/api/v1/securities", Jason.encode!(%{security: %{name: name, currency_code: "EUR"}}))
    |> json_response(201)
    |> get_in(["data", "id"])
  end

  defp journal_entry(conn, id) do
    conn
    |> api_conn(@default_token)
    |> get("/api/v1/journal", %{"resource_type" => "security", "resource_id" => to_string(id)})
    |> json_response(200)
    |> Map.fetch!("data")
    |> hd()
  end

  # User story (E25 S7, G26):
  # As an operator who gives each agent or script its own API token,
  # I want every write journaled under the name of the token that made it,
  # so that the audit trail says which credential wrote rather than one
  # anonymous label for every write.
  #
  # Acceptance criteria:
  # - A write under the second named token journals actor_type api_token_rw
  #   and actor_label that token's name; the first named token its own name.
  # - A write under the unnamed default token (PORTFOLIXIR_API_TOKEN) journals
  #   no label, as before named tokens existed.
  # - A token no entry carries answers 401 and writes nothing.
  test "a write journals the name of the token entry it was made with", %{conn: conn} do
    scripts_id = create_security(conn, @scripts_token, "Written By Scripts")
    agent_id = create_security(conn, @agent_token, "Written By The Agent")
    default_id = create_security(conn, @default_token, "Written Unnamed")

    assert %{"actor_type" => "api_token_rw", "actor_label" => "scripts"} =
             journal_entry(conn, scripts_id)

    assert %{"actor_type" => "api_token_rw", "actor_label" => "mcp"} =
             journal_entry(conn, agent_id)

    assert %{"actor_type" => "api_token_rw", "actor_label" => nil} =
             journal_entry(conn, default_id)

    refused =
      conn
      |> api_conn(String.duplicate("x", 40))
      |> post(
        "/api/v1/securities",
        Jason.encode!(%{security: %{name: "Nobody", currency_code: "EUR"}})
      )

    assert json_response(refused, 401)
  end

  test "the label comes from the matched entry, never from the request", %{conn: conn} do
    id =
      conn
      |> put_req_header("x-actor-label", "operator")
      |> create_security(@scripts_token, "Claimed Elsewhere")

    assert %{"actor_label" => "scripts"} = journal_entry(conn, id)
  end
end
