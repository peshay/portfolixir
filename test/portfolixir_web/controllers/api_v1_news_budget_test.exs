defmodule PortfolixirWeb.ApiV1NewsBudgetTest do
  # ADR-0056 §9, §14 item 2 and the amendment of 2026-11-08, C5 (Sprint 27
  # closing act, AG1): the agent's reads hold their budgets on the text the
  # companion returns, where every invisible character is spelled
  # `[U+XXXX]` (ADR-0054 §4). Items are stored through the ingest at times
  # relative to now; synthetic names and hosts only, no socket.
  #
  # The answers are also written, with ids and times normalized, to
  # mcp-server/test/fixtures/news-budget/, and the companion's test runs
  # them through `callTool` and counts what the tool returns; this test
  # fails when they no longer match what the server answers. Regenerate
  # them with PORTFOLIXIR_WRITE_NEWS_BUDGET=1.
  use PortfolixirWeb.ConnCase

  import Portfolixir.NewsFixtures, only: [feed!: 1]
  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Input.Text
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.Repo

  @agent_token String.duplicate("a", 40)
  @fixtures Path.expand("../../../mcp-server/test/fixtures/news-budget", __DIR__)

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

  @shy "\u00AD"
  @tag_a <<0xE0041::utf8>>

  defp hours_ago(now, hours), do: DateTime.add(now, -round(hours * 3600), :second)

  defp ingest!(feed, items, at) do
    {:ok, %{stored: stored}} = Ingest.ingest(feed, items, at)
    assert stored == length(items)
  end

  defp item(title, link, attrs \\ %{}),
    do: struct!(Parsed, Map.merge(%{title: title, link: link}, attrs))

  # 160 code points: a soft hyphen after every letter, each spelled
  # [U+00AD], eight characters, where the operator sees nothing.
  defp shy_title(n) do
    "Holding #{n} quarterly release and outlook raised"
    |> String.graphemes()
    |> Enum.map_join(&(&1 <> @shy))
    |> String.slice(0, 160)
  end

  # 160 code points: a few words, then tag characters, which a grapheme
  # count reads as one character.
  defp tag_title(n), do: String.pad_trailing("Profit warning #{n} ", 160, @tag_a)

  defp tag_excerpt, do: String.pad_trailing("Excerpt ", 600, @tag_a)

  # Characters / 4 of what the companion returns: invisible characters
  # spelled, counted in code points.
  defp tokens(%Plug.Conn{resp_body: body}),
    do: (body |> Text.escape_invisible() |> String.length()) / 4

  defp held!(world, n) do
    security =
      create_security!(
        name: "Holding #{n} Synthetic Group AG",
        ticker: nil,
        asset_class: "equity"
      )

    buy!(world, security, quantity: "1", price: "10")
    security
  end

  # Normalized so the fixture does not change with ids and the clock, and
  # written in ASCII: every character beyond it as a JSON \u escape, so the
  # file holds no raw invisible character (the pre-commit hooks refuse one).
  defp normalize(body) do
    body
    |> String.replace(~r/\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z/, "2026-11-08T09:00:00Z")
    |> String.replace(~r/"(\w*id)":\d+/, ~s("\\1":1))
    |> String.replace(~r/~\d+"/, ~s(~1"))
    |> Jason.decode!()
    |> Jason.encode!(pretty: true, escape: :unicode_safe)
  end

  defp fixture!(name, %Plug.Conn{resp_body: body}) do
    path = Path.join(@fixtures, name <> ".json")
    normalized = normalize(body) <> "\n"

    if System.get_env("PORTFOLIXIR_WRITE_NEWS_BUDGET") == "1" do
      File.mkdir_p!(@fixtures)
      File.write!(path, normalized)
    else
      assert File.read!(path) == normalized,
             "#{path} no longer matches the server's answer: regenerate it with " <>
               "PORTFOLIXIR_WRITE_NEWS_BUDGET=1 and rerun the companion's budget test"
    end
  end

  # User story (ADR-0056 §9, §14 item 2; the amendment of 2026-11-08, C5):
  # As the operator whose agent pays for every token it reads,
  # I want the digest, a list page and one story to hold their budgets on
  # the text the companion hands the agent, whatever invisible characters
  # a feed put in its titles and excerpts and however long its links,
  # so that a hostile feed cannot make a news read cost ten times its
  # budget.
  #
  # Acceptance criteria (characters / 4 of the answer with every invisible
  # character spelled [U+XXXX], counted in code points):
  # - the digest at its default max_rows, 14 securities active, titles of
  #   160 code points with a soft hyphen after every letter: at most 800;
  #   with tag-character titles: at most 800;
  # - 20 list rows with tag-character titles: at most 1,500;
  # - news.get of a story with a tag-character title and excerpt, a link
  #   of 2,048 characters and five members: at most 400 besides its link,
  #   which is cut to 300 characters with an ellipsis (the whole link stays
  #   stored). The link stands outside the budget: a 160-character title, a
  #   600-character excerpt and five members leave about 100 characters of
  #   400 tokens, and a link cut that short would be a wrong `source_url`
  #   for the research log; 300 keeps ordinary links whole and costs at
  #   most 75 tokens;
  # - each answer is the fixture the companion's test measures.
  test "digest, list and get hold their budgets with invisible characters spelled",
       %{conn: conn, now: now} do
    world = base_world(name: "Budget", cash_name: "Cash", depot_name: "Depot")
    securities = for n <- 1..28, do: held!(world, n)

    securities
    |> Enum.with_index(1)
    |> Enum.each(fn {security, n} ->
      title = if n <= 14, do: shy_title(n), else: tag_title(n)
      at = if n <= 14, do: hours_ago(now, 2 + n * 0.1), else: hours_ago(now, 30)

      ingest!(
        feed!(%{class: "issuer", security_id: security.id}),
        [item(title, "https://ir#{n}.example.com/r/#{n}")],
        at
      )
    end)

    shy_digest = get(conn, "/api/v1/news/digest")
    assert %{"truncated" => true} = json_response(shy_digest, 200)["data"]
    assert tokens(shy_digest) <= 800, "digest (soft hyphens): #{tokens(shy_digest)}"
    fixture!("digest-soft-hyphens", shy_digest)

    since = DateTime.to_iso8601(hours_ago(now, 40))
    tag_digest = get(conn, "/api/v1/news/digest?" <> URI.encode_query(since: since))
    assert tokens(tag_digest) <= 800, "digest (tag characters): #{tokens(tag_digest)}"

    busy = hd(securities)
    busy_feed = feed!(%{class: "issuer", security_id: busy.id})

    for n <- 1..21 do
      ingest!(
        busy_feed,
        [item(tag_title(100 + n), "https://ir.example.com/t/#{n}")],
        hours_ago(now, 1 + n * 0.01)
      )
    end

    page = get(conn, "/api/v1/news/stories?security_id=#{busy.id}")
    assert length(json_response(page, 200)["data"]["rows"]) == 20
    assert tokens(page) <= 1_500, "20 list rows (tag characters): #{tokens(page)}"
    fixture!("list-tag-characters", page)

    long = "https://ir.example.com/" <> String.duplicate("a", 2_048 - 23)

    ingest!(
      busy_feed,
      [item(tag_title(999), long, %{excerpt: tag_excerpt()})],
      hours_ago(now, 0.2)
    )

    for d <- 1..5 do
      ingest!(
        feed!(%{class: "issuer", security_id: busy.id}),
        [item(tag_title(999), "https://newsroom-#{d}.example.com/x", %{excerpt: tag_excerpt()})],
        hours_ago(now, 0.1)
      )
    end

    stored = Repo.get_by!(Item, canonical_url: long)
    assert String.length(stored.canonical_url) == 2_048

    one = get(conn, "/api/v1/news/stories/#{stored.cluster_id}")
    story = json_response(one, 200)["data"]
    assert String.length(story["url"]) == 300 and String.ends_with?(story["url"], "…")
    assert tokens(one) - 300 / 4 <= 400, "get (tag characters, long link): #{tokens(one)}"
    fixture!("get-tag-characters", one)

    one_item = get(conn, "/api/v1/news/items/#{stored.id}")
    assert tokens(one_item) - 300 / 4 <= 400, "get item: #{tokens(one_item)}"
  end
end
