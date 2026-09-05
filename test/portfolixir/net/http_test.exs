defmodule Portfolixir.Net.HttpTest do
  # Issue #763: every outbound client is built through one bounded Req —
  # a body cap enforced while streaming, a connect timeout, and a deadline on
  # the whole request — so a slow or oversized upstream costs at most the cap.
  use ExUnit.Case, async: true

  alias Portfolixir.Net.Http

  # User story:
  # As an operator whose instance fetches from third parties on a schedule,
  # I want an oversized response cut off at a byte cap while it streams,
  # so that a misbehaving upstream cannot fill the instance's memory.
  #
  # Acceptance criteria:
  # - A body under the cap arrives intact and is still JSON-decoded.
  # - A body over the cap is cut and reported as an error, not a response.
  # - A Content-Length over the cap is refused before the body is read.
  test "cuts a streamed body at the cap and keeps small bodies intact" do
    req = Http.new(max_bytes: 100)

    assert {:ok, %Req.Response{status: 200, body: body}} =
             Http.get(req,
               plug: fn conn -> Plug.Conn.send_resp(conn, 200, String.duplicate("a", 50)) end
             )

    assert body == String.duplicate("a", 50)

    assert {:error, %Http.BodyTooLarge{limit: 100}} =
             Http.get(req,
               plug: fn conn -> Plug.Conn.send_resp(conn, 200, String.duplicate("a", 500)) end
             )
  end

  test "still decodes JSON under the cap" do
    req = Http.new(max_bytes: 1_000)

    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, ~s({"a": 1}))
    end

    assert {:ok, %Req.Response{body: %{"a" => 1}}} = Http.get(req, plug: plug)
  end

  test "refuses a declared Content-Length over the cap before reading" do
    req = Http.new(max_bytes: 100)

    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-length", "5000")
      |> Plug.Conn.send_resp(200, String.duplicate("a", 10))
    end

    assert {:error, %Http.BodyTooLarge{}} = Http.get(req, plug: plug)
  end

  # User story:
  # As an operator,
  # I want a hung upstream to cost a bounded wall-clock time,
  # so that a scheduler tick or an API call never waits forever on a socket
  # that trickles one byte per receive timeout.
  #
  # Acceptance criteria:
  # - A request that does not finish inside the deadline returns {:error, :deadline}.
  # - The Req carries a connect timeout.
  test "gives up at the deadline" do
    req = Http.new(max_bytes: 100, deadline_ms: 50)

    plug = fn conn ->
      Process.sleep(500)
      Plug.Conn.send_resp(conn, 200, "late")
    end

    assert {:error, :deadline} = Http.get(req, plug: plug)
  end

  test "carries a connect timeout and retries off" do
    req = Http.new(max_bytes: 100)

    assert get_in(req.options, [:connect_options, :timeout]) == 5_000
    assert req.options[:retry] == false
  end

  # User story:
  # As a caller of a bounded client,
  # I want a failure inside the adapter returned as a value,
  # so that a scheduler tick never crashes on one upstream.
  #
  # Acceptance criteria:
  # - An exception or an exit inside the request is {:error, term}.
  # - A Content-Length that is not a number is ignored; the streamed cap still applies.
  # - The cap error names both sizes.
  test "returns adapter failures as values and ignores a malformed Content-Length" do
    req = Http.new(max_bytes: 100)

    assert {:error, %RuntimeError{message: "boom"}} =
             Http.get(req, plug: fn _conn -> raise "boom" end)

    assert {:error, {:exit, :boom}} = Http.get(req, plug: fn _conn -> exit(:boom) end)

    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-length", "not-a-number")
      |> Plug.Conn.send_resp(200, "ok")
    end

    assert {:ok, %Req.Response{body: "ok"}} = Http.get(req, plug: plug)

    assert Exception.message(%Http.BodyTooLarge{limit: 10, size: 20}) ==
             "upstream body of 20 bytes exceeds the 10-byte cap"
  end
end
