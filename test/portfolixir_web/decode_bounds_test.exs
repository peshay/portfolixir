defmodule PortfolixirWeb.DecodeBoundsTest do
  # Serves the real endpoint with the locked Bandit on an ephemeral loopback
  # port, as Bandit.PhoenixAdapter serves it in a release, and talks to the
  # LiveView socket with a hand-built WebSocket client. Not async: it sets the
  # UI password and traces the JSON decoder globally. Loopback only.
  use PortfolixirWeb.ConnCase, async: false

  import ExUnit.CaptureLog, only: [with_log: 1]

  # The bounds this file pins: the socket's frame and message bound, the
  # JSON nesting bound, and the HTTP body bound.
  @frame_bound 524_288
  @depth_bound 100
  @body_bound 2_000_000

  @password "synthetic-decode-bounds-ui-password"

  setup do
    # The most protective documented setting: a UI password is set. The
    # socket path below needs none of it.
    previous = Application.get_env(:portfolixir, :ui_password)
    Application.put_env(:portfolixir, :ui_password, @password)
    on_exit(fn -> Application.put_env(:portfolixir, :ui_password, previous) end)

    server =
      start_supervised!(
        {Bandit, plug: PortfolixirWeb.Endpoint, ip: :loopback, port: 0, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %{port: port}
  end

  # User story (security review 2026-10-12, H02):
  # As the operator whose instance answers on the network,
  # I want the LiveView socket to refuse a message it should never have to
  # decode, before it decodes it,
  # so that a client without a password, cookie or token cannot spend the
  # server's CPU and memory on one oversized or deeply nested message.
  #
  # Acceptance criteria:
  # - An oversized text frame is refused before any decode: no reply, and the
  #   transport's heap stays small.
  # - A message assembled from fragments past the same bound is refused
  #   before any decode.
  # - A message within the size bound but nested past the depth bound is
  #   refused before any decode.
  # - The socket's transport process runs under the heap cap.
  # - The socket line names the frame bound, and an ordinary message is still
  #   answered.
  test "an unauthenticated client cannot make the LiveView socket decode a multi-megabyte frame",
       %{port: port} do
    before = MapSet.new(Process.list())
    {sock, head} = ws_upgrade(port)
    # The handshake itself needs no cookie, no CSRF token, no Origin and no
    # password, before and after the bound.
    assert head =~ "HTTP/1.1 101", head

    transport = await_transport_pid(before)
    {:max_heap_size, cap} = Process.info(transport, :max_heap_size)

    # A well-formed heartbeat whose payload is ~8 MB of nested arrays.
    nested_bytes = 8_000_000
    depth = div(nested_bytes, 2)

    frame_payload =
      IO.iodata_to_binary([
        ~s([null,"1","phoenix","heartbeat",),
        :binary.copy("[", depth),
        :binary.copy("]", depth),
        "]"
      ])

    :erlang.trace(transport, true, [:garbage_collection, {:tracer, self()}])
    monitor = Process.monitor(transport)
    started = System.monotonic_time(:millisecond)

    # Bandit logs a refused frame as a protocol error as the transport ends:
    # captured until it has ended, not asserted.
    {answer, _log} =
      with_log(fn ->
        _ = :gen_tcp.send(sock, frame(1, 1, frame_payload))
        answer = recv_frame(sock, 90_000)

        receive do
          {:DOWN, ^monitor, :process, _pid, _reason} -> :ok
        after
          1_000 -> :ok
        end

        answer
      end)

    elapsed_ms = System.monotonic_time(:millisecond) - started
    untrace(transport, [:garbage_collection])
    peak_heap_mb = div(drain_gc_peak(transport, 0) * :erlang.system_info(:wordsize), 1_000_000)

    {decoded?, answer_text} = decoded?(answer)

    report =
      "frame #{byte_size(frame_payload)} bytes, no cookie/CSRF/Origin/token, UI password set; " <>
        "transport max_heap_size.size=#{cap.size}; answer=#{String.slice(answer_text, 0, 80)}; " <>
        "elapsed=#{elapsed_ms} ms; transport peak heap ~#{peak_heap_mb} MB"

    :gen_tcp.close(sock)

    refute decoded?, "the socket decoded an oversized frame: " <> report
    assert peak_heap_mb < 32, "the transport's heap grew: " <> report
  end

  test "the LiveView socket's transport process runs under the heap cap", %{port: port} do
    before = MapSet.new(Process.list())
    {sock, head} = ws_upgrade(port)
    assert head =~ "HTTP/1.1 101", head
    transport = await_transport_pid(before)
    {:max_heap_size, cap} = Process.info(transport, :max_heap_size)
    :gen_tcp.close(sock)

    assert cap.size == PortfolixirWeb.HeapCap.max_heap_words() and
             cap.include_shared_binaries == true,
           "the socket transport process carries no heap cap: #{inspect(cap)}"
  end

  test "a fragmented message past the bound is refused before it is decoded", %{port: port} do
    before = MapSet.new(Process.list())
    {sock, head} = ws_upgrade(port)
    assert head =~ "HTTP/1.1 101", head
    transport = await_transport_pid(before)

    # Two fragments, each under the frame bound, together past it.
    half = div(@frame_bound, 2) + 1
    first = ~s([null,"1","phoenix","heartbeat",{"pad":") <> :binary.copy("a", half)
    second = :binary.copy("a", half) <> ~s("}])

    {{answer, decodes}, _log} =
      with_log(fn ->
        trace_decodes(transport, fn ->
          _ = :gen_tcp.send(sock, [frame(0, 1, first), frame(1, 0, second)])
          recv_frame(sock, 10_000)
        end)
      end)

    :gen_tcp.close(sock)
    {decoded?, answer_text} = decoded?(answer)

    refute decoded?, "the socket answered a fragmented oversized message: #{answer_text}"
    assert decodes == [], "the socket decoded an oversized message: #{inspect(decodes)}"
  end

  test "a message nested past the depth bound is refused before it is decoded", %{port: port} do
    before = MapSet.new(Process.list())
    {sock, head} = ws_upgrade(port)
    assert head =~ "HTTP/1.1 101", head
    transport = await_transport_pid(before)

    depth = @depth_bound + 1

    payload =
      IO.iodata_to_binary([
        ~s([null,"1","phoenix","heartbeat",),
        :binary.copy("[", depth),
        :binary.copy("]", depth),
        "]"
      ])

    assert byte_size(payload) < @frame_bound

    {{answer, decodes}, _log} =
      with_log(fn ->
        trace_decodes(transport, fn ->
          _ = :gen_tcp.send(sock, frame(1, 1, payload))
          recv_frame(sock, 10_000)
        end)
      end)

    :gen_tcp.close(sock)
    {decoded?, answer_text} = decoded?(answer)

    refute decoded?, "the socket answered a deeply nested message: #{answer_text}"
    assert decodes == [], "the socket decoded a deeply nested message: #{inspect(decodes)}"
  end

  test "the socket line bounds the frame, and an ordinary message is still answered",
       %{port: port} do
    [{"/live", _socket, opts}] = PortfolixirWeb.Endpoint.__sockets__()
    assert opts[:websocket][:max_frame_size] == @frame_bound

    {sock, head} = ws_upgrade(port)
    assert head =~ "HTTP/1.1 101", head

    # A heartbeat nested exactly to the depth bound is answered.
    depth = @depth_bound - 1
    nested = :binary.copy("[", depth) <> :binary.copy("]", depth)
    _ = :gen_tcp.send(sock, frame(1, 1, ~s([null,"1","phoenix","heartbeat",#{nested}])))
    answer = recv_frame(sock, 5_000)
    :gen_tcp.close(sock)

    assert {true, _text} = decoded?(answer), inspect(answer)
  end

  # User story (security review 2026-10-12, H02):
  # As the operator whose API answers on the network,
  # I want a request body bounded in size and nesting before it is decoded,
  # so that a client without a token cannot make the server decode megabytes
  # of JSON before the token is checked.
  #
  # Acceptance criteria:
  # - A multi-megabyte JSON body is never decoded; it answers 413.
  # - The body bound is the largest documented API body with headroom: a
  #   body of exactly the bound passes the parser, one byte more answers 413.
  # - A body nested past the depth bound answers 400 without being decoded;
  #   a body nested exactly to the bound passes the parser.
  test "an unauthenticated multi-megabyte JSON body is not decoded before authentication",
       %{conn: conn} do
    depth = 2_000_000
    body = :binary.copy("[", depth) <> :binary.copy("]", depth)

    {result, decoded_sizes} = traced_dispatch(json_conn(conn), "/api/v1/portfolios", body)

    assert outcome(result) == {:raised, Plug.Parsers.RequestTooLargeError, 413}

    refute Enum.any?(decoded_sizes, &(&1 >= 1_000_000)),
           "a body of #{byte_size(body)} bytes was decoded before authentication: " <>
             inspect(decoded_sizes)
  end

  test "the body bound admits exactly the documented largest body and refuses one byte more",
       %{conn: conn} do
    at_bound = padded_json(@body_bound)
    assert byte_size(at_bound) == @body_bound

    # Parsed, then refused by the token check: the parser let it through.
    {result, _decoded} = traced_dispatch(json_conn(conn), "/api/v1/portfolios", at_bound)
    assert outcome(result) == 401

    {result, decoded} =
      traced_dispatch(json_conn(conn), "/api/v1/portfolios", padded_json(@body_bound + 1))

    assert outcome(result) == {:raised, Plug.Parsers.RequestTooLargeError, 413}
    assert decoded == []
  end

  test "a body nested past the depth bound answers 400 without being decoded", %{conn: conn} do
    too_deep = :binary.copy("[", @depth_bound + 1) <> :binary.copy("]", @depth_bound + 1)
    {result, decoded} = traced_dispatch(json_conn(conn), "/api/v1/portfolios", too_deep)

    assert outcome(result) == {:raised, Plug.Parsers.ParseError, 400}
    assert decoded == []

    at_bound = :binary.copy("[", @depth_bound) <> :binary.copy("]", @depth_bound)
    {result, decoded} = traced_dispatch(json_conn(conn), "/api/v1/portfolios", at_bound)

    assert outcome(result) == 401
    assert decoded == [byte_size(at_bound)]
  end

  # --- helpers ---------------------------------------------------------------

  defp json_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
  end

  # The answer's status, or the exception the dispatch raised with its status.
  defp outcome(%Plug.Conn{status: status}), do: status
  defp outcome({:raised, error}), do: {:raised, error.__struct__, Plug.Exception.status(error)}

  # A JSON object of exactly `bytes` bytes.
  defp padded_json(bytes) do
    shell = ~s({"pad":""})
    ~s({"pad":") <> :binary.copy("a", bytes - byte_size(shell)) <> ~s("})
  end

  # Dispatches in a process of its own and records the size of every body
  # Jason.decode! is called on by that process.
  defp traced_dispatch(conn, path, body) do
    task =
      Task.async(fn ->
        receive do
          :go -> :ok
        end

        try do
          Phoenix.ConnTest.dispatch(conn, PortfolixirWeb.Endpoint, :post, path, body)
        rescue
          error -> {:raised, error}
        end
      end)

    :erlang.trace_pattern({Jason, :decode!, :_}, true, [:global])
    :erlang.trace(task.pid, true, [:call, {:tracer, self()}])
    send(task.pid, :go)
    {result, _log} = with_log(fn -> Task.await(task, 60_000) end)
    :erlang.trace_pattern({Jason, :decode!, :_}, false, [:global])

    {result, drain_decodes(task.pid, [])}
  end

  defp trace_decodes(pid, fun) do
    :erlang.trace_pattern({Jason, :decode!, :_}, true, [:global])
    :erlang.trace(pid, true, [:call, {:tracer, self()}])
    result = fun.()
    untrace(pid, [:call])
    :erlang.trace_pattern({Jason, :decode!, :_}, false, [:global])
    {result, drain_decodes(pid, [])}
  end

  # The traced process may have ended in the meantime; its trace ended with it.
  defp untrace(pid, flags) do
    :erlang.trace(pid, false, flags)
  rescue
    ArgumentError -> 0
  end

  defp drain_decodes(pid, sizes) do
    receive do
      {:trace, ^pid, :call, {Jason, :decode!, [input | _]}} when is_binary(input) ->
        drain_decodes(pid, [byte_size(input) | sizes])

      {:trace, ^pid, :call, _other} ->
        drain_decodes(pid, sizes)
    after
      200 -> Enum.reverse(sizes)
    end
  end

  defp decoded?(answer) do
    case answer do
      {:ok, 1, text} -> {text =~ ~s("phx_reply") and text =~ ~s("ok"), text}
      {:ok, 8, <<code::16, _::binary>>} -> {false, "close #{code}"}
      other -> {false, inspect(other)}
    end
  end

  defp ws_upgrade(port) do
    {:ok, sock} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, packet: :raw])

    request =
      "GET /live/websocket?vsn=2.0.0 HTTP/1.1\r\n" <>
        "Host: localhost\r\n" <>
        "Upgrade: websocket\r\n" <>
        "Connection: Upgrade\r\n" <>
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" <>
        "Sec-WebSocket-Version: 13\r\n\r\n"

    :ok = :gen_tcp.send(sock, request)
    {:ok, head} = recv_until(sock, "\r\n\r\n", "")
    {sock, head}
  end

  defp recv_until(sock, marker, acc) do
    if String.contains?(acc, marker) do
      {:ok, acc}
    else
      case :gen_tcp.recv(sock, 0, 5_000) do
        {:ok, data} -> recv_until(sock, marker, acc <> data)
        error -> error
      end
    end
  end

  # Phoenix.Socket.__init__/1 labels the transport process.
  defp await_transport_pid(before, attempts \\ 100) do
    pids =
      for pid <- Process.list(),
          not MapSet.member?(before, pid),
          {:dictionary, dict} <- [Process.info(pid, :dictionary)],
          {_, {Phoenix.Socket, Phoenix.LiveView.Socket, _}} <-
            [List.keyfind(dict, :"$process_label", 0)],
          do: pid

    case pids do
      [pid] ->
        pid

      _ when attempts > 0 ->
        Process.sleep(10)
        await_transport_pid(before, attempts - 1)

      other ->
        flunk("expected one LiveView socket transport process, found #{inspect(other)}")
    end
  end

  # A client frame must be masked; a zero mask key leaves the bytes as they
  # are. `fin` 0 opens a fragmented message, opcode 0 continues it.
  defp frame(fin, opcode, payload) do
    len = byte_size(payload)

    header =
      cond do
        len < 126 -> <<fin::1, 0::3, opcode::4, 1::1, len::7>>
        len < 65_536 -> <<fin::1, 0::3, opcode::4, 1::1, 126::7, len::16>>
        true -> <<fin::1, 0::3, opcode::4, 1::1, 127::7, len::64>>
      end

    [header, <<0, 0, 0, 0>>, payload]
  end

  defp recv_frame(sock, timeout) do
    with {:ok, <<_fin::1, _rsv::3, opcode::4, 0::1, len7::7>>} <- :gen_tcp.recv(sock, 2, timeout),
         {:ok, len} <- frame_length(sock, len7, timeout),
         {:ok, payload} <- recv_payload(sock, len, timeout) do
      {:ok, opcode, payload}
    end
  end

  defp frame_length(sock, 126, timeout) do
    with {:ok, <<len::16>>} <- :gen_tcp.recv(sock, 2, timeout), do: {:ok, len}
  end

  defp frame_length(sock, 127, timeout) do
    with {:ok, <<len::64>>} <- :gen_tcp.recv(sock, 8, timeout), do: {:ok, len}
  end

  defp frame_length(_sock, len, _timeout), do: {:ok, len}

  defp recv_payload(_sock, 0, _timeout), do: {:ok, ""}
  defp recv_payload(sock, len, timeout), do: :gen_tcp.recv(sock, len, timeout)

  # Peak heap (words) over the GC trace events of `pid`.
  defp drain_gc_peak(pid, peak) do
    receive do
      {:trace, ^pid, _event, info} when is_list(info) ->
        words =
          Keyword.get(info, :heap_size, 0) + Keyword.get(info, :old_heap_size, 0) +
            Keyword.get(info, :mbuf_size, 0)

        drain_gc_peak(pid, max(peak, words))
    after
      200 -> peak
    end
  end
end
