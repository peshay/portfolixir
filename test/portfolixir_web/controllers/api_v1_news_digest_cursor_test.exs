defmodule PortfolixirWeb.ApiV1NewsDigestCursorTest do
  # ADR-0056 §9 (Sprint 28, N3): the digest's consumer cursor, at least
  # once. Items are stored through the ingest at times relative to now;
  # synthetic names and hosts only, no socket.
  use PortfolixirWeb.ConnCase

  import Ecto.Query
  import Portfolixir.NewsFixtures, only: [feed!: 1]
  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.News
  alias Portfolixir.News.DigestConsumer
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.Repo
  alias PortfolixirWeb.Api.V1.DigestCursorKey

  @agent_token String.duplicate("a", 40)

  setup %{conn: conn} do
    previous = Application.get_env(:portfolixir, :api_tokens)
    Application.put_env(:portfolixir, :api_tokens, [{"mcp", @agent_token}])
    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> @agent_token)

    %{conn: conn, now: DateTime.utc_now() |> DateTime.truncate(:second)}
  end

  defp hours_ago(now, hours), do: DateTime.add(now, -round(hours * 3600), :second)

  defp digest(conn, query), do: get(conn, "/api/v1/news/digest?" <> URI.encode_query(query))

  defp data(conn, status \\ 200), do: json_response(conn, status)["data"]

  defp errors(conn), do: json_response(conn, 422)["errors"]

  defp held!(world, name) do
    security = create_security!(name: name, ticker: nil, asset_class: "equity")
    buy!(world, security, quantity: "1", price: "10")
    security
  end

  defp release!(security, title, link, at) do
    item = struct!(Parsed, %{title: title, link: link})
    feed = feed!(%{class: "issuer", security_id: security.id})
    {:ok, %{stored: 1}} = Ingest.ingest(feed, [item], at)
  end

  defp top_titles(conn), do: Enum.map(data(conn)["rows"], & &1["top"]["title"])

  defp consumer!(name), do: Repo.get_by!(DigestConsumer, name: name)

  # User story (ADR-0056 §9, plan D-1 criterion 4):
  # As the operator whose agent reads the news digest once a run,
  # I want the server to keep my agent's confirmed position, and to read
  # again from it until my agent confirms the cursor of an answer it has
  # handled,
  # so that a run that breaks off after the read loses no story, and two
  # agents reading the digest under their own names never move each other.
  #
  # Acceptance criteria:
  # - With `consumer` the digest reads from the consumer's confirmed
  #   position (a new consumer starts 24 hours back, the default window),
  #   answers it as `since`, and carries a `cursor`.
  # - A call without `ack_cursor` reads again from the confirmed position:
  #   the same stories come back.
  # - `ack_cursor` confirms that cursor before the read: the position moves
  #   to it, and the read starts there.
  # - Confirming a cursor older than the stored position changes nothing.
  # - One consumer's confirmation never moves another's position.
  # - A cursor the server did not issue to that consumer — forged, altered,
  #   or another consumer's — answers 422 naming `ack_cursor`, and nothing
  #   moves.
  # - `since` without `consumer` keeps no state; `since` beside `consumer`,
  #   `ack_cursor` without `consumer`, and a consumer name outside the
  #   identifier shape answer 422 naming the parameter.
  describe "GET /api/v1/news/digest with consumer" do
    test "a run that breaks off reads again; a confirmed cursor moves only its consumer",
         %{conn: conn, now: now} do
      world = base_world(name: "Cursor", cash_name: "Cash", depot_name: "Depot")
      northwind = held!(world, "Northwind Cursor AG")

      release!(
        northwind,
        "Northwind first release",
        "https://ir.example.com/1",
        hours_ago(now, 2)
      )

      first = digest(conn, consumer: "morning-run")
      assert %{"since" => since, "cursor" => cursor} = data(first)
      {:ok, start, 0} = DateTime.from_iso8601(since)
      assert abs(DateTime.diff(start, hours_ago(now, 24))) <= 2
      assert top_titles(first) == ["Northwind first release"]

      # The run breaks off: no confirmation. The next call reads the same.
      again = digest(conn, consumer: "morning-run")
      assert data(again)["since"] == since
      assert top_titles(again) == ["Northwind first release"]

      # Another consumer starts on its own.
      evening = digest(conn, consumer: "evening-run")
      assert top_titles(evening) == ["Northwind first release"]

      # The morning run confirms what it handled: the story is behind it.
      confirmed = digest(conn, consumer: "morning-run", ack_cursor: cursor)
      assert data(confirmed)["since"] > since
      assert top_titles(confirmed) == []
      assert %{"cursor" => _next} = data(confirmed)

      # The evening run did not move.
      assert top_titles(digest(conn, consumer: "evening-run")) == ["Northwind first release"]

      # A story entering scope after the confirmed position is new.
      release!(northwind, "Northwind second release", "https://ir.example.com/2", now)
      assert top_titles(digest(conn, consumer: "morning-run")) == ["Northwind second release"]
    end

    test "an older cursor is a no-op; a cursor not issued to the consumer is refused",
         %{conn: conn, now: now} do
      assert %{"cursor" => _} = data(digest(conn, consumer: "morning-run"))
      assert %{"cursor" => evening_cursor} = data(digest(conn, consumer: "evening-run"))

      morning = consumer!("morning-run")
      older = News.issue_digest_cursor(morning, hours_ago(now, 10), DigestCursorKey.key())
      newer = News.issue_digest_cursor(morning, hours_ago(now, 5), DigestCursorKey.key())

      assert data(digest(conn, consumer: "morning-run", ack_cursor: newer))["since"] ==
               iso(hours_ago(now, 5))

      # Older than the stored position: nothing moves back.
      assert data(digest(conn, consumer: "morning-run", ack_cursor: older))["since"] ==
               iso(hours_ago(now, 5))

      [position, tag] = String.split(newer, "~")
      later = Integer.to_string(String.to_integer(position) + 3600)

      for {cursor, what} <- [
            {evening_cursor, "another consumer's cursor"},
            {later <> "~" <> tag, "a cursor whose position was altered"},
            {position <> "~" <> String.duplicate("A", String.length(tag)), "a forged tag"},
            {"not-a-cursor", "a string of no cursor's shape"}
          ] do
        refused = digest(conn, consumer: "morning-run", ack_cursor: cursor)

        assert %{"ack_cursor" => [message]} = errors(refused), what
        assert message =~ "morning-run", what
      end

      # A consumer the server never issued a cursor to has none to confirm.
      assert %{"ack_cursor" => [_]} =
               errors(digest(conn, consumer: "night-run", ack_cursor: newer))

      refute Repo.get_by(DigestConsumer, name: "night-run")
      assert DateTime.compare(consumer!("morning-run").position, hours_ago(now, 5)) == :eq
      assert data(digest(conn, consumer: "morning-run"))["since"] == iso(hours_ago(now, 5))
    end

    test "since keeps no state, and the parameters are checked", %{conn: conn} do
      assert %{"as_of" => _} = data(digest(conn, since: "2026-11-01"))
      refute Map.has_key?(data(digest(conn, since: "2026-11-01")), "cursor")
      assert Repo.aggregate(DigestConsumer, :count) == 0

      assert %{"since" => [_]} = errors(digest(conn, consumer: "run", since: "2026-11-01"))
      assert %{"ack_cursor" => [_]} = errors(digest(conn, ack_cursor: "1~x"))

      for name <- ["", " run", "run run", String.duplicate("r", 65), "run\u200B", "-run"] do
        if name == "" do
          # An empty consumer is no consumer: the stateless digest.
          assert %{"as_of" => _} = data(digest(conn, consumer: name))
        else
          assert %{"consumer" => [_]} = errors(digest(conn, consumer: name)), inspect(name)
        end
      end

      assert Repo.aggregate(DigestConsumer, :count) == 0
    end

    test "the server keeps at most 32 consumers; a new one beyond answers 422 naming the cap",
         %{conn: conn} do
      for n <- 1..32, do: assert(%{"cursor" => _} = data(digest(conn, consumer: "run-#{n}")))

      assert %{"consumer" => [message]} = errors(digest(conn, consumer: "run-33"))
      assert message =~ "32"
      assert Repo.aggregate(DigestConsumer, :count) == 32

      # A stored consumer still reads.
      assert %{"cursor" => _} = data(digest(conn, consumer: "run-7"))
    end
  end

  test "the key a cursor is signed with is derived, never stored or answered", %{conn: conn} do
    answer = digest(conn, consumer: "morning-run")
    key = DigestCursorKey.key()
    assert byte_size(key) == 32
    refute key == PortfolixirWeb.Endpoint.config(:secret_key_base)

    for encoded <- [Base.encode64(key), Base.url_encode64(key, padding: false), key] do
      refute String.contains?(answer.resp_body, encoded)
    end

    assert DigestConsumer.__schema__(:fields) == [
             :id,
             :name,
             :position,
             :inserted_at,
             :updated_at
           ]

    assert [_] = Repo.all(from(c in DigestConsumer, select: c.name))
  end

  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)
end
