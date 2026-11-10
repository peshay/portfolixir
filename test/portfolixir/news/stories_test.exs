defmodule Portfolixir.News.StoriesTest do
  # ADR-0056 §4, §14 item 3, B3, B4 and B5 (Sprint 27, N5): stories as
  # connected components, their survivor and representative never by id
  # or by order. Synthetic data only; the rated domains are this module's
  # own (`*.stories-test.example.com`), so no other async module's
  # uncommitted rating blocks or is blocked by them (Sprint 28, #1424).
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Item
  alias Portfolixir.News.Reads
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.Repo
  alias Portfolixir.Settings
  alias Portfolixir.WorldFixtures

  @t ~U[2026-11-03 07:00:00.000000Z]
  @agent Actor.api_token_rw("synthetic-agent")

  @q3 "Northwind Harbour Logistics reports third quarter 2026 results"
  @cfo "Northwind Harbour names new chief financial officer"
  @q3_de "Northwind Harbour Logistics meldet Ergebnisse für das dritte Quartal 2026"

  # The fixture: {key, feed, domain, title, claimed (hours after @t), seen
  # (hours after @t), language}. Hours are decimals of minutes where needed.
  @fixture [
    # The same release from several domains, reworded (§14 item 3): one story.
    {:q3_issuer, :issuer, "newsroom.northwind.example", @q3, 0, 5 / 60, "en"},
    # A future claim, clamped to its first sight (B4).
    {:q3_reg, :regulatory, "filings.regulator.example",
     "Northwind Harbour Logistics: third quarter 2026 results", 24 * 28, 3, "en"},
    # An aggregator naming a primary domain, with the earliest claim of all:
    # secondary (B5), never the representative over a true primary.
    {:q3_wire, :aggregator, "wire.stories-test.example.com", @q3, -1, 40 / 60, "en"},
    {:q3_daily, :aggregator, "daily.stories-test.example.com",
     "NORTHWIND HARBOUR LOGISTICS REPORTS THIRD-QUARTER 2026 RESULTS!", 10 / 60, 50 / 60, "en"},
    # Eight shared words of ten: a Jaccard similarity of exactly 0.8.
    {:q3_chatter, :aggregator, "chatter.example.org",
     "Northwind Harbour Logistics reports third quarter 2026 results, beats estimates", 20 / 60,
     1, "en"},
    # A zero-width space inside a word does not dodge the dedupe.
    {:q3_zw, :aggregator, "gossip.example.org",
     "North\u200Bwind Harbour Logistics reports third quarter 2026 results", 15 / 60, 55 / 60,
     "en"},
    # A ~ B, B ~ C, A not ~ C: one story whatever the order.
    {:chain_a, :aggregator, "daily.stories-test.example.com",
     "Northwind Harbour opens new container terminal at Baltic deepwater port", 30, 30, "en"},
    {:chain_b, :aggregator, "chatter.example.org",
     "Northwind Harbour unveils new container terminal at Baltic deepwater port", 31, 31, "en"},
    {:chain_c, :aggregator, "wire.stories-test.example.com",
     "Northwind Harbour unveils second container terminal at Baltic deepwater port", 32, 32,
     "en"},
    # Linked through time: x ~ y and y ~ z are 60 hours apart, x and z 120.
    {:cfo_x, :issuer, "newsroom.northwind.example", @cfo, 1, 1, "en"},
    {:cfo_y, :aggregator, "daily.stories-test.example.com", @cfo, 61, 61, "en"},
    {:cfo_z, :aggregator, "chatter.example.org", @cfo, 121, 121, "en"},
    # The same title outside the 72 hours: a story of its own.
    {:q3_late, :aggregator, "daily.stories-test.example.com", @q3, 100, 100, "en"},
    {:strike, :aggregator, "chatter.example.org", "Harbour cranes idle during regional strike",
     50, 50, "en"},
    # Titles without a word match nothing, not even each other.
    {:stars_1, :aggregator, "daily.stories-test.example.com", "***", 70, 70, "en"},
    {:stars_2, :aggregator, "chatter.example.org", "***", 70, 70 + 5 / 60, "en"},
    # The same release in German: its own story, apart from the English one.
    {:q3_de_issuer, :issuer, "newsroom.northwind.example", @q3_de, 0, 5 / 60, "de"},
    {:q3_de_wire, :aggregator, "wire.stories-test.example.com", @q3_de, 0, 45 / 60, "de"}
  ]

  # The stories the fixture must give, each with its representative.
  @expected_en [
    {~w(q3_issuer q3_reg q3_wire q3_daily q3_chatter q3_zw)a, :q3_issuer},
    {~w(chain_a chain_b chain_c)a, :chain_a},
    {~w(cfo_x cfo_y cfo_z)a, :cfo_x},
    {~w(q3_late)a, :q3_late},
    {~w(strike)a, :strike},
    {~w(stars_1)a, :stars_1},
    {~w(stars_2)a, :stars_2}
  ]
  @expected_de [{~w(q3_de_issuer q3_de_wire)a, :q3_de_issuer}]

  defp at(hours), do: DateTime.add(@t, round(hours * 3600), :second)
  defp url({key, _feed, domain, _title, _claimed, _seen, _language}), do: url(key, domain)
  defp url(key, domain), do: "https://#{domain}/#{key}"

  defp expected(stories, fixture) do
    urls = Map.new(fixture, fn row -> {elem(row, 0), url(row)} end)

    MapSet.new(stories, fn {keys, representative} ->
      {MapSet.new(keys, &Map.fetch!(urls, &1)), Map.fetch!(urls, representative)}
    end)
  end

  describe "the title keys (§4)" do
    # User story (ADR-0056 §4):
    # As the operator who wants one story per event,
    # I want titles compared by their words, not their spelling,
    # so that case, punctuation and invisible characters do not split a
    # story, and nothing joins titles that share no word.
    #
    # Acceptance criteria:
    # - The normalized title is lower-cased (Unicode), format characters
    #   (zero-width, bidirectional) removed, every run of characters that
    #   are not letters, marks or digits one space, the ends trimmed.
    # - Its words are the distinct words, sorted; its hash the SHA-256 of
    #   the normalized title in lower-case hex.
    test "case, punctuation and invisible characters do not change the keys" do
      keys = Stories.title_keys(@q3)

      assert Stories.normalize_title(
               "NORTHWIND HARBOUR LOGISTICS REPORTS THIRD-QUARTER 2026 RESULTS!"
             ) ==
               "northwind harbour logistics reports third quarter 2026 results"

      assert Stories.title_keys(
               "  north\u200Bwind harbour  Logistics: reports third quarter 2026 results..."
             ) ==
               keys

      assert keys.title_words ==
               ~w(2026 harbour logistics northwind quarter reports results third)

      assert keys.title_norm_hash ==
               :sha256
               |> :crypto.hash("northwind harbour logistics reports third quarter 2026 results")
               |> Base.encode16(case: :lower)

      assert Stories.title_keys("Übernahme: Ölpreis steigt, Straße gesperrt").title_words ==
               ~w(gesperrt steigt straße ölpreis übernahme)

      assert Stories.title_keys("***").title_words == []
    end
  end

  describe "cluster/2, the pure rule (B3, B4, B5)" do
    # User story (ADR-0056 B3 to B5; §14 item 3):
    # As the operator and the agent who read stories,
    # I want the same items to give the same stories and representatives
    # in any order, a story to be a connected component of "within 72
    # hours and the same or a similar title", and the representative chosen
    # by tier, clamped time and URL,
    # so that no fetch order, no id and no claim inside an item decides
    # what a story is or which item stands for it.
    #
    # Acceptance criteria:
    # - The fixture gives exactly the expected stories per language, with
    #   the expected representatives, in 50 shuffled orders.
    # - A ~ B, B ~ C, A not ~ C is one story; a similarity of exactly 0.8
    #   links; 72 hours apart links, a microsecond more does not.
    # - A future claim cannot make an item the representative (B4); an
    #   aggregator item naming a primary domain is secondary and loses to a
    #   true primary (B5); at an equal tier and time the smaller URL wins.
    test "the fixture gives the expected stories in every order" do
      for language <- ["en", "de"] do
        items = for row <- @fixture, elem(row, 6) == language, do: pure_item(row)

        expected =
          expected(if(language == "en", do: @expected_en, else: @expected_de), @fixture)

        for _round <- 1..50 do
          assert items |> Enum.shuffle() |> Stories.cluster() |> as_sets() == expected
        end
      end
    end

    test "72 hours apart links, a microsecond more does not" do
      a = pure_item({:a, :aggregator, "daily.stories-test.example.com", @cfo, 0, 0, "en"})
      b = %{a | canonical_url: "https://b.example/b", published_at: at(72), first_seen_at: at(72)}
      assert [_one] = Stories.cluster([a, b])

      late = DateTime.add(at(72), 1, :microsecond)
      b = %{b | published_at: late, first_seen_at: late}
      assert [_one, _two] = Stories.cluster([a, b])
    end

    test "the representative: best tier, then earliest clamped time, then the smaller URL" do
      row = fn key, feed, domain, seen ->
        pure_item({key, feed, domain, @q3, seen, seen, "en"})
      end

      primary_b = row.(:b, :issuer, "newsroom.b.example", 1)
      primary_a = row.(:a, :regulatory, "filings.a.example", 1)
      secondary = row.(:early, :aggregator, "wire.stories-test.example.com", 0)

      assert [%{representative: rep}] = Stories.cluster([primary_b, secondary, primary_a])
      assert rep.canonical_url == "https://filings.a.example/a"

      # A future claim is clamped to the first sight: the item stays later.
      future = %{primary_a | published_at: at(5), first_seen_at: at(5)}

      assert [%{representative: rep}] = Stories.cluster([future, primary_b, secondary])
      assert rep.canonical_url == "https://newsroom.b.example/b"
    end

    test "the similarity and the window are settings" do
      items = for row <- @fixture, elem(row, 6) == "en", do: pure_item(row)

      stories = Stories.cluster(items, similarity: Decimal.new("0.81"))

      assert Enum.any?(
               stories,
               &(urls(&1) == MapSet.new(["https://chatter.example.org/q3_chatter"]))
             )

      stories = Stories.cluster(items, window_hours: 48)

      refute Enum.any?(
               stories,
               &(MapSet.size(urls(&1)) == 3 and &1.representative.canonical_url =~ "cfo_x")
             )

      assert Settings.news_cluster_window_hours() == 72
      assert Settings.news_cluster_similarity() == Decimal.new("0.8")

      assert :ok = Settings.set_news_cluster_window_hours(@agent, 48)
      assert :ok = Settings.set_news_cluster_similarity(@agent, Decimal.new("0.85"))
      assert Settings.news_cluster_window_hours() == 48
      assert Settings.news_cluster_similarity() == Decimal.new("0.85")
      assert Settings.get("news_cluster_similarity") == "0.85"

      assert {:error, :invalid} = Settings.set_news_cluster_window_hours(@agent, 0)
      assert {:error, :invalid} = Settings.set_news_cluster_similarity(@agent, Decimal.new("1.1"))
      assert {:error, :invalid} = Settings.set_news_cluster_similarity(@agent, Decimal.new("0"))

      assert [_, _] =
               Portfolixir.Journal.list_entries(resource_type: "setting")
               |> Enum.filter(&(&1.actor_label == "synthetic-agent"))
    end
  end

  describe "recluster/4 (B3)" do
    # User story (ADR-0056 B3, B7; Sprint 27 plan D-1 criterion 3):
    # As the agent that is handed a story's id,
    # I want the stored stories to be the components of the stored items,
    # whatever order the items were fetched in and the reclusters ran in,
    # and a story's id to keep pointing at the same story across reclusters,
    # so that no order decides a story, and an id I hold stays good.
    #
    # Acceptance criteria:
    # - The fixture inserted in 50 random orders, with reclusters at random
    #   points and random clocks, stores exactly the expected stories and
    #   representatives per language.
    # - Every stored story counts its members, names a member as its
    #   representative, and carries their best tier and earliest times.
    # - A recluster with nothing new changes no story; a joining item keeps
    #   the story's id; a merge keeps the story whose earliest member is
    #   earliest by (first seen, URL), whichever id is smaller.
    setup do
      {:ok, _} = Sources.put_source(@agent, "wire.stories-test.example.com", :primary)
      {:ok, _} = Sources.put_source(@agent, "daily.stories-test.example.com", :secondary)
      security = WorldFixtures.create_security!(name: "Northwind Harbour", ticker: nil)

      feeds = %{
        {:issuer, "en"} => feed!(%{class: "issuer", security_id: security.id, language: "en"}),
        {:issuer, "de"} => feed!(%{class: "issuer", security_id: security.id, language: "de"}),
        {:regulatory, "en"} =>
          feed!(%{class: "regulatory", security_id: security.id, language: "en"}),
        {:aggregator, "en"} => feed!(%{class: "aggregator", language: "en"}),
        {:aggregator, "de"} => feed!(%{class: "aggregator", language: "de"})
      }

      %{security: security, feeds: feeds}
    end

    test "the fixture in 50 orders stores the same stories", %{security: security, feeds: feeds} do
      scope = {:security, security.id}
      clocks = Enum.map(@fixture, &at(elem(&1, 5) + 1))

      for _round <- 1..50 do
        Repo.transaction(fn ->
          @fixture
          |> Enum.shuffle()
          |> Enum.chunk_by(fn _row -> :rand.uniform(3) == 1 end)
          |> Enum.each(fn batch ->
            Enum.each(batch, &insert!(&1, security, feeds))

            for language <- Enum.shuffle(["en", "de"]),
                do: {:ok, _} = Stories.recluster(scope, language, Enum.random(clocks))
          end)

          assert stored(security, "en") == expected(@expected_en, @fixture)
          assert stored(security, "de") == expected(@expected_de, @fixture)
          Repo.rollback(:round_done)
        end)
      end
    end

    test "an id stays with its story; a merge keeps the earliest story", %{
      security: security,
      feeds: feeds
    } do
      scope = {:security, security.id}
      now = at(200)

      # The later story is stored first, so its id is the smaller one.
      late =
        insert!(
          {:late, :aggregator, "daily.stories-test.example.com", @cfo, 100, 100, "en"},
          security,
          feeds
        )

      {:ok, _} = Stories.recluster(scope, "en", now)

      early =
        insert!(
          {:early, :issuer, "newsroom.northwind.example", @cfo, 0, 0, "en"},
          security,
          feeds
        )

      {:ok, _} = Stories.recluster(scope, "en", now)

      late_story = Repo.reload!(late).cluster_id
      early_story = Repo.reload!(early).cluster_id
      assert late_story < early_story

      # Nothing new: no story changes.
      before = Repo.all(from(c in Cluster, order_by: c.id))
      {:ok, _} = Stories.recluster(scope, "en", now)
      assert Repo.all(from(c in Cluster, order_by: c.id)) == before

      # An item 50 hours from each links them: the earliest story survives.
      bridge =
        insert!(
          {:bridge, :aggregator, "chatter.example.org", @cfo, 50, 50, "en"},
          security,
          feeds
        )

      {:ok, summary} = Stories.recluster(scope, "en", now)
      assert summary.merged == 1

      assert [%Cluster{id: ^early_story} = story] = Repo.all(Cluster)
      assert story.member_count == 3
      assert story.representative_item_id == early.id

      assert Enum.map([late, early, bridge], &Repo.reload!(&1).cluster_id) ==
               List.duplicate(early_story, 3)

      # A joining item keeps the id.
      insert!(
        {:joiner, :aggregator, "daily.stories-test.example.com", @cfo, 51, 51, "en"},
        security,
        feeds
      )

      {:ok, _} = Stories.recluster(scope, "en", now)
      assert [%Cluster{id: ^early_story, member_count: 4}] = Repo.all(Cluster)
    end

    test "a category's thematic items cluster the same way" do
      {:ok, classification} =
        Classifications.create_classification(Actor.owner_ui(), %{name: "Themes"})

      {:ok, category} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Shipping"
        })

      feed = feed!(%{class: "thematic", category_id: category.id, language: "en"})

      for {key, domain} <- [
            one: "daily.stories-test.example.com",
            two: "wire.stories-test.example.com"
          ] do
        %Item{}
        |> Item.changeset(
          Map.merge(Stories.title_keys(@q3), %{
            feed_id: feed.id,
            class: :thematic,
            category_id: category.id,
            assignment: :assigned,
            first_seen_at: @t,
            title: @q3,
            canonical_url: url(key, domain),
            domain: domain,
            tier: Sources.tier_for(domain, :thematic),
            language: "en",
            content_hash: String.duplicate("c", 64)
          })
        )
        |> Repo.insert!()
      end

      assert {:ok, %{created: 1}} = Stories.recluster({:category, category.id}, "en", @t)

      assert [%Cluster{category_id: id, member_count: 2, best_tier: :secondary}] =
               Repo.all(Cluster)

      assert id == category.id
    end
  end

  # --- closing act, Fix-2 (ADR-0056 amendment of 2026-11-08, C1 and C2) -------

  @results "Northwind Harbour reports third quarter 2026 results"
  @resigns "Northwind Harbour chief executive resigns with immediate effect"

  # Titles stepping from `a` to `b` one word at a time, each with a Jaccard
  # similarity of at least 0.8 to the one before: true items an aggregator
  # can publish, which B3 as written lets link any two headlines.
  defp chain(a, b) do
    wa = Stories.title_keys(a).title_words
    wb = Stories.title_keys(b).title_words
    grown = Enum.scan(wb -- wa, wa, fn word, acc -> acc ++ [word] end)
    shrunk = (wa -- wb) |> Enum.scan(List.last(grown), fn word, acc -> acc -- [word] end)
    Enum.map(grown ++ Enum.drop(shrunk, -1), &Enum.join(&1, " "))
  end

  describe "the closing act's order rules (C1, C2)" do
    # User story (ADR-0056 amendment of 2026-11-08, C2):
    # As the agent that holds a primary story's id,
    # I want a merge to keep the id of the story with the best tier, then
    # the earliest first sight, then the smallest link,
    # so that an attacker's link at "https://a.example" cannot make its own
    # story survive a merge with an issuer's and delete the id I hold.
    #
    # Acceptance criteria:
    # - An issuer's story and an aggregator's story first seen in the same
    #   tick, merged by bridging items inserted in any order, keep the
    #   issuer story's id, whether the aggregator's link sorts before or
    #   after the issuer's.
    setup do
      security = WorldFixtures.create_security!(name: "Northwind Harbour", ticker: nil)

      feeds = %{
        {:issuer, "en"} => feed!(%{class: "issuer", security_id: security.id, language: "en"}),
        {:aggregator, "en"} => feed!(%{class: "aggregator", language: "en"})
      }

      %{security: security, feeds: feeds}
    end

    # User story (ADR-0056 amendment of 2026-11-08, C1):
    # As the operator and the agent reading an issuer's headlines,
    # I want a chain of lower-tier items never to join two primary stories,
    # so that ten true aggregator items, each a word away from the last,
    # cannot fold a chief executive's resignation into last quarter's
    # results and hide it from the digest and the list.
    #
    # Acceptance criteria:
    # - The pure rule, in 50 shuffled orders, keeps the two issuer items in
    #   two stories; the chain joins the one whose survivor key is smaller
    #   (the earlier results), and the resignation stands alone.
    # - Stored in 30 random orders with reclusters at random points, the
    #   stored stories are those of the pure rule; the resignation's story
    #   keeps its id once the chain arrives, and the digest and the list
    #   show its headline.
    # - A lower-tier item linked only through other lower-tier items to a
    #   primary story joins it with them (the N5 fixture's cfo story).
    test "C1: a lower-tier chain cannot join two primary stories", %{
      security: security,
      feeds: feeds
    } do
      scope = {:security, security.id}
      results = {:results, :issuer, "newsroom.northwind.example", @results, 0, 0, "en"}
      resigns = {:resigns, :issuer, "newsroom.northwind.example", @resigns, 24, 24, "en"}

      links =
        for {title, i} <- Enum.with_index(chain(@results, @resigns)),
            do: {:"chain_#{i}", :aggregator, "attacker.example", title, 1 + i, 25, "en"}

      rows = [results, resigns | links]
      pure = Enum.map(rows, &pure_item/1)

      for _round <- 1..50 do
        stories = pure |> Enum.shuffle() |> Stories.cluster()
        assert length(stories) == 2
        [first, second] = stories
        assert first.representative.key == :results
        assert length(first.members) == length(rows) - 1
        assert [%{key: :resigns}] = second.members
      end

      expected = MapSet.new(Stories.cluster(pure), &{urls(&1), &1.representative.canonical_url})
      clocks = Enum.map(rows, &at(elem(&1, 5) + 1))

      for _round <- 1..30 do
        Repo.transaction(fn ->
          rows
          |> Enum.shuffle()
          |> Enum.chunk_by(fn _row -> :rand.uniform(3) == 1 end)
          |> Enum.each(fn batch ->
            Enum.each(batch, &insert!(&1, security, feeds))
            {:ok, _} = Stories.recluster(scope, "en", Enum.random(clocks))
          end)

          {:ok, _} = Stories.recluster(scope, "en", at(30))
          assert stored(security, "en") == expected
          Repo.rollback(:round_done)
        end)
      end

      # In the order of the finding: the resignation's id survives the chain.
      Repo.transaction(fn ->
        insert!(results, security, feeds)
        {:ok, _} = Stories.recluster(scope, "en", at(0))
        resignation = insert!(resigns, security, feeds)
        {:ok, _} = Stories.recluster(scope, "en", at(24))
        held = Repo.reload!(resignation).cluster_id
        Enum.each(links, &insert!(&1, security, feeds))
        {:ok, _} = Stories.recluster(scope, "en", at(25))

        assert Repo.reload!(resignation).cluster_id == held
        assert {:ok, %{title: @resigns}} = Reads.story(held)

        digest = Reads.digest([security.id], at(23), false, 10)
        # The digest cuts a title at 45 (S28 N2; 50 before its closing act,
        # AG1): the resignation's is the top.
        assert [%{top: %{title: top}, count: 2}] = digest.rows
        assert top == Reads.clip_spelled(@resigns, 45)

        {:ok, page} = Reads.list(scope, limit: 20)
        assert Enum.any?(page.rows, &(&1.title == @resigns))
        Repo.rollback(:done)
      end)
    end

    # The incremental recluster reads every story the relation links to
    # the stories it rewrites, so C1's choice of a primary story is made
    # with all of them: a lower-tier item whose nearest primary stories
    # merge moves to the merged one even when it lies more than a window
    # from the new item.
    test "C1: a recluster after a merge of primary stories equals the full one", %{
      security: security,
      feeds: feeds
    } do
      scope = {:security, security.id}
      base = "Northwind Harbour board approves new container terminal at Baltic port"

      rows = [
        {:q2, :issuer, "newsroom.northwind.example", base <> " alpha", -50, 300, "en"},
        {:t, :issuer, "newsroom.northwind.example", base <> " beta gamma", 200, 301, "en"},
        {:q1, :issuer, "newsroom.northwind.example", base <> " beta", 70, 302, "en"},
        {:l, :aggregator, "attacker.example", base <> " beta", 140, 303, "en"}
      ]

      Enum.each(rows, &insert!(&1, security, feeds))
      {:ok, _} = Stories.recluster(scope, "en", at(303))
      seed = {:seed, :issuer, "newsroom.northwind.example", base, 0, 500, "en"}
      insert!(seed, security, feeds)
      {:ok, _} = Stories.recluster(scope, "en", at(500))

      expected =
        MapSet.new(
          Stories.cluster(Enum.map([seed | rows], &pure_item/1)),
          &{urls(&1), &1.representative.canonical_url}
        )

      assert stored(security, "en") == expected
    end

    test "C2: a merge keeps the primary story's id, whatever link the other has", %{
      security: security,
      feeds: feeds
    } do
      scope = {:security, security.id}

      for attacker <- ["a.example", "zz.example"], _round <- 1..5 do
        Repo.transaction(fn ->
          primary =
            insert!(
              {:q3, :issuer, "newsroom.northwind.example", @results, 0, 0, "en"},
              security,
              feeds
            )

          attack = insert!({:x, :aggregator, attacker, @resigns, 0, 0, "en"}, security, feeds)
          {:ok, _} = Stories.recluster(scope, "en", at(0))
          held = Repo.reload!(primary).cluster_id
          assert held != Repo.reload!(attack).cluster_id

          chain(@results, @resigns)
          |> Enum.with_index()
          |> Enum.shuffle()
          |> Enum.each(fn {title, i} ->
            insert!(
              {:"bridge_#{i}", :aggregator, "bridge.example", title, 1, 2, "en"},
              security,
              feeds
            )
          end)

          {:ok, _} = Stories.recluster(scope, "en", at(2))

          assert Repo.reload!(primary).cluster_id == held, attacker
          assert %Cluster{representative_item_id: rep} = Repo.get(Cluster, held)
          assert rep == primary.id
          Repo.rollback(:round_done)
        end)
      end
    end
  end

  # --- helpers ---------------------------------------------------------------

  defp pure_item({key, feed, domain, title, claimed, seen, language}) do
    seen = at(seen)
    claimed = at(claimed)
    published = if DateTime.compare(claimed, seen) == :gt, do: seen, else: claimed

    Map.merge(Stories.title_keys(title), %{
      key: key,
      canonical_url: url(key, domain),
      first_seen_at: seen,
      published_at: published,
      tier: Sources.tier(feed, rated(domain)),
      language: language
    })
  end

  defp rated("wire.stories-test.example.com"), do: :primary
  defp rated("daily.stories-test.example.com"), do: :secondary
  defp rated(_domain), do: nil

  defp urls(story), do: MapSet.new(story.members, & &1.canonical_url)

  defp as_sets(stories),
    do: MapSet.new(stories, &{urls(&1), &1.representative.canonical_url})

  defp actor!,
    do: Repo.query!("SELECT set_config('portfolixir.journal_actor', 'synthetic-fixture', true)")

  defp feed!(attrs) do
    actor!()

    %Feed{}
    |> Feed.changeset(
      Map.merge(
        %{
          url: "https://feeds.example.com/#{System.unique_integer([:positive])}",
          interval_minutes: 60
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp insert!({key, feed_class, domain, title, claimed, seen, language} = row, security, feeds) do
    feed = Map.fetch!(feeds, {feed_class, language})

    %Item{}
    |> Item.changeset(
      Map.merge(Stories.title_keys(title), %{
        feed_id: feed.id,
        class: feed.class,
        security_id: security.id,
        assignment: :assigned,
        first_seen_at: at(seen),
        published_at_claimed: at(claimed),
        title: title,
        canonical_url: url(row),
        domain: domain,
        tier: Sources.tier_for(domain, feed.class),
        language: language,
        content_hash: :sha256 |> :crypto.hash(to_string(key)) |> Base.encode16(case: :lower)
      })
    )
    |> Repo.insert!()
  end

  # The stored stories of one security and language, as sets of URLs with
  # their representative's; each story's own fields checked against its
  # members on the way.
  defp stored(security, language) do
    stories =
      Repo.all(
        from(c in Cluster,
          where: c.security_id == ^security.id and c.language == ^language,
          preload: :items
        )
      )

    unclustered =
      Repo.aggregate(
        from(i in Item,
          where:
            i.security_id == ^security.id and i.language == ^language and is_nil(i.cluster_id)
        ),
        :count
      )

    assert unclustered == 0

    MapSet.new(stories, fn story ->
      members = story.items
      assert story.member_count == length(members)
      representative = Enum.find(members, &(&1.id == story.representative_item_id))
      assert representative, "the representative is a member"

      earliest =
        Enum.min_by(
          members,
          &{DateTime.to_unix(&1.first_seen_at, :microsecond), &1.canonical_url}
        )

      assert story.earliest_first_seen_at == earliest.first_seen_at
      assert story.earliest_url == earliest.canonical_url

      assert story.earliest_published_at ==
               Enum.min_by(members, &DateTime.to_unix(&1.published_at, :microsecond)).published_at

      assert story.best_tier ==
               Enum.min_by(
                 members,
                 &Enum.find_index([:primary, :secondary, :awareness], fn t -> t == &1.tier end)
               ).tier

      {MapSet.new(members, & &1.canonical_url), representative.canonical_url}
    end)
  end
end
