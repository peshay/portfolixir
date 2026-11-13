defmodule Portfolixir.News.RetierAttackTest do
  # Sprint 29 plan D-8 item 5: the attack lens on N1 (#1444; ADR-0056 E1,
  # amendment of 2026-11-12) before integration. Each case tries to make a
  # rating break E1 or leave stored rows that disagree with each other: a
  # promoted item moved, a domain row reaching another domain's items, a
  # write that changes nothing re-rating anyway, a retry that leaves half a
  # write, a removal that leaves a story without its representative. The
  # cases that race two real connections are in
  # `Portfolixir.LockRace.NewsRetierAttackTest` below.
  #
  # Synthetic names and hosts only; every rated domain is this module's own
  # (`atk-<n>.example` and its relatives), so no async module holds its row.
  use Portfolixir.DataCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Item
  alias Portfolixir.News.Label
  alias Portfolixir.News.Source
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo

  @agent Actor.api_token_rw("synthetic-agent")

  defp n, do: System.unique_integer([:positive])
  defp domain, do: "atk-#{n()}.example"

  defp rate!(domain, tier), do: {:ok, %Source{}} = Sources.put_source(@agent, domain, tier)

  # One stored item of `class` from `domain`, with the tier its domain has
  # now, as the ingest stores it: bound to `opts[:security]` or
  # `opts[:category]`, or unassigned. Published `opts[:at]` seconds after a
  # fixed hour; titled `opts[:title]`.
  defp item!(class, domain, opts) do
    n = n()
    at = DateTime.add(~U[2026-11-10 09:00:00.000000Z], Keyword.get(opts, :at, 0), :second)
    title = Keyword.get(opts, :title, "Harbour wrap #{n}")
    link = "https://#{domain}/r-#{n}"

    {feed_attrs, binding} =
      case {class, opts[:security], opts[:category]} do
        {:issuer, security, nil} ->
          {%{class: "issuer", security_id: security.id},
           %{security_id: security.id, assignment: :assigned}}

        {:aggregator, nil, nil} ->
          {%{class: "aggregator"}, %{assignment: :unassigned}}

        {:aggregator, security, nil} ->
          {%{class: "aggregator"}, %{security_id: security.id, assignment: :assigned}}

        {:thematic, nil, category} ->
          {%{class: "thematic", category_id: category.id},
           %{category_id: category.id, assignment: :assigned}}
      end

    feed = NewsFixtures.feed!(feed_attrs)

    %Item{}
    |> Item.changeset(
      Stories.title_keys(title)
      |> Map.merge(binding)
      |> Map.merge(%{
        feed_id: feed.id,
        class: feed.class,
        first_seen_at: at,
        published_at_claimed: at,
        title: title,
        canonical_url: link,
        domain: domain,
        tier: Sources.tier_for(domain, feed.class),
        language: Keyword.get(opts, :language, "en"),
        content_hash: :sha256 |> :crypto.hash(link) |> Base.encode16(case: :lower),
        status: :new
      })
    )
    |> Repo.insert!()
  end

  defp cluster!(security) do
    {:ok, _} = Stories.recluster({:security, security.id}, "en", DateTime.utc_now(), full: true)
  end

  defp reload(%Item{id: id}), do: Repo.get(Item, id)
  defp story_of(%Item{} = item), do: Repo.get!(Cluster, reload(item).cluster_id)

  defp members(cluster_id),
    do: Repo.all(from(i in Item, where: i.cluster_id == ^cluster_id, order_by: i.id))

  defp entries(domain) do
    case Repo.get_by(Source, domain: domain) do
      nil -> []
      %Source{id: id} -> Journal.list_entries(resource_type: "news_source", resource_id: "#{id}")
    end
  end

  defp counts(domain),
    do:
      domain
      |> entries()
      |> hd()
      |> Map.fetch!(:after)
      |> Map.take(~w(items_rerated items_removed items_kept_promoted))

  # E1 rule 1 and 2, read off the table as it is now: every unpromoted item
  # still stored carries `Sources.tier(class, rated)` for the row
  # `Sources.lookup/1` names for its domain, the ingest's own reading.
  defp assert_follows_table!(items) do
    for %Item{} = item <- items,
        stored = reload(item),
        stored != nil,
        stored.status != :promoted and stored.note_ids == [] do
      rated = Map.get(Sources.lookup([stored.domain]), stored.domain)

      assert stored.tier == Sources.tier(stored.class, rated),
             "#{stored.domain}: stored #{stored.tier}, the table gives #{inspect(rated)}"
    end
  end

  # A story's stored summary agrees with its members (B3, C2): it has at
  # least one, its representative is one of them and ranks first, its best
  # tier is the best member's, and its count is theirs.
  @rank %{primary: 0, secondary: 1, awareness: 2}
  defp assert_story_whole!(cluster_id) do
    story = Repo.get!(Cluster, cluster_id)
    members = members(cluster_id)
    assert members != [], "story #{cluster_id} has no member"
    assert story.member_count == length(members)
    assert story.representative_item_id in Enum.map(members, & &1.id)
    best = members |> Enum.map(&@rank[&1.tier]) |> Enum.min()
    assert @rank[story.best_tier] == best
    rep = Enum.find(members, &(&1.id == story.representative_item_id))
    assert @rank[rep.tier] == best
  end

  # Marks `item` as naming a note without promoting it (status stays new),
  # as a hand write of `note_ids` would: E1 rule 5 reads either as promoted.
  defp name_a_note!(%Item{id: id}),
    do: Repo.update_all(from(i in Item, where: i.id == ^id), set: [note_ids: [9_999_001]])

  # (a) A rating that wants to move a promoted item.
  describe "(a) a promoted item, or one naming a note, is never moved" do
    test "an item naming a note but not promoted keeps its tier through a downgrade and a block" do
      rated = domain()
      rate!(rated, :secondary)
      security = NewsFixtures.security!()

      noted = item!(:aggregator, rated, security: security, title: "Quay one noted")
      open = item!(:aggregator, rated, title: "Quay open noted")
      plain = item!(:aggregator, rated, title: "Quay plain")
      name_a_note!(noted)
      name_a_note!(open)
      cluster!(security)

      rate!(rated, :awareness)
      assert %Item{tier: :secondary} = reload(noted)
      assert %Item{tier: :secondary} = reload(open)
      assert %Item{tier: :awareness} = reload(plain)

      assert counts(rated) == %{
               "items_rerated" => 1,
               "items_removed" => 0,
               "items_kept_promoted" => 2
             }

      rate!(rated, :blocked)
      assert %Item{tier: :secondary} = reload(noted)
      assert %Item{tier: :secondary} = reload(open)
      assert reload(plain) == nil

      assert counts(rated) == %{
               "items_rerated" => 0,
               "items_removed" => 1,
               "items_kept_promoted" => 2
             }
    end

    test "a story promoted before a later member arrived: the block takes the late member only" do
      security = NewsFixtures.security!()
      rated = domain()
      other = domain()
      rate!(rated, :secondary)
      title = "Quay Harbour wins the canal tender"

      first = item!(:aggregator, other, security: security, title: title, at: 0)
      cluster!(security)

      {:ok, _note} =
        News.append_note_from_story(
          @agent,
          %{"security_id" => security.id, "author" => "agent", "body" => "Synthetic."},
          story_of(first).id
        )

      assert %Item{status: :promoted} = reload(first)

      # A later fetch adds a member of a better tier: it represents the story.
      late = item!(:aggregator, rated, security: security, title: title, at: 60)
      cluster!(security)
      story = story_of(first)
      assert story.id == story_of(late).id
      assert story.representative_item_id == late.id

      rate!(rated, :blocked)

      assert reload(late) == nil
      assert %Item{status: :promoted, tier: :awareness} = reload(first)
      assert Repo.get!(Cluster, story.id).representative_item_id == first.id
      assert_story_whole!(story.id)
    end
  end

  # (b) A domain row that covers another domain's items wrongly.
  describe "(b) a row decides exactly the items the ingest's lookup gives it" do
    test "look-alikes, a suffix of another domain and a label prefix are not covered" do
      d = domain()
      base = String.trim_trailing(d, ".example")

      covered = [d, "x.#{d}", "deep.x.#{d}", "www.#{d}", "www.www.#{d}"]

      outside = [
        "evil-#{d}",
        "x#{d}",
        "#{d}.evil.net",
        "#{base}.example.evil.net",
        "#{base}-example",
        "#{base}.examplex"
      ]

      items =
        Map.new(covered ++ outside, fn dom -> {dom, item!(:aggregator, dom, title: dom)} end)

      rate!(d, :secondary)

      for dom <- covered, do: assert(%Item{tier: :secondary} = reload(items[dom]), dom)
      for dom <- outside, do: assert(%Item{tier: :awareness} = reload(items[dom]), dom)
      assert counts(d)["items_rerated"] == length(covered)
      assert_follows_table!(Map.values(items))

      rate!(d, :blocked)

      for dom <- covered, do: assert(reload(items[dom]) == nil, dom)
      for dom <- outside, do: assert(%Item{tier: :awareness} = reload(items[dom]), dom)
      assert counts(d)["items_removed"] == length(covered)
    end

    test "case, whitespace, a trailing dot and www. name the same row and the same items" do
      d = domain()
      items = [item!(:aggregator, d, title: "a"), item!(:aggregator, "news.#{d}", title: "b")]
      rate!(d, :awareness)

      assert {:ok, %Source{domain: ^d, tier: :secondary}} =
               Sources.put_source(@agent, "  WWW.#{String.upcase(d)}.  ", :secondary)

      assert Repo.aggregate(from(s in Source, where: s.domain == ^d), :count) == 1
      for item <- items, do: assert(%Item{tier: :secondary} = reload(item))
      assert counts(d)["items_rerated"] == 2
    end

    test "a row stored as www.<domain> (from www.www.) decides what the lookup gives it" do
      d = domain()
      under_www = "www.#{d}"

      items =
        for dom <- [d, under_www, "www.www.#{d}", "a.www.#{d}"],
            do: item!(:aggregator, dom, title: dom)

      assert {:ok, %Source{domain: ^under_www}} =
               Sources.put_source(@agent, "www.www.#{d}", :secondary)

      assert_follows_table!(items)

      rate!("www.www.#{d}", :blocked)
      assert_follows_table!(items)
      # The lookup reads www.<d> as <d>, which no row rates: kept, unrated.
      assert %Item{tier: :awareness} = reload(Enum.at(items, 1))
      assert reload(Enum.at(items, 2)) == nil
      assert reload(Enum.at(items, 3)) == nil
    end

    test "an IDN is refused as a row; its punycode form decides its punycode items" do
      n = n()

      assert {:error, changeset} = Sources.put_source(@agent, "bücher-#{n}.example", :blocked)
      assert %{domain: [_ | _]} = errors_on(changeset)

      puny = "xn--bcher-#{n}-kva.example"
      item = item!(:aggregator, "news.#{puny}", title: "puny")
      unrelated = item!(:aggregator, "news.bcher-#{n}-kva.example", title: "ascii")
      rate!(puny, :blocked)
      assert reload(item) == nil
      assert %Item{tier: :awareness} = reload(unrelated)
    end

    test "a two-label public-suffix-like row covers every domain under it (§3 has no suffix list)" do
      suffix = "co.uk-#{n()}"

      items =
        for dom <- ["bank.#{suffix}", "news.shop.#{suffix}"], do: item!(:aggregator, dom, [])

      rate!(suffix, :secondary)
      for item <- items, do: assert(%Item{tier: :secondary} = reload(item))
      assert_follows_table!(items)
    end
  end

  # (e) A rating that changes nothing but set_by, or nothing at all.
  describe "(e) a write that leaves the tier re-rates nothing" do
    test "the same write twice writes once; a tier that leaves every item's tier counts zero" do
      d = domain()
      security = NewsFixtures.security!()
      aggregator = item!(:aggregator, d, title: "wrap")
      issuer = item!(:issuer, "ir.#{d}", security: security, title: "results")

      rate!(d, :secondary)
      assert counts(d)["items_rerated"] == 1
      written = length(entries(d))

      # The same write: nothing written, nothing journaled, nothing re-rated.
      assert {:ok, %Source{tier: :secondary}} = Sources.put_source(@agent, d, :secondary)
      assert length(entries(d)) == written

      # secondary -> primary: B5 caps the aggregator item at secondary and the
      # issuer item is primary already; the row changes, no item does.
      before = Enum.map([aggregator, issuer], &reload/1)
      rate!(d, :primary)
      assert Enum.map([aggregator, issuer], &reload/1) == before

      assert counts(d) == %{
               "items_rerated" => 0,
               "items_removed" => 0,
               "items_kept_promoted" => 0
             }
    end

    test "a first rating of awareness, the tier the items were stored with, counts zero" do
      d = domain()
      item = item!(:aggregator, "x.#{d}", title: "wrap")
      before = reload(item)
      rate!(d, :awareness)
      assert reload(item) == before
      assert counts(d)["items_rerated"] == 0
    end
  end

  # (f) The retry path: an item that moves between the rating's first read
  # and its locks makes the write run again, at most three times, then 422.
  # The move is made inside the rating's own transaction, right after it
  # took the matcher's lock (its telemetry event), so the rollback of each
  # attempt undoes it and the next attempt meets it anew, as three
  # assignments landing in the window would.
  describe "(f) the retry path" do
    defp move_after_matcher_lock(item_id, moves) do
      test = self()
      handler = "retier-attack-move-#{n()}"
      langs = Enum.take(~w(de fr it nl), moves)
      {:ok, agent} = Agent.start_link(fn -> {langs, 0} end)

      :ok =
        :telemetry.attach(
          handler,
          [:portfolixir, :repo, :query],
          fn _event, _measurements, metadata, _config ->
            if self() == test and is_binary(metadata[:query]) and
                 String.contains?(metadata[:query], "/* news matcher */") do
              case Agent.get_and_update(agent, fn
                     {[lang | rest], seen} -> {lang, {rest, seen + 1}}
                     {[], seen} -> {nil, {[], seen + 1}}
                   end) do
                nil ->
                  :ok

                lang ->
                  Repo.update_all(from(i in Item, where: i.id == ^item_id),
                    set: [language: lang]
                  )
              end
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler) end)

      fn ->
        :telemetry.detach(handler)
        Agent.get(agent, fn {_rest, seen} -> seen end)
      end
    end

    test "three moves: the write is refused naming domain, and nothing of it is left" do
      d = domain()
      rate!(d, :secondary)
      security = NewsFixtures.security!()
      # Assigned, in no story yet: its language can change without a story.
      item = item!(:aggregator, d, security: security, title: "moving wrap")
      written = length(entries(d))

      attempts = move_after_matcher_lock(item.id, 3)

      assert {:error, changeset} = Sources.put_source(@agent, d, :awareness)
      assert attempts.() == 3
      assert %{domain: [message]} = errors_on(changeset)
      assert message =~ "send it again"

      assert %Source{tier: :secondary} = Repo.get_by!(Source, domain: d)
      assert length(entries(d)) == written
      assert %Item{tier: :secondary, language: "en"} = reload(item)
    end

    test "two moves: the third attempt writes, and re-rates the item where it is" do
      d = domain()
      rate!(d, :secondary)
      security = NewsFixtures.security!()
      item = item!(:aggregator, d, security: security, title: "moving wrap")

      attempts = move_after_matcher_lock(item.id, 2)

      assert {:ok, %Source{tier: :awareness}} = Sources.put_source(@agent, d, :awareness)
      assert attempts.() == 3
      assert %Item{tier: :awareness} = reload(item)
      assert counts(d)["items_rerated"] == 1
    end

    test "a refused first rating leaves no row behind" do
      d = domain()
      security = NewsFixtures.security!()
      item = item!(:aggregator, d, security: security, title: "moving wrap")

      attempts = move_after_matcher_lock(item.id, 3)

      assert {:error, _changeset} = Sources.put_source(@agent, d, :secondary)
      assert attempts.() == 3
      assert Repo.get_by(Source, domain: d) == nil
      assert %Item{tier: :awareness} = reload(item)
    end
  end

  # (g) Removing items through Stories.remove/5: no story without a
  # representative, no label or assignment left pointing nowhere.
  describe "(g) a block's removals leave every story whole" do
    # Three titles of nine shared words: A and B, and B and C, are alike
    # (Jaccard 10/11 and 10/12), A and C are not (9/12), so B holds the
    # story together.
    @shared "alpha bravo charlie delta echo foxtrot golf hotel india"
    @a @shared <> " kilo"
    @b @shared <> " kilo lima"
    @c @shared <> " lima mike"

    test "a blocked item that held a story together splits it; each part is whole" do
      security = NewsFixtures.security!()
      blocked = domain()
      other = domain()
      rate!(blocked, :secondary)

      a = item!(:aggregator, other, security: security, title: @a, at: 0)
      b = item!(:aggregator, blocked, security: security, title: @b, at: 60)
      c = item!(:aggregator, other, security: security, title: @c, at: 120)
      cluster!(security)

      story = story_of(a)
      assert Enum.map(members(story.id), & &1.id) == Enum.sort([a.id, b.id, c.id])
      assert story.representative_item_id == b.id
      label = NewsFixtures.label!(story.id)

      rate!(blocked, :blocked)

      assert reload(b) == nil
      assert counts(blocked)["items_removed"] == 1
      parts = Enum.uniq([reload(a).cluster_id, reload(c).cluster_id])
      assert length(parts) == 2
      for part <- parts, do: assert_story_whole!(part)
      # D4's recorded limit: the label stays with the part that keeps the id.
      assert story.id in parts
      assert %Label{cluster_id: cluster_id} = Repo.get!(Label, label.id)
      assert cluster_id == story.id
    end

    test "a thematic story of a category: its blocked representative leaves, the story stays whole" do
      category = NewsFixtures.category!()
      blocked = domain()
      other = domain()
      rate!(blocked, :secondary)
      title = "Water week opens in the harbour"

      kept = item!(:thematic, other, category: category, title: title, at: 0)
      lost = item!(:thematic, blocked, category: category, title: title, at: 60)
      {:ok, _} = Stories.recluster({:category, category.id}, "en", DateTime.utc_now(), full: true)
      story = story_of(kept)
      assert story.representative_item_id == lost.id

      rate!(blocked, :blocked)

      assert reload(lost) == nil
      assert story_of(kept).id == story.id
      assert_story_whole!(story.id)
    end

    test "unassigned and ambiguous items of a blocked domain are deleted; no story is touched" do
      blocked = domain()
      rate!(blocked, :secondary)
      s1 = NewsFixtures.security!("Ambig One Quay AG")
      s2 = NewsFixtures.security!("Ambig Two Quay AG")
      open = item!(:aggregator, blocked, title: "open wrap")
      ambiguous = item!(:aggregator, "x.#{blocked}", title: "ambiguous wrap")

      Repo.update_all(from(i in Item, where: i.id == ^ambiguous.id),
        set: [assignment: :ambiguous, candidates: [s1.id, s2.id]]
      )

      stories = Repo.aggregate(Cluster, :count)
      rate!(blocked, :blocked)
      assert reload(open) == nil
      assert reload(ambiguous) == nil
      assert counts(blocked)["items_removed"] == 2
      assert Repo.aggregate(Cluster, :count) == stories
    end
  end
end

defmodule Portfolixir.LockRace.NewsRetierAttackTest do
  # Sprint 29 plan D-8 item 5: the attack lens's races on N1 (#1444;
  # ADR-0056 E1 "Order"; `Portfolixir.LockTable`, rows 22 and 23), on two
  # real connections by the lock-order harness (#996): a block against a
  # fetch of a subdomain, two overlapping ratings in the order the order
  # tests leave out, two domains whose tier keys collide, a security merge,
  # retention, and a promotion of a story a block empties. A deadlock, a
  # writer that never waits and a writer that raises each fail the race.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name and host is synthetic.
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle
  alias Portfolixir.LockRace
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Retention
  alias Portfolixir.News.Source
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @moduletag :lock_race

  setup_all do
    %{db: LockRace.database!()}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  defp agent, do: Actor.api_token_rw("synthetic-agent")
  defp n, do: System.unique_integer([:positive])
  defp domain, do: "atk-race-#{n()}.example"

  defp rate!(domain, tier), do: {:ok, %Source{}} = Sources.put_source(agent(), domain, tier)

  defp feed!(attrs) do
    {:ok, feed} = Repo.transaction(fn -> NewsFixtures.feed!(attrs) end)
    feed
  end

  defp parsed(domain, title \\ nil) do
    n = n()

    %Parsed{
      title: title || "A synthetic market wrap #{n}",
      link: "https://search.example.com/r?u=atk-#{n}",
      source_domain: domain
    }
  end

  defp fetch!(domain) do
    feed = feed!(%{class: "aggregator"})
    {:ok, %{stored: 1}} = Ingest.ingest(feed, [parsed(domain)], DateTime.utc_now())
    Repo.get_by!(Item, feed_id: feed.id)
  end

  # A story of `security` of one aggregator item of `domain`, first seen
  # `ago` seconds before now, stored with the tier its domain has now.
  defp story!(security, domain, ago \\ 3600) do
    feed = feed!(%{class: "aggregator"})
    title = "Synthetic Quay wins a harbour tender #{n()}"
    link = "https://#{domain}/r-#{n()}"
    at = DateTime.add(DateTime.utc_now(), -ago, :second)

    item =
      %Item{}
      |> Item.changeset(
        Map.merge(Stories.title_keys(title), %{
          feed_id: feed.id,
          class: :aggregator,
          security_id: security.id,
          assignment: :assigned,
          first_seen_at: at,
          published_at_claimed: at,
          title: title,
          canonical_url: link,
          domain: domain,
          tier: Sources.tier_for(domain, :aggregator),
          language: "en",
          content_hash: :sha256 |> :crypto.hash(link) |> Base.encode16(case: :lower)
        })
      )
      |> Repo.insert!()

    {:ok, _} = Stories.recluster({:security, security.id}, "en", DateTime.utc_now(), full: true)
    item = Repo.get!(Item, item.id)
    {item, Repo.get!(Cluster, item.cluster_id)}
  end

  defp counts(domain) do
    %Source{id: id} = Repo.get_by!(Source, domain: domain)
    [entry | _] = Journal.list_entries(resource_type: "news_source", resource_id: to_string(id))
    Map.take(entry.after, ~w(items_rerated items_removed items_kept_promoted))
  end

  defp rating_lock?(%{query: query}) when is_binary(query), do: query =~ "news tier: rating"
  defp rating_lock?(_metadata), do: false

  # The fetch's shared tier lock of `domain` itself. A fetch of a
  # subdomain's item takes one key per suffix, one query each, in ascending
  # key order (`Sources.lock_ingest/1`), so its first lock query may be the
  # subdomain's key: paused there, it does not yet hold the key a rating of
  # `domain` asks for. Paused after this one, it does.
  defp ingest_lock_of?(domain) do
    key = :erlang.phash2(domain)

    fn
      %{query: query, params: [_tier_lock, ^key]} when is_binary(query) ->
        query =~ "news tier: ingest"

      _metadata ->
        false
    end
  end

  defp item_lock?(%{query: query}) when is_binary(query),
    do: query =~ ~s(FROM "news_items") and query =~ "FOR UPDATE"

  defp item_lock?(_metadata), do: false

  defp securities_lock?(%{source: "securities", query: query}) when is_binary(query),
    do: query =~ "FOR UPDATE"

  defp securities_lock?(_metadata), do: false

  # (c) A block racing a fetch, the fetch's item on a subdomain of the row.
  describe "(c) a block and a fetch of a subdomain" do
    test "the block holding its lock: the fetch waits, then drops the item as blocked",
         %{db: db} do
      rated = domain()
      rate!(rated, :secondary)
      feed = feed!(%{class: "aggregator"})

      {rating, fetched} =
        LockRace.race!(
          db,
          {fn -> Sources.put_source(agent(), rated, :blocked) end, &rating_lock?/1},
          fn -> Ingest.ingest(feed, [parsed("www.markets." <> rated)], DateTime.utc_now()) end
        )

      assert {:ok, %Source{tier: :blocked}} = rating
      assert {:ok, %{stored: 0, dropped_blocked: 1}} = fetched
      assert Repo.all(from(i in Item, where: i.feed_id == ^feed.id)) == []
    end

    test "the fetch holding its lock: the block waits, then removes what it stored",
         %{db: db} do
      rated = domain()
      rate!(rated, :secondary)
      feed = feed!(%{class: "aggregator"})

      {fetched, rating} =
        LockRace.race!(
          db,
          {fn -> Ingest.ingest(feed, [parsed("markets." <> rated)], DateTime.utc_now()) end,
           ingest_lock_of?(rated)},
          fn -> Sources.put_source(agent(), rated, :blocked) end
        )

      assert {:ok, %{stored: 1}} = fetched
      assert {:ok, %Source{tier: :blocked}} = rating
      assert Repo.all(from(i in Item, where: i.feed_id == ^feed.id)) == []
      assert counts(rated)["items_removed"] == 1
    end
  end

  # (d) Two overlapping ratings, the parent's first (the order tests race
  # the child's first), and two unrelated domains whose tier keys collide.
  describe "(d) overlapping ratings and colliding tier keys" do
    test "the parent's downgrade first: the child's rating then takes its own items back",
         %{db: db} do
      parent = domain()
      child = "markets." <> parent
      by_child = fetch!(child)
      by_parent = fetch!(parent)

      {first, second} =
        LockRace.race!(
          db,
          {fn -> Sources.put_source(agent(), parent, :secondary) end, &rating_lock?/1},
          fn -> Sources.put_source(agent(), child, :awareness) end
        )

      assert {:ok, %Source{tier: :secondary}} = first
      assert {:ok, %Source{tier: :awareness}} = second
      assert %Item{tier: :awareness} = Repo.get!(Item, by_child.id)
      assert %Item{tier: :secondary} = Repo.get!(Item, by_parent.id)
    end

    # E1's precision of 2026-11-12 (found by this attack): a block's removal
    # is the block's own. A child row written after it re-rates what is
    # stored, and the removed item is no longer stored; the next fetch that
    # lists it stores it again at the child's tier.
    test "the parent's block first: its removal stands, and the next fetch stores the child's item at the child's tier",
         %{db: db} do
      parent = domain()
      child = "markets." <> parent
      by_child = fetch!(child)
      by_parent = fetch!(parent)

      {first, second} =
        LockRace.race!(
          db,
          {fn -> Sources.put_source(agent(), parent, :blocked) end, &rating_lock?/1},
          fn -> Sources.put_source(agent(), child, :secondary) end
        )

      assert {:ok, %Source{tier: :blocked}} = first
      assert {:ok, %Source{tier: :secondary}} = second
      assert Repo.get(Item, by_parent.id) == nil
      assert Repo.get(Item, by_child.id) == nil

      assert %Item{tier: :secondary, domain: ^child} = fetch!(child)
    end

    # clash-3422.example and clash-26552.example share :erlang.phash2/1,
    # the tier key (`Sources`, `tier_key/1`): found by a search, fixed here.
    test "colliding tier keys: an unrelated fetch waits for the rating and reads its own tier",
         %{db: db} do
      {a, b} = {"clash-3422.example", "clash-26552.example"}
      assert :erlang.phash2(a) == :erlang.phash2(b)
      rate!(a, :secondary)
      rate!(b, :awareness)
      feed = feed!(%{class: "aggregator"})

      {rating, fetched} =
        LockRace.race!(
          db,
          {fn -> Sources.put_source(agent(), a, :blocked) end, &rating_lock?/1},
          fn -> Ingest.ingest(feed, [parsed(b)], DateTime.utc_now()) end
        )

      assert {:ok, %Source{tier: :blocked}} = rating
      assert {:ok, %{stored: 1}} = fetched
      assert %Item{tier: :awareness, domain: ^b} = Repo.get_by!(Item, feed_id: feed.id)

      # And two ratings of them: one waits for the other, each re-rates its own.
      {first, second} =
        LockRace.race!(
          db,
          {fn -> Sources.put_source(agent(), b, :secondary) end, &rating_lock?/1},
          fn -> Sources.put_source(agent(), a, :awareness) end
        )

      assert {:ok, %Source{tier: :secondary}} = first
      assert {:ok, %Source{tier: :awareness}} = second
      assert %Item{tier: :secondary} = Repo.get_by!(Item, feed_id: feed.id)
      assert counts(b)["items_rerated"] == 1
      assert counts(a)["items_rerated"] == 0
    end
  end

  # (h) A rating against a security merge and against retention.
  defp watched!(name, token) do
    security = WorldFixtures.create_security!(name: name, ticker: nil, asset_class: "equity")

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_watch: true,
        news_aliases: [%{token: token, context: [], case: "insensitive"}]
      })

    security
  end

  defp merge_world(name, rated) do
    n = n()
    source = watched!("#{name} AG", "Sourcetoken#{n}")
    target = watched!("#{name} AG", "Targettoken#{n}")
    feed = feed!(%{class: "aggregator"})
    parsed = parsed(rated, "Sourcetoken#{n} reports third quarter results")
    {:ok, %{stored: 1}} = Ingest.ingest(feed, [parsed], DateTime.utc_now())
    item = Repo.get_by!(Item, feed_id: feed.id)
    assert %Item{assignment: :assigned, security_id: source_id} = item
    assert source_id == source.id
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)
    %{source: source, target: target, item: item, digest: preview.plan_digest}
  end

  defp merge(w) do
    Lifecycle.merge_security(agent(), w.source.id, w.target.id, %{
      plan_digest: w.digest,
      collapse_key_equal: false
    })
  end

  describe "(h) a rating and a security merge" do
    test "the rating holding the item: the merge waits, then moves the re-rated item",
         %{db: db} do
      rated = domain()
      rate!(rated, :secondary)
      w = merge_world("Retier First Harbour", rated)

      {rating, merged} =
        LockRace.race!(
          db,
          {fn -> Sources.put_source(agent(), rated, :awareness) end, &item_lock?/1},
          fn -> merge(w) end
        )

      assert {:ok, %Source{tier: :awareness}} = rating
      assert {:ok, _record, :applied} = merged

      assert %Item{tier: :awareness, security_id: target_id} = Repo.get!(Item, w.item.id)
      assert target_id == w.target.id
    end

    test "the merge holding the securities: the rating waits, runs again, re-rates the item",
         %{db: db} do
      rated = domain()
      rate!(rated, :secondary)
      w = merge_world("Merge First Quay", rated)

      {merged, rating} =
        LockRace.race!(
          db,
          {fn -> merge(w) end, &securities_lock?/1},
          fn -> Sources.put_source(agent(), rated, :awareness) end
        )

      assert {:ok, _record, :applied} = merged
      assert {:ok, %Source{tier: :awareness}} = rating
      assert %Item{tier: :awareness, security_id: target_id} = Repo.get!(Item, w.item.id)
      assert target_id == w.target.id
      assert counts(rated)["items_rerated"] == 1
    end
  end

  describe "(h) a rating and retention" do
    test "retention holding the scope: the rating waits and counts what is left", %{db: db} do
      rated = domain()
      rate!(rated, :secondary)
      security = WorldFixtures.create_security!(name: "Retention First Quay AG", ticker: nil)
      {old, story} = story!(security, rated, 100 * 86_400)

      {retained, rating} =
        LockRace.race!(
          db,
          {fn -> Retention.run(DateTime.utc_now()) end, &LockRace.lock?/1},
          fn -> Sources.put_source(agent(), rated, :awareness) end
        )

      assert {:ok, %{items: removed}} = retained
      assert removed >= 1
      assert {:ok, %Source{tier: :awareness}} = rating
      assert Repo.get(Item, old.id) == nil
      assert Repo.get(Cluster, story.id) == nil
      assert counts(rated)["items_rerated"] == 0
    end

    test "the rating holding the item: retention waits, then removes the re-rated item",
         %{db: db} do
      rated = domain()
      rate!(rated, :secondary)
      security = WorldFixtures.create_security!(name: "Rating First Quay AG", ticker: nil)
      {old, story} = story!(security, rated, 100 * 86_400)

      {rating, retained} =
        LockRace.race!(
          db,
          {fn -> Sources.put_source(agent(), rated, :awareness) end, &item_lock?/1},
          fn -> Retention.run(DateTime.utc_now()) end
        )

      assert {:ok, %Source{tier: :awareness}} = rating
      assert {:ok, %{items: removed}} = retained
      assert removed >= 1
      assert Repo.get(Item, old.id) == nil
      assert Repo.get(Cluster, story.id) == nil
      assert counts(rated)["items_rerated"] == 1
    end
  end

  # (g) with (h): a promotion of a story that a block empties meanwhile.
  describe "(g) a block emptying a story while it is promoted" do
    test "the block first: the promotion answers an error, no note names a removed item",
         %{db: db} do
      rated = domain()
      rate!(rated, :secondary)
      security = WorldFixtures.create_security!(name: "Emptied Story Quay AG", ticker: nil)
      {member, story} = story!(security, rated)

      {rating, promoted} =
        LockRace.race!(
          db,
          {fn -> Sources.put_source(agent(), rated, :blocked) end, &item_lock?/1},
          fn ->
            News.append_note_from_story(
              agent(),
              %{"security_id" => security.id, "author" => "agent", "body" => "Synthetic."},
              story.id
            )
          end
        )

      assert {:ok, %Source{tier: :blocked}} = rating
      assert {:error, _reason} = promoted
      assert Repo.get(Item, member.id) == nil
      assert Repo.get(Cluster, story.id) == nil
    end
  end
end
