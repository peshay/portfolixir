defmodule Portfolixir.Net.HttpPoolTest do
  # mint 1.11.0 leaves a connection open after a receive timeout, and Finch
  # 0.23.0 then checked it back into its pool with the timed-out request
  # still pending on it. The next request to the same host was sent on that
  # connection and read the late answer meant for the one before (a
  # CaseClauseError inside Finch). The bounded client's pool kept no idle
  # connection for that. Finch 0.24.0 closes an HTTP/1 connection after a
  # request or response error before it goes back to the pool (upstream
  # #397), and #1116's experiment showed that covers this case, so the pool
  # keeps idle connections again: a connection answered in time serves the
  # next request, one a request timed out on serves none.
  #
  # These tests go through the real transport, to a listener on the loopback
  # interface this test opens itself: no request leaves the machine. They call
  # `Req` with the bounded `Req` directly, because `Http.get/2` refuses a
  # loopback address by policy, as it should.
  use ExUnit.Case, async: true

  alias Portfolixir.Net.Http

  # User story:
  # As an operator whose quote sync asks one provider for many securities in
  # a row,
  # I want a request that timed out to leave no half-read connection behind,
  # so that the next request to that provider gets its own answer, not the
  # late answer to the request before it.
  #
  # Acceptance criteria:
  # - A request whose answer is late ends in a receive timeout.
  # - The next request to the same host arrives on a connection of its own
  #   and gets its own answer, in a pool that keeps idle connections (#1116).
  # - So does one sent after the late answer reached the closed connection.
  test "a request after a receive timeout gets its own connection and its own answer" do
    %{base: base} = start_server()
    req = Http.new(max_bytes: 1_000, allowed_hosts: :any, receive_timeout: 200)

    assert {:error, %Req.TransportError{reason: :timeout}} = Req.get(req, url: base <> "/slow")
    assert {:ok, %Req.Response{status: 200, body: "fast"}} = Req.get(req, url: base <> "/fast")

    assert_receive {:request, slow_conn, "/slow"}
    assert_receive {:request, fast_conn, "/fast"}
    assert slow_conn != fast_conn

    assert {:error, %Req.TransportError{reason: :timeout}} = Req.get(req, url: base <> "/slow")
    # The late answer (600 ms) has been written by now.
    Process.sleep(700)
    assert {:ok, %Req.Response{status: 200, body: "fast"}} = Req.get(req, url: base <> "/fast")
  end

  # User story (#1116):
  # As an operator whose quote sync asks one provider for many securities in
  # a row,
  # I want a connection answered in time to serve the next request to that
  # host,
  # so that the sync does not pay a handshake per request, now that Finch
  # 0.24.0 closes a connection a request failed on.
  #
  # Acceptance criteria:
  # - Two requests in a row to one host, both answered in time, arrive on
  #   one connection, and each gets its own answer.
  test "a connection answered in time serves the next request" do
    %{base: base} = start_server()
    req = Http.new(max_bytes: 1_000, allowed_hosts: :any)

    assert {:ok, %Req.Response{status: 200, body: "fast"}} = Req.get(req, url: base <> "/fast")
    assert {:ok, %Req.Response{status: 200, body: "fast"}} = Req.get(req, url: base <> "/fast")

    assert_receive {:request, first, "/fast"}
    assert_receive {:request, second, "/fast"}
    assert first == second
  end

  # User story:
  # As an operator whose logo override or a provider redirect names a host
  # by its IPv6 address,
  # I want that request to still connect over IPv6,
  # so that the bounded pool's own connection options do not cost the
  # address family Req would otherwise have chosen.
  #
  # Acceptance criteria:
  # - A request to an IPv6-literal host carries inet6 in its connection
  #   options, next to the pool's connect timeout; the pool sets no idle
  #   time of its own (#1116).
  # - A request to a host name carries no inet6.
  test "a request to an IPv6-literal host keeps IPv6 in its pool options" do
    test = self()

    # The pool options as the adapter receives them: a request step appended
    # after every other one reports them, and a plug answers in place of the
    # network (#1019: Req deprecates a function as the adapter).
    req =
      Http.new(max_bytes: 1_000, allowed_hosts: :any)
      |> Req.Request.append_request_steps(
        report_finch: fn request ->
          send(test, {:finch, request.url.host, request.options[:finch]})
          request
        end
      )

    answer = fn conn -> Plug.Conn.send_resp(conn, 200, "") end

    assert {:ok, _} = Http.get(req, url: "https://[2606:4700::1]/logo.png", plug: answer)
    assert {:ok, _} = Http.get(req, url: "https://upstream.test/logo.png", plug: answer)

    assert_receive {:finch, "2606:4700::1", literal}
    assert get_in(literal, [:conn_opts, :transport_opts, :inet6]) == true
    assert get_in(literal, [:conn_opts, :transport_opts, :timeout]) == 5_000
    refute Keyword.has_key?(literal, :conn_max_idle_time)

    assert_receive {:finch, "upstream.test", named}
    assert get_in(named, [:conn_opts, :transport_opts, :inet6]) == nil
  end

  # -- a loopback HTTP/1.1 server ------------------------------------------
  #
  # Keeps every connection alive; "/slow" is answered after 600 ms, anything
  # else at once. Each request is reported to the test as
  # {:request, connection, path}.

  defp start_server do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listen)
    test = self()
    acceptor = spawn(fn -> accept(listen, test, 1) end)

    on_exit(fn ->
      Process.exit(acceptor, :kill)
      :gen_tcp.close(listen)
    end)

    %{base: "http://127.0.0.1:#{port}"}
  end

  defp accept(listen, test, n) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        handler =
          spawn(fn ->
            receive do
              :go -> serve(socket, test, n, "")
            end
          end)

        :ok = :gen_tcp.controlling_process(socket, handler)
        send(handler, :go)
        accept(listen, test, n + 1)

      {:error, _closed} ->
        :ok
    end
  end

  defp serve(socket, test, n, buffer) do
    case String.split(buffer, "\r\n\r\n", parts: 2) do
      [head, rest] ->
        [_method, path | _] = head |> String.split("\r\n") |> hd() |> String.split(" ")
        send(test, {:request, n, path})
        if path == "/slow", do: Process.sleep(600)
        body = if path == "/slow", do: "slow", else: "fast"

        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\ncontent-length: " <>
            "#{byte_size(body)}\r\n\r\n" <> body
        )

        serve(socket, test, n, rest)

      [_incomplete] ->
        case :gen_tcp.recv(socket, 0, 5_000) do
          {:ok, data} -> serve(socket, test, n, buffer <> data)
          {:error, _closed} -> :gen_tcp.close(socket)
        end
    end
  end
end
