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
    5. **caps the feed at 200 items in 24 hours** (A3): the rolling count of
       the feed's items by `first_seen_at`, read under the feed's row lock,
       leaves room for the first items in the feed's order; the rest are
       counted `dropped_cap`. This is the one order that decides (B3), and
       it belongs to the feed that floods;
    6. **stores** each item with `first_seen_at` the clock and
       `published_at` the claim clamped to it (`News.Item.changeset/2`, B4):
       an `issuer` or `regulatory` item `assigned` to its feed's security and
       `primary` by construction, a `thematic` one `assigned` to its feed's
       category, an `aggregator` one `unassigned` with no candidates; every
       item but those two classes' is `awareness` until the tier table rates
       it (the extension point below).

  The day's counters go to `news_feed_days` (the server's day of the
  clock). Items and day rows are a staging area, not journaled (B7,
  `Portfolixir.Journal.Allowlist`); the fetcher that calls this is the
  registered system job.

  **Extension points**, no-ops here, filled by later stories: before the
  insert, `tier_and_block/2` (the source tier table and its `blocked`
  drops, N5); after it, `assign_aggregator/1` (the alias matcher, N4) and
  `cluster/1` (the stories, N5).
  """

  import Ecto.Query

  alias Portfolixir.Clock
  alias Portfolixir.News.Feed
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
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
    assign_aggregator(stored)
    cluster(stored)

    {:ok, summary}
  end

  # Extension point (N5): rate each candidate by the source tier table and
  # drop a `blocked` domain's items, counting them `dropped_blocked`. B5: an
  # aggregator item is at most `secondary`. A no-op until N5 fills it.
  defp tier_and_block(candidates, summary), do: {candidates, summary}

  # Extension point (N4): match the stored `aggregator` items against the
  # universe by the alias grammar (§2). A no-op until N4 fills it.
  defp assign_aggregator(_items), do: :ok

  # Extension point (N5): fold the stored items into stories (B3). A no-op
  # until N5 fills it.
  defp cluster(_items), do: :ok

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
    words = title_words(item.title)
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
      title_words: words,
      title_norm_hash: sha256(Enum.join(words, " ")),
      content_hash: sha256(item.title <> "\n" <> (excerpt || "")),
      candidates: []
    }
    |> Map.merge(bound_to(feed))
  end

  # §2: the class decides the binding; issuer and regulatory are primary by
  # construction (B5), everything else awareness until rated.
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

      case Repo.insert(changeset,
             on_conflict: :nothing,
             conflict_target: [:feed_id, :canonical_url]
           ) do
        {:ok, %Item{id: nil}} -> {stored, %{summary | known: summary.known + 1}}
        {:ok, item} -> {[item | stored], %{summary | stored: summary.stored + 1}}
        {:error, _changeset} -> {stored, %{summary | invalid: summary.invalid + 1}}
      end
    end)
    |> then(fn {stored, summary} -> {Enum.reverse(stored), summary} end)
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

  @doc """
  A title's normalized words, the input of the stories' similarity (B3):
  compatibility-normalized (NFKC), lower-cased, split at every character
  that is not a letter or a digit, each word once in its first position.
  `title_norm_hash` is the SHA-256 of these words joined by single spaces.
  """
  @spec title_words(String.t()) :: [String.t()]
  def title_words(title) when is_binary(title) do
    title
    |> :unicode.characters_to_nfkc_binary()
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.uniq()
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
