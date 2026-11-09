defmodule PortfolixirWeb.ApiV1NewsN34AttackTest do
  # Sprint 28 plan D-8 (carry-forwards 1 and 5): the order lens's attack on
  # the digest's consumer cursor (N3) and news.assign (N4) over the API.
  # The question each case asks: once a consumer confirms a cursor, can a
  # story it has not been shown fall behind its position for good? Cases
  # tagged `:n34_attack_red` show a loss the attack found and fail until it
  # is fixed. Synthetic names and hosts only, no socket.
  use PortfolixirWeb.ConnCase

  import Ecto.Query
  import Portfolixir.NewsFixtures, only: [feed!: 1, label!: 2]
  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.News.DigestConsumer
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Label
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
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer " <> @agent_token)

    %{conn: conn, now: DateTime.utc_now() |> DateTime.truncate(:second)}
  end

  defp hours_ago(now, hours), do: DateTime.add(now, -round(hours * 3600), :second)

  defp digest(conn, query), do: get(conn, "/api/v1/news/digest?" <> URI.encode_query(query))

  defp data(conn, status \\ 200), do: json_response(conn, status)["data"]

  defp row_ids(answer), do: Enum.map(answer["rows"], & &1["id"])

  defp watched!(name, token) do
    security = create_security!(name: name, ticker: nil, asset_class: "equity")

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_watch: true,
        news_aliases: [%{token: token, context: [], case: "insensitive"}]
      })

    security
  end

  defp release!(security, title, at) do
    n = System.unique_integer([:positive])
    item = struct!(Parsed, %{title: title, link: "https://ir.example.com/#{n}"})
    feed = feed!(%{class: "issuer", security_id: security.id})
    {:ok, %{stored: 1}} = Ingest.ingest(feed, [item], at)
  end

  defp aggregator_item!(title, at) do
    n = System.unique_integer([:positive])
    feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss-#{n}"})
    link = "https://search.example.com/r?u=#{n}"
    item = struct!(Parsed, %{title: title, link: link, source_domain: "wire.example.com"})
    {:ok, %{stored: 1}} = Ingest.ingest(feed, [item], at)
    Repo.get_by!(Item, canonical_url: link)
  end

  # User story (ADR-0056 §9 "at least once", plan D-1 criterion 4):
  # As the operator whose agent reads the digest under a consumer name with
  # the default max_rows,
  # I want a cursor never to confirm past a row the answer left out,
  # so that a busy day's thirteenth security is not lost to the agent.
  #
  # Acceptance criteria:
  # - A truncated answer's cursor, confirmed, still lets the consumer read
  #   the rows that answer left out. Since the closing act (AT5) a
  #   truncated consumer answer carries no cursor at all, only next_page;
  #   the page it names holds the row left out and the cursor, and
  #   confirming that cursor loses nothing.
  test "a truncated digest's cursor no longer confirms past the rows it left out",
       %{conn: conn, now: now} do
    securities =
      for n <- 1..13 do
        security = watched!("Truncation #{n} AG", "Truncation#{n}")
        release!(security, "Truncation #{n} release", hours_ago(now, 2))
        security
      end

    first = data(digest(conn, consumer: "busy-run"))
    assert first["truncated"] == true and first["more"] == 1
    [left_out] = Enum.map(securities, & &1.id) -- row_ids(first)

    # Observed before AT5: the first answer carried a cursor, and the call
    # confirming it answered rows [] and nothing truncated — the thirteenth
    # security's release was behind the confirmed position for good.
    assert first["cursor"] == nil
    assert is_binary(first["next_page"])

    next = data(digest(conn, consumer: "busy-run", page: first["next_page"]))

    assert left_out in row_ids(next),
           "the row the truncated answer left out (security #{left_out}) was not paged: " <>
             inspect(Map.take(next, ["rows", "truncated", "more", "since"]))

    confirmed = data(digest(conn, consumer: "busy-run", ack_cursor: next["cursor"]))
    assert row_ids(confirmed) == []
  end

  # User story (ADR-0056 §7 fail-open, §9 at least once, C5):
  # As the operator whose labeller runs after the fetcher,
  # I want an aggregator story the digest hid as unlabelled to reach my
  # agent once the labeller rates it material,
  # so that a confirmed cursor never turns "not labelled yet" into "never".
  #
  # Acceptance criteria:
  # - A story counted `hidden` (unlabelled) in an answer whose cursor the
  #   consumer confirms, then labelled materiality 3, reads in the
  #   consumer's next digest; the stateless digest over the same window
  #   shows it.
  # - Once that answer's cursor is confirmed, it does not read again
  #   (closing act, AT6: the label's time counts once, as a member's does).
  test "a story hidden as unlabelled and labelled after the confirmation reaches the consumer once",
       %{conn: conn, now: now} do
    northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
    item = aggregator_item!("Northwind Harbour issues a profit warning", hours_ago(now, 2))
    story = Repo.get!(Item, item.id).cluster_id
    assert is_integer(story)

    first = data(digest(conn, consumer: "label-lag-run"))
    assert first["hidden"] == 1
    assert row_ids(first) == []

    # The labeller runs after the agent's read, and before its next one.
    label!(story, materiality: 3)

    stateless = data(digest(conn, since: DateTime.to_iso8601(hours_ago(now, 24))))
    assert northwind.id in row_ids(stateless)

    next = data(digest(conn, consumer: "label-lag-run", ack_cursor: first["cursor"]))

    assert northwind.id in row_ids(next),
           "the material story was confirmed past while unlabelled: " <>
             inspect(Map.take(next, ["rows", "hidden", "since"]))

    # The label was written between the two reads; a test's two cursors
    # fall within one second, so its time is set where the wall clock
    # would have put it, before the second cursor's position.
    [seconds, _tag] = String.split(next["cursor"], "~")
    before_next = DateTime.add(DateTime.from_unix!(String.to_integer(seconds)), -1, :second)

    {:ok, _} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'synthetic-clock', true)")

        Repo.update_all(from(l in Label, where: l.cluster_id == ^story),
          set: [created_at: before_next, updated_at: before_next]
        )
      end)

    after_next = data(digest(conn, consumer: "label-lag-run", ack_cursor: next["cursor"]))
    refute northwind.id in row_ids(after_next)
  end

  # User story (plan D-8 carry-forward 5, the order lens; C3):
  # As the operator whose agent assigns an old item by hand after the
  # digest's consumer confirmed its position,
  # I want the item's story to read as new in that consumer's next digest,
  # so that news.assign never lands an item behind a confirmed position.
  #
  # Acceptance criteria:
  # - An aggregator item seen 2 hours ago, assigned over the API after the
  #   consumer confirmed, joins the target's (older) issuer story and that
  #   security reads in the consumer's next digest.
  test "an item assigned after the confirmation reads in the consumer's next digest",
       %{conn: conn, now: now} do
    _northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
    harbourline = watched!("Harbourline Shipping AG", "Harbourline")
    title = "Northwind Harbour reports third quarter results"
    release!(harbourline, title, hours_ago(now, 30))
    item = aggregator_item!(title, hours_ago(now, 2))

    first = data(digest(conn, consumer: "assign-run"))
    refute harbourline.id in row_ids(first)

    confirmed = data(digest(conn, consumer: "assign-run", ack_cursor: first["cursor"]))
    refute harbourline.id in row_ids(confirmed)

    assigned =
      put(
        conn,
        "/api/v1/news/items/#{item.id}/assignment",
        Jason.encode!(%{assignment: %{security_id: harbourline.id}})
      )

    assert %{"security_id" => security_id} = data(assigned)
    assert security_id == harbourline.id

    next = data(digest(conn, consumer: "assign-run", ack_cursor: confirmed["cursor"]))
    assert harbourline.id in row_ids(next)
  end

  # User story (ADR-0056 §9, the cap; plan D-8 security lens):
  # As the operator whose read-only agent may call the digest with a fresh
  # consumer name each run,
  # I want to know what the 32-consumer cap costs: here, characterised —
  # a read call with fresh names fills it, every new name answers 422
  # after, and no API path removes a consumer.
  test "read calls with fresh names fill the cap, and nothing over the API removes one",
       %{conn: conn} do
    for n <- 1..32, do: assert(%{"cursor" => _} = data(digest(conn, consumer: "fresh-#{n}")))

    assert %{"consumer" => [_]} =
             json_response(digest(conn, consumer: "the-labeller-run"), 422)["errors"]

    assert Repo.aggregate(DigestConsumer, :count) == 32

    for path <- ["/api/v1/news/digest/consumers/fresh-1", "/api/v1/news/consumers/fresh-1"] do
      assert delete(conn, path).status == 404, path
    end

    assert Repo.aggregate(DigestConsumer, :count) == 32
  end
end
