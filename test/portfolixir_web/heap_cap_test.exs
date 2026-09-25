defmodule PortfolixirWeb.HeapCapTest do
  # E25 S4, G05 (#889): no per-process heap limit contained an oversized read
  # or write, so one runaway request could take the whole node down instead
  # of failing alone. Defence in depth behind the bounded inputs: every HTTP
  # request process and every LiveView process runs under a heap cap that
  # counts the shared binaries it holds.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.HeapCap

  defp capped?(pid) do
    {:max_heap_size, cap} = Process.info(pid, :max_heap_size)

    cap.size == HeapCap.max_heap_words() and cap.kill == true and
      cap.include_shared_binaries == true
  end

  # User story:
  # As the operator running one instance on one machine,
  # I want each request and each open page to fail alone when it grows past
  # a fixed heap,
  # so that a runaway read or write cannot take every other request with it.
  #
  # Acceptance criteria:
  # - An API request's process carries the cap, counting shared binaries,
  #   and killing the process past it.
  # - A LiveView's process carries the same cap.
  test "API request and LiveView processes each run under a heap cap that counts shared binaries",
       %{conn: conn} do
    refute capped?(self())

    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get("/api/v1/portfolios")
    |> json_response(200)

    # ConnTest runs the endpoint in the calling process: this IS the request
    # process.
    assert capped?(self())

    {:ok, view, _html} = live(build_conn(), "/")
    assert capped?(view.pid)
  end
end
