defmodule PortfolixirWeb.ApiAuthThrottleTest do
  # Issue #771: the bearer check is constant-time already; the missing piece
  # was a bound on attempts per source.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Auth.Throttle

  # User story:
  # As the operator,
  # I want a source that keeps sending wrong bearer tokens answered 429 with Retry-After,
  # so that the token cannot be guessed online, and a wrong-then-right sequence still waits.
  #
  # Acceptance criteria:
  # - Up to the threshold, a wrong token is 401.
  # - After the threshold the source gets 429 with a Retry-After header, even with the right token.
  # - Another source is unaffected.
  test "locks a source out after repeated wrong tokens", %{conn: conn} do
    source = {10, 0, 0, System.unique_integer([:positive]) |> rem(250)}
    conn = %{conn | remote_ip: source}

    Throttle.success(:api, Throttle.source_key(source))

    # The failure that reaches the threshold is itself answered 401; every
    # request after it, right token or wrong, meets the lock.
    for _ <- 1..Throttle.max_failures() do
      assert conn
             |> put_req_header("authorization", "Bearer wrong")
             |> get("/api/v1/portfolios")
             |> json_response(401)
    end

    locked = conn |> put_req_header("authorization", "Bearer wrong") |> get("/api/v1/portfolios")
    assert locked.status == 429
    assert [retry] = get_resp_header(locked, "retry-after")
    assert String.to_integer(retry) >= 1

    still_locked =
      conn
      |> put_req_header("authorization", "Bearer test-api-token")
      |> get("/api/v1/portfolios")

    assert still_locked.status == 429

    other = %{conn | remote_ip: {10, 0, 1, 1}}

    assert other
           |> put_req_header("authorization", "Bearer test-api-token")
           |> get("/api/v1/portfolios")
           |> json_response(200)
  end
end
