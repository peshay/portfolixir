defmodule PortfolixirWeb.ApiThrottleBoundedTableTest do
  # The throttle table is bounded in count, not only in time (security
  # review 2026-10-12, H03). Only documentation addresses (2001:db8::/32,
  # 172.18.0.1) are used; the real-socket test listens on an ephemeral
  # loopback port. No network.
  use PortfolixirWeb.ConnCase, async: false

  alias Portfolixir.Auth.Throttle

  # The documented Compose deployment: the proxy reaches the container from
  # the Docker bridge gateway, and the operator names that exact address.
  @gateway {172, 18, 0, 1}
  # A release holds every token to the 32-byte floor (token-first order).
  @sound_token String.duplicate("t", 32)
  # More sources than any bound the table may keep.
  @flood 60_000

  setup do
    previous_proxies = Application.get_env(:portfolixir, :trusted_proxies)
    previous_tokens = Application.get_env(:portfolixir, :api_tokens)
    Application.put_env(:portfolixir, :api_tokens, [{nil, @sound_token}])

    on_exit(fn ->
      Application.put_env(:portfolixir, :trusted_proxies, previous_proxies)
      Application.put_env(:portfolixir, :api_tokens, previous_tokens)
      forget_rows()
    end)

    :ok
  end

  # User story (security review 2026-10-12, H03):
  # As the operator behind a reverse proxy that forwards IPv6 clients,
  # I want every address of one IPv6 /64 counted as one source,
  # so that one client's prefix cannot make the throttle remember it once per
  # address.
  #
  # Acceptance criteria:
  # - Wrong tokens from many addresses inside one /64, forwarded by the named
  #   proxy, are answered as from one source (401 up to the lock, 429 past
  #   it) and leave at most one source row in the throttle table.
  # - The source key of an IPv6 address is the text of its /64; an IPv4
  #   address and an IPv4-mapped IPv6 address keep the IPv4 text.
  test "fresh addresses inside one IPv6 /64 behind the named proxy are one source" do
    assert Throttle.source_key({0x2001, 0xDB8, 1, 2, 0, 0, 0, 0x1F}) ==
             Throttle.source_key({0x2001, 0xDB8, 1, 2, 0xAB, 0xCD, 0xEF, 0x99})

    assert Throttle.source_key({0x2001, 0xDB8, 1, 2, 0, 0, 0, 0x1F}) == "2001:db8:1:2::"
    assert Throttle.source_key({198, 51, 100, 7}) == "198.51.100.7"
    assert Throttle.source_key({0, 0, 0, 0, 0, 0xFFFF, 0xC633, 0x6407}) == "198.51.100.7"

    Application.put_env(:portfolixir, :trusted_proxies, [{@gateway, 32}])
    requests = 3_000
    rows_before = source_rows()

    statuses =
      for i <- 1..requests do
        conn =
          %{build_conn() | remote_ip: @gateway}
          |> put_req_header("accept", "application/json")
          |> put_req_header("authorization", "Bearer wrong")
          |> put_req_header("x-forwarded-for", "2001:db8:1:2::" <> Integer.to_string(i, 16))
          |> get("/api/v1/portfolios")

        conn.status
      end

    assert_one_source(statuses)
    grown = source_rows() - rows_before
    assert grown <= 1, "one /64 behind the named proxy left #{grown} throttle rows"
  end

  # User story (security review 2026-10-12, H03):
  # As the operator whose reverse proxy keeps one upstream connection alive,
  # I want the clients it forwards from one IPv6 /64 counted as one source,
  # so that a kept-alive connection cannot grow the throttle table per request.
  #
  # Acceptance criteria:
  # - Over a real listener, wrong tokens forwarded on one connection from
  #   many addresses of one /64 are answered as from one source (401 up to
  #   the lock, 429 past it) and leave at most one source row.
  test "over a real socket, one kept-alive proxy connection adds at most one row for a /64" do
    Application.put_env(:portfolixir, :trusted_proxies, [{{127, 0, 0, 1}, 32}])

    server =
      start_supervised!(
        {Bandit,
         plug: PortfolixirWeb.Endpoint,
         scheme: :http,
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    {:ok, conn} = Mint.HTTP.connect(:http, "127.0.0.1", port, mode: :passive)

    requests = 5_000
    rows_before = source_rows()

    {conn, statuses} =
      Enum.reduce(1..requests, {conn, []}, fn i, {conn, statuses} ->
        headers = [
          {"accept", "application/json"},
          {"authorization", "Bearer wrong"},
          {"x-forwarded-for", "2001:db8:3:4::" <> Integer.to_string(i, 16)}
        ]

        {:ok, conn, ref} = Mint.HTTP.request(conn, "GET", "/api/v1/portfolios", headers, nil)
        {conn, status} = receive_status(conn, ref, nil)
        {conn, [status | statuses]}
      end)

    {:ok, _conn} = Mint.HTTP.close(conn)

    assert_one_source(Enum.reverse(statuses))
    grown = source_rows() - rows_before
    assert grown <= 1, "one /64 through a loopback proxy left #{grown} throttle rows"
  end

  # User story (security review 2026-10-12, H03):
  # As the operator,
  # I want the API scope to stop remembering first failures from new sources
  # past a scope-wide ceiling,
  # so that failures spread over many prefixes cannot grow the table for the
  # whole retention hour.
  #
  # Acceptance criteria:
  # - Single failures from many sources, each in its own /64, leave fewer
  #   rows than sources, also after a sweep; every call returns :ok.
  test "the API scope remembers fewer first failures than it receives" do
    rows_before = rows()

    for i <- 1..@flood do
      ip = {0x2001, 0xDB8, div(i, 0x10000), rem(i, 0x10000), 0, 0, 0, 1}
      assert :ok = Throttle.failure(:api, Throttle.source_key(ip))
    end

    send(Process.whereis(Throttle), :sweep)
    :sys.get_state(Throttle)

    grown = rows() - rows_before
    assert grown < @flood, "no bound: #{grown} rows kept for #{@flood} failed sources"
  end

  # User story (security review 2026-10-12, H03):
  # As the operator,
  # I want the throttle table to hold a bounded number of rows whatever
  # scope fills it,
  # so that the application's memory has a ceiling an attacker cannot lift.
  #
  # Acceptance criteria:
  # - Failures recorded from more sources than the bound leave fewer rows
  #   than sources.
  # - Once the table is full, a wrong token from a fresh source is still
  #   answered 401 and adds no source row; at most the minute's bucket of the
  #   first-failure ceiling, which is counted even then, is added.
  test "a full throttle table adds no source row and still answers 401" do
    rows_before = rows()

    for i <- 1..@flood do
      assert :ok = Throttle.failure(:cap_fill, "fill-#{i}")
    end

    grown = rows() - rows_before
    assert grown < @flood, "no cap: #{grown} rows kept for #{@flood} failed sources"

    full = rows()
    full_sources = source_rows()

    conn =
      %{build_conn() | remote_ip: {198, 51, 100, 77}}
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer wrong")
      |> get("/api/v1/portfolios")

    assert conn.status == 401
    assert source_rows() == full_sources
    assert rows() <= full + 1
  end

  # One source: refused until its lock, then told to wait.
  defp assert_one_source(statuses) do
    {before_lock, past_lock} = Enum.split(statuses, Throttle.max_failures())
    assert Enum.all?(before_lock, &(&1 == 401))
    assert past_lock != [] and Enum.all?(past_lock, &(&1 == 429))
  end

  defp receive_status(conn, ref, status) do
    case Mint.HTTP.recv(conn, 0, 10_000) do
      {:ok, conn, responses} ->
        {status, done?} =
          Enum.reduce(responses, {status, false}, fn
            {:status, ^ref, code}, {_status, done?} -> {code, done?}
            {:done, ^ref}, {status, _done?} -> {status, true}
            _other, acc -> acc
          end)

        if done?, do: {conn, status}, else: receive_status(conn, ref, status)

      {:error, conn, reason, _responses} ->
        flunk(
          "socket error #{inspect(reason)} after status #{inspect(status)} (#{inspect(conn)})"
        )
    end
  end

  defp rows, do: :ets.info(Throttle, :size)

  # Rows keyed by a source, leaving out the per-minute ceiling buckets.
  defp source_rows,
    do: :ets.select_count(Throttle, [{{{:_, :"$1"}, :_, :_, :_}, [{:is_binary, :"$1"}], [true]}])

  # This module's rows: the filler scope, the documentation prefixes, the
  # fresh source of the last test and the API scope's ceiling buckets.
  defp forget_rows do
    :ets.select_delete(Throttle, [{{{:cap_fill, :_}, :_, :_, :_}, [], [true]}])
    :ets.select_delete(Throttle, [{{{:api, {:_, :_}}, :_, :_, :_}, [], [true]}])

    Throttle
    |> :ets.select([{{{:api, :"$1"}, :_, :_, :_}, [{:is_binary, :"$1"}], [:"$1"]}])
    |> Enum.filter(&(String.starts_with?(&1, "2001:db8:") or &1 == "198.51.100.77"))
    |> Enum.each(&Throttle.success(:api, &1))
  end
end
