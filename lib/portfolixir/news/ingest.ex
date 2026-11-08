defmodule Portfolixir.News.Ingest do
  @moduledoc """
  What the fetcher stores of one feed's parsed answer (ADR-0056 §2, §4, A3,
  B4, B7). `ingest/3` takes the feed, the parser's items
  (`Portfolixir.News.Parser.Item`, already plain text by
  `Portfolixir.News.Text`, so nothing is cleaned twice) and the server's
  clock, and, in the feed's own order:

    1. **skips an item without a title or a link** (`incomplete`, returned,
       not stored, not counted in a day row: it has nothing to show or key);
    2. **takes the domain**: for an `aggregator` item the `<source>` domain,
       else the item is dropped and counted `dropped_no_source` and no
       redirect is followed (§2); for every other class the link's host,
       else the feed's host;
    3. **drops a claim older than the retention window** (90 days before
       the clock), counted `dropped_old` (B4), so a feed that keeps listing
       old items does not refill what retention removed;
    4. **keys the item by its canonical URL** (`canonical_url/1`): a URL the
       feed already stored, or one repeated in the same answer, is `known`
       and neither stored nor counted again;
    5. **rates each item by the tier table** (§3, B5;
       `Portfolixir.News.Sources`, read once for the batch): an `issuer`
       or `regulatory` item is `primary` by construction, any other is its
       domain's tier (or a parent domain's), at most `secondary`, and
       `awareness` when unrated; an item of a `blocked` domain is dropped
       and counted `dropped_blocked`, before the cap, so it takes no room;
    6. **caps the feed at 200 items in 24 hours** (A3): the rolling count of
       the feed's items by `first_seen_at`, read under the feed's row lock,
       leaves room for the first items in the feed's order; the rest are
       counted `dropped_cap`. This is the one order that decides (B3), and
       it belongs to the feed that floods;
    7. **stores** each item, in its own savepoint (a row the database
       refuses is counted `invalid` and costs no other item), with `first_seen_at` the clock and
       `published_at` the claim clamped to it (`News.Item.changeset/2`, B4),
       and the title keys the clustering reads (`title_words`,
       `title_norm_hash`: `Portfolixir.News.Stories.title_keys/1`, the one
       source of both): an `issuer` or `regulatory` item `assigned` to its
       feed's security, a `thematic` one `assigned` to its feed's category,
       an `aggregator` one `unassigned` with no candidates.

  The day's counters go to `news_feed_days` (the server's day of the
  clock). Items and day rows are a staging area, not journaled (B7,
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

  alias Portfolixir.Clock
  alias Portfolixir.News
  alias Portfolixir.News.Feed
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.Repo

  @cap 200
  @cap_window_seconds 24 * 60 * 60
  @retention_days 90
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

  @doc "The retention window in days: an older claim is not stored (B4, §12)."
  @spec retention_days() :: pos_integer()
  def retention_days, do: @retention_days

  @doc """
  Stores what is new in `items` for `feed` at the server's clock `now`; see
  the moduledoc. `{:ok, summary}`, the stored rows in `summary.items`.
  """
  @spec ingest(Feed.t(), [Parsed.t()], DateTime.t()) :: {:ok, summary()}
  def ingest(%Feed{} = feed, items, %DateTime{} = now) when is_list(items) do
    {:ok, summary} =
      Repo.transaction(fn ->
        # One ingest per feed at a time: the cap's count and the inserts
        # below must not interleave with another fetch of the same feed.
        Repo.one!(from(f in Feed, where: f.id == ^feed.id, lock: "FOR UPDATE", select: f.id))

        {candidates, summary} = prepare(feed, items, now)
        {candidates, summary} = tier_and_block(candidates, summary)
        {stored, summary} = store(feed, candidates, now, summary)

        count_day(feed, now, summary)
        %{summary | items: stored}
      end)

    stored = summary.items
    assign_aggregator(stored, now)
    cluster(stored, now)

    {:ok, summary}
  end

  # §3, B5: each candidate's tier from the tier table, read once for the
  # batch; a `blocked` domain's candidates are dropped and counted
  # `dropped_blocked`, before the cap, so a blocked item takes no room.
  defp tier_and_block([], summary), do: {[], summary}

  defp tier_and_block(candidates, summary) do
    rated = candidates |> Enum.map(& &1.domain) |> Enum.uniq() |> Sources.lookup()

    {kept, blocked} =
      candidates
      |> Enum.map(&%{&1 | tier: Sources.tier(&1.class, Map.get(rated, &1.domain))})
      |> Enum.split_with(&(&1.tier != :blocked))

    {kept, %{summary | dropped_blocked: summary.dropped_blocked + length(blocked)}}
  end

  # §2: the stored `aggregator` items are matched against the universe by
  # the alias grammar, after the insert's commit (the matcher locks the
  # items and the securities it names in a transaction of its own). Every
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
          {:drop, counter} -> {kept, Map.update!(summary, counter, &(&1 + 1))}
        end
      end)

    kept = kept |> Enum.reverse() |> Enum.uniq_by(& &1.canonical_url)
    known = known_urls(feed, Enum.map(kept, & &1.canonical_url))
    {fresh, seen} = Enum.split_with(kept, &(not MapSet.member?(known, &1.canonical_url)))

    {fresh, %{summary | known: length(seen)}}
  end

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
      items: []
    }
  end

  defp candidate(_feed, _feed_host, %Parsed{title: title, link: link}, _oldest)
       when is_nil(title) or is_nil(link),
       do: {:drop, :incomplete}

  defp candidate(feed, feed_host, %Parsed{} = item, oldest) do
    with {:ok, domain} <- domain(feed, feed_host, item),
         :ok <- recent(item.published_at, oldest),
         {:ok, url} <- canonical(item.link) do
      {:ok, attrs(feed, item, domain, url)}
    end
  end

  defp domain(%Feed{class: :aggregator}, _feed_host, %Parsed{source_domain: nil}),
    do: {:drop, :dropped_no_source}

  defp domain(%Feed{class: :aggregator}, _feed_host, %Parsed{source_domain: domain}),
    do: {:ok, domain}

  defp domain(_feed, feed_host, %Parsed{link: link}), do: {:ok, host(link) || feed_host}

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

  defp known_urls(feed, urls) do
    from(i in Item,
      where: i.feed_id == ^feed.id and i.canonical_url in ^urls,
      select: i.canonical_url
    )
    |> Repo.all()
    |> MapSet.new()
  end

  # -- storing -----------------------------------------------------------------

  defp store(feed, candidates, now, summary) do
    room = max(@cap - stored_in_window(feed, now), 0)
    {admitted, capped} = Enum.split(candidates, room)
    summary = %{summary | dropped_cap: summary.dropped_cap + length(capped)}

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
    counts = [
      items_stored: summary.stored,
      dropped_cap: summary.dropped_cap,
      dropped_no_source: summary.dropped_no_source,
      dropped_old: summary.dropped_old,
      dropped_blocked: summary.dropped_blocked
    ]

    add_to_day(feed.id, now, counts)
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
