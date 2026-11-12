defmodule PortfolixirWeb.ApiV1ChainsTest do
  # ADR-0059 §8, §11 (Sprint 29, H6, FR-58): GET /api/v1/chains and
  # POST /api/v1/chains/:chain/refresh. Every chain answer is synthetic
  # (Portfolixir.EsploraFixtures); no test touches the network. The
  # ten-minute throttle is read to the second with an injected clock in
  # test/portfolixir/chains/chains_test.exs; here the stored last try is set
  # three minutes before the request, so retry_after lies within a few
  # seconds of 420.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.EsploraFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Chains.ChainRead
  alias Portfolixir.Repo

  @tip 870_000

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp bound!(chain) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Chain Coin #{System.unique_integer([:positive])}",
        currency_code: "USD",
        asset_class: "crypto"
      })

    {:ok, bound} =
      Catalog.update_security(Actor.api_token_rw("synthetic-agent"), security, %{
        halving_chain: chain
      })

    bound
  end

  # User story (ADR-0059 §8, §11):
  # As the operator's agent,
  # I want the registered chains with their constants, and Bitcoin's health
  # and estimate inputs, over the API,
  # so that I see whether the halvings I read are current.
  #
  # Acceptance criteria:
  # - 401 without the token, on both routes.
  # - 200 lists bitcoin, bitcoin_cash and litecoin with their constants;
  #   the chains without a source carry health, next_halving_inputs and
  #   refresh as null.
  # - After a run, bitcoin's health names the host and its times as ISO 8601
  #   UTC, stale false, the inputs with mean_block_seconds a decimal string.
  # - A query parameter is refused with 422 naming it.
  test "GET /api/v1/chains lists the registry with Bitcoin's health", %{conn: conn} do
    assert build_conn() |> get("/api/v1/chains") |> json_response(401)
    assert build_conn() |> post("/api/v1/chains/bitcoin/refresh") |> json_response(401)

    bound!(:bitcoin)
    serve(%{"mempool.space" => {:chain, @tip}})

    assert %{"data" => %{"run" => %{"status" => "ok"}}} =
             conn |> post("/api/v1/chains/bitcoin/refresh") |> json_response(200)

    %{"data" => chains} = conn |> get("/api/v1/chains") |> json_response(200)
    assert Enum.map(chains, & &1["chain"]) == ["bitcoin", "bitcoin_cash", "litecoin"]

    assert %{
             "halving_interval" => 840_000,
             "target_spacing_seconds" => 150,
             "has_source" => false,
             "bound_securities" => 0,
             "health" => nil,
             "next_halving_inputs" => nil,
             "refresh" => nil
           } = List.last(chains)

    bitcoin = hd(chains)
    assert {bitcoin["has_source"], bitcoin["bound_securities"]} == {true, 1}

    assert %{
             "source_host" => "mempool.space",
             "last_error" => nil,
             "stale" => false,
             "last_tried_at" => tried,
             "last_ok_at" => tried
           } = bitcoin["health"]

    assert {:ok, _at, 0} = DateTime.from_iso8601(tried)

    assert bitcoin["next_halving_inputs"] == %{
             "tip_height" => @tip,
             "tip_at" => timestamp(@tip) |> DateTime.from_unix!() |> DateTime.to_iso8601(),
             "tip_2016_at" =>
               timestamp(@tip - 2016) |> DateTime.from_unix!() |> DateTime.to_iso8601(),
             "period_blocks" => 2016,
             "mean_block_seconds" => "600"
           }

    assert %{"interval_seconds" => 600, "available_at" => available} = bitcoin["refresh"]
    assert is_binary(available)

    assert %{"errors" => %{"limit" => [message]}} =
             conn |> get("/api/v1/chains?limit=5") |> json_response(422)

    assert message =~ "no parameters"
  end

  # User story (ADR-0059 §11):
  # As the operator's agent asking for a fresh read of Bitcoin,
  # I want an on-demand run that answers with the health, refused politely
  # within ten minutes of the last one,
  # so that I can refresh without ever hammering a public host.
  #
  # Acceptance criteria:
  # - 200: the run (status ok, host, tip, securities) beside the chain's
  #   entry.
  # - Within ten minutes of the last try: 429 with errors.retry_after, the
  #   seconds left, and the Retry-After header the same; no host is asked.
  # - A chain without a source: 422 errors.code no_source naming the chain;
  #   an unregistered chain: 404; a parameter or body field: 422 naming it,
  #   before anything runs.
  test "POST /api/v1/chains/:chain/refresh runs once per ten minutes", %{conn: conn} do
    bound!(:bitcoin)
    serve(%{"mempool.space" => {:chain, @tip}})

    assert %{"data" => data} =
             conn |> post("/api/v1/chains/bitcoin/refresh") |> json_response(200)

    assert data["run"] == %{
             "status" => "ok",
             "host" => "mempool.space",
             "tip" => @tip,
             "securities" => 1
           }

    assert data["chain"] == "bitcoin"
    assert data["health"]["source_host"] == "mempool.space"

    refused = post(conn, "/api/v1/chains/bitcoin/refresh")

    assert %{"errors" => %{"retry_after" => seconds, "detail" => detail}} =
             json_response(refused, 429)

    assert seconds in 595..600
    assert get_resp_header(refused, "retry-after") == [Integer.to_string(seconds)]
    assert detail =~ "10 minutes"
  end

  test "a stored try three minutes ago leaves about seven minutes", %{conn: conn} do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%ChainRead{
      chain: "bitcoin",
      last_tried_at: DateTime.add(now, -180),
      inserted_at: now,
      updated_at: now
    })

    conn = post(conn, "/api/v1/chains/bitcoin/refresh")
    assert %{"errors" => %{"retry_after" => seconds}} = json_response(conn, 429)
    assert seconds in 410..420
    refute_received {:esplora, _host, _path}
  end

  test "no source, an unknown chain and a parameter are refused before anything runs",
       %{conn: conn} do
    bound!(:litecoin)

    for chain <- ["litecoin", "bitcoin_cash"] do
      assert %{"errors" => %{"code" => "no_source", "chain" => ^chain, "detail" => detail}} =
               conn |> post("/api/v1/chains/#{chain}/refresh") |> json_response(422)

      assert detail =~ "no source"
    end

    assert %{"errors" => %{"detail" => "not found"}} =
             conn |> post("/api/v1/chains/dogecoin/refresh") |> json_response(404)

    assert %{"errors" => %{"force" => [_]}} =
             conn |> post("/api/v1/chains/bitcoin/refresh?force=true") |> json_response(422)

    assert %{"errors" => %{"chain" => [_]}} =
             conn
             |> post("/api/v1/chains/bitcoin/refresh", %{"chain" => "litecoin"})
             |> json_response(422)

    refute_received {:esplora, _host, _path}
  end
end
