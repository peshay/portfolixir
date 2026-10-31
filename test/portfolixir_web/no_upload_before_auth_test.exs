defmodule PortfolixirWeb.NoUploadBeforeAuthTest do
  # Serves the real endpoint with the locked Bandit on an ephemeral loopback
  # port and talks to it over one Mint connection. Not async: it reads the
  # node's upload directory, which every request process shares. No request
  # leaves the machine.
  use PortfolixirWeb.ConnCase, async: false

  alias Portfolixir.Auth.Throttle

  @boundary "synthetic-boundary"
  @part_bytes 1_000_000

  setup do
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

    # The API path counts a failure per refused request against 127.0.0.1.
    on_exit(fn -> Throttle.success(:api, "127.0.0.1") end)

    %{port: port}
  end

  # User story (security review 2026-10-12, H01):
  # As the operator whose instance answers on the network,
  # I want no request to make the server write a file before it is
  # authenticated,
  # so that nobody without a password or token can fill the disk the
  # database lives on.
  #
  # Acceptance criteria:
  # - A multipart request answered 404 or 401 on a kept-alive connection
  #   leaves no upload file on disk once its answer has arrived.
  # - The endpoint's body parsers do not include the multipart parser; the
  #   Imports upload travels over the LiveView socket.
  test "a 404 on an unknown path leaves no upload behind on a kept-alive connection",
       %{port: port} do
    # /health has only a GET route: a POST is a NoRouteError, which Phoenix
    # renders as 404 without re-raising, so Bandit keeps the connection.
    {statuses, held_after_each, after_close} = run_requests(port, "/health", 5)

    assert statuses == List.duplicate(404, 5)

    assert Enum.all?(held_after_each, fn {count, _bytes} -> count == 0 end),
           "upload files held on disk after each unauthenticated 404 " <>
             "on one kept-alive connection ({files, bytes}): #{inspect(held_after_each)}; " <>
             "after the client closed the socket: #{inspect(after_close)}"
  end

  test "a 401 from the API token check leaves no upload behind on a kept-alive connection",
       %{port: port} do
    # The bearer check answers 401 and halts (no raise), so Bandit keeps the
    # connection.
    {statuses, held_after_each, after_close} = run_requests(port, "/api/v1/securities", 3)

    assert statuses == List.duplicate(401, 3)

    assert Enum.all?(held_after_each, fn {count, _bytes} -> count == 0 end),
           "upload files held on disk after each unauthenticated 401 " <>
             "on one kept-alive connection ({files, bytes}): #{inspect(held_after_each)}; " <>
             "after the client closed the socket: #{inspect(after_close)}"
  end

  test "the endpoint parses no multipart body" do
    parsers = endpoint_parsers(File.read!("lib/portfolixir_web/endpoint.ex"))

    assert parsers != [], "the endpoint scan found no Plug.Parsers"
    refute :multipart in parsers, "the endpoint parses multipart bodies: #{inspect(parsers)}"
  end

  # Sends `n` unauthenticated multipart POSTs with one 1 MB file part each,
  # all on one connection while the server keeps it, and records the upload
  # files on disk after each answer has fully arrived; then closes the socket
  # and records what is left once the server has seen the close.
  defp run_requests(port, path, n) do
    body = multipart_body(@part_bytes)
    {:ok, conn} = connect(port)

    {conn, statuses, held} =
      Enum.reduce(1..n, {conn, [], []}, fn _i, {conn, statuses, held} ->
        conn = if Mint.HTTP.open?(conn), do: conn, else: elem(connect(port), 1)
        {conn, status} = send_multipart(conn, path, body)
        {conn, [status | statuses], [held_uploads() | held]}
      end)

    {:ok, _conn} = Mint.HTTP.close(conn)
    after_close = wait_until_released(40)

    {Enum.reverse(statuses), Enum.reverse(held), after_close}
  end

  defp connect(port), do: Mint.HTTP.connect(:http, "127.0.0.1", port, mode: :passive)

  defp send_multipart(conn, path, body) do
    headers = [
      {"content-type", "multipart/form-data; boundary=" <> @boundary},
      {"content-length", Integer.to_string(byte_size(body))}
    ]

    {:ok, conn, ref} = Mint.HTTP.request(conn, "POST", path, headers, body)
    receive_response(conn, ref, nil)
  end

  defp receive_response(conn, ref, status) do
    case Mint.HTTP.recv(conn, 0, 10_000) do
      {:ok, conn, responses} ->
        {status, done?} = absorb(responses, ref, status)
        if done?, do: {conn, status}, else: receive_response(conn, ref, status)

      {:error, conn, _reason, responses} ->
        {status, _done?} = absorb(responses, ref, status)
        {conn, status}
    end
  end

  defp absorb(responses, ref, status) do
    Enum.reduce(responses, {status, false}, fn
      {:status, ^ref, code}, {_status, done?} -> {code, done?}
      {:done, ^ref}, {status, _done?} -> {status, true}
      _other, acc -> acc
    end)
  end

  defp multipart_body(bytes) do
    IO.iodata_to_binary([
      "--",
      @boundary,
      "\r\n",
      ~s(content-disposition: form-data; name="f"; filename="f.bin"\r\n),
      "content-type: application/octet-stream\r\n\r\n",
      :binary.copy("A", bytes),
      "\r\n--",
      @boundary,
      "--\r\n"
    ])
  end

  # Plug.Upload's own files of this node, read from disk: every
  # `multipart-*` file under the node's `plug-*-<suffix>` directories.
  defp held_uploads do
    files = upload_files()
    {length(files), files |> Enum.map(&File.stat!(&1).size) |> Enum.sum()}
  end

  defp upload_files do
    {roots, suffix} = :persistent_term.get(Plug.Upload)

    roots
    |> Enum.flat_map(&Path.wildcard(Path.join([&1, "plug-*-" <> suffix, "multipart-*"])))
    |> Enum.filter(&File.regular?/1)
  end

  defp wait_until_released(0), do: held_uploads()

  defp wait_until_released(tries) do
    case held_uploads() do
      {0, 0} = none ->
        none

      _some ->
        Process.sleep(50)
        wait_until_released(tries - 1)
    end
  end

  # The `parsers:` of every `plug(Plug.Parsers, ...)` in the endpoint source.
  defp endpoint_parsers(source) do
    {_ast, parsers} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:plug, _, [{:__aliases__, _, [:Plug, :Parsers]}, opts]} = node, acc when is_list(opts) ->
          {node, acc ++ Keyword.get(opts, :parsers, [])}

        node, acc ->
          {node, acc}
      end)

    parsers
  end
end
