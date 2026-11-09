defmodule PortfolixirWeb.ApiV1DossierNewsTest do
  # ADR-0056 §9's extension (Sprint 28, N6; plan D-8, carry-forward 4):
  # securities.dossier gains a news block — the stories of the last 7 days,
  # how many are primary, their highest materiality, and the newest primary
  # story — held to about 50 tokens on the text the companion returns.
  #
  # The block is also written, ids and times normalized, to
  # mcp-server/test/fixtures/news-budget/dossier-news.json, and the
  # companion's test (news-dossier.test.ts) runs it through `callTool` and
  # counts what the tool returns; this test fails when the fixture no longer
  # matches what the server answers. Regenerate it with
  # PORTFOLIXIR_WRITE_NEWS_BUDGET=1. Synthetic names and hosts only, every
  # domain this module's own.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Actor
  alias Portfolixir.Input.Text
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Item
  alias Portfolixir.News.Reads
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo

  @fixture Path.expand(
             "../../../mcp-server/test/fixtures/news-budget/dossier-news.json",
             __DIR__
           )

  # About 50 tokens: characters / 4 of the block as the companion spells it.
  @budget 50

  @tag_a <<0xE0041::utf8>>

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # One story of `security`: an item of an issuer feed (primary) or of an
  # aggregator feed on a domain of this module rated secondary, first seen
  # `hours` ago, clustered.
  defp story!(security, title, class, hours) do
    n = System.unique_integer([:positive])
    domain = "dossier-#{n}.example.org"
    {:ok, _} = Sources.put_source(Actor.owner_ui(), domain, :secondary)

    feed =
      if class == :issuer,
        do: NewsFixtures.feed!(%{class: "issuer", security_id: security.id}),
        else: NewsFixtures.feed!(%{class: "aggregator"})

    link = "https://#{domain}/n/#{n}"
    at = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)

    item =
      %Item{}
      |> Item.changeset(
        Map.merge(Stories.title_keys(title), %{
          feed_id: feed.id,
          class: feed.class,
          security_id: security.id,
          assignment: :assigned,
          first_seen_at: at,
          title: title,
          canonical_url: link,
          domain: domain,
          tier: Sources.tier_for(domain, feed.class),
          language: "en",
          content_hash: :sha256 |> :crypto.hash(link) |> Base.encode16(case: :lower)
        })
      )
      |> Repo.insert!()

    {:ok, _} = Stories.recluster({:security, security.id}, "en", DateTime.utc_now())
    Repo.get!(Cluster, Repo.get!(Item, item.id).cluster_id)
  end

  defp news(conn, security),
    do: conn |> get("/api/v1/securities/#{security.id}/dossier") |> json_response(200)

  defp spelled(block), do: block |> Jason.encode!() |> Text.escape_invisible()

  defp normalize(block) do
    block
    |> Jason.encode!()
    |> String.replace(~r/\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ/, "2026-11-09T09:00:00Z")
    |> String.replace(~r/"id":\d+/, ~s("id":1))
    |> Jason.decode!()
    |> then(&%{"data" => %{"security_id" => 1, "news" => &1}})
    |> Jason.encode!(pretty: true, escape: :unicode_safe)
  end

  defp fixture!(block) do
    normalized = normalize(block) <> "\n"

    if System.get_env("PORTFOLIXIR_WRITE_NEWS_BUDGET") == "1" do
      File.write!(@fixture, normalized)
    else
      assert File.read!(@fixture) == normalized,
             "#{@fixture} no longer matches the server's answer: regenerate it with " <>
               "PORTFOLIXIR_WRITE_NEWS_BUDGET=1 and rerun the companion's test"
    end
  end

  # User story (ADR-0056 §9, "securities.dossier gains a news block"):
  # As the operating agent starting a research run from the dossier,
  # I want to see at once how much news the security had this week, how
  # much of it primary, the most material label, and the newest primary
  # story,
  # so that I know whether to read the news before I read anything else.
  #
  # Acceptance criteria:
  # - news.count_7d counts the security's stories that had a member enter
  #   their scope within 7 days (news.list's since), primary_7d those whose
  #   best tier is primary; max_materiality is the highest materiality of
  #   their active labels (newest prompt version); newest_primary is its
  #   newest primary story at any age (id, title cut at 50 as the companion
  #   spells it, at), the order of news.list.
  # - A story older than 7 days is not counted; a security without news
  #   answers 0, 0 and nulls.
  # - parts.news names news.list.
  # - With a title of 160 tag characters, the block holds 50 tokens on the
  #   companion's text (ids at their widest), and it is the fixture the
  #   companion's test measures.
  test "the dossier carries the news block within its budget", %{conn: conn} do
    security = NewsFixtures.security!("Dossier News AG")
    hostile = String.pad_trailing("Profit warning ", 160, @tag_a)

    _old = story!(security, "Dossier News AG older release", :issuer, 24 * 10)
    issuer = story!(security, hostile, :issuer, 30)
    wire = story!(security, "Dossier News AG on the wire", :aggregator, 5)
    _other = story!(security, "Dossier News AG in the press", :aggregator, 2)
    NewsFixtures.label!(wire.id, materiality: 3)
    NewsFixtures.label!(issuer.id, materiality: 1)

    data = news(conn, security)["data"]
    block = data["news"]

    assert data["parts"]["news"] =~ "portfolixir.news.list"
    assert %{"count_7d" => 3, "primary_7d" => 1, "max_materiality" => 3} = block

    assert %{"id" => id, "title" => title, "at" => at} = block["newest_primary"]
    assert id == issuer.id
    assert String.ends_with?(title, "…")
    assert Reads.spelled_width(title) <= 50
    assert {:ok, _at, 0} = DateTime.from_iso8601(at)

    widest = put_in(block, ["newest_primary", "id"], 9_223_372_036_854_775_807)
    chars = widest |> spelled() |> String.length()
    assert chars / 4 <= @budget, "news block: #{chars / 4} tokens"

    fixture!(block)

    quiet = NewsFixtures.security!("Dossier Quiet AG")

    assert news(conn, quiet)["data"]["news"] == %{
             "count_7d" => 0,
             "primary_7d" => 0,
             "max_materiality" => nil,
             "newest_primary" => nil
           }
  end
end
