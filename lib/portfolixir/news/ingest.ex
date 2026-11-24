defmodule Portfolixir.News.Ingest do
  @moduledoc """
  What the fetcher stores of one feed's parsed answer (ADR-0056 §2, §4, A3,
  B4, B7). `ingest/3` takes the feed, the parser's items
  (`Portfolixir.News.Parser.Item`, already plain text by
  `Portfolixir.News.Text`, so nothing is cleaned twice) and the server's
  clock, and, in the feed's own order:

    1. **skips an item without a title or a link** (`incomplete`, returned,
       not stored, not counted in a day row: it has nothing to show or key),
       a title of only invisible characters and whitespace counting as none
       (closing act, EDGE5);
    2. **takes the domain**: for an `aggregator` item the `<source>` domain,
       else the item is dropped and counted `dropped_no_source` and no
       redirect is followed (§2); for every other class the link's host,
       else the feed's host. A domain that has not a domain's shape
       (`Portfolixir.News.Shapes.domain?/1`: at most 253 bytes, its labels
       letters, digits and hyphens) is refused here, before anything is
       derived from it, and counted `invalid`, as the item's own check
       would refuse it (N-11);
    3. **drops a claim older than the retention window** (90 days before
       the clock), counted `dropped_old` (B4), so a feed that keeps listing
       old items does not refill what retention removed; an item retention
       removed from this feed in the last 90 days (a tombstone of its
       canonical URL, `Portfolixir.News.Retention`) is dropped the same way,
       dated or not (closing act, COR2);
    4. **keys the item by its canonical URL** (`canonical_url/1`): a URL the
       feed already stored, one an item a deleted feed of the same class and
       binding left detached holds (a feed deleted and registered again,
       #1356: the identity is the binding and the link, never the feed's
       row), or one repeated in the same answer, is `known` and neither
       stored nor counted again;
    5. **drops an item of a `blocked` domain** (§3), counted
       `dropped_blocked`, before the cap, so it takes no room: the tier
       table is read once for the whole answer, without a lock;
    6. **caps the feed at 200 items in 24 hours** (A3): the rolling count of
       the feed's items by `first_seen_at`, read under the feed's row lock,
       leaves room for the first items in the feed's order; the rest are
       counted `dropped_cap`. This is the one order that decides (B3), and
       it belongs to the feed that floods. **And at `tier_keys_max/0` tier
       locks an answer** (512, N-11): the items are admitted in the same
       order only while the tier locks of their domains (below; one per
       suffix of a domain) fit that number; the rest is counted
       `dropped_cap` as well and, the day's room allowing, stored by the
       next fetch that lists it. An answer of ordinary sources never
       reaches it: 200 items of 200 unrelated three-label domains take 400;
    7. **rates each admitted item by the tier table** (§3, B5;
       `Portfolixir.News.Sources`, read again for what was admitted, under
       its domains' tier locks held until the items commit, so a rating
       written meanwhile either waits for them and re-rates them or is read
       here as written, ADR-0056 E1): an `issuer`
       or `regulatory` item is `primary` by construction, any other is its
       domain's tier (or a parent domain's), at most `secondary`, and
       `awareness` when unrated; an item a rating blocked since step 5 is
       dropped and counted `dropped_blocked`, its room left unused;
    8. **stores** each item, in its own savepoint (a row the database
       refuses is counted `invalid` and costs no other item), with `first_seen_at` the clock and
       `published_at` the claim clamped to it (`News.Item.changeset/2`, B4),
       and the title keys the clustering reads (`title_words`,
       `title_norm_hash`: `Portfolixir.News.Stories.title_keys/1`, the one
       source of both): an `issuer` or `regulatory` item `assigned` to its
       feed's security, a `thematic` one `assigned` to its feed's category,
       an `aggregator` one `unassigned` with no candidates.

  The whole batch runs under the feed's row lock, taken after the feed's
  security or category is held `FOR KEY SHARE`, on the feed as read under
  that lock (#1457; `Portfolixir.LockTable`, row 23): a security merge that
  commits while a fetch waits has the fetch store its items on the target.

  The day's counters go to `news_feed_days` (the server's day of the
  clock); a dropped item counts there once per feed, canonical URL, reason
  and server day, however often it is fetched (`news_feed_drops`, closing
  act COR4), while the fetch's summary reports every drop of its answer. Items and day rows are a staging area, not journaled (B7,
  `Portfolixir.Journal.Allowlist`); the fetcher that calls this is the
  registered system job.

  **After the insert commits:**

    * the stored `aggregator` items are matched against the universe
      (`Portfolixir.News.assign_aggregator_items/2`, §2): one security named
      `assigned`, none `unassigned`, several `ambiguous` with the
      candidates; the matcher folds the items it assigns into their stories;
    * the items bound by construction are folded into the stories of their
      security (or category) and language
      (`Portfolixir.News.Stories.recluster/4`, B3), each scope once.

  Either step failing leaves the items stored and in no story; the next
  recluster of their scope reads them as seeds.
  """

  import Ecto.Query

  require Logger

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Clock
  alias Portfolixir.News
  alias Portfolixir.News.Feed
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Shapes
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.Repo

  @cap 200
  @cap_window_seconds 24 * 60 * 60
  # The most tier locks one answer's items take (`admit/4`).
  @tier_keys_max 512
  @retention_days 90
  # How often a fetch locks its feed again when the feed's parent changed
  # between the two locks (`under_feed_lock/3`).
  @lock_attempts 3
  # Query parameters that track a reader and name no document.
  @tracking_params ~w(fbclid gclid dclid msclkid mc_cid mc_eid igshid)
  @default_ports %{"https" => 443, "http" => 80}

  @type summary :: %{
          stored: non_neg_integer(),
          known: non_neg_integer(),
          incomplete: non_neg_integer(),
          dropped_cap: non_neg_integer(),
          dropped_no_source: non_neg_integer(),
          dropped_old: non_neg_integer(),
          dropped_blocked: non_neg_integer(),
          invalid: non_neg_integer(),
          items: [Item.t()]
        }

  @doc "The most items a feed stores in 24 hours (A3)."
  @spec cap() :: pos_integer()
  def cap, do: @cap

  @doc """
  The most tier locks one answer takes (`Portfolixir.News.Sources.lock_ingest/1`):
  its items are admitted in the feed's order while their domains' locks fit.
  """
  @spec tier_keys_max() :: pos_integer()
  def tier_keys_max, do: @tier_keys_max

  @doc "The retention window in days: an older claim is not stored (B4, §12)."
  @spec retention_days() :: pos_integer()
  def retention_days, do: @retention_days

  @doc """
  Stores what is new in `items` for `feed` at the server's clock `now`; see
  the moduledoc. `{:ok, summary}`, the stored rows in `summary.items`.
  """
  @spec ingest(Feed.t(), [Parsed.t()], DateTime.t()) :: {:ok, summary()}
  def ingest(%Feed{} = feed, items, %DateTime{} = now) when is_list(items) do
    summary =
      under_feed_lock(feed, @lock_attempts, fn feed ->
        {candidates, summary} = prepare(feed, items, now)
        {candidates, summary} = drop_blocked(candidates, summary)
        {candidates, summary} = admit(feed, candidates, now, summary)
        {candidates, summary} = tier_and_block(candidates, summary)
        {stored, summary} = store(candidates, now, summary)

        count_day(feed, now, summary)
        summary |> Map.delete(:drops) |> Map.put(:items, stored)
      end)

    stored = summary.items
    assign_aggregator(stored, now)
    cluster(stored, now)

    {:ok, summary}
  end

  # One ingest per feed at a time: the cap's count and the inserts must not
  # interleave with another fetch of the same feed, so the feed's row is
  # held `FOR UPDATE` to the commit. **Its parent first** (#1457;
  # `Portfolixir.LockTable`, row 23): the security (or category) the feed
  # names, `FOR KEY SHARE`, the lock the items' foreign key takes, before
  # the feed, as every news writer takes the securities before any news
  # row. A security merge holds both securities `FOR UPDATE` and then asks
  # the source's feeds (row 13), and a category's delete holds the category
  # and then checks the feeds that name it, so a fetch that held its feed
  # first and then inserted closed a cycle with either. `fun` runs on the
  # feed as read under its lock, never on the caller's earlier read: a
  # merge that committed while the fetch waited has moved the feed to its
  # target, and its items are stored there. A feed whose parent changed
  # between the lock on the parent and the lock on the feed is not locked
  # out of order: the attempt is rolled back, releasing both, and runs
  # again on the parent the feed names now.
  defp under_feed_lock(%Feed{} = feed, 0, _fun),
    do: raise("news feed #{feed.id} was rebound #{@lock_attempts} times during one fetch")

  defp under_feed_lock(%Feed{} = feed, attempts, fun) do
    result =
      Repo.transaction(fn ->
        lock_parent(feed)

        locked = Repo.one!(from(f in Feed, where: f.id == ^feed.id, lock: "FOR UPDATE"))

        if parent(locked) == parent(feed),
          do: fun.(locked),
          else: Repo.rollback({:rebound, locked})
      end)

    case result do
      {:ok, summary} -> summary
      {:error, {:rebound, locked}} -> under_feed_lock(locked, attempts - 1, fun)
    end
  end

  defp parent(%Feed{security_id: id}) when is_integer(id), do: {:security, id}
  defp parent(%Feed{category_id: id}) when is_integer(id), do: {:category, id}
  defp parent(%Feed{}), do: nil

  defp lock_parent(feed) do
    case parent(feed) do
      {:security, id} -> key_share(from(s in Security, where: s.id == ^id, select: s.id))
      {:category, id} -> key_share(from(c in Category, where: c.id == ^id, select: c.id))
      nil -> []
    end
  end

  defp key_share(query), do: query |> lock("FOR KEY SHARE") |> Repo.all()

  # §3: a `blocked` domain's candidates are dropped and counted
  # `dropped_blocked`, before the cap, so a blocked item takes no room. The
  # tier table is read once for the whole answer and without a lock: what
  # is stored is rated again under its tier locks (`tier_and_block/2`), and
  # an item a rating unblocked this instant is stored by the next fetch.
  defp drop_blocked([], summary), do: {[], summary}

  defp drop_blocked(candidates, summary) do
    rated = candidates |> Enum.map(& &1.domain) |> Enum.uniq() |> Sources.lookup()

    {open, blocked} =
      Enum.split_with(
        candidates,
        &(Sources.tier(&1.class, Map.get(rated, &1.domain)) != :blocked)
      )

    {open, drop(summary, :dropped_blocked, Enum.map(blocked, & &1.canonical_url))}
  end

  # A3 and N-11: the candidates that are stored, in the feed's own order:
  # as many as the feed's 200 in 24 hours leave room for, and only while
  # the tier locks of their domains fit `@tier_keys_max`. The rest counts
  # `dropped_cap`. So the locks one answer takes, and with them the tier
  # read under them, are bounded by numbers the server chooses, whatever
  # the answer names.
  defp admit(_feed, [], _now, summary), do: {[], summary}

  defp admit(feed, candidates, now, summary) do
    room = max(@cap - stored_in_window(feed, now), 0)

    {count, _keys} =
      Enum.reduce_while(candidates, {0, MapSet.new()}, fn candidate, {count, keys} ->
        keys = if count < room, do: MapSet.union(keys, tier_keys(candidate)), else: keys

        if count < room and MapSet.size(keys) <= @tier_keys_max,
          do: {:cont, {count + 1, keys}},
          else: {:halt, {count, keys}}
      end)

    {admitted, capped} = Enum.split(candidates, count)
    {admitted, drop(summary, :dropped_cap, Enum.map(capped, & &1.canonical_url))}
  end

  defp tier_keys(candidate), do: candidate.domain |> Sources.tier_keys() |> MapSet.new()

  # §3, B5: each admitted candidate's tier from the tier table, read under
  # the domains' tier locks (E1); a candidate whose domain a rating blocked
  # since `drop_blocked/2` read it is dropped and counted `dropped_blocked`.
  defp tier_and_block([], summary), do: {[], summary}

  defp tier_and_block(candidates, summary) do
    domains = candidates |> Enum.map(& &1.domain) |> Enum.uniq()
    # --- S29 N1 begin ---
    # E1 ("Order"): the tier locks of the domains, shared, held until the
    # items commit, before their tiers are read: a rating of one of them
    # waits for this fetch and re-rates what it stores, and one that holds
    # its lock first is read here as written (`Sources.lock_rating/1`).
    :ok = Sources.lock_ingest(domains)
    # --- S29 N1 end ---
    rated = Sources.lookup(domains)

    {kept, blocked} =
      candidates
      |> Enum.map(&%{&1 | tier: Sources.tier(&1.class, Map.get(rated, &1.domain))})
      |> Enum.split_with(&(&1.tier != :blocked))

    summary = drop(summary, :dropped_blocked, Enum.map(blocked, & &1.canonical_url))
    {kept, summary}
  end

  # §2: the stored `aggregator` items are matched against the universe by
  # the alias grammar, after the insert's commit (the matcher locks the
  # securities it names, then the items, in a transaction of its own;
  # `Portfolixir.LockTable`, row 26). Every
  # other class is bound by construction and skipped by the matcher.
  # The matcher folds the items it assigns into their stories itself.
  defp assign_aggregator(items, now) do
    case for(%Item{class: :aggregator} = item <- items, do: item) do
      [] -> :ok
      aggregator -> {:ok, _counts} = News.assign_aggregator_items(aggregator, now: now)
    end

    :ok
  end

  # B3: the items bound by construction are folded into the stories of their
  # security (or category) and language; an aggregator's are the matcher's
  # (above). A failed recluster leaves the items in no story, and the next
  # recluster of their scope reads them as seeds.
  defp cluster(items, now) do
    items
    |> Enum.filter(&(&1.class != :aggregator and &1.assignment == :assigned))
    |> Enum.map(&{Stories.scope(&1), &1.language})
    |> Enum.uniq()
    |> Enum.each(fn {scope, language} -> recluster(scope, language, now) end)
  end

  defp recluster(scope, language, now) do
    case Stories.recluster(scope, language, now) do
      {:ok, _summary} ->
        :ok

      {:error, changeset} ->
        Logger.warning(
          "news stories of #{inspect(scope)} (#{language}) not written: " <>
            inspect(changeset.errors)
        )
    end
  end

  # -- preparing ---------------------------------------------------------------

  defp prepare(feed, items, now) do
    oldest = DateTime.add(now, -@retention_days, :day)
    feed_host = host(feed.url)

    {kept, summary} =
      Enum.reduce(items, {[], empty_summary()}, fn item, {kept, summary} ->
        case candidate(feed, feed_host, item, oldest) do
          {:ok, attrs} -> {[attrs | kept], summary}
          {:drop, :incomplete} -> {kept, Map.update!(summary, :incomplete, &(&1 + 1))}
          {:drop, :invalid} -> {kept, Map.update!(summary, :invalid, &(&1 + 1))}
          {:drop, counter} -> {kept, drop(summary, counter, [canonical_url(item.link)])}
        end
      end)

    kept = kept |> Enum.reverse() |> Enum.uniq_by(& &1.canonical_url)
    known = known_urls(feed, Enum.map(kept, & &1.canonical_url))
    {fresh, seen} = Enum.split_with(kept, &(not MapSet.member?(known, &1.canonical_url)))

    removed = removed_urls(feed, Enum.map(fresh, & &1.canonical_url))
    {fresh, gone} = Enum.split_with(fresh, &(not MapSet.member?(removed, &1.canonical_url)))

    summary =
      drop(%{summary | known: length(seen)}, :dropped_old, Enum.map(gone, & &1.canonical_url))

    {fresh, summary}
  end

  # COR4: a drop counts in the fetch's summary at once, and in the day's row
  # only once per feed, canonical URL, reason and server day
  # (`count_day/3`, `news_feed_drops`).
  defp drop(summary, counter, urls) do
    summary
    |> Map.update!(counter, &(&1 + length(urls)))
    |> Map.update!(:drops, &(Enum.map(urls, fn url -> {counter, url} end) ++ &1))
  end

  # COR2: the URLs of `urls` that retention removed from this feed in the
  # last 90 days (`news_item_tombstones`), so a dateless item is not stored
  # again as new.
  defp removed_urls(_feed, []), do: MapSet.new()

  defp removed_urls(feed, urls) do
    by_hash = Map.new(urls, &{url_hash(&1), &1})
    hashes = Map.keys(by_hash)

    from(t in "news_item_tombstones",
      where: t.feed_id == ^feed.id and t.url_hash in ^hashes,
      select: t.url_hash
    )
    |> Repo.all()
    |> MapSet.new(&Map.fetch!(by_hash, &1))
  end

  @doc """
  The SHA-256 of a canonical URL in lower-case hex, the key of a
  tombstone (`news_item_tombstones`, closing act COR2).
  """
  @spec url_hash(String.t()) :: String.t()
  def url_hash(url) when is_binary(url), do: sha256(url)

  defp empty_summary do
    %{
      stored: 0,
      known: 0,
      incomplete: 0,
      dropped_cap: 0,
      dropped_no_source: 0,
      dropped_old: 0,
      dropped_blocked: 0,
      invalid: 0,
      items: [],
      drops: []
    }
  end

  defp candidate(_feed, _feed_host, %Parsed{title: title, link: link}, _oldest)
       when is_nil(title) or is_nil(link),
       do: {:drop, :incomplete}

  defp candidate(feed, feed_host, %Parsed{} = item, oldest) do
    with :ok <- visible(item.title),
         {:ok, domain} <- domain(feed, feed_host, item),
         :ok <- shaped(domain),
         :ok <- recent(item.published_at, oldest),
         {:ok, url} <- canonical(item.link) do
      {:ok, attrs(feed, item, domain, url)}
    end
  end

  # Closing act, EDGE5: a title of only format characters (`\\p{Cf}`) and
  # whitespace shows nothing, so the item is `incomplete` like one without a
  # title. A visible title keeps its invisible characters as received.
  defp visible(title) do
    if String.replace(title, ~r/[\p{Cf}\s]/u, "") == "",
      do: {:drop, :incomplete},
      else: :ok
  end

  defp domain(%Feed{class: :aggregator}, _feed_host, %Parsed{source_domain: nil}),
    do: {:drop, :dropped_no_source}

  defp domain(%Feed{class: :aggregator}, _feed_host, %Parsed{source_domain: domain}),
    do: {:ok, domain}

  defp domain(_feed, feed_host, %Parsed{link: link}), do: {:ok, host(link) || feed_host}

  # N-11: a domain is checked for its shape before the tier table, the tier
  # locks or anything else is asked about it. What fails here would fail
  # the item's own check (`News.Item.changeset/2`) and counts as that does.
  defp shaped(domain), do: if(Shapes.domain?(domain), do: :ok, else: {:drop, :invalid})

  defp recent(nil, _oldest), do: :ok

  defp recent(%DateTime{} = claimed, oldest),
    do: if(DateTime.compare(claimed, oldest) == :lt, do: {:drop, :dropped_old}, else: :ok)

  defp canonical(link) do
    case canonical_url(link) do
      nil -> {:drop, :incomplete}
      url -> {:ok, url}
    end
  end

  defp attrs(feed, item, domain, url) do
    excerpt = item.excerpt

    %{
      feed_id: feed.id,
      class: feed.class,
      canonical_url: url,
      domain: domain,
      language: feed.language,
      title: item.title,
      excerpt: excerpt,
      published_at_claimed: item.published_at,
      content_hash: sha256(item.title <> "\n" <> (excerpt || "")),
      candidates: []
    }
    |> Map.merge(Stories.title_keys(item.title))
    |> Map.merge(bound_to(feed))
  end

  # §2: the class decides the binding; the tier here is a placeholder that
  # `tier_and_block/2` replaces from the tier table (issuer and regulatory
  # are primary by construction, B5).
  defp bound_to(%Feed{class: class, security_id: security_id})
       when class in [:issuer, :regulatory],
       do: %{assignment: :assigned, security_id: security_id, tier: :primary}

  defp bound_to(%Feed{class: :thematic, category_id: category_id}),
    do: %{assignment: :assigned, category_id: category_id, tier: :awareness}

  defp bound_to(%Feed{class: :aggregator}), do: %{assignment: :unassigned, tier: :awareness}

  defp known_urls(_feed, []), do: MapSet.new()

  # #1356 (Sprint 30, A2): an item's identity is its feed's class and
  # binding and its link, never the feed's row. A URL is known when this
  # feed stored it, or when an item a deleted feed of the same class and
  # binding left detached (`feed_id` NULL, `Portfolixir.News.delete_feed/2`)
  # holds it: a feed deleted and registered again does not store its items
  # twice. Both read the `(feed_id, canonical_url)` index, the detached
  # rows by `feed_id IS NULL`.
  defp known_urls(feed, urls) do
    own =
      from(i in Item,
        where: i.feed_id == ^feed.id and i.canonical_url in ^urls,
        select: i.canonical_url
      )

    detached =
      from(i in Item,
        where: is_nil(i.feed_id) and i.canonical_url in ^urls and i.class == ^feed.class,
        select: i.canonical_url
      )
      |> same_binding(feed)

    MapSet.new(Repo.all(own) ++ Repo.all(detached))
  end

  # The binding an item of the feed's class takes by construction (§2); an
  # aggregator item has none at ingest, so its class and link are its
  # identity.
  defp same_binding(query, %Feed{class: class, security_id: security_id})
       when class in [:issuer, :regulatory],
       do: where(query, [i], i.security_id == ^security_id)

  defp same_binding(query, %Feed{class: :thematic, category_id: category_id}),
    do: where(query, [i], i.category_id == ^category_id)

  defp same_binding(query, %Feed{class: :aggregator}), do: query

  # -- storing -----------------------------------------------------------------

  defp store(admitted, now, summary) do
    Enum.reduce(admitted, {[], summary}, fn attrs, {stored, summary} ->
      changeset = Item.changeset(%Item{}, Map.put(attrs, :first_seen_at, now))

      case insert_item(changeset) do
        {:ok, %Item{id: nil}} -> {stored, %{summary | known: summary.known + 1}}
        {:ok, item} -> {[item | stored], %{summary | stored: summary.stored + 1}}
        {:error, _reason} -> {stored, %{summary | invalid: summary.invalid + 1}}
      end
    end)
    |> then(fn {stored, summary} -> {Enum.reverse(stored), summary} end)
  end

  # Each item in its own savepoint (closing act, SEC2/EDGE1): a row the
  # database refuses rolls back to it, so the batch's transaction is never
  # aborted and the feed's other items are stored.
  defp insert_item(%Ecto.Changeset{valid?: false} = changeset), do: {:error, changeset}

  defp insert_item(changeset) do
    Repo.insert(changeset,
      on_conflict: :nothing,
      conflict_target: [:feed_id, :canonical_url],
      mode: :savepoint
    )
  rescue
    error in [Ecto.ConstraintError, Postgrex.Error] ->
      Logger.warning("news item refused by the database: #{Exception.message(error)}")
      {:error, :refused}
  end

  defp stored_in_window(feed, now) do
    since = DateTime.add(now, -@cap_window_seconds, :second)

    Repo.aggregate(
      from(i in Item, where: i.feed_id == ^feed.id and i.first_seen_at > ^since),
      :count
    )
  end

  defp count_day(feed, now, summary) do
    new_drops = new_drops(feed, now, summary.drops)

    counts = [
      items_stored: summary.stored,
      dropped_cap: Map.get(new_drops, :dropped_cap, 0),
      dropped_no_source: Map.get(new_drops, :dropped_no_source, 0),
      dropped_old: Map.get(new_drops, :dropped_old, 0),
      dropped_blocked: Map.get(new_drops, :dropped_blocked, 0)
    ]

    add_to_day(feed.id, now, counts)
  end

  @drop_reasons %{
    dropped_cap: "cap",
    dropped_no_source: "no_source",
    dropped_old: "old",
    dropped_blocked: "blocked"
  }
  @drop_counters Map.new(@drop_reasons, fn {counter, reason} -> {reason, counter} end)

  # COR4: records this fetch's drops for the server day and answers, per
  # counter, how many were not recorded yet: only those reach the day row.
  defp new_drops(_feed, _now, []), do: %{}

  defp new_drops(feed, now, drops) do
    day = Clock.local_date(now)

    drops
    |> Enum.map(fn {counter, url} ->
      %{
        feed_id: feed.id,
        url_hash: url_hash(url || ""),
        reason: Map.fetch!(@drop_reasons, counter),
        day: day
      }
    end)
    |> Enum.uniq()
    |> Enum.chunk_every(1_000)
    |> Enum.flat_map(fn rows ->
      {_count, inserted} =
        Repo.insert_all("news_feed_drops", rows,
          on_conflict: :nothing,
          conflict_target: [:feed_id, :url_hash, :reason, :day],
          returning: [:reason]
        )

      inserted
    end)
    |> Enum.frequencies_by(&Map.fetch!(@drop_counters, &1.reason))
  end

  @doc """
  Adds `counts` (a keyword list of `Portfolixir.News.FeedDay` counters) to
  feed `feed_id`'s row for the server's day of `now`, creating it at zero.
  Counts of zero alone write nothing.
  """
  @spec add_to_day(pos_integer(), DateTime.t(), keyword(non_neg_integer())) :: :ok
  def add_to_day(feed_id, %DateTime{} = now, counts) do
    counts = Enum.reject(counts, fn {_counter, n} -> n == 0 end)

    if counts != [] do
      day =
        %FeedDay{}
        |> FeedDay.changeset(Map.merge(%{feed_id: feed_id, day: Clock.local_date(now)}, zeros()))
        |> Ecto.Changeset.change(counts)

      Repo.insert!(day, on_conflict: [inc: counts], conflict_target: [:feed_id, :day])
    end

    :ok
  end

  defp zeros, do: Map.new(FeedDay.counters(), &{&1, 0})

  # -- keys --------------------------------------------------------------------

  @doc """
  An item link's canonical form, the item's key within its feed: scheme
  and host lower-cased, the default port, the fragment, the `utm_*` and
  other click-tracking query parameters removed, the rest kept as given.
  Nil for a link that is not an absolute http or https URL.
  """
  @spec canonical_url(String.t() | nil) :: String.t() | nil
  def canonical_url(link) when is_binary(link) do
    case URI.parse(link) do
      %URI{scheme: scheme, host: host} = uri when is_binary(scheme) and is_binary(host) ->
        scheme = String.downcase(scheme)

        if scheme in ["http", "https"] and host != "" do
          %URI{
            uri
            | scheme: scheme,
              host: String.downcase(host),
              port: canonical_port(scheme, uri.port),
              fragment: nil,
              query: canonical_query(uri.query)
          }
          |> URI.to_string()
        end

      _other ->
        nil
    end
  end

  def canonical_url(_link), do: nil

  defp canonical_port(scheme, port), do: if(@default_ports[scheme] == port, do: nil, else: port)

  defp canonical_query(nil), do: nil

  defp canonical_query(query) do
    query
    |> String.split("&")
    |> Enum.reject(fn pair ->
      name = pair |> String.split("=", parts: 2) |> hd() |> String.downcase()
      name == "" or String.starts_with?(name, "utm_") or name in @tracking_params
    end)
    |> case do
      [] -> nil
      pairs -> Enum.join(pairs, "&")
    end
  end

  defp sha256(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)

  defp host(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> String.downcase(host)
      _other -> nil
    end
  end

  defp host(_url), do: nil
end
