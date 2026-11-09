defmodule PortfolixirWeb.ApiV1NewsRegistryTest do
  # ADR-0056 §9, §10 and the coverage rule (AGENTS.md "Coverage runs both
  # ways"; Sprint 28, N7 coverage): the news page's Feeds and Quellen tabs
  # show each registered feed (URL, class, binding, language, paused) and
  # each rated source (domain, tier, by hand or default). GET
  # /api/v1/news/registry and portfolixir.news.registry list the same rows
  # to the agent, read through the context function the page reads.
  #
  # The budget (plan D-8, carry-forward 4, measured on the companion's
  # text): a page at the default limit of 40 rows of the worst-case
  # fixture — 40 feeds whose links are 300 characters wide as the companion
  # spells them, 100 sources of 253-character domains, every id at the
  # widest a bigint is — holds at most 4,500 tokens. The first two pages
  # (40 feeds; 40 sources) are written, ids and times normalized, to
  # mcp-server/test/fixtures/news-budget/registry-worst-case.json, which the
  # companion's test (news-registry.test.ts) runs through `callTool`; this
  # test fails when the fixture no longer matches what the server answers.
  # Regenerate it with PORTFOLIXIR_WRITE_NEWS_BUDGET=1. Synthetic names and
  # hosts only, every domain this module's own.
  use PortfolixirWeb.ConnCase

  import Portfolixir.NewsFixtures, only: [category!: 0, feed!: 1, security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Input.Text
  alias Portfolixir.News
  alias Portfolixir.News.Reads
  alias Portfolixir.News.Sources

  @agent_token String.duplicate("r", 40)
  @fixture Path.expand(
             "../../../mcp-server/test/fixtures/news-budget/registry-worst-case.json",
             __DIR__
           )

  # About 110 tokens a feed at its widest, 75 a source: 40 rows of feeds
  # are the heaviest page.
  @budget 4_500

  setup %{conn: conn} do
    previous = Application.get_env(:portfolixir, :api_tokens)
    Application.put_env(:portfolixir, :api_tokens, [{"mcp", @agent_token}])
    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> @agent_token)

    %{conn: conn}
  end

  defp registry(conn, query \\ ""), do: get(conn, "/api/v1/news/registry" <> query)

  # User story (ADR-0056 §10; AGENTS.md "Coverage runs both ways"):
  # As the operator's agent,
  # I want to read every registered feed and every rated source, as the
  # operator's page shows them,
  # so that I can check what the collector fetches and how each domain is
  # rated without asking the operator to read a screen to me.
  #
  # Acceptance criteria:
  # - Feeds come first, by id: id, url, class, the binding (security_id or
  #   category_id; none for an aggregator), language and enabled; then
  #   sources, by domain: domain, tier and set_by (hand or seed).
  # - Compact: a field without a value is left out, never null.
  # - A feed's link is cut at 300 characters as the companion spells it,
  #   as news.get cuts a story's.
  # - It is a read: it writes nothing and answers the same twice.
  test "lists every feed, then every rated source, compact", %{conn: conn} do
    security = security!("Registry Holding AG")
    category = category!()

    issuer = feed!(%{class: "issuer", security_id: security.id, language: "de"})

    thematic =
      feed!(%{class: "thematic", category_id: category.id, url: "https://themes.example.org/w"})

    aggregator =
      feed!(%{class: "aggregator", url: "https://reg-wire.example.org/rss", enabled: false})

    long = "https://reg-long.example.org/" <> String.duplicate(~s("), 400)
    long_feed = feed!(%{class: "aggregator", url: long})

    {:ok, _} = Sources.put_source(Actor.owner_ui(), "reg-ir.example.org", "primary")

    {:ok, _} =
      Sources.put_source(Actor.owner_ui(), "reg-wire.example.org", "secondary", set_by: :seed)

    data = conn |> registry() |> json_response(200) |> Map.fetch!("data")

    assert data["feeds"] == [
             %{
               "id" => issuer.id,
               "url" => issuer.url,
               "class" => "issuer",
               "security_id" => security.id,
               "language" => "de",
               "enabled" => true
             },
             %{
               "id" => thematic.id,
               "url" => "https://themes.example.org/w",
               "class" => "thematic",
               "category_id" => category.id,
               "language" => "en",
               "enabled" => true
             },
             %{
               "id" => aggregator.id,
               "url" => "https://reg-wire.example.org/rss",
               "class" => "aggregator",
               "language" => "en",
               "enabled" => false
             },
             %{
               "id" => long_feed.id,
               "url" => Reads.clip_spelled(long, 300),
               "class" => "aggregator",
               "language" => "en",
               "enabled" => true
             }
           ]

    assert String.ends_with?(List.last(data["feeds"])["url"], "…")

    assert data["sources"] == [
             %{"domain" => "reg-ir.example.org", "tier" => "primary", "set_by" => "hand"},
             %{"domain" => "reg-wire.example.org", "tier" => "secondary", "set_by" => "seed"}
           ]

    assert data["truncated"] == false
    assert data["limit"] == 40
    refute Map.has_key?(data, "cursor")
    assert conn |> registry() |> json_response(200) |> Map.fetch!("data") == data
  end

  # User story (ADR-0056 §9: "a truncated flag with a cursor instead of a
  # large page"):
  # As the operator's agent reading a large registry,
  # I want it in pages of `limit` rows with a cursor,
  # so that one answer stays within its budget and the walk loses no row
  # and repeats none.
  #
  # Acceptance criteria:
  # - limit (default 40, at most 100) counts feeds and sources together;
  #   a page with more behind it answers truncated and a cursor.
  # - Walking the cursor returns every feed, then every source, once each,
  #   also where a page ends exactly on the last feed.
  # - A limit above 100 reads 100, as every list read caps it; a limit
  #   below 1 or not a number, a cursor this read did not answer and a
  #   parameter it does not take answer 422 naming it.
  test "pages by limit and cursor, feeds then sources, without loss or repeat", %{conn: conn} do
    feeds =
      for n <- 1..3, do: feed!(%{class: "aggregator", url: "https://reg-p#{n}.example.org/rss"})

    domains = for n <- 1..3, do: "reg-page-#{n}.example.org"

    for domain <- domains,
        do: {:ok, _} = Sources.put_source(Actor.owner_ui(), domain, "secondary")

    walk = fn limit ->
      Stream.unfold({nil, true}, fn
        {_cursor, false} ->
          nil

        {cursor, true} ->
          query =
            "?limit=#{limit}" <>
              if(cursor, do: "&cursor=" <> URI.encode_www_form(cursor), else: "")

          data = conn |> registry(query) |> json_response(200) |> Map.fetch!("data")
          assert length(data["feeds"]) + length(data["sources"]) <= limit
          assert data["truncated"] == Map.has_key?(data, "cursor")
          {data, {data["cursor"], data["truncated"]}}
      end)
      |> Enum.to_list()
    end

    for limit <- [1, 2, 3, 4, 5, 6, 40] do
      pages = walk.(limit)

      assert Enum.flat_map(pages, & &1["feeds"]) |> Enum.map(& &1["id"]) ==
               Enum.map(feeds, & &1.id)

      assert Enum.flat_map(pages, & &1["sources"]) |> Enum.map(& &1["domain"]) == domains
      assert length(pages) == max(div(6 + limit - 1, limit), 1)
    end

    assert conn |> registry("?limit=101") |> json_response(200) |> get_in(["data", "limit"]) ==
             100

    for {query, field} <- [
          {"?limit=0", "limit"},
          {"?limit=ten", "limit"},
          {"?cursor=feed~x", "cursor"},
          {"?cursor=story~1", "cursor"},
          {"?cursor=source~NOT%20A%20DOMAIN", "cursor"},
          {"?since=2026-11-01", "since"}
        ] do
      errors = conn |> registry(query) |> json_response(422) |> Map.fetch!("errors")
      assert Map.has_key?(errors, field), "#{query}: #{inspect(errors)}"
    end
  end

  # A host of 253 characters, the most a name holds.
  defp long_host(n) do
    label = String.duplicate("r", 63)
    Enum.join([label, label, label, String.pad_trailing("reg#{n}", 53, "q"), "example"], ".")
  end

  defp tokens(%Plug.Conn{resp_body: body}),
    do: (body |> Text.escape_invisible() |> String.length()) / 4

  # Normalized so the fixture does not change with ids, every id the widest
  # a bigint is, and written in ASCII (every character beyond it a JSON \u
  # escape).
  defp normalize(body) do
    body
    |> String.replace(~r/"(\w*id)":\d+/, ~s("\\1":9223372036854775807))
    |> String.replace(~r/"cursor":"[^"]*"/, ~s("cursor":"feed~9223372036854775807"))
    |> Jason.decode!()
  end

  defp fixture!(pages) do
    normalized = Jason.encode!(Enum.map(pages, &normalize/1), pretty: true, escape: :unicode_safe)
    normalized = normalized <> "\n"

    if System.get_env("PORTFOLIXIR_WRITE_NEWS_BUDGET") == "1" do
      File.mkdir_p!(Path.dirname(@fixture))
      File.write!(@fixture, normalized)
    else
      assert File.read!(@fixture) == normalized,
             "#{@fixture} no longer matches the server's answer: regenerate it with " <>
               "PORTFOLIXIR_WRITE_NEWS_BUDGET=1 and rerun the companion's test"
    end
  end

  # User story (plan D-8, carry-forward 4; ADR-0056 §9):
  # As the operator whose agent pays for every token it reads,
  # I want the registry's pages to hold their budget on the text the
  # companion hands the agent, however long a feed's link or a domain,
  # so that one read of the registry cannot cost ten times its budget.
  #
  # Acceptance criteria (characters / 4 of the answer, counted in code
  # points, invisible characters spelled):
  # - 40 feeds, each link 400 double quotes long (two characters each in
  #   JSON) and cut to 300 as spelled, bound to a security or a category,
  #   some paused; 100 sources of 253-character domains rated by hand:
  #   every page at the default limit of 40 holds at most 4,500 tokens,
  #   and the walk takes four pages (40 feeds; 40, 40 and 20 sources).
  # - The first two pages are the fixture the companion's test measures.
  test "every page at the default limit holds its budget on the worst case", %{conn: conn} do
    security = security!("Registry Budget Holding AG")
    category = category!()

    for n <- 1..40 do
      binding =
        case rem(n, 3) do
          0 -> %{class: "regulatory", security_id: security.id}
          1 -> %{class: "thematic", category_id: category.id}
          2 -> %{class: "issuer", security_id: security.id}
        end

      url = "https://reg-budget-#{n}.example.org/" <> String.duplicate(~s("), 400)
      feed!(Map.merge(binding, %{url: url, language: "pt-br", enabled: rem(n, 2) == 0}))
    end

    for n <- 1..100,
        do: {:ok, _} = Sources.put_source(Actor.owner_ui(), long_host(n), "secondary")

    pages =
      Stream.unfold(nil, fn
        :done ->
          nil

        cursor ->
          query = if cursor, do: "?cursor=" <> URI.encode_www_form(cursor), else: ""
          answer = registry(conn, query)
          data = json_response(answer, 200)["data"]
          {{answer, data}, if(data["truncated"], do: data["cursor"], else: :done)}
      end)
      |> Enum.to_list()

    assert Enum.map(pages, fn {_answer, data} ->
             {length(data["feeds"]), length(data["sources"])}
           end) ==
             [{40, 0}, {0, 40}, {0, 40}, {0, 20}]

    for {answer, _data} <- pages do
      assert tokens(answer) <= @budget, "#{tokens(answer)} tokens"
    end

    pages |> Enum.take(2) |> Enum.map(fn {answer, _data} -> answer.resp_body end) |> fixture!()
  end

  # User story (ADR-0056 §10, plan D-1 criterion 6):
  # As the operator who reads the page while the agent reads the API,
  # I want both to read one context function,
  # so that the page cannot list a feed or a source the API does not.
  #
  # Acceptance criteria:
  # - `Portfolixir.News.registry/1` without a limit answers every feed and
  #   source the API's walk answers, in the same order.
  test "the API answers what the context's registry holds", %{conn: conn} do
    feed!(%{class: "aggregator", url: "https://reg-ctx.example.org/rss"})
    {:ok, _} = Sources.put_source(Actor.owner_ui(), "reg-ctx.example.org", "awareness")

    registry = News.registry()
    data = conn |> registry() |> json_response(200) |> Map.fetch!("data")

    assert Enum.map(data["feeds"], & &1["id"]) == Enum.map(registry.feeds, & &1.id)
    assert Enum.map(data["sources"], & &1["domain"]) == Enum.map(registry.sources, & &1.domain)
    assert registry.truncated == false
  end
end
