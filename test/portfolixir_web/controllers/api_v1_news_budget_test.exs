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

  # Sprint 28, N1 attack AT1: a name of one letter and 254 combining marks,
  # one grapheme and 255 characters on the wire, is cut like any other.
  @hostile_name "H" <> String.duplicate("\u0301", 254)

  defp held!(world, n, name \\ nil) do
    security =
      create_security!(
        name: name || "Holding #{n} Synthetic Group AG",
        ticker: nil,
        asset_class: "equity"
      )

    buy!(world, security, quantity: "1", price: "10")
    security
  end

  # Every name a digest row carries is at most 20 code points, the hostile
  # one among them (N1 attack AT1).
  defp assert_short_names!(digest) do
    names = Enum.map(json_response(digest, 200)["data"]["rows"], & &1["name"])
    assert Enum.any?(names, &String.starts_with?(&1, "H\u0301"))
    wide = Enum.filter(names, &(length(String.codepoints(&1)) > 20))

    assert wide == [],
           "names wider than 20 code points: #{inspect(Enum.map(wide, &length(String.codepoints(&1))), charlists: :as_lists)}"
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
  #   with tag-character titles: at most 800; one security named by one
  #   letter and 254 combining marks, its name cut to 20 code points;
  # - 20 list rows with tag-character titles: at most 1,500;
  # - news.get of a story with a tag-character title and excerpt, a link
  #   of 2,048 characters and five members: at most 400, its link included,
  #   which is cut to 300 characters with an ellipsis (the whole link stays
  #   stored); the item's answer too (closing act, AG1 rest);
  # - the worst case of the same, every domain of 253 characters: at most
  #   400 with its link, the domains cut to 40, and the excerpt cut to what
  #   the rest leaves; and a title and excerpt of JSON-quoted characters
  #   (`"`, `\`), each two characters on the wire: at most 400;
  # - each answer is the fixture the companion's test measures.
  test "digest, list and get hold their budgets with invisible characters spelled",
       %{conn: conn, now: now} do
    world = base_world(name: "Budget", cash_name: "Cash", depot_name: "Depot")
    securities = for n <- 1..28, do: held!(world, n, if(n == 1, do: @hostile_name))

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
    assert_short_names!(shy_digest)
    fixture!("digest-soft-hyphens", shy_digest)

    since = DateTime.to_iso8601(hours_ago(now, 40))
    tag_digest = get(conn, "/api/v1/news/digest?" <> URI.encode_query(since: since))
    assert tokens(tag_digest) <= 800, "digest (tag characters): #{tokens(tag_digest)}"
    assert_short_names!(tag_digest)

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
    assert tokens(one) <= 400, "get (tag characters, long link): #{tokens(one)}"
    fixture!("get-tag-characters", one)

    one_item = get(conn, "/api/v1/news/items/#{stored.id}")
    assert tokens(one_item) <= 400, "get item: #{tokens(one_item)}"

    # --- closing act, AG1 rest: the worst case, every domain at 253 --------
    worst = held!(world, 777)
    worst_link = "https://" <> long_host(0) <> "/"
    worst_link = worst_link <> String.duplicate("a", 2_048 - String.length(worst_link))

    ingest!(
      feed!(%{class: "issuer", security_id: worst.id}),
      [item(tag_title(777), worst_link, %{excerpt: tag_excerpt()})],
      hours_ago(now, 0.2)
    )

    for d <- 1..5 do
      ingest!(
        feed!(%{class: "issuer", security_id: worst.id}),
        [item(tag_title(777), "https://#{long_host(d)}/x", %{excerpt: tag_excerpt()})],
        hours_ago(now, 0.1)
      )
    end

    worst_item = Repo.get_by!(Item, canonical_url: worst_link)
    assert String.length(worst_item.domain) == 253

    worst_get = get(conn, "/api/v1/news/stories/#{worst_item.cluster_id}")
    worst_story = json_response(worst_get, 200)["data"]
    assert length(worst_story["members"]) == 5
    assert String.length(worst_story["url"]) == 300

    for domain <- [worst_story["domain"] | Enum.map(worst_story["members"], & &1["domain"])] do
      assert String.length(domain) == 40 and String.ends_with?(domain, "…"), domain
    end

    assert tokens(worst_get) <= 400, "get (worst case): #{tokens(worst_get)}"
    fixture!("get-worst-case", worst_get)

    worst_one = get(conn, "/api/v1/news/items/#{worst_item.id}")
    assert tokens(worst_one) <= 400, "get item (worst case): #{tokens(worst_one)}"

    quoted = held!(world, 778)
    quote_link = "https://ir.example.com/q"

    ingest!(
      feed!(%{class: "issuer", security_id: quoted.id}),
      [
        item("Quote " <> String.duplicate(~s("), 154), quote_link, %{
          excerpt: String.duplicate("\\", 600)
        })
      ],
      hours_ago(now, 0.2)
    )

    quote_item = Repo.get_by!(Item, canonical_url: quote_link)
    quote_get = get(conn, "/api/v1/news/stories/#{quote_item.cluster_id}")
    assert tokens(quote_get) <= 400, "get (JSON-quoted text): #{tokens(quote_get)}"
    # --- end closing act, AG1 rest ------------------------------------------
  end

  # A host of 253 characters, the most a name holds: three labels of 63
  # and one of 53, then `.example`.
  defp long_host(d) do
    label = String.duplicate("n", 63)
    Enum.join([label, label, label, String.pad_trailing("m#{d}", 53, "m"), "example"], ".")
  end
end
