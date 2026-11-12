defmodule Portfolixir.News.PromotionTest do
  # ADR-0056 §8, A2 and ADR-0044's amendment of 2026-11-06 (Sprint 28, N5):
  # a story becomes knowledge only by a confirmed write. notes.append with a
  # cluster_id pre-fills what the story knows, the agent writes the body,
  # and the story is promoted and links the note; events.create takes an
  # item as its source. Risk tier SECURITY: an agent write path from foreign
  # text into the append-only log. Synthetic names and hosts only, every
  # domain this module's own (no row shared with another async module).
  use Portfolixir.DataCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Knowledge.SecurityEvent
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Reads
  alias Portfolixir.News.Retention
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Predictions.Prediction
  alias Portfolixir.Repo

  @agent Actor.api_token_rw("agent")

  # A domain of this module alone, rated `tier` (nil leaves it unrated:
  # awareness), with the class of feed that gives that tier: an issuer's
  # item is primary by construction, an aggregator's its domain's (B5).
  defp domain!(tier) do
    domain = "promo-#{System.unique_integer([:positive])}.example.org"
    if tier, do: {:ok, _} = Sources.put_source(Actor.owner_ui(), domain, tier)
    {domain, if(tier == :primary, do: :issuer, else: :aggregator)}
  end

  # One story of `security`: one item per `{domain, class}` (or `{domain,
  # class, link}`) of `members`, all titled `title`, stored a second apart
  # in that order and clustered.
  defp story!(security, title, members) do
    at = DateTime.add(DateTime.utc_now(), -3600, :second)

    items =
      members
      |> Enum.with_index()
      |> Enum.map(fn {member, index} ->
        {domain, class, link} =
          case member do
            {domain, class} -> {domain, class, "https://#{domain}/release-#{index}"}
            {_domain, _class, _link} = given -> given
          end

        feed =
          if class == :issuer,
            do: NewsFixtures.feed!(%{class: "issuer", security_id: security.id}),
            else: NewsFixtures.feed!(%{class: "aggregator"})

        %Item{}
        |> Item.changeset(
          Map.merge(Stories.title_keys(title), %{
            feed_id: feed.id,
            class: feed.class,
            security_id: security.id,
            assignment: :assigned,
            first_seen_at: DateTime.add(at, index, :second),
            title: title,
            canonical_url: link,
            domain: domain,
            tier: Sources.tier_for(domain, feed.class),
            language: "en",
            content_hash: :sha256 |> :crypto.hash(link) |> Base.encode16(case: :lower)
          })
        )
        |> Repo.insert!()
      end)

    {:ok, _} = Stories.recluster({:security, security.id}, "en", DateTime.utc_now())
    Repo.get!(Cluster, Repo.get!(Item, hd(items).id).cluster_id)
  end

  defp members(story),
    do: Repo.all(from(i in Item, where: i.cluster_id == ^story.id, order_by: i.id))

  defp promote(security, story, attrs \\ %{}) do
    News.append_note_from_story(
      @agent,
      Map.merge(
        %{"security_id" => security.id, "author" => "agent", "body" => "Summary."},
        attrs
      ),
      story.id
    )
  end

  defp errors({:error, %Ecto.Changeset{} = changeset}),
    do: changeset.errors |> Keyword.keys() |> Enum.map(&Atom.to_string/1)

  defp errors({:error, %{} = errors}), do: Map.keys(errors)

  # User story (ADR-0056 §8, A2; ADR-0044's amendment of 2026-11-06):
  # As the operating agent who judged a story worth keeping,
  # I want notes.append with its cluster_id to fill in what the story
  # already knows — kind, date, link, source quality, headline, event type
  # and tone — while I write the body,
  # so that the entry states the story's provenance by rule, and the story
  # shows it was kept.
  #
  # Acceptance criteria:
  # - The entry is an evidence entry: as_of is the story's publication day,
  #   source_url its best-tier member's link, source_quality by §3's rule,
  #   headline its title, event type and tone its active label's (newest
  #   prompt version), news_label_id that label's id; the body is the
  #   agent's, the author the credential's, the write journaled.
  # - Every member of the story is promoted and names the note.
  describe "notes.append with a cluster_id" do
    test "pre-fills the entry from the story and its active label, and promotes the story" do
      security = NewsFixtures.security!()
      primary = domain!(:primary)
      story = story!(security, "Northwind raises its outlook", [primary, domain!(:secondary)])
      _old = NewsFixtures.label!(story.id, event_type: "earnings", tone: -1, prompt_version: "a1")
      label = NewsFixtures.label!(story.id, event_type: "guidance", tone: 1, prompt_version: "a2")

      assert {:ok, %SecurityNote{} = note} = promote(security, story)

      representative = Repo.get!(Item, story.representative_item_id)
      assert representative.domain == elem(primary, 0)
      assert note.kind == :evidence
      assert note.body == "Summary."
      assert note.author == :agent
      assert note.as_of == Clock.local_date(representative.published_at)
      assert note.source_url == representative.canonical_url
      assert note.source_quality == :primary
      assert note.headline == "Northwind raises its outlook"
      assert {note.event_type, note.tone, note.news_label_id} == {:guidance, 1, label.id}

      for item <- members(story) do
        assert {item.status, item.note_ids} == {:promoted, [note.id]}
      end

      assert [%{actor_label: "agent", operation: :create}] =
               Journal.list_entries(resource_type: "security_note", resource_id: "#{note.id}")
    end

    test "source_quality follows §3: two secondary domains, one, awareness only" do
      security = NewsFixtures.security!()
      [s1, s2] = [domain!(:secondary), domain!(:secondary)]

      for {domains, expected} <- [
            {[s1, s2], :secondary_multi},
            {[s1, s1], :unverified},
            {[domain!(nil), domain!(:awareness)], :awareness}
          ] do
        title = "Northwind story #{System.unique_integer([:positive])}"
        story = story!(security, title, domains)
        assert {:ok, note} = promote(security, story)
        assert note.source_quality == expected, inspect(domains)
      end
    end

    test "a title over 80 is cut on a word boundary by its spelled width" do
      security = NewsFixtures.security!()
      words = ~s(Northwind "Harbour" \\ Logistics announces a long synthetic headline about)
      title = words <> " its quarterly figures and the outlook for the coming year"
      story = story!(security, title, [domain!(:primary)])

      assert {:ok, note} = promote(security, story)
      assert String.ends_with?(note.headline, "…")
      prefix = String.trim_trailing(note.headline, "…")
      assert String.starts_with?(title, prefix)
      # The cut falls between two words, and the headline spelled for the
      # agent (quotes and backslashes escaped) fits 80.
      assert String.at(title, String.length(prefix)) == " "
      refute String.ends_with?(prefix, " ")
      assert Reads.spelled_width(note.headline) <= 80
      # ... and it is the longest such cut: the next word would not fit.
      [next | _] = title |> String.slice(String.length(prefix) + 1, 200) |> String.split(" ")
      assert Reads.spelled_width(prefix <> " " <> next <> "…") > 80

      long_word = String.duplicate("N", 120)
      story = story!(security, long_word, [domain!(:primary)])
      assert {:ok, note} = promote(security, story)
      assert note.headline == String.duplicate("N", 79) <> "…"
    end
  end

  # User story (ADR-0044's amendment: "the writer may change any of them
  # before the write"):
  # As the operating agent confirming the proposal,
  # I want to change the headline, the event type or the tone in the same
  # call, or leave one out, and record an event_result instead of evidence,
  # so that what is stored is what I judged, and the label id stays only
  # when something was taken from the label.
  #
  # Acceptance criteria:
  # - headline, event_type and tone sent beside cluster_id replace the
  #   pre-fill; a null leaves the field out; with both event type and tone
  #   sent, the entry keeps no label id.
  # - kind event_result is taken; another kind answers naming kind.
  # - as_of, source_url and source_quality beside cluster_id answer naming
  #   the field: they are the story's.
  # - A noise label pre-fills no event type; a story without a label
  #   pre-fills neither and keeps no label id.
  describe "the pre-fill is a proposal" do
    test "headline, event type and tone are the caller's to change" do
      security = NewsFixtures.security!()
      story = story!(security, "Northwind files a synthetic report", [domain!(:primary)])
      label = NewsFixtures.label!(story.id, event_type: "legal", tone: -1)

      assert {:ok, note} =
               promote(security, story, %{"headline" => "Report filed", "tone" => 0})

      assert {note.headline, note.event_type, note.tone} == {"Report filed", :legal, 0}
      assert note.news_label_id == label.id

      assert {:ok, note} =
               promote(security, story, %{
                 "kind" => "event_result",
                 "headline" => nil,
                 "event_type" => "product",
                 "tone" => 1
               })

      assert {note.kind, note.headline, note.event_type, note.tone} ==
               {:event_result, nil, :product, 1}

      assert note.news_label_id == nil
    end

    test "another kind, and the story's own fields, are refused naming the field" do
      security = NewsFixtures.security!()
      story = story!(security, "Northwind synthetic refusal", [domain!(:primary)])

      assert ["kind"] = errors(promote(security, story, %{"kind" => "thesis"}))

      for {field, value} <- [
            {"as_of", "2026-01-01"},
            {"source_url", "https://elsewhere.example.org/x"},
            {"source_quality", "primary"}
          ] do
        assert [^field] = errors(promote(security, story, %{field => value}))
      end

      assert Repo.aggregate(SecurityNote, :count) == 0
      assert Enum.all?(members(story), &(&1.status == :new))
    end

    test "a noise label pre-fills no event type; no label pre-fills neither" do
      security = NewsFixtures.security!()
      noisy = story!(security, "Northwind noise", [domain!(:primary)])
      label = NewsFixtures.label!(noisy.id, event_type: "noise", tone: 0)

      assert {:ok, note} = promote(security, noisy)
      assert {note.event_type, note.tone, note.news_label_id} == {nil, 0, label.id}

      quiet = story!(security, "Northwind unlabelled", [domain!(:primary)])
      assert {:ok, note} = promote(security, quiet)
      assert {note.event_type, note.tone, note.news_label_id} == {nil, nil, nil}
    end
  end

  # User story (ADR-0056 §8):
  # As the operator whose agent may promote a story twice, or name the
  # wrong one,
  # I want a second promotion to add a second entry the story links beside
  # the first, and a story of another security or none refused,
  # so that nothing kept is lost and no entry lands on the wrong security.
  #
  # Acceptance criteria:
  # - A second promotion appends another entry; every member names both.
  # - A story of another security, a category's story and an id naming no
  #   story answer naming cluster_id, and nothing is written.
  # - A story whose every link is 300 characters, as an aggregator's
  #   redirect links often are, is promoted with its representative's link
  #   (ADR-0056 E2: an entry's link holds the 2,048 characters the parser
  #   accepts, so no member's link is too long for it).
  describe "which story" do
    test "a second promotion appends another entry, and the story links both" do
      security = NewsFixtures.security!()
      story = story!(security, "Northwind promoted twice", [domain!(:primary)])

      assert {:ok, first} = promote(security, story)
      assert {:ok, second} = promote(security, story, %{"kind" => "event_result"})

      assert [%Item{note_ids: ids}] = members(story)
      assert ids == [first.id, second.id]
    end

    test "a story of another security, a category's story or none is refused" do
      security = NewsFixtures.security!()
      other = NewsFixtures.security!("Southwind Synthetic AG")
      theirs = story!(other, "Southwind story", [domain!(:primary)])

      assert ["cluster_id"] = errors(promote(security, theirs))
      assert ["cluster_id"] = errors(promote(security, %{id: 9_000_000_000}))

      category = NewsFixtures.category!()
      feed = NewsFixtures.feed!(%{class: "thematic", category_id: category.id})
      parsed = %Parsed{title: "Water theme", link: "https://#{elem(domain!(nil), 0)}/w"}
      {:ok, %{stored: 1}} = Ingest.ingest(feed, [parsed], DateTime.utc_now())
      %Item{cluster_id: themed} = Repo.get_by!(Item, feed_id: feed.id)

      assert ["cluster_id"] = errors(promote(security, %{id: themed}))
      assert Repo.aggregate(SecurityNote, :count) == 0
    end

    test "a story whose every link is 300 characters is promoted with its representative's" do
      security = NewsFixtures.security!()
      {first, :issuer} = domain!(:primary)
      {second, :aggregator} = domain!(:secondary)
      first_link = "https://#{first}/" <> String.duplicate("a", 300 - String.length(first) - 9)
      second_link = "https://#{second}/" <> String.duplicate("b", 300 - String.length(second) - 9)
      assert String.length(first_link) == 300 and String.length(second_link) == 300

      story =
        story!(security, "Northwind long links", [
          {first, :issuer, first_link},
          {second, :aggregator, second_link}
        ])

      assert Repo.get!(Item, story.representative_item_id).canonical_url == first_link
      assert {:ok, note} = promote(security, story)
      assert note.source_url == first_link
      assert note.source_quality == :primary
      assert Enum.all?(members(story), &(&1.status == :promoted and &1.note_ids == [note.id]))
    end
  end

  # User story (ADR-0056 E1 rule 5, precision of the closing act, Sprint
  # 29, #1444):
  # As the operator who re-rated a domain after one of its stories was
  # promoted,
  # I want a second entry from that story, and an event from one of its
  # items, to state the source quality my table gives now,
  # so that no new entry claims a better source than the table allows.
  #
  # Acceptance criteria:
  # - A second promotion reads each member's current tier; a member whose
  #   domain is now blocked is left out, and a story with no member left is
  #   refused naming cluster_id.
  # - The first entry and the members' stored tiers are unchanged (rule 5).
  # - events.create with a news_id reads the item's current tier, and an
  #   item whose domain is now blocked is refused naming news_id.
  describe "after a re-rating (E1 rule 5)" do
    test "a second promotion after a block is refused naming cluster_id" do
      security = NewsFixtures.security!()
      {domain, :aggregator} = member = domain!(:secondary)
      story = story!(security, "Northwind wins a tender", [member])

      assert {:ok, %SecurityNote{source_quality: :unverified} = first} = promote(security, story)
      assert {:ok, _} = Sources.put_source(Actor.owner_ui(), domain, :blocked)
      assert [%Item{tier: :secondary, status: :promoted}] = members(story)

      assert {:error, %{"cluster_id" => [message]}} =
               promote(security, story, %{"kind" => "event_result"})

      assert message =~ "blocked"
      assert Repo.all(from(n in SecurityNote, select: n.id)) == [first.id]
      assert {:error, %{"cluster_id" => _}} = News.story_proposal(story.id, security.id)
    end

    test "a second promotion after a downgrade states the lower quality" do
      security = NewsFixtures.security!()
      {one, _} = domain!(:primary)
      {two, _} = domain!(:primary)

      story =
        story!(security, "Northwind wins a second tender", [
          {one, :aggregator},
          {two, :aggregator}
        ])

      assert {:ok, %SecurityNote{source_quality: :secondary_multi} = first} =
               promote(security, story)

      assert {:ok, _} = Sources.put_source(Actor.owner_ui(), one, :awareness)
      assert {:ok, _} = Sources.put_source(Actor.owner_ui(), two, :awareness)

      assert {:ok, %SecurityNote{source_quality: :awareness}} =
               promote(security, story, %{"kind" => "event_result"})

      assert Repo.get!(SecurityNote, first.id).source_quality == :secondary_multi
      assert Enum.map(members(story), & &1.tier) == [:secondary, :secondary]
    end

    test "a member now blocked is left out, and the link is another member's" do
      security = NewsFixtures.security!()
      {one, _} = blocked_later = domain!(:secondary)
      kept = domain!(:secondary)
      story = story!(security, "Northwind wins a third tender", [blocked_later, kept])

      assert {:ok, %SecurityNote{source_quality: :secondary_multi}} = promote(security, story)
      assert {:ok, _} = Sources.put_source(Actor.owner_ui(), one, :blocked)

      assert {:ok, %SecurityNote{source_quality: :unverified, source_url: url}} =
               promote(security, story, %{"kind" => "event_result"})

      assert URI.parse(url).host == elem(kept, 0)
    end

    test "events.create with a news_id reads the item's current tier" do
      security = NewsFixtures.security!()
      {domain, :aggregator} = member = domain!(:secondary)
      story = story!(security, "Northwind dates its tender", [member])
      [item] = members(story)

      assert {:ok, _} = promote(security, story)
      assert {:ok, _} = Sources.put_source(Actor.owner_ui(), domain, :awareness)
      assert %Item{tier: :secondary} = Repo.get!(Item, item.id)

      assert {:ok, %{"source_quality" => :awareness}} = News.event_source(security.id, item.id)

      assert {:ok, _} = Sources.put_source(Actor.owner_ui(), domain, :blocked)
      assert {:error, %{"news_id" => [message]}} = News.event_source(security.id, item.id)
      assert message =~ "blocked"
    end
  end

  # User story (ADR-0056 §8; ADR-0048):
  # As the operating agent recording a date a news item announced,
  # I want events.create to take the item as its source,
  # so that the event carries the item's link and a source quality by §3's
  # rule without my copying them.
  #
  # Acceptance criteria:
  # - An item of the event's security gives its link and its tier's
  #   quality (primary, secondary as unverified, awareness).
  # - An item of another security, and an id naming none, answer naming
  #   news_id.
  # - An item whose link is 300 characters gives it whole (ADR-0056 E2).
  describe "events.create with a news_id" do
    test "an item gives its link and source quality; another security's is refused" do
      security = NewsFixtures.security!()

      for {tier, expected} <- [primary: :primary, secondary: :unverified, awareness: :awareness] do
        story = story!(security, "Northwind dated #{tier}", [domain!(tier)])
        [item] = members(story)

        assert {:ok, %{"source_url" => url, "source_quality" => ^expected}} =
                 News.event_source(security.id, item.id)

        assert url == item.canonical_url
      end

      other = NewsFixtures.security!("Eastwind Synthetic AG")
      [theirs] = members(story!(other, "Eastwind dated", [domain!(:primary)]))

      assert {:error, %{"news_id" => _}} = News.event_source(security.id, theirs.id)
      assert {:error, %{"news_id" => _}} = News.event_source(security.id, 9_000_000_000)
    end

    test "an item whose link is 300 characters gives it whole" do
      security = NewsFixtures.security!()
      {domain, :aggregator} = domain!(:secondary)
      link = "https://#{domain}/" <> String.duplicate("c", 300 - String.length(domain) - 9)
      assert String.length(link) == 300

      [item] = members(story!(security, "Northwind dated long", [{domain, :aggregator, link}]))

      assert {:ok, %{"source_url" => ^link, "source_quality" => :unverified}} =
               News.event_source(security.id, item.id)

      assert {:ok, %SecurityEvent{source_url: ^link}} =
               Events.create_event(@agent, %{
                 "security_id" => security.id,
                 "kind" => "earnings",
                 "date" => "2026-11-20",
                 "timing" => "exact",
                 "source_url" => link,
                 "source_quality" => "unverified"
               })
    end
  end

  # User story (ADR-0056 §8, NFR-10; Sprint 28 D-1 criterion 5):
  # As the operator who keeps what an outside model proposes a proposal,
  # I want nothing in the news layer to write a research-log entry, an
  # event or a prediction by itself,
  # so that a story becomes knowledge only by a confirmed write.
  #
  # Acceptance criteria:
  # - Ingest, clustering, labels, the reads, health, an assignment and the
  #   retention run leave the research log, the events and the predictions
  #   empty.
  # - In lib/portfolixir/news and news.ex only the promotion module calls
  #   the research log's write, and no news module calls an event's or a
  #   prediction's write.
  describe "NFR-10" do
    test "the news layer's own work writes no note, event or prediction" do
      security = NewsFixtures.security!()
      story = story!(security, "Northwind left alone", [domain!(:primary), domain!(:secondary)])
      NewsFixtures.label!(story.id, materiality: 3, tone: 1)
      now = DateTime.utc_now()

      {:ok, _} = Reads.list({:security, security.id}, limit: 20, prompt_version: "v1")
      {:ok, _} = Reads.story(story.id, "v1")
      _digest = Reads.digest([security.id], DateTime.add(now, -86_400, :second), true, 12)
      _health = News.health(now)
      {:ok, _} = Retention.run(DateTime.add(now, 200, :day))

      assert Repo.aggregate(SecurityNote, :count) == 0
      assert Repo.aggregate(SecurityEvent, :count) == 0
      assert Repo.aggregate(Prediction, :count) == 0
    end

    test "only the promotion module calls the research log's write" do
      files = ["lib/portfolixir/news.ex" | Path.wildcard("lib/portfolixir/news/**/*.ex")]

      for file <- files, source = File.read!(file) do
        unless Path.basename(file) == "promotion.ex" do
          refute source =~ ~r/Knowledge\.append_note|%SecurityNote\{\}/, file
        end

        refute source =~ ~r/Events\.(create|update)_event|Predictions\.create/, file
      end
    end
  end
end
