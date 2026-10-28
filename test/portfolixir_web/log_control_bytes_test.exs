defmodule PortfolixirWeb.LogControlBytesTest do
  # The application's own endpoint runs under a Bandit listener on an
  # ephemeral loopback port with the release's listener options, and the
  # Logger is raised to the production level, info. What is captured is what
  # the console handler writes: a handler with the console handler's filters
  # and the default formatter, colours off, so every control byte in the
  # capture came from the entry or the request.
  #
  # Not async: it raises the global Logger level and adds a handler.
  # Loopback only, synthetic strings only, no credential sent, nothing written.
  use ExUnit.Case, async: false

  defmodule ConsoleMirror do
    @moduledoc false
    # A :logger handler that hands the test what its formatter writes.
    def log(event, %{config: %{pid: pid}, formatter: {module, config}}) do
      send(pid, {:console, IO.chardata_to_string(module.format(event, config))})
    end
  end

  setup do
    level = Logger.level()
    Logger.configure(level: :info)

    # The console handler's filters as configured (the suite's own log-noise
    # filter on the running handler is left out).
    console = Application.get_env(:logger, :default_handler, [])

    :ok =
      :logger.add_handler(:console_mirror, ConsoleMirror, %{
        level: :all,
        filters: Keyword.get(console, :filters, []),
        filter_default: Keyword.get(console, :filter_default, :log),
        formatter: Logger.default_formatter(colors: [enabled: false]),
        config: %{pid: self()}
      })

    on_exit(fn ->
      :logger.remove_handler(:console_mirror)
      Logger.configure(level: level)
    end)

    http =
      :portfolixir
      |> Application.get_env(PortfolixirWeb.Endpoint, [])
      |> Keyword.get(:http, [])
      |> Keyword.merge(port: 0, ip: {127, 0, 0, 1}, startup_log: false)

    [spec] =
      Bandit.PhoenixAdapter.child_specs(PortfolixirWeb.Endpoint,
        otp_app: :portfolixir,
        http: http
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(start_supervised!(spec))
    %{port: port}
  end

  # A C0 control or DEL other than TAB and the formatter's own LF.
  defp control, do: ~r/[\x00-\x08\x0B-\x1F\x7F]/

  # User story (security review 2026-10-12, H69):
  # As the operator who reads the application's log in a terminal,
  # I want every control character on its way to the console written as a
  # visible escape,
  # so that nothing a request carries can forge a log line or send my
  # terminal an escape sequence.
  #
  # Acceptance criteria:
  # - A log entry carrying control characters reaches the console with each
  #   of them escaped, line feeds and tabs kept, whether it is a string or a
  #   format with its arguments.
  # - The release's and the development server's console handler carry the
  #   escaping filter, beside the default remote group-leader filter.
  # - A request path or a WebSocket Origin carrying control characters is
  #   refused with 400, and no control byte reaches the console.
  # - A line feed cannot arrive inside a request path: cleartext HTTP/2 is
  #   refused, and no log line of the request's own making is written.
  test "a log entry's control characters reach the console escaped" do
    require Logger

    {_result, log} =
      with_console(fn ->
        Logger.warning(
          "synthetic-entry\e]0;SYNTHETIC-TITLE\a\e[31mRED\e[0m\rOVER\x7F\nnext\tline"
        )

        :logger.warning(~c"synthetic-format ~ts", ["\e[2K\e[1AHIDDEN"])
      end)

    assert log =~
             ~S"synthetic-entry\x1B]0;SYNTHETIC-TITLE\x07\x1B[31mRED\x1B[0m\x0DOVER\x7F" <>
               "\nnext\tline"

    assert log =~ ~S"synthetic-format \x1B[2K\x1B[1AHIDDEN"
    refute log =~ control(), "control bytes reached the console: " <> inspect(log)
  end

  test "the release's and the development server's console handler escape control bytes" do
    # config.exs configures the console handler for every environment, and
    # neither prod.exs nor dev.exs replaces it.
    filters =
      "config/config.exs"
      |> Config.Reader.read!(env: :prod, target: :host)
      |> get_in([:logger, :default_handler, :filters])

    assert {&Portfolixir.LogEscape.filter/2, []} in Keyword.values(filters || [])
    assert Keyword.fetch!(filters, :remote_gl) == {&:logger_filters.remote_gl/2, :stop}

    for env <- [:prod, :dev] do
      config = Config.Reader.read!("config/#{env}.exs", env: env, target: :host)
      assert get_in(config, [:logger, :default_handler]) == nil, "#{env}"
    end
  end

  test "control bytes in an HTTP/1.1 request path are not written to the log raw",
       %{port: port} do
    path =
      "/probe-h1-SYNTHETIC" <>
        "\e]0;SYNTHETIC-TITLE\a\e[31mSYNTHETIC-RED\e[0m\rSYNTHETIC-OVERWRITE"

    {status, log} =
      with_console(fn ->
        http1(port, "GET " <> path <> " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
      end)

    # Bandit refuses a control character in the request line.
    assert status == 400

    refute log =~ control(),
           "control bytes from an unauthenticated request path reached the log: " <> inspect(log)
  end

  test "a line feed in an HTTP/2 :path does not write a log line of its own", %{port: port} do
    forged = "12:00:00.000 [warning] SYNTHETIC-FORGED-LINE"

    {status, log} = with_console(fn -> h2c_get(port, "/probe-h2-SYNTHETIC\n" <> forged) end)

    # Cleartext HTTP/2 is off: the connection is closed.
    assert status == :closed

    refute log =~ ~r/^12:00:00\.000 \[warning\] SYNTHETIC-FORGED-LINE/m,
           "an unauthenticated HTTP/2 :path wrote a log line of its own: " <> inspect(log)
  end

  test "control bytes in a refused WebSocket Origin are not written to the log raw",
       %{port: port} do
    origin = "http://synthetic-origin.example\e]0;SYNTHETIC-TITLE\a\e[2K\e[1ASYNTHETIC-HIDDEN"

    request =
      "GET /live/websocket?vsn=2.0.0 HTTP/1.1\r\n" <>
        "Host: localhost\r\n" <>
        "Upgrade: websocket\r\nConnection: Upgrade\r\n" <>
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n" <>
        "Origin: " <> origin <> "\r\n\r\n"

    {status, log} = with_console(fn -> http1(port, request) end)

    # Bandit refuses a control character in a field value.
    assert status == 400

    refute log =~ control(),
           "control bytes from an unauthenticated Origin reached the log: " <> inspect(log)
  end

  # --- the console capture ---

  # What the console handler writes while `fun` runs; the same events are
  # captured, so none of them counts as an uncaptured warning.
  defp with_console(fun) do
    {result, _captured} = ExUnit.CaptureLog.with_log([level: :info], fun)
    {result, drain_console("")}
  end

  defp drain_console(acc) do
    receive do
      {:console, text} -> drain_console(acc <> text)
    after
      200 -> acc
    end
  end

  # --- loopback clients ---

  defp http1(port, request) do
    {:ok, sock} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    :ok = :gen_tcp.send(sock, request)
    response = read_http1(sock, "")
    :gen_tcp.close(sock)
    # The request line is logged before the answer; the pause keeps the
    # "Sent ..." line inside the capture too.
    Process.sleep(200)

    case Regex.run(~r/\AHTTP\/1\.[01] (\d{3})/, response) do
      [_, code] -> String.to_integer(code)
      nil -> :no_response
    end
  end

  defp read_http1(sock, acc) do
    with [head, body] <- :binary.split(acc, "\r\n\r\n"),
         [_, len] <- Regex.run(~r/\r\ncontent-length:\s*(\d+)/i, head),
         true <- byte_size(body) >= String.to_integer(len) do
      acc
    else
      _ ->
        case :gen_tcp.recv(sock, 0, 5_000) do
          {:ok, data} -> read_http1(sock, acc <> data)
          {:error, _closed_or_timeout} -> acc
        end
    end
  end

  defp h2c_get(port, path) do
    {:ok, sock} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])

    {block, _table} =
      HPAX.encode(
        [
          {:store, ":method", "GET"},
          {:store, ":scheme", "http"},
          {:store, ":authority", "localhost"},
          {:store, ":path", path}
        ],
        HPAX.new(4096)
      )

    preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
    settings = frame(0x4, 0x0, 0, "")
    # HEADERS on stream 1, END_STREAM | END_HEADERS.
    headers = frame(0x1, 0x5, 1, IO.iodata_to_binary(block))
    :ok = :gen_tcp.send(sock, preface <> settings <> headers)
    status = read_h2_status(sock, "", HPAX.new(4096))
    :gen_tcp.close(sock)
    Process.sleep(200)
    status
  end

  defp frame(type, flags, stream_id, payload) do
    <<byte_size(payload)::24, type::8, flags::8, 0::1, stream_id::31, payload::binary>>
  end

  defp read_h2_status(sock, buffer, table) do
    case buffer do
      <<len::24, type::8, _flags::8, _r::1, stream::31, payload::binary-size(len), rest::binary>> ->
        cond do
          type == 0x1 and stream == 1 ->
            {:ok, headers, _table} = HPAX.decode(payload, table)
            {":status", status} = List.keyfind(headers, ":status", 0)
            status

          type == 0x3 and stream == 1 ->
            :rst_stream

          type == 0x7 ->
            :goaway

          true ->
            read_h2_status(sock, rest, table)
        end

      _incomplete ->
        case :gen_tcp.recv(sock, 0, 5_000) do
          {:ok, data} -> read_h2_status(sock, buffer <> data, table)
          {:error, _closed_or_timeout} -> :closed
        end
    end
  end
end
