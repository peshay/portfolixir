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

  # User story (E25 S7, G26 on the ADR-0050 merges):
  # As an operator who gives each agent or script its own API token,
  # I want a lifecycle merge recorded under the name of the token that
  # applied it — on its merge record and on every journal entry it wrote,
  # so that the audit read of a destructive write says which credential made
  # it, like every other write.
  #
  # Acceptance criteria:
  # - POST /api/v1/cash_accounts/:id/merge and /securities/:id/merge answer a
  #   merge record with actor_type api_token_rw and actor_label the name of
  #   the entry the presented token matched, whatever the request says.
  # - GET /api/v1/merges lists each record under that name.
  # - The journal entries the merge wrote (the moved booking, the deleted
  #   source) carry the same name.
  test "a merge records the name of the token it was applied with", %{conn: conn} do
    {:ok, portfolio} =
      Portfolixir.Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Named merges",
        base_currency_code: "EUR"
      })

    target = cash!(portfolio, "Savings")
    source = cash!(portfolio, "Savings (old)")

    {:ok, deposit} =
      Portfolixir.Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: source.id,
        type: "deposit",
        date: ~D[2025-01-02],
        gross_amount: "100.00",
        currency_code: "EUR"
      })

    cash_record =
      merge!(conn, @scripts_token, "/api/v1/cash_accounts/#{source.id}", target.id)

    assert %{"actor_type" => "api_token_rw", "actor_label" => "scripts"} = cash_record

    kept = create_security(conn, @default_token, "Named Merge Fund", "XS00EXTGTF03")
    gone = create_security(conn, @default_token, "Named Merge Fund (duplicate)", "XS00EXSRCE01")

    security_record =
      conn
      |> put_req_header("x-actor-label", "operator")
      |> merge!(@agent_token, "/api/v1/securities/#{gone}", kept, %{
        identity_choice: "keep_target_isin"
      })

    assert %{"actor_type" => "api_token_rw", "actor_label" => "mcp"} = security_record

    listed =
      conn
      |> api_conn(@default_token)
      |> get("/api/v1/merges")
      |> json_response(200)
      |> Map.fetch!("data")
      |> Map.new(&{&1["id"], &1["actor_label"]})

    assert listed == %{cash_record["id"] => "scripts", security_record["id"] => "mcp"}

    assert %{"actor_label" => "scripts"} =
             journal_entry(conn, "transaction", deposit.id, "update")

    assert %{"actor_label" => "scripts"} =
             journal_entry(conn, "cash_account", source.id, "delete")

    assert %{"actor_label" => "mcp"} = journal_entry(conn, "security", gone, "delete")
  end

  defp cash!(portfolio, name) do
    {:ok, cash} =
      Portfolixir.Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end

  defp create_security(conn, token, name, isin) do
    conn
    |> api_conn(token)
    |> post(
      "/api/v1/securities",
      Jason.encode!(%{security: %{name: name, currency_code: "EUR", isin: isin}})
    )
    |> json_response(201)
    |> get_in(["data", "id"])
  end

  # The preview under the default token, the apply under `token`.
  defp merge!(conn, token, source_path, target_id, choices \\ %{}) do
    preview =
      conn
      |> api_conn(@default_token)
      |> get(source_path <> "/merge_preview?target_id=#{target_id}")
      |> json_response(200)
      |> Map.fetch!("data")

    body = Map.merge(%{target_id: target_id, plan_digest: preview["plan_digest"]}, choices)

    conn
    |> api_conn(token)
    |> post(source_path <> "/merge", Jason.encode!(body))
    |> json_response(201)
    |> Map.fetch!("data")
  end

  defp journal_entry(conn, resource_type, id, operation) do
    conn
    |> api_conn(@default_token)
    |> get("/api/v1/journal", %{
      "resource_type" => resource_type,
      "resource_id" => to_string(id)
    })
    |> json_response(200)
    |> Map.fetch!("data")
    |> Enum.find(&(&1["operation"] == operation))
  end
end
