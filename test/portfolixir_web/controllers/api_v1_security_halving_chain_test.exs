defmodule PortfolixirWeb.ApiV1SecurityHalvingChainTest do
  # ADR-0059 §4, §11 (Sprint 29 H1, FR-58): a security's halving_chain over
  # the securities routes. The MCP tool is portfolixir.securities.update.
  # Every name and identifier is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Knowledge.Events
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

  defp post_event(conn, security_id, event),
    do: post(conn, "/api/v1/securities/#{security_id}/events", Jason.encode!(%{"event" => event}))

  defp halving(height, extra \\ %{}) do
    Map.merge(
      %{
        "kind" => "halving",
        "chain_height" => height,
        "date" => "2019-08-05",
        "timing" => "exact",
        "confirmed" => true,
        "source_quality" => "primary"
      },
      extra
    )
  end

  # User story (ADR-0048's amendment of 2026-11-12, items 1 to 4):
  # As the agent recording a halving through the API,
  # I want a halving refused with a code that names why when the security
  # is unbound or bound to a chain the app reads itself, and stored with its
  # chain_height otherwise,
  # so that I know whether to bind first or to leave it to the chain.
  #
  # Acceptance criteria:
  # - On an unbound security: 422 errors.code "no_halving_chain".
  # - On a litecoin-bound security: 201 with kind "halving" and chain_height
  #   840000; a height that is no halving of litecoin is 422 naming
  #   chain_height.
  # - On a bitcoin-bound security: create, update and delete of a halving
  #   answer 422 errors.code "halving_from_chain" with errors.chain
  #   "bitcoin", and the stored row is unchanged.
  test "a halving over the events routes: no chain, a hand-written chain, the chain's own",
       %{conn: conn} do
    unbound = security!("Coin Unbound H1")

    assert %{"errors" => %{"code" => "no_halving_chain", "kind" => [_]}} =
             conn |> post_event(unbound.id, halving(840_000)) |> json_response(422)

    litecoin = security!("Coin Litecoin H1")

    {:ok, litecoin} =
      Catalog.update_security(Actor.owner_ui(), litecoin, %{halving_chain: :litecoin})

    assert %{"data" => %{"kind" => "halving", "chain_height" => 840_000}} =
             conn |> post_event(litecoin.id, halving(840_000)) |> json_response(201)

    assert %{"errors" => %{"chain_height" => [message]}} =
             conn |> post_event(litecoin.id, halving(420_000)) |> json_response(422)

    assert message =~ "litecoin"

    bitcoin = security!("Coin Bitcoin H1")

    {:ok, bitcoin} =
      Catalog.update_security(Actor.owner_ui(), bitcoin, %{halving_chain: :bitcoin})

    assert %{"errors" => %{"code" => "halving_from_chain", "chain" => "bitcoin"}} =
             conn |> post_event(bitcoin.id, halving(840_000)) |> json_response(422)

    {:ok, event} =
      Events.put_chain_halving(Actor.system_job("chain_read"), bitcoin.id, :bitcoin, 840_000, %{
        date: ~D[2024-04-20],
        timing: :exact,
        confirmed: true,
        source_quality: :primary
      })

    body = Jason.encode!(%{"event" => %{"note" => "by hand"}})

    assert %{"errors" => %{"code" => "halving_from_chain", "chain" => "bitcoin"}} =
             conn |> patch("/api/v1/security_events/#{event.id}", body) |> json_response(422)

    assert %{"errors" => %{"code" => "halving_from_chain", "chain" => "bitcoin"}} =
             conn |> delete("/api/v1/security_events/#{event.id}") |> json_response(422)

    assert Events.get_event(event.id) == event
  end

  # User story (ADR-0059 §4):
  # As the agent that rebinds a coin to another chain,
  # I want the answer to count the halving events the rebinding deleted,
  # so that I know what my write removed without a second read.
  #
  # Acceptance criteria:
  # - A PATCH that sends halving_chain answers halving_events_deleted beside
  #   data: 0 when the chain stays, the number deleted when it changes.
  # - A PATCH without halving_chain carries no such key.
  test "a rebinding counts the halving events it deleted", %{conn: conn} do
    security = security!("Coin Rebound H1")

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{halving_chain: :litecoin})

    for height <- [840_000, 1_680_000] do
      conn |> post_event(security.id, halving(height)) |> json_response(201)
    end

    assert %{"halving_events_deleted" => 0, "data" => %{"halving_chain" => "litecoin"}} =
             conn
             |> patch_security(security.id, %{"halving_chain" => "litecoin"})
             |> json_response(200)

    assert %{"halving_events_deleted" => 2, "data" => %{"halving_chain" => "bitcoin_cash"}} =
             conn
             |> patch_security(security.id, %{"halving_chain" => "bitcoin_cash"})
             |> json_response(200)

    refute Map.has_key?(
             conn |> patch_security(security.id, %{"note" => "Synthetic."}) |> json_response(200),
             "halving_events_deleted"
           )
  end

  # User story (ADR-0048's amendment, item 8):
  # As the agent previewing a merge of two listings of one coin,
  # I want the halvings the merge would drop listed with their height and
  # reason,
  # so that I see what goes before I apply it.
  #
  # Acceptance criteria:
  # - The merge preview's events carry dropped, each with id, kind, date,
  #   chain_height and reason ("height_held" or "chain_differs").
  test "the merge preview lists the halvings it drops", %{conn: conn} do
    source = security!("Coin Twin Drop H1")
    target = security!("Coin Twin Drop H1")

    for security <- [source, target] do
      {:ok, _} = Catalog.update_security(Actor.owner_ui(), security, %{halving_chain: :litecoin})
      conn |> post_event(security.id, halving(840_000)) |> json_response(201)
    end

    assert %{"data" => %{"events" => %{"moved" => [], "dropped" => [dropped]}}} =
             conn
             |> get("/api/v1/securities/#{source.id}/merge_preview?target_id=#{target.id}")
             |> json_response(200)

    assert %{
             "kind" => "halving",
             "date" => "2019-08-05",
             "chain_height" => 840_000,
             "reason" => "height_held"
           } = dropped
  end
end
