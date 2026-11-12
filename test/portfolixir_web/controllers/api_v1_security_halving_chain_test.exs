defmodule PortfolixirWeb.ApiV1SecurityHalvingChainTest do
  # ADR-0059 §4, §11 (Sprint 29 H1, FR-58): a security's halving_chain over
  # the securities routes. The MCP tool is portfolixir.securities.update.
  # Every name and identifier is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Lifecycle

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp security!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: "EUR",
        asset_class: "crypto"
      })

    security
  end

  defp patch_security(conn, id, security),
    do: patch(conn, "/api/v1/securities/#{id}", Jason.encode!(%{"security" => security}))

  # User story (ADR-0059 §4, §11):
  # As the agent that knows which chain a coin lives on,
  # I want to bind a security to a registered chain with securities.update,
  # read the binding back on every security read, and clear it with null,
  # so that the operator's screen and my reads agree on what is bound.
  #
  # Acceptance criteria:
  # - PATCH with halving_chain "bitcoin" answers 200 with data.halving_chain
  #   "bitcoin"; GET /securities/:id and ?fields=halving_chain read it.
  # - An unknown chain ("zcash", a number) answers 422 naming halving_chain
  #   and writes nothing; null clears it.
  # - A security a merge took away is refused naming merged_into.
  test "binds, reads, refuses and clears a halving chain", %{conn: conn} do
    security = security!("Coin API H1")

    assert %{"data" => %{"halving_chain" => nil}} =
             conn |> get("/api/v1/securities/#{security.id}") |> json_response(200)

    assert %{"data" => %{"halving_chain" => "bitcoin"}} =
             conn
             |> patch_security(security.id, %{"halving_chain" => "bitcoin"})
             |> json_response(200)

    assert %{"data" => %{"halving_chain" => "bitcoin"}} =
             conn |> get("/api/v1/securities/#{security.id}") |> json_response(200)

    assert %{"data" => rows} =
             conn
             |> get("/api/v1/securities?fields=id,halving_chain")
             |> json_response(200)

    assert %{"id" => security.id, "halving_chain" => "bitcoin"} in rows

    for bad <- ["zcash", "Bitcoin", 7] do
      assert %{"errors" => %{"halving_chain" => [_ | _]}} =
               conn
               |> patch_security(security.id, %{"halving_chain" => bad})
               |> json_response(422)
    end

    assert Catalog.get_security(security.id).halving_chain == :bitcoin

    assert %{"data" => %{"halving_chain" => nil}} =
             conn |> patch_security(security.id, %{"halving_chain" => nil}) |> json_response(200)
  end

  test "a security a merge took away is refused naming merged_into", %{conn: conn} do
    source = security!("Coin Twin H1")
    target = security!("Coin Twin H1")
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.owner_ui(), source.id, target.id, %{
        plan_digest: preview.plan_digest
      })

    assert %{"errors" => %{"merged_into" => %{"kind" => "security", "id" => target_id}}} =
             conn
             |> patch_security(source.id, %{"halving_chain" => "bitcoin"})
             |> json_response(404)

    assert target_id == target.id
  end
end
