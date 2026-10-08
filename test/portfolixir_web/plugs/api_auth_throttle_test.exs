defmodule PortfolixirWeb.ApiAuthThrottleTest do
  # Issue #771: the bearer check is constant-time already; the missing piece
  # was a bound on attempts per source.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Auth.Throttle

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
    {conn, _key} = locked_out_conn(conn)

    locked = conn |> put_req_header("authorization", "Bearer wrong") |> get("/api/v1/portfolios")

    assert json_response(locked, 429) == %{
             "errors" => %{"detail" => "too many failed attempts; retry later"}
           }

    assert [retry] = get_resp_header(locked, "retry-after")
    # The wrong token past the threshold counted: the lock doubled.
    assert String.to_integer(retry) > Throttle.base_lock_seconds()

    other = %{conn | remote_ip: {10, 0, 1, 1}}

    assert other
           |> put_req_header("authorization", "Bearer test-api-token")
           |> get("/api/v1/portfolios")
           |> json_response(200)
  end

  # User story (#974, the Sprint 20 plan's D-11):
  # As the operator, whose host clients all reach the published port from one
  # address,
  # I want my agent's correct token to pass while that address is locked,
  # so that a stale client sending an old token after a rotation never locks
  # my agent out, while its wrong tokens stay refused.
  #
  # Acceptance criteria:
  # - While the source is locked, the right token is answered 200.
  # - The lock stays: the source is still locked, and the next wrong token
  #   from it is still 429.
  # (The 32-byte boot floor on every token, `RuntimeConfig.api_tokens!/3`,
  # is what makes a locked guesser's correct guess infeasible.)
  test "a correct token passes while its source is locked, and the lock stays", %{conn: conn} do
    {conn, key} = locked_out_conn(conn)
    assert {:locked, _seconds} = Throttle.check(:api, key)

    assert conn
           |> put_req_header("authorization", "Bearer test-api-token")
           |> get("/api/v1/portfolios")
           |> json_response(200)

    assert {:locked, _seconds} = Throttle.check(:api, key)

    still_locked =
      conn |> put_req_header("authorization", "Bearer wrong") |> get("/api/v1/portfolios")

    assert still_locked.status == 429
  end
end
