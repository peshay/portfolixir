defmodule PortfolixirWeb.ListenerBoundsTest do
  # Every listener test starts the listener the way the release does --
  # Bandit.PhoenixAdapter.child_specs/2 with PortfolixirWeb.Endpoint as the
  # plug and the `http:` options config/runtime.exs builds under :prod,
  # merged over config.exs and prod.exs -- on an ephemeral loopback port.
  #
  # async: false -- it sets the environment variables config/runtime.exs reads
  # and opens over a thousand sockets. Loopback only.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @endpoint_mod PortfolixirWeb.Endpoint

  # What config/runtime.exs needs under :prod to evaluate at all, each a
  # synthetic value its own check accepts (the idiom of
  # test/portfolixir/release_background_fetch_test.exs).
  @release_env %{
    "SECRET_KEY_BASE" => String.duplicate("k7Qm", 16),
    "PHX_HOST" => "portfolixir.example",
    "DATABASE_URL" => "ecto://portfolixir:synthetic@db.example/portfolixir_prod",
    "PORTFOLIXIR_API_TOKEN" => String.duplicate("t3Zx", 12)
  }

  # The soft descriptor limit a container runs under when nothing raises it.
  @container_nofile_soft 1_024

  # The listener's bounds: acceptors, connections per acceptor, and the read
  # timeout that closes a connection whose client stops sending.
  @num_acceptors 10
  @num_connections 50
  @read_timeout 15_000

  # RFC 9113 §6.5.2 recommends a MAX_CONCURRENT_STREAMS of no less than 100.
  @stream_bound 100
  @streams_opened 1_000

  setup do
    http = prod_http_options()
    listener = Keyword.merge(http, port: 0, ip: {127, 0, 0, 1}, startup_log: false)

    [spec] =
      Bandit.PhoenixAdapter.child_specs(@endpoint_mod, otp_app: :portfolixir, http: listener)

    server = start_supervised!(spec)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %{server: server, port: port, http: http}
  end

  # User story (security review 2026-10-12, H09):
  # As the operator whose instance answers on the network,
  # I want the listener bounded for one operator and the companion,
  # so that a client without a credential cannot exhaust its connections,
  # hold a connection without finishing its request, or open unbounded
  # request processes through one connection.
  #
  # Acceptance criteria:
  # - The release's listener caps connections, closes a connection whose
  #   client stops sending, and serves no cleartext HTTP/2.
  # - A flood of connections whose headers never complete meets the
  #   listener's own cap, below the container's descriptor limit.
  # - A connection whose headers stop arriving is closed.
  # - Both Compose files give the app a descriptor limit above the cap.
  # - The deployment guide (EN, DE) says the port sits behind a reverse
  #   proxy with header timeouts.
  test "the release's listener carries its bounds", %{http: http} do
    assert http[:thousand_island_options] == [
             num_acceptors: @num_acceptors,
             num_connections: @num_connections,
             read_timeout: @read_timeout
           ]

    assert http[:http_2_options] == [enabled: false]
    assert http[:websocket_options] == [max_fragmented_message_size: 524_288]
  end

  test "cleartext HTTP/2 is refused, or one connection holds a bounded number of streams",
       %{server: server, port: port} do
    {result, _log} =
      with_log(fn ->
        {:ok, sock} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 2_000)
        :ok = :gen_tcp.send(sock, ["PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n", frame(0x4, 0x0, 0, "")])

        case recv_frame(sock, 3_000) do
          {:error, :closed} ->
            :h2c_refused

          {:ok, {0x4, 0x0, 0, payload}} ->
            announced = settings(payload)
            :ok = :gen_tcp.send(sock, frame(0x4, 0x1, 0, ""))

            # HEADERS without END_STREAM: a JSON body is announced and never sent.
            {frames, _table} =
              Enum.map_reduce(1..@streams_opened, HPAX.new(4096), fn i, table ->
                {block, table} = HPAX.encode(:no_store, request_headers(), table)
                {frame(0x1, 0x4, 2 * i - 1, block), table}
              end)

            :ok = :gen_tcp.send(sock, frames)
            Process.sleep(2_000)

            received = drain(sock, [])
            goaway? = Enum.any?(received, &match?({0x7, _, _, _}, &1))
            {:ok, handlers} = ThousandIsland.connection_pids(server)
            open_streams = handlers |> Enum.map(&stream_processes/1) |> Enum.sum()
            :gen_tcp.close(sock)

            {:h2c_served,
             %{announced_settings: announced, streams: open_streams, goaway: goaway?}}
        end
      end)

    case result do
      :h2c_refused ->
        :ok

      {:h2c_served, stats} ->
        assert stats.goaway or stats.streams <= @stream_bound,
               "one cleartext HTTP/2 connection holds #{stats.streams} request processes: " <>
                 inspect(stats)
    end
  end

  test "a flood of partial-header connections meets the listener's own cap, below the descriptor limit",
       %{server: server, port: port} do
    n = @container_nofile_soft + 100

    {{socks, held}, _log} =
      with_log(fn ->
        socks =
          Enum.reduce(1..n, [], fn _, socks ->
            case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 3_000) do
              {:ok, s} ->
                _ = :gen_tcp.send(s, "GET / HTTP/1.1\r\nHost: localhost\r\nX-Slow: ")
                [s | socks]

              {:error, _} ->
                socks
            end
          end)

        Process.sleep(2_000)
        {:ok, pids} = ThousandIsland.connection_pids(server)
        held = length(pids)
        Enum.each(socks, &:gen_tcp.close/1)
        Process.sleep(500)
        {socks, held}
      end)

    # The cap is per acceptor; each acceptor may hold one more connection
    # while it waits for a free slot.
    cap = @num_acceptors * @num_connections + @num_acceptors

    assert held <= cap,
           "the listener holds #{held} of #{length(socks)} connections whose headers " <>
             "never complete, past its cap of #{cap}"

    assert held < @container_nofile_soft
  end

  test "a connection whose headers stop arriving is closed within 20 s", %{port: port} do
    {{result, waited}, _log} =
      with_log(fn ->
        {:ok, s} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 2_000)
        :ok = :gen_tcp.send(s, "GET / HTTP/1.1\r\nHost: localhost\r\nX-Slow: ")
        started = System.monotonic_time(:millisecond)
        result = :gen_tcp.recv(s, 0, 20_000)
        waited = System.monotonic_time(:millisecond) - started
        :gen_tcp.close(s)
        # Let the server's handler log its 408 inside the capture.
        Process.sleep(200)
        {result, waited}
      end)

    assert match?({:error, :closed}, result) or
             match?({:ok, <<"HTTP/1.", _, " 408", _::binary>>}, result),
           "an idle partial request header is still open after #{waited} ms"
  end

  test "both Compose files give the app a descriptor limit above the listener's cap" do
    cap = @num_acceptors * @num_connections

    for path <- ["docker-compose.yml", "docker-compose.dev.yml"] do
      [app] = Regex.run(~r/^  app:\n(?:    .*\n|\n)*/m, File.read!(path))

      nofile =
        Regex.run(
          ~r/^    ulimits:\n      nofile:\n        soft: (\d+)\n        hard: (\d+)$/m,
          app
        )

      assert nofile, "#{path}: the app service sets no descriptor limit"
      [_, soft, hard] = nofile

      assert String.to_integer(soft) == 4_096, path
      assert String.to_integer(hard) == 4_096, path
      assert String.to_integer(soft) > cap, path
    end
  end

  test "the deployment guide puts the port behind a reverse proxy with header timeouts" do
    for {path, phrase} <- [
          {"docs/home-deployment.md", "header timeouts"},
          {"docs/de/home-deployment.md", "Header-Timeouts"}
        ] do
      guide = path |> File.read!() |> String.replace(~r/\s+/, " ")
      assert guide =~ phrase, path
      assert guide =~ "HTTP/2", path
    end
  end

  # -- the production listener options ---------------------------------------

  defp prod_http_options do
    base = Application.get_env(:portfolixir, @endpoint_mod, [])

    prod =
      "config/prod.exs"
      |> Config.Reader.read!(env: :prod, target: :host)
      |> get_in([:portfolixir, @endpoint_mod]) || []

    runtime =
      with_env(@release_env, fn ->
        "config/runtime.exs"
        |> Config.Reader.read!(env: :prod, target: :host)
        |> get_in([:portfolixir, @endpoint_mod])
      end) || []

    [portfolixir: [{@endpoint_mod, base}]]
    |> Config.Reader.merge(portfolixir: [{@endpoint_mod, prod}])
    |> Config.Reader.merge(portfolixir: [{@endpoint_mod, runtime}])
    |> get_in([:portfolixir, @endpoint_mod, :http])
  end

  defp with_env(env, fun) do
    previous = Map.new(env, fn {name, _value} -> {name, System.get_env(name)} end)

    try do
      Enum.each(env, fn {name, value} -> System.put_env(name, value) end)
      fun.()
    after
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end
  end

  # -- HTTP/2 framing (RFC 9113 §4.1) ----------------------------------------

  defp request_headers do
    [
      {":method", "POST"},
      {":scheme", "http"},
      {":authority", "localhost"},
      {":path", "/"},
      {"content-type", "application/json"},
      {"content-length", "100"}
    ]
  end

  defp frame(type, flags, stream_id, payload) do
    payload = IO.iodata_to_binary(payload)
    <<byte_size(payload)::24, type::8, flags::8, 0::1, stream_id::31, payload::binary>>
  end

  defp recv_frame(sock, timeout) do
    with {:ok, <<len::24, type::8, flags::8, _::1, stream_id::31>>} <-
           :gen_tcp.recv(sock, 9, timeout),
         {:ok, payload} <- recv_payload(sock, len, timeout) do
      {:ok, {type, flags, stream_id, payload}}
    end
  end

  defp recv_payload(_sock, 0, _timeout), do: {:ok, ""}
  defp recv_payload(sock, len, timeout), do: :gen_tcp.recv(sock, len, timeout)

  defp drain(sock, acc) do
    case recv_frame(sock, 300) do
      {:ok, {type, flags, stream_id, payload}} ->
        drain(sock, [{type, flags, stream_id, payload} | acc])

      _timeout_or_closed ->
        Enum.reverse(acc)
    end
  end

  defp settings(payload), do: for(<<id::16, value::32 <- payload>>, do: {id, value})

  # -- the server's stream processes -----------------------------------------

  defp stream_processes(handler) do
    case Process.info(handler, :links) do
      {:links, links} -> Enum.count(links, &(is_pid(&1) and stream_process?(&1)))
      nil -> 0
    end
  end

  defp stream_process?(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} -> match?({Bandit.HTTP2.StreamProcess, _, _}, dict[:"$initial_call"])
      nil -> false
    end
  end
end
