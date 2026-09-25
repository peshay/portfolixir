defmodule PortfolixirWeb.ApiV1DeltaCursorTest do
  # E25 S6 (#891), G06: a row's updated_at is stamped when its transaction
  # writes it, not when that transaction commits, and a delta read's `as_of`
  # was the read instant less one second. A writer whose transaction stayed
  # open past a poll committed a row stamped before that poll's `as_of`, so
  # the next poll — cut strictly after `as_of` — never delivered it.
  # Commit-ordered cursors are the long-term design (issue #897); this pins
  # the bound that closes the loss today.
  use PortfolixirWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures
  alias PortfolixirWeb.Api.V1.SinceParam

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  # A writer on a connection of its own, outside the sandbox: it opens a
  # transaction, writes (so it holds a transaction id, as every writer
  # does), reports the stamp a row it writes carries, and stays open until
  # told. Its write is rolled back: nothing it does outlives the test.
  defp open_writer do
    parent = self()

    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.transaction(fn ->
          Repo.query!("INSERT INTO derived_data_version_events (basis) VALUES ('g06-writer')")
          send(parent, {:stamped, NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)})

          receive do
            :finish -> Repo.rollback(:done)
          end
        end)
      end)
    end)
  end

  defp backdate!(security, naive) do
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test_backdate', true)")
    Repo.query!("UPDATE securities SET updated_at = $1 WHERE id = $2", [naive, security.id])
  end

  # User story:
  # As an agent polling a delta read with the `as_of` of my last poll,
  # I want a row written by a transaction that was still open during that
  # poll to come back on the next one,
  # so that a long import never leaves rows my copy will never see.
  #
  # Acceptance criteria:
  # - While a writer's transaction is open, a poll's `as_of` lies no later
  #   than one second before that transaction's first write.
  # - The row the writer stamped then — committed after the poll — is
  #   delivered by the next poll from that `as_of`.
  test "a row stamped before a poll but committed after it is delivered by the next poll from the returned as_of",
       %{conn: conn} do
    writer = open_writer()
    assert_receive {:stamped, stamp}, 5_000

    # The poll happens more than the margin after the writer's stamp.
    Process.sleep(1_200)

    first =
      conn
      |> api_conn()
      |> get("/api/v1/securities?since=2026-01-01T00:00:00Z")
      |> json_response(200)

    send(writer.pid, :finish)
    Task.await(writer)

    # What the writer committed: a row carrying the stamp it took inside its
    # transaction, visible only now.
    security = WorldFixtures.create_security!(name: "Harbor Light Utilities SE", ticker: "HLU")
    backdate!(security, stamp)

    next =
      build_conn()
      |> api_conn()
      |> get("/api/v1/securities?since=#{first["as_of"]}")
      |> json_response(200)

    assert security.id in Enum.map(next["data"], & &1["id"]),
           "a row stamped #{stamp} was lost by a poll from #{first["as_of"]}"
  end

  test "as_of never passes the read instant less the margin" do
    {:ok, parsed} = SinceParam.parse(%{"since" => "2026-06-01"})
    now = DateTime.truncate(DateTime.utc_now(), :second)
    assert DateTime.compare(parsed.as_of, DateTime.add(now, -1, :second)) in [:lt, :eq]
  end
end
