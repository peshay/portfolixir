defmodule Portfolixir.News.TablesTest do
  # ADR-0056 §2, §3, §4, A3 and B3 to B5 (Sprint 27, N2): the news layer's
  # tables. Every rule is seen twice — refused by the changeset with a field
  # error, and refused by the database when a row bypasses the changeset —
  # so a later writer that skips the changeset still cannot store a row the
  # record forbids. Synthetic data only.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Feed
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Item
  alias Portfolixir.News.Source
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @seen ~U[2026-11-07 10:00:00.000000Z]

  # Feeds and sources are journal-armed (B7); these tests write rows past
  # the context, so they name an actor for the guard before each write (a
  # journaled write, such as a security's create, resets it when it ends).
  # The guard itself is pinned in "the journal's guard" below, without one.
  defp actor! do
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'synthetic-schema-test', true)")
  end

  @hash String.duplicate("a", 64)
  @other_hash String.duplicate("b", 64)

  defp security!(name \\ "Northwind Harbour Logistics AG"),
    do: WorldFixtures.create_security!(name: name, ticker: nil, asset_class: "equity")

  defp category! do
    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{
        name: "Themes #{System.unique_integer([:positive])}"
      })

    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Water"
      })

    category
  end

  defp feed!(attrs) do
    actor!()

    %Feed{}
    |> Feed.changeset(
      Map.merge(
        %{url: "https://newsroom.example.com/feed-#{System.unique_integer([:positive])}.xml"},
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp issuer_feed!(security),
    do: feed!(%{class: "issuer", security_id: security.id, language: "en"})

  defp item_attrs(feed, attrs) do
    Map.merge(
      %{
        feed_id: feed.id,
        class: feed.class,
        security_id: feed.security_id,
        category_id: feed.category_id,
        assignment: "assigned",
        first_seen_at: @seen,
        published_at_claimed: ~U[2026-11-07 09:00:00.000000Z],
        title: "Northwind reports third-quarter results",
        canonical_url: "https://newsroom.example.com/q3-#{System.unique_integer([:positive])}",
        domain: "newsroom.example.com",
        tier: "primary",
        language: "en",
        content_hash: @hash,
        title_norm_hash: @other_hash,
        title_words: ~w(northwind reports third quarter results)
      },
      attrs
    )
  end

  defp item!(feed, attrs \\ %{}),
    do: %Item{} |> Item.changeset(item_attrs(feed, attrs)) |> Repo.insert!()

  defp cluster!(item, attrs \\ %{}) do
    %Cluster{}
    |> Cluster.changeset(
      Map.merge(
        %{
          security_id: item.security_id,
          category_id: item.category_id,
          language: item.language,
          representative_item_id: item.id,
          member_count: 1,
          earliest_first_seen_at: item.first_seen_at,
          earliest_published_at: item.published_at,
          earliest_url: item.canonical_url,
          best_tier: item.tier
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  # A row written past the changeset, in a savepoint so the test's
  # transaction survives the refusal: the name of the constraint the
  # database refused it by, or `:inserted`.
  defp raw_insert(table, row) do
    columns = Map.keys(row)
    placeholders = Enum.map_join(1..length(columns), ", ", &"$#{&1}")

    sql =
      "INSERT INTO #{table} (#{Enum.join(columns, ", ")}) VALUES (#{placeholders})"

    actor!()

    case Repo.query(sql, Enum.map(columns, &raw_value(Map.fetch!(row, &1))), mode: :savepoint) do
      {:ok, _result} -> :inserted
      {:error, %Postgrex.Error{postgres: %{constraint: constraint}}} -> constraint
      {:error, %Postgrex.Error{postgres: %{code: code}}} -> code
    end
  end

  defp raw_value(%DateTime{} = value), do: DateTime.to_naive(value)

  defp raw_value(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp raw_value(value), do: value

  defp now_naive, do: NaiveDateTime.utc_now()

  defp raw_feed(attrs) do
    Map.merge(
      %{
        class: "aggregator",
        url: "https://search.example.com/rss-#{System.unique_integer([:positive])}",
        enabled: true,
        interval_minutes: 60,
        language: "en",
        failures: 0,
        inserted_at: now_naive(),
        updated_at: now_naive()
      },
      attrs
    )
  end

  defp raw_item(feed, attrs) do
    feed
    |> item_attrs(%{published_at: ~U[2026-11-07 09:00:00.000000Z]})
    |> Map.merge(%{
      candidates: [],
      note_ids: [],
      status: "new",
      inserted_at: now_naive(),
      updated_at: now_naive()
    })
    |> Map.merge(attrs)
  end

  describe "news_sources (§3)" do
    # User story (ADR-0056 §3):
    # As the operator rating where news comes from,
    # I want each domain stored once, lower-case, with one of four tiers and
    # whether a hand or a seed set it,
    # so that a correction by hand can be told from a seed's and is never
    # overwritten by one.
    #
    # Acceptance criteria:
    # - A domain is stored lower-case and trimmed; a domain with a scheme, a
    #   path, a space or an upper-case letter is refused by the database.
    # - The tier is primary, secondary, awareness or blocked; `set_by` is
    #   hand or seed; anything else is refused by both.
    # - A domain is unique: a second row for it is a changeset error.
    test "a source is one lower-case domain with a tier and who set it" do
      actor!()

      {:ok, source} =
        %Source{}
        |> Source.changeset(%{domain: " Reuters.Example.COM ", tier: "secondary", set_by: "hand"})
        |> Repo.insert()

      assert source.domain == "reuters.example.com"
      assert source.tier == :secondary
      assert source.set_by == :hand

      assert {:error, changeset} =
               %Source{}
               |> Source.changeset(%{
                 domain: "reuters.example.com",
                 tier: "primary",
                 set_by: "seed"
               })
               |> Repo.insert()

      assert %{domain: ["has already been taken"]} = errors_on(changeset)

      changeset =
        Source.changeset(%Source{}, %{domain: "https://x.example", tier: "best", set_by: "agent"})

      errors = errors_on(changeset)
      assert errors.domain == ["is not a domain (lower-case letters, digits, dots and hyphens)"]
      assert errors.tier == ["is invalid"]
      assert errors.set_by == ["is invalid"]

      row = %{
        tier: "secondary",
        set_by: "seed",
        inserted_at: now_naive(),
        updated_at: now_naive()
      }

      assert raw_insert("news_sources", Map.put(row, :domain, "Upper.example.com")) ==
               "news_sources_domain_check"

      assert raw_insert("news_sources", Map.put(row, :domain, "x.example.com/path")) ==
               "news_sources_domain_check"

      assert raw_insert("news_sources", Map.merge(row, %{domain: "a.example", tier: "gold"})) ==
               "news_sources_tier_check"

      assert raw_insert("news_sources", Map.merge(row, %{domain: "b.example", set_by: "import"})) ==
               "news_sources_set_by_check"

      assert raw_insert("news_sources", Map.put(row, :domain, "reuters.example.com")) ==
               "news_sources_domain_index"

      assert raw_insert("news_sources", Map.put(row, :domain, "c.example")) == :inserted
    end
  end

  describe "news_feeds (§2, §4, §5)" do
    # User story (ADR-0056 §2):
    # As the operator's agent registering a feed,
    # I want the feed's class to decide what it is bound to,
    # so that an issuer or regulatory feed always names its security, a
    # thematic feed its category, and an aggregator feed neither.
    #
    # Acceptance criteria:
    # - issuer and regulatory: a security, no category; thematic: a
    #   category, no security; aggregator: neither. Every other combination
    #   is refused by the changeset and by the database.
    # - The class is one of the four; anything else is refused by both.
    # - Without an interval, a feed takes its class's default (§5: 10, 15,
    #   60, 180 minutes).
    test "the class decides the binding, and the interval defaults by class" do
      security = security!()
      category = category!()

      assert %Feed{class: :issuer, interval_minutes: 15} = issuer_feed!(security)

      assert %Feed{interval_minutes: 10} =
               feed!(%{class: "regulatory", security_id: security.id, language: "en"})

      assert %Feed{interval_minutes: 60} = feed!(%{class: "aggregator", language: "de"})

      assert %Feed{interval_minutes: 180} =
               feed!(%{class: "thematic", category_id: category.id, language: "en"})

      for {attrs, field} <- [
            {%{class: "issuer"}, :security_id},
            {%{class: "issuer", security_id: security.id, category_id: category.id},
             :category_id},
            {%{class: "regulatory", category_id: category.id}, :security_id},
            {%{class: "thematic", security_id: security.id}, :category_id},
            {%{class: "aggregator", security_id: security.id}, :security_id},
            {%{class: "aggregator", category_id: category.id}, :category_id}
          ] do
        changeset =
          Feed.changeset(%Feed{}, Map.merge(%{url: "https://a.example/f", language: "en"}, attrs))

        assert Map.has_key?(errors_on(changeset), field), inspect(attrs)
      end

      assert %{class: ["is invalid"]} =
               errors_on(Feed.changeset(%Feed{}, %{class: "blog", url: "https://a.example/f"}))

      for row <- [
            %{class: "issuer"},
            %{class: "issuer", security_id: security.id, category_id: category.id},
            %{class: "regulatory", category_id: category.id},
            %{class: "thematic"},
            %{class: "thematic", security_id: security.id},
            %{class: "aggregator", security_id: security.id},
            %{class: "aggregator", category_id: category.id}
          ] do
        assert raw_insert("news_feeds", raw_feed(row)) == "news_feeds_binding_check", inspect(row)
      end

      assert raw_insert("news_feeds", raw_feed(%{class: "blog"})) == "news_feeds_class_check"
    end

    # User story (ADR-0056 §5, B2):
    # As the operator whose instance fetches only what was registered,
    # I want a feed's URL to be an https URL of bounded length without
    # userinfo, unique among feeds, and its interval and language bounded,
    # so that no stored feed names a scheme or a host form the fetcher must
    # not request, and no feed is fetched twice.
    #
    # Acceptance criteria:
    # - http, a URL with userinfo, a space, or more than 2,048 characters is
    #   refused by the changeset and by the database.
    # - A second feed with the same URL is a changeset error.
    # - The interval is 1 to 1,440 minutes (a feed fetched less often than
    #   daily would read stale by design, §6); the language a lower-case
    #   code of 2 to 8 characters ("en", "de", "pt-br").
    # - Failures are never negative, a retry time exists only after a
    #   failure, and the last success is never after the last fetch.
    test "the URL, the interval, the language and the backoff state are bounded" do
      base = %{class: "aggregator", language: "en"}
      long = "https://a.example/" <> String.duplicate("p", 2031)

      for url <- [
            "http://a.example/feed",
            "https://user:pw@a.example/feed",
            "https://a.example/a feed",
            "ftp://a.example/feed",
            long
          ] do
        assert %{url: [_ | _]} = errors_on(Feed.changeset(%Feed{}, Map.put(base, :url, url))),
               url

        assert raw_insert("news_feeds", raw_feed(%{url: url})) == "news_feeds_url_check", url
      end

      assert %Feed{} =
               feed!(Map.put(base, :url, "https://a.example/" <> String.duplicate("p", 2030)))

      assert %Feed{} = feed!(Map.put(base, :url, "https://a.example:8443/feed?q=x#top"))

      _first = feed!(Map.put(base, :url, "https://search.example.com/q"))

      assert {:error, changeset} =
               %Feed{}
               |> Feed.changeset(Map.put(base, :url, "https://search.example.com/q"))
               |> Repo.insert()

      assert %{url: ["has already been taken"]} = errors_on(changeset)

      for {attrs, field} <- [
            {%{interval_minutes: 0}, :interval_minutes},
            {%{interval_minutes: 1441}, :interval_minutes},
            {%{language: "english"}, :language},
            {%{language: "e"}, :language},
            {%{language: nil}, :language}
          ] do
        changeset =
          Feed.changeset(%Feed{}, Map.merge(Map.put(base, :url, "https://b.example/f"), attrs))

        assert Map.has_key?(errors_on(changeset), field), inspect(attrs)
      end

      assert %Feed{language: "pt-br"} =
               feed!(%{class: "aggregator", language: "PT-BR", url: "https://c.example/f"})

      assert raw_insert("news_feeds", raw_feed(%{interval_minutes: 0})) ==
               "news_feeds_interval_minutes_check"

      assert raw_insert("news_feeds", raw_feed(%{interval_minutes: 1441})) ==
               "news_feeds_interval_minutes_check"

      assert raw_insert("news_feeds", raw_feed(%{language: "EN"})) == "news_feeds_language_check"
      assert raw_insert("news_feeds", raw_feed(%{failures: -1})) == "news_feeds_failures_check"

      assert raw_insert("news_feeds", raw_feed(%{retry_at: now_naive()})) ==
               "news_feeds_retry_at_check"

      assert raw_insert(
               "news_feeds",
               raw_feed(%{
                 last_ok_at: ~N[2026-11-07 10:00:00],
                 last_fetch_at: ~N[2026-11-07 09:00:00]
               })
             ) == "news_feeds_last_ok_at_check"

      assert raw_insert("news_feeds", raw_feed(%{last_error: String.duplicate("e", 501)})) ==
               "news_feeds_last_error_check"

      feed = feed!(Map.put(base, :url, "https://d.example/f"))

      health =
        Feed.health_changeset(feed, %{
          failures: 2,
          retry_at: ~U[2026-11-07 11:00:00.000000Z],
          last_fetch_at: ~U[2026-11-07 10:00:00.000000Z],
          last_ok_at: ~U[2026-11-07 10:00:01.000000Z],
          last_error: String.duplicate("e", 501)
        })

      assert %{last_ok_at: [_], last_error: [_]} = errors_on(health)

      assert %{retry_at: [_]} =
               errors_on(Feed.health_changeset(feed, %{retry_at: ~U[2026-11-07 11:00:00Z]}))

      assert {:ok, %Feed{failures: 1}} =
               feed
               |> Feed.health_changeset(%{
                 failures: 1,
                 retry_at: ~U[2026-11-07 11:00:00Z],
                 last_fetch_at: ~U[2026-11-07 10:00:00Z],
                 last_error: "http_503"
               })
               |> Repo.update()
    end
  end

  describe "news_items (§4, B4, B5)" do
    # User story (ADR-0056 B4):
    # As the operator's agent reading what is new,
    # I want an item's `published_at` to be the feed's claim clamped to the
    # moment the server first saw it, with the claim kept beside it,
    # so that a future date cannot make an item the newest.
    #
    # Acceptance criteria:
    # - A claim before `first_seen_at` is `published_at`; a later claim is
    #   clamped to `first_seen_at`; no claim gives `first_seen_at`.
    # - The claim is kept as the feed stated it.
    # - A row whose `published_at` is not the clamped claim is refused by the
    #   database, a future one included.
    test "published_at is the claim clamped to first_seen_at" do
      feed = issuer_feed!(security!())

      earlier = item!(feed)
      assert earlier.published_at == ~U[2026-11-07 09:00:00.000000Z]
      assert earlier.published_at_claimed == ~U[2026-11-07 09:00:00.000000Z]

      future = item!(feed, %{published_at_claimed: ~U[2027-01-01 00:00:00.000000Z]})
      assert future.published_at == @seen
      assert future.published_at_claimed == ~U[2027-01-01 00:00:00.000000Z]

      unclaimed = item!(feed, %{published_at_claimed: nil})
      assert unclaimed.published_at == @seen

      ignored =
        Item.changeset(%Item{}, item_attrs(feed, %{published_at: ~U[2030-01-01 00:00:00Z]}))

      assert Ecto.Changeset.get_field(ignored, :published_at) == ~U[2026-11-07 09:00:00.000000Z]

      assert raw_insert("news_items", raw_item(feed, %{published_at: ~U[2026-11-08 00:00:00Z]})) ==
               "news_items_published_at_check"

      assert raw_insert(
               "news_items",
               raw_item(feed, %{published_at_claimed: nil, published_at: ~U[2026-11-07 08:00:00Z]})
             ) == "news_items_published_at_check"
    end

    # User story (ADR-0056 §4, §9; plan D-6):
    # As the operator who keeps condensed signals, never an archive,
    # I want a title of at most 160 and an excerpt of at most 600
    # characters, counted as characters, without control characters, with
    # invisible characters kept as received,
    # so that nothing stored is an article and the evidence is not altered.
    #
    # Acceptance criteria:
    # - 160 multi-byte characters fit a title, 161 do not; 600 fit an
    #   excerpt, 601 do not; a blank title is refused — by the changeset and
    #   by the database.
    # - A control character is refused in a title; a zero-width space is
    #   stored as received.
    test "the title and the excerpt are capped by characters and keep invisible characters" do
      feed = issuer_feed!(security!())

      assert %Item{} =
               item!(feed, %{
                 title: String.duplicate("ü", 160),
                 excerpt: String.duplicate("é", 600)
               })

      assert %Item{title: "Split\u200Bwise"} = item!(feed, %{title: "Split\u200Bwise"})

      for {attrs, field} <- [
            {%{title: String.duplicate("ü", 161)}, :title},
            {%{title: "  "}, :title},
            {%{title: "Bell\u0007 rings"}, :title},
            {%{excerpt: String.duplicate("é", 601)}, :excerpt}
          ] do
        assert Map.has_key?(errors_on(Item.changeset(%Item{}, item_attrs(feed, attrs))), field)
      end

      assert raw_insert("news_items", raw_item(feed, %{title: String.duplicate("ü", 161)})) ==
               "news_items_title_check"

      assert raw_insert("news_items", raw_item(feed, %{title: " "})) == "news_items_title_check"

      assert raw_insert("news_items", raw_item(feed, %{title: "Bell\u0007 rings"})) ==
               "news_items_title_check"

      assert raw_insert("news_items", raw_item(feed, %{excerpt: String.duplicate("é", 601)})) ==
               "news_items_excerpt_check"
    end

    # User story (ADR-0056 §2, B5):
    # As the operator trusting a story's tier,
    # I want an item's binding to follow its class, its candidates to exist
    # only while it is ambiguous, and an aggregator's item never to be
    # primary,
    # so that no stored item is bound by guesswork or ranked by a claim.
    #
    # Acceptance criteria:
    # - issuer and regulatory items are assigned to a security, thematic
    #   items to a category; an aggregator item is assigned to a security,
    #   or unassigned, or ambiguous with at least two candidates, never to a
    #   category.
    # - Candidates are stored sorted and without repeats, and only on an
    #   ambiguous item.
    # - An aggregator item is never primary; no item is blocked.
    # - An item's class is its feed's.
    # - Each rule is refused by the changeset and by the database.
    test "the binding follows the class, candidates only while ambiguous, an aggregator never primary" do
      security = security!()
      other = security!("Larkspur Robotics Inc")
      category = category!()
      issuer = issuer_feed!(security)
      aggregator = feed!(%{class: "aggregator", language: "en"})
      thematic = feed!(%{class: "thematic", category_id: category.id, language: "en"})

      assert %Item{assignment: :assigned} = item!(thematic, %{tier: "secondary"})

      assert %Item{assignment: :unassigned, candidates: []} =
               item!(aggregator, %{assignment: "unassigned", tier: "secondary"})

      assert %Item{assignment: :ambiguous, candidates: candidates} =
               item!(aggregator, %{
                 assignment: "ambiguous",
                 tier: "awareness",
                 candidates: [other.id, security.id, other.id]
               })

      assert candidates == Enum.sort([other.id, security.id])

      assert %Item{security_id: id} =
               item!(aggregator, %{
                 assignment: "assigned",
                 security_id: security.id,
                 tier: "secondary"
               })

      assert id == security.id

      for {feed, attrs, field} <- [
            {issuer, %{security_id: nil}, :security_id},
            {issuer, %{assignment: "unassigned", security_id: nil}, :assignment},
            {issuer, %{category_id: category.id}, :category_id},
            {thematic, %{category_id: nil, tier: "secondary"}, :category_id},
            {aggregator, %{category_id: category.id, tier: "secondary"}, :category_id},
            {aggregator, %{assignment: "assigned", tier: "secondary"}, :security_id},
            {aggregator, %{assignment: "unassigned", security_id: security.id, tier: "secondary"},
             :security_id},
            {aggregator, %{assignment: "ambiguous", candidates: [security.id], tier: "secondary"},
             :candidates},
            {aggregator,
             %{assignment: "unassigned", candidates: [security.id, other.id], tier: "secondary"},
             :candidates},
            {aggregator, %{assignment: "unassigned", tier: "primary"}, :tier},
            {issuer, %{tier: "blocked"}, :tier},
            {issuer, %{assignment: "maybe"}, :assignment}
          ] do
        changeset = Item.changeset(%Item{}, item_attrs(feed, attrs))
        assert Map.has_key?(errors_on(changeset), field), "#{feed.class} #{inspect(attrs)}"
      end

      for {feed, attrs, constraint} <- [
            {issuer, %{security_id: nil}, "news_items_binding_check"},
            {issuer, %{category_id: category.id}, "news_items_binding_check"},
            {thematic, %{category_id: nil}, "news_items_binding_check"},
            {aggregator, %{category_id: category.id, tier: "secondary"},
             "news_items_binding_check"},
            {aggregator, %{assignment: "assigned", tier: "secondary"},
             "news_items_binding_check"},
            {aggregator, %{assignment: "unassigned", security_id: security.id, tier: "secondary"},
             "news_items_binding_check"},
            {aggregator, %{assignment: "ambiguous", candidates: [security.id], tier: "secondary"},
             "news_items_candidates_check"},
            {aggregator,
             %{assignment: "unassigned", candidates: [security.id, other.id], tier: "secondary"},
             "news_items_candidates_check"},
            {aggregator, %{assignment: "unassigned", tier: "primary"}, "news_items_tier_check"},
            {issuer, %{tier: "blocked"}, "news_items_tier_check"},
            {issuer, %{assignment: "maybe"}, "news_items_assignment_check"},
            {issuer, %{status: "read"}, "news_items_status_check"},
            {issuer, %{class: "blog"}, "news_items_class_check"},
            {issuer, %{class: "aggregator", tier: "secondary"}, "news_items_feed_class_fkey"}
          ] do
        assert raw_insert("news_items", raw_item(feed, attrs)) == constraint,
               "#{feed.class} #{inspect(attrs)}"
      end
    end

    # User story (ADR-0056 §4, §8, §12):
    # As the maintainer of the matcher and the clustering,
    # I want an item's URL, domain, language and hashes stored in one
    # checked shape, a promoted item to name its notes, and a re-fetch of
    # the same item to store nothing new,
    # so that dedupe and retention read the same values every writer wrote.
    #
    # Acceptance criteria:
    # - The canonical URL is http or https, without spaces, at most 2,048
    #   characters; the domain lower-case; the hashes 64 lower-case hex
    #   digits; at most 160 title words.
    # - A promoted item names at least one note.
    # - The same canonical URL from the same feed is a changeset error the
    #   second time (the re-fetch is idempotent); from another feed it is
    #   stored.
    test "url, domain, hashes and words have one shape; a re-fetch of the same item stores nothing" do
      security = security!()
      feed = issuer_feed!(security)
      second = issuer_feed!(security)

      item =
        item!(feed, %{
          canonical_url: "https://newsroom.example.com/same",
          domain: "NewsRoom.Example.com"
        })

      assert item.domain == "newsroom.example.com"

      assert {:error, changeset} =
               %Item{}
               |> Item.changeset(
                 item_attrs(feed, %{canonical_url: "https://newsroom.example.com/same"})
               )
               |> Repo.insert()

      assert %{canonical_url: ["has already been taken"]} = errors_on(changeset)

      assert %Item{} = item!(second, %{canonical_url: "https://newsroom.example.com/same"})
      assert %Item{} = item!(feed, %{canonical_url: "http://plain.example.com/a"})

      for {attrs, field} <- [
            {%{canonical_url: "javascript:alert(1)"}, :canonical_url},
            {%{canonical_url: "https://a.example/" <> String.duplicate("p", 2031)},
             :canonical_url},
            {%{domain: "a b.example"}, :domain},
            {%{content_hash: "XYZ"}, :content_hash},
            {%{title_norm_hash: String.duplicate("A", 64)}, :title_norm_hash},
            {%{title_words: List.duplicate("w", 161)}, :title_words},
            {%{status: "promoted"}, :note_ids}
          ] do
        assert Map.has_key?(errors_on(Item.changeset(%Item{}, item_attrs(feed, attrs))), field),
               inspect(attrs) |> String.slice(0, 80)
      end

      assert %Item{status: :promoted, note_ids: [7]} =
               item!(feed, %{status: "promoted", note_ids: [7]})

      for {attrs, constraint} <- [
            {%{canonical_url: "ftp://a.example/x"}, "news_items_canonical_url_check"},
            {%{canonical_url: "https://a.example/a b"}, "news_items_canonical_url_check"},
            {%{domain: "News.example.com"}, "news_items_domain_check"},
            {%{language: "EN"}, "news_items_language_check"},
            {%{content_hash: String.duplicate("A", 64)}, "news_items_content_hash_check"},
            {%{title_norm_hash: "abc"}, "news_items_title_norm_hash_check"},
            {%{title_words: List.duplicate("w", 161)}, "news_items_title_words_check"},
            {%{status: "promoted"}, "news_items_note_ids_check"},
            {%{canonical_url: "https://newsroom.example.com/same"},
             "news_items_feed_id_canonical_url_index"}
          ] do
        assert raw_insert("news_items", raw_item(feed, attrs)) == constraint, constraint
      end
    end

    # User story (ADR-0056 §4, B3):
    # As the maintainer of the clustering,
    # I want an item to sit only in a story of its own security (or
    # category) and language, and only once it is assigned,
    # so that no story mixes companies or languages, whoever writes it.
    #
    # Acceptance criteria:
    # - An assigned item joins a story of its security and language.
    # - An unassigned item in a story, an item in another security's story
    #   and an item in another language's story are refused by the database.
    test "an item sits only in a story of its own security and language" do
      security = security!()
      other = security!("Larkspur Robotics Inc")
      feed = issuer_feed!(security)
      german = feed!(%{class: "issuer", security_id: security.id, language: "de"})
      other_feed = issuer_feed!(other)
      aggregator = feed!(%{class: "aggregator", language: "en"})

      first = item!(feed)
      cluster = cluster!(first)

      assert {:ok, %Item{cluster_id: cluster_id}} =
               first |> Item.changeset(%{cluster_id: cluster.id}) |> Repo.update()

      assert cluster_id == cluster.id

      assert raw_insert("news_items", raw_item(feed, %{cluster_id: cluster.id})) == :inserted

      assert raw_insert("news_items", raw_item(other_feed, %{cluster_id: cluster.id})) ==
               "news_items_cluster_security_fkey"

      assert raw_insert("news_items", raw_item(german, %{language: "de", cluster_id: cluster.id})) ==
               "news_items_cluster_security_fkey"

      assert raw_insert(
               "news_items",
               raw_item(aggregator, %{
                 assignment: "unassigned",
                 tier: "secondary",
                 security_id: nil,
                 cluster_id: cluster.id
               })
             ) == "news_items_cluster_check"

      unassigned = item!(aggregator, %{assignment: "unassigned", tier: "secondary"})

      assert %{cluster_id: [_]} =
               errors_on(Item.changeset(unassigned, %{cluster_id: cluster.id}))
    end
  end

  describe "news_clusters (§4, B3)" do
    # User story (ADR-0056 §4, B3):
    # As the operator reading one story per event,
    # I want a story to belong to exactly one security or category and one
    # language, to count its members, to name its representative and to
    # carry the survivor key of a merge — the earliest member's first sight
    # and canonical URL, never an id,
    # so that the same items give the same stories in any order.
    #
    # Acceptance criteria:
    # - Exactly one of security and category; at least one member; a best
    #   tier other than blocked; the earliest publication never after the
    #   earliest first sight; the earliest URL in the items' URL shape.
    # - Each is refused by the changeset and by the database.
    test "a story belongs to one security or category and carries its survivor key" do
      security = security!()
      category = category!()
      item = item!(issuer_feed!(security))
      cluster = cluster!(item)

      assert cluster.security_id == security.id
      assert cluster.earliest_url == item.canonical_url
      assert cluster.best_tier == :primary

      for {attrs, field} <- [
            {%{security_id: nil}, :security_id},
            {%{category_id: category.id}, :category_id},
            {%{member_count: 0}, :member_count},
            {%{best_tier: "blocked"}, :best_tier},
            {%{earliest_published_at: ~U[2026-11-07 10:00:01Z]}, :earliest_published_at},
            {%{earliest_url: "mailto:x@example.com"}, :earliest_url},
            {%{language: "EN!"}, :language}
          ] do
        changeset =
          Cluster.changeset(
            %Cluster{},
            %{
              security_id: security.id,
              language: "en",
              representative_item_id: item.id,
              member_count: 1,
              earliest_first_seen_at: @seen,
              earliest_published_at: @seen,
              earliest_url: item.canonical_url,
              best_tier: "primary"
            }
            |> Map.merge(attrs)
          )

        assert Map.has_key?(errors_on(changeset), field), inspect(attrs)
      end

      row = %{
        security_id: security.id,
        language: "en",
        representative_item_id: item.id,
        member_count: 1,
        earliest_first_seen_at: ~N[2026-11-07 10:00:00],
        earliest_published_at: ~N[2026-11-07 09:00:00],
        earliest_url: item.canonical_url,
        best_tier: "secondary",
        inserted_at: now_naive(),
        updated_at: now_naive()
      }

      assert raw_insert("news_clusters", row) == :inserted

      for {attrs, constraint} <- [
            {%{security_id: nil}, "news_clusters_scope_check"},
            {%{category_id: category.id}, "news_clusters_scope_check"},
            {%{member_count: 0}, "news_clusters_member_count_check"},
            {%{best_tier: "blocked"}, "news_clusters_best_tier_check"},
            {%{earliest_published_at: ~N[2026-11-07 10:00:01]}, "news_clusters_earliest_check"},
            {%{earliest_url: "mailto:x@example.com"}, "news_clusters_earliest_url_check"},
            {%{language: "En"}, "news_clusters_language_check"},
            {%{representative_item_id: -1}, "news_clusters_representative_item_id_fkey"}
          ] do
        assert raw_insert("news_clusters", Map.merge(row, attrs)) == constraint, constraint
      end
    end
  end

  describe "news_feed_days (§6, A3)" do
    # User story (ADR-0056 §6, A3):
    # As the operator reading a feed's health,
    # I want one counter row per feed and server day — items stored,
    # errors, and the items dropped for the cap, a missing source, age and
    # a blocked domain —
    # so that the day's dropped and blocked counts and the errors of the
    # last 24 hours can be read from stored rows.
    #
    # Acceptance criteria:
    # - One row per feed and day: a second is a changeset error.
    # - Counters start at zero and are never negative, by the changeset and
    #   by the database.
    test "one counter row per feed and day, never negative" do
      feed = feed!(%{class: "aggregator", language: "en"})

      day =
        %FeedDay{}
        |> FeedDay.changeset(%{feed_id: feed.id, day: ~D[2026-11-07], dropped_cap: 3})
        |> Repo.insert!()

      assert {day.items_stored, day.errors, day.dropped_cap, day.dropped_no_source,
              day.dropped_old, day.dropped_blocked} == {0, 0, 3, 0, 0, 0}

      assert {:error, changeset} =
               %FeedDay{}
               |> FeedDay.changeset(%{feed_id: feed.id, day: ~D[2026-11-07]})
               |> Repo.insert()

      assert %{day: ["has already been taken"]} = errors_on(changeset)

      assert %{errors: [_], dropped_old: [_]} =
               errors_on(
                 FeedDay.changeset(%FeedDay{}, %{
                   feed_id: feed.id,
                   day: ~D[2026-11-08],
                   errors: -1,
                   dropped_old: -2
                 })
               )

      for column <-
            ~w(items_stored errors dropped_cap dropped_no_source dropped_old dropped_blocked)a do
        row = %{feed_id: feed.id, day: ~D[2026-11-09]} |> Map.put(column, -1)
        assert raw_insert("news_feed_days", row) == "news_feed_days_counts_check", "#{column}"
      end
    end
  end

  describe "the journal's guard (B7)" do
    # User story (ADR-0056 B7):
    # As the operator reading the journal,
    # I want every write of a source and every write of what a feed's
    # registration states to need a journal actor, and the fetcher's health
    # writes and the items not to,
    # so that master data cannot change unrecorded while a fetch every ten
    # minutes does not fill the journal.
    #
    # Acceptance criteria:
    # - Without an actor, a source's insert, a feed's insert and an update of
    #   a feed's URL, interval or enabled flag are refused by the guard.
    # - Without an actor, a feed's health update and an item's insert are
    #   stored.
    test "sources and a feed's registration need an actor; health and items do not" do
      feed = issuer_feed!(security!())
      Repo.query!("SELECT set_config('portfolixir.journal_actor', '', true)")

      refused = fn sql, params ->
        match?(
          {:error, %Postgrex.Error{postgres: %{code: :restrict_violation}}},
          Repo.query(sql, params, mode: :savepoint)
        )
      end

      assert refused.(
               "INSERT INTO news_sources (domain, tier, set_by, inserted_at, updated_at) " <>
                 "VALUES ('x.example', 'primary', 'hand', now(), now())",
               []
             )

      assert refused.(
               "INSERT INTO news_feeds (class, url, interval_minutes, language, inserted_at, " <>
                 "updated_at) VALUES ('aggregator', 'https://g.example/f', 60, 'en', now(), now())",
               []
             )

      for set <- ["url = 'https://moved.example/f'", "interval_minutes = 30", "enabled = false"] do
        assert refused.("UPDATE news_feeds SET #{set} WHERE id = $1", [feed.id]), set
      end

      assert {:ok, %Feed{failures: 1}} =
               feed
               |> Feed.health_changeset(%{
                 failures: 1,
                 retry_at: ~U[2026-11-07 11:00:00Z],
                 last_fetch_at: @seen,
                 last_error: "http_503"
               })
               |> Repo.update()

      assert %Item{} = item!(feed)
    end
  end

  describe "the foreign keys and what removes them" do
    # User story (ADR-0050 §11, §14; ADR-0056 §12):
    # As the operator deleting a security, a category or a feed,
    # I want news rows that point at it to refuse the delete instead of
    # vanishing by cascade or breaking with a server error,
    # so that a promoted item never disappears with its feed and a delete
    # answers in words.
    #
    # Acceptance criteria:
    # - A security a feed or an item names is not deletable: the answer
    #   counts the news rows by table.
    # - A category a thematic feed names is not deletable: a changeset
    #   error, never a raised constraint error.
    # - A feed its items or its day rows name is refused by the database.
    test "news rows refuse the delete of what they name" do
      security = security!()
      feed = issuer_feed!(security)
      _item = item!(feed)

      assert {:error, {:referenced, referenced_by}} =
               Portfolixir.Catalog.delete_security(Actor.owner_ui(), security)

      assert referenced_by == %{"news_feeds" => 1, "news_items" => 1}

      category = category!()
      _thematic = feed!(%{class: "thematic", category_id: category.id, language: "en"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Classifications.delete_category(Actor.owner_ui(), category)

      assert %{id: ["is bound to a news feed or story"]} = errors_on(changeset)

      assert_raise Ecto.ConstraintError, ~r/news_items_feed_id_fkey/, fn ->
        Repo.delete(feed)
      end
    end
  end
end
