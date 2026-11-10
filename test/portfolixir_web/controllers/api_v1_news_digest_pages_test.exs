defmodule PortfolixirWeb.ApiV1NewsDigestPagesTest do
  # ADR-0056 §9 (Sprint 28 closing act, AT5): a consumer's truncated digest
  # is paged, and only its last page carries the cursor the consumer
  # confirms, so a confirmation never passes a row an answer left out.
  # Items are stored through the ingest at times relative to now; synthetic
  # names and hosts only, no socket.
  use PortfolixirWeb.ConnCase

  import Portfolixir.NewsFixtures, only: [feed!: 1]
  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.News.DigestConsumer
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.Repo

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

  defp data(conn), do: json_response(conn, 200)["data"]

  defp errors(conn), do: json_response(conn, 422)["errors"]

  defp row_ids(answer), do: Enum.map(answer["rows"], & &1["id"])

  defp position(name), do: Repo.get_by!(DigestConsumer, name: name).position

  defp watched!(name, token) do
    security = create_security!(name: name, ticker: nil, asset_class: "equity")

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_watch: true,
        news_aliases: [%{token: token, context: [], case: "insensitive"}]
      })

    security
  end

  defp released!(prefix, count, at) do
    for n <- 1..count do
      security = watched!("#{prefix} #{n} AG", "#{prefix}#{n}")
      item = struct!(Parsed, %{title: "#{prefix} #{n} release", link: link()})
      feed = feed!(%{class: "issuer", security_id: security.id})
      {:ok, %{stored: 1}} = Ingest.ingest(feed, [item], at)
      security.id
    end
  end

  defp link, do: "https://ir.example.com/#{System.unique_integer([:positive])}"

  # Every page of one read, from its first call (`query`) to the page that
  # carries the cursor: the answers in order.
  defp pages(conn, query) do
    first = data(digest(conn, query))

    Stream.unfold(first, fn
      nil ->
        nil

      %{"next_page" => token} = answer ->
        refute Map.has_key?(answer, "cursor")
        {answer, data(digest(conn, consumer: query[:consumer], page: token))}

      answer ->
        {answer, nil}
    end)
    |> Enum.to_list()
  end

  # User story (ADR-0056 §9 "at least once", plan D-1 criterion 4):
  # As the operator whose agent reads the digest under a consumer name on a
  # busy day,
  # I want an answer that cannot hold every row to be paged, and only its
  # last page to carry the cursor my agent confirms,
  # so that no row an answer left out falls behind the confirmed position,
  # whatever arrives while my agent pages.
  #
  # Acceptance criteria:
  # - 13 securities with news, max_rows 10 (12 before the closing act's
  #   AG1): the first page has 10 rows, truncated, more 3 and next_page,
  #   and no cursor; the page next_page names has the other 3 and the
  #   cursor.
  # - 13 more securities' news arriving between the pages: page and ack
  #   lose none of the 26; the next read (paged again) has the 13 new ones.
  # - Paging moves no position; only the confirmation does.
  test "13 + 13 securities across two pages and an ack lose none", %{conn: conn, now: now} do
    early = released!("Pageone", 13, hours_ago(now, 2))

    first = data(digest(conn, consumer: "paging-run"))
    assert length(first["rows"]) == 10
    assert %{"truncated" => true, "more" => 3, "next_page" => _} = first
    refute Map.has_key?(first, "cursor")
    start = position("paging-run")

    # The 13 later ones arrive between the first page and the second.
    late = released!("Pagetwo", 13, DateTime.utc_now())

    second = data(digest(conn, consumer: "paging-run", page: first["next_page"]))
    assert %{"cursor" => cursor} = second
    refute Map.has_key?(second, "next_page")
    assert second["truncated"] == false
    assert ((row_ids(first) ++ row_ids(second)) -- late) |> Enum.sort() == Enum.sort(early)
    assert position("paging-run") == start

    after_ack = pages(conn, consumer: "paging-run", ack_cursor: cursor)
    assert DateTime.compare(position("paging-run"), start) == :gt
    seen = Enum.flat_map([first, second | after_ack], &row_ids/1)

    assert Enum.sort(early ++ late) -- seen == []
    assert Enum.sort(late) -- Enum.flat_map(after_ack, &row_ids/1) == []
    assert %{"cursor" => _} = List.last(after_ack)
  end

  # User story (ADR-0056 §9; the security lens):
  # As the operator whose two agents page the digest under their own names
  # at once,
  # I want a page to be its consumer's own and to move nothing,
  # so that neither agent skips the other's rows or moves its position.
  #
  # Acceptance criteria:
  # - Two consumers paging at once each read their own pages; one's page
  #   token sent under the other's name answers 422 naming page.
  # - No page moves a position; one consumer's confirmation moves only its
  #   own, and the other's page token still reads.
  test "two consumers paging concurrently never move each other", %{conn: conn, now: now} do
    ids = released!("Twopager", 13, hours_ago(now, 2))

    a1 = data(digest(conn, consumer: "run-a"))
    b1 = data(digest(conn, consumer: "run-b"))
    {a_start, b_start} = {position("run-a"), position("run-b")}

    assert %{"page" => [_]} = errors(digest(conn, consumer: "run-a", page: b1["next_page"]))
    assert %{"page" => [_]} = errors(digest(conn, consumer: "run-b", page: a1["next_page"]))

    a2 = data(digest(conn, consumer: "run-a", page: a1["next_page"]))
    assert Enum.sort(row_ids(a1) ++ row_ids(a2)) == Enum.sort(ids)
    assert {position("run-a"), position("run-b")} == {a_start, b_start}

    data(digest(conn, consumer: "run-a", ack_cursor: a2["cursor"]))
    assert DateTime.compare(position("run-a"), a_start) == :gt
    assert position("run-b") == b_start

    b2 = data(digest(conn, consumer: "run-b", page: b1["next_page"]))
    refute Map.has_key?(b2, "restarted")
    assert Enum.sort(row_ids(b1) ++ row_ids(b2)) == Enum.sort(ids)
  end

  # User story (ADR-0056 §9; the security lens):
  # As the operator whose agent holds a page token and a cursor at once,
  # I want neither to pass for the other, and an edited or borrowed one
  # refused,
  # so that no client confirms a position by a page or skips rows by a
  # cursor.
  #
  # Acceptance criteria:
  # - A page token sent as ack_cursor answers 422 naming ack_cursor, and a
  #   cursor sent as page 422 naming page; nothing moves.
  # - An edited page token (each part) answers 422 naming page.
  # - page without consumer, and page beside ack_cursor, answer 422 naming
  #   page.
  test "a page token is no cursor, a cursor no page, and an edited one is refused",
       %{conn: conn, now: now} do
    released!("Tokenpage", 13, hours_ago(now, 2))
    first = data(digest(conn, consumer: "token-run"))
    token = first["next_page"]
    start = position("token-run")

    second = data(digest(conn, consumer: "token-run", page: token))
    cursor = second["cursor"]

    assert %{"ack_cursor" => [_]} =
             errors(digest(conn, consumer: "token-run", ack_cursor: token))

    assert %{"page" => [_]} = errors(digest(conn, consumer: "token-run", page: cursor))
    assert position("token-run") == start

    parts = String.split(token, "~")

    edits =
      for index <- 0..(length(parts) - 1) do
        parts |> List.update_at(index, &(&1 <> "0")) |> Enum.join("~")
      end

    for edited <- edits ++ [token <> "~", "~" <> token, String.replace(token, "~", "-")] do
      assert %{"page" => [_]} = errors(digest(conn, consumer: "token-run", page: edited)),
             edited
    end

    assert %{"page" => [_]} = errors(digest(conn, page: token))

    assert %{"page" => [_]} =
             errors(digest(conn, consumer: "token-run", page: token, ack_cursor: cursor))

    assert position("token-run") == start
  end

  # User story (ADR-0056 §9):
  # As the operator whose agent resumes paging after another run of the
  # same consumer confirmed a newer position,
  # I want the stale page to start again from the confirmed position, and
  # to say so,
  # so that the agent neither skips the rows after it nor mistakes a fresh
  # first page for the rest of its old read.
  #
  # Acceptance criteria:
  # - A page token issued before the position moved answers the first page
  #   from the new position, with restarted true; its since is the new
  #   position.
  test "a page whose position moved meanwhile starts again from it, flagged",
       %{conn: conn, now: now} do
    released!("Stalepage", 13, hours_ago(now, 2))
    stale = data(digest(conn, consumer: "stale-run"))["next_page"]

    [_first, last] = pages(conn, consumer: "stale-run") |> then(&[hd(&1), List.last(&1)])
    released!("Stalelate", 2, DateTime.utc_now())
    moved = data(digest(conn, consumer: "stale-run", ack_cursor: last["cursor"]))
    assert length(moved["rows"]) == 2
    refute Map.has_key?(moved, "restarted")

    restarted = data(digest(conn, consumer: "stale-run", page: stale))
    assert restarted["restarted"] == true
    assert restarted["since"] == moved["since"]
    assert restarted["rows"] == moved["rows"]
    assert Map.has_key?(restarted, "cursor")
  end
end
