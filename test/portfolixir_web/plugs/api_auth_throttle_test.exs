defmodule PortfolixirWeb.ApiAuthThrottleTest do
  # Issue #771: the bearer check is constant-time already; the missing piece
  # was a bound on attempts per source.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Auth.Throttle
  alias Portfolixir.RuntimeConfig

  # A token at the 32-byte floor a release holds every token to at boot
  # (`RuntimeConfig.api_tokens!/3`): the token compares first only when every
  # configured token meets it (#974).
  @sound_token String.duplicate("t", 32)

  # config/test.exs's `:api_token`, the fallback a from-source server reads
  # from PORTFOLIXIR_API_TOKEN with no floor: 14 bytes.
  @short_token "test-api-token"

  defp with_tokens(tokens) do
    previous = Application.get_env(:portfolixir, :api_tokens)
    Application.put_env(:portfolixir, :api_tokens, tokens)
    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)
  end

  defp locked_out_conn(conn) do
    source = {10, 0, 0, System.unique_integer([:positive]) |> rem(250)}
    conn = %{conn | remote_ip: source}

    Throttle.success(:api, Throttle.source_key(source))

    # The failure that reaches the threshold is itself answered 401; every
    # wrong token after it meets the lock.
    for _ <- 1..Throttle.max_failures() do
      assert conn
             |> put_req_header("authorization", "Bearer wrong")
             |> get("/api/v1/portfolios")
             |> json_response(401)
    end

    {conn, Throttle.source_key(source)}
  end

  defp request(conn, token) do
    conn |> put_req_header("authorization", "Bearer " <> token) |> get("/api/v1/portfolios")
  end

  # User story (#771; #974, the Sprint 20 plan's D-11):
  # As the operator,
  # I want a source that keeps sending wrong bearer tokens answered 429 with
  # Retry-After, each wrong token counted while it is locked,
  # so that the token cannot be guessed online without the lock growing.
  #
  # Acceptance criteria:
  # - Up to the threshold, a wrong token is 401.
  # - Past it, a wrong token is 429 with a Retry-After header, and it counts:
  #   the lock it answers with is longer than the first.
  # - Another source is unaffected.
  test "locks a source out after repeated wrong tokens, and counts each one", %{conn: conn} do
    with_tokens([{nil, @sound_token}])
    {conn, _key} = locked_out_conn(conn)

    locked = request(conn, "wrong")

    assert json_response(locked, 429) == %{
             "errors" => %{"detail" => "too many failed attempts; retry later"}
           }

    assert [retry] = get_resp_header(locked, "retry-after")
    # The wrong token past the threshold counted: the lock doubled.
    assert String.to_integer(retry) > Throttle.base_lock_seconds()

    other = %{conn | remote_ip: {10, 0, 1, 1}}

    assert other |> request(@sound_token) |> json_response(200)
  end

  # User story (#974, the Sprint 20 plan's D-11):
  # As the operator, whose host clients all reach the published port from one
  # address,
  # I want my agent's correct token to pass while that address is locked,
  # so that a stale client sending an old token after a rotation never locks
  # my agent out, while its wrong tokens stay refused.
  #
  # Acceptance criteria:
  # - While the source is locked, the right token is answered 200, when every
  #   configured token meets the 32-byte floor.
  # - The lock stays: the source is still locked, and the next wrong token
  #   from it is still 429.
  # (The floor, `RuntimeConfig.min_token_bytes/0`, is what makes a locked
  # guesser's correct guess infeasible.)
  test "a correct token passes while its source is locked, and the lock stays", %{conn: conn} do
    assert byte_size(@sound_token) == RuntimeConfig.min_token_bytes()
    with_tokens([{nil, @sound_token}])
    {conn, key} = locked_out_conn(conn)
    assert {:locked, _seconds} = Throttle.check(:api, key)

    assert conn |> request(@sound_token) |> json_response(200)

    assert {:locked, _seconds} = Throttle.check(:api, key)

    assert request(conn, "wrong").status == 429
  end

  # User story (#974, Sprint 20 γ closing act, the security lens):
  # As the operator who runs from source, where PORTFOLIXIR_API_TOKEN alone
  # is read with no length floor,
  # I want a locked source refused before its token is compared, as before
  # #974, whenever a configured token is shorter than the floor,
  # so that a short token, guessable where a 32-byte one is not, is never
  # guessed through the lock.
  #
  # Acceptance criteria:
  # - With the one configured token below `RuntimeConfig.min_token_bytes/0`,
  #   a locked source is answered 429 with Retry-After for the right token
  #   too, and the lock stays.
  # - One token of several below the floor is enough: the floor holds for
  #   every configured token, or every token meets the lock first.
  # - Another source, not locked, is answered 200 for the right token.
  test "a token below the floor does not pass a locked source", %{conn: conn} do
    assert byte_size(@short_token) < RuntimeConfig.min_token_bytes()
    {conn, key} = locked_out_conn(conn)

    locked = request(conn, @short_token)

    assert json_response(locked, 429) == %{
             "errors" => %{"detail" => "too many failed attempts; retry later"}
           }

    assert [_retry] = get_resp_header(locked, "retry-after")
    assert {:locked, _seconds} = Throttle.check(:api, key)

    assert %{conn | remote_ip: {10, 0, 1, 2}} |> request(@short_token) |> json_response(200)
  end

  test "one configured token below the floor keeps every token lock-first", %{conn: conn} do
    with_tokens([{"mcp", @sound_token}, {nil, @short_token}])
    {conn, key} = locked_out_conn(conn)

    for token <- [@sound_token, @short_token] do
      assert conn |> request(token) |> json_response(429)
    end

    assert {:locked, _seconds} = Throttle.check(:api, key)
  end
end
