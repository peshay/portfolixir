defmodule Portfolixir.News.Stories do
  @moduledoc """
  Stories (ADR-0056 §4, B3 to B5): the items about one security — or one
  category — in one language that are one event.

  ## The rule (B3)

  Two items are **linked** when their `published_at` (the claim clamped to
  the first sight, B4) lie within the window of each other (72 hours,
  inclusive) and their titles are the same story: their normalized titles
  are equal, or the Jaccard similarity of their title words reaches the
  threshold (0.8). **A story is a connected component** of that relation:
  with A linked to B and B to C, A, B and C are one story even when A and C
  are not linked, whatever order they came in. Both values are settings
  (`Portfolixir.Settings.news_cluster_window_hours/0` and
  `news_cluster_similarity/0`); the similarity is compared exactly, in
  integers: `|A ∩ B| · d ≥ n · |A ∪ B|` for the threshold `n / d`.

  A title without a word (`***`) links to nothing, not even to an equal
  title: there is nothing to compare.

  **A primary story is anchored** (C1, ADR-0056 amendment of 2026-11-08):
  the components are taken of the `primary` items alone and of the
  lower-tier items alone; a lower-tier component the relation links to one
  or more primary components joins, whole, the one whose survivor key
  (below) is smallest, and any other lower-tier component is a story of
  its own. So a chain of aggregator items, each a word away from the last,
  never joins two primary stories into one and hides the newer headline.

  ## The title keys (`title_keys/1`)

  A title is normalized by: Unicode NFKC (full-width and compatibility
  forms fold to their plain letters), format characters removed
  (zero-width and bidirectional controls, so an invisible character inside
  a word does not split it), lower-cased by Unicode's rules, every run of
  characters that are not letters, marks or digits replaced by one space,
  the ends trimmed. **No stop words** and no stemming: the threshold carries
  the rewording, and a word list would be one more thing per language to
  keep. Its **words** are the distinct words, sorted (a set: the Jaccard
  similarity reads sets); its **hash** is the SHA-256 of the normalized
  title in lower-case hex. Ingest stores both on the item
  (`title_words`, `title_norm_hash`), and the clustering reads them.

  ## The order of members, never by id

    * **The representative** (B3) is the member of the best tier
      (`primary`, then `secondary`, then `awareness`), then the earliest
      clamped `published_at`, then the smallest canonical URL. An
      aggregator's item is at most `secondary` (B5), so it never stands for
      a story that has a true primary; a future claim is clamped (B4), so it
      cannot make an item the earliest.
    * **The earliest member** is the member earliest by
      `(first_seen_at, canonical URL)`, stored on the story as
      `earliest_first_seen_at` and `earliest_url`.
    * **The survivor member** (C2, ADR-0056 amendment of 2026-11-08) is
      the member of the best tier, then the earliest `first_seen_at`, then
      the smallest canonical URL: the story's survivor key. Within one
      scheduler tick every item shares `first_seen_at`, so without the tier
      first an attacker's URL would decide which story id survives.
    * Where two members agree on all of that, the comparison continues over
      their other stored fields (the other times, the tier, the hashes, the
      title); two items equal on all of them are indistinguishable to every
      reader. No id and no insertion order enters any comparison.

  ## Cost

  `cluster/2` sorts the items by publication and compares each item only
  with those published within the window after it: O(n log n + n · k), k
  the most items of one scope and language published within one window.
  The fetcher keeps at most 200 items per feed and day (A3), so k is at
  most 200 · (window in days + 1) per feed bound to the scope — for the
  default window and one busy feed, about 800 — and each comparison is a
  set intersection of at most 80 words (a title has at most 160
  characters).

  ## Recluster (`recluster/4`)

  Rewrites the stories of one scope and language in one transaction,
  serialized per scope and language by an advisory lock. Which items it
  reads:

    1. **the seeds**: the scope's items in no story yet (new, or newly
       assigned), and those first seen within one window before `now` —
       so the recent window is recomputed on every run;
    2. **their neighbours**: the scope's items in a story whose
       `published_at` lies within one window of a seed's — the only items a
       seed can link to;
    3. **every member of every story a seed or a neighbour belongs to.**

  A stored story is a component of the stored items, or (C1) part of one:
  a lower-tier component that joined one primary story may also be linked
  to another. So the read is closed over the relation: every story with an
  item linked to an item read is read whole, until no link runs between an
  item read and one not read. The components of what is read are then
  whole, C1 chooses with every primary story there is, and every other
  story stays as it is. With `full: true`
  every item of the scope and language is read, for a changed window or
  threshold, or after a retention run removed an item that held a story
  together.

  **Identity** (B3, C2): each old story goes with its survivor member to
  the new story that member is in. A new story that receives several keeps
  the one whose survivor member is smallest by the survivor key, and the
  others are deleted, merged into it; a new story that receives none is
  created. So a story's id keeps pointing at the story that holds its
  survivor member, as long as it lives, and a primary story's id is never
  given up for a lower tier's. The writes keep N2's restrict keys: stories
  are inserted or updated first (a representative is an existing item),
  then members move, then the merged stories, by then empty, are deleted.

  Stories and items are not journaled (B7): a staging area that retention
  empties, written by a system job.
  """
  import Ecto.Query

  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Item
  alias Portfolixir.Repo
  alias Portfolixir.Settings

  @tier_rank %{primary: 0, secondary: 1, awareness: 2}
  @words_max 160

  # The first key of the two-key advisory lock, distinct from the app's
  # other advisory locks; the second is the scope and language's hash.
  @lock_key 727_227_005

  # ADR-0056 §4's starting values, the pure function's defaults;
  # `recluster/4` reads the settings.
  @default_window_hours 72
  @default_similarity "0.8"

  # More disjoint publication ranges than this are read as one span.
  @ranges_max 50

  @type scope :: {:security, pos_integer()} | {:category, pos_integer()}
  @type story :: %{members: [map()], representative: map(), earliest: map()}
  @type summary :: %{
          stories: non_neg_integer(),
          created: non_neg_integer(),
          merged: non_neg_integer(),
          moved: non_neg_integer()
        }

  # --- the title keys -----------------------------------------------------

  @doc "A title as the clustering compares it; see the moduledoc."
  @spec normalize_title(String.t()) :: String.t()
  def normalize_title(title) when is_binary(title) do
    title
    |> nfkc()
    |> String.replace(~r/\p{Cf}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{M}\p{N}]+/u, " ")
    |> String.trim()
  end

  defp nfkc(title) do
    case :unicode.characters_to_nfkc_binary(title) do
      normalized when is_binary(normalized) -> normalized
      _invalid -> title
    end
  end

  @doc """
  The two keys an item stores for the clustering: `title_norm_hash` (the
  SHA-256 of the normalized title, lower-case hex) and `title_words` (its
  distinct words, sorted).
  """
  @spec title_keys(String.t()) :: %{title_norm_hash: String.t(), title_words: [String.t()]}
  def title_keys(title) when is_binary(title) do
    normalized = normalize_title(title)

    words =
      normalized |> String.split(" ", trim: true) |> Enum.uniq() |> Enum.sort()

    %{
      title_norm_hash: :sha256 |> :crypto.hash(normalized) |> Base.encode16(case: :lower),
      title_words: Enum.take(words, @words_max)
    }
  end

  @doc """
  The scope an assigned item's stories are kept in: `{:security, id}` or
  `{:category, id}`.
  """
  @spec scope(Item.t() | map()) :: scope()
  def scope(%{security_id: id}) when is_integer(id), do: {:security, id}
  def scope(%{category_id: id}) when is_integer(id), do: {:category, id}

  # --- the pure rule ------------------------------------------------------

  @doc """
  The stories of `items` — all of one scope and one language — as
  connected components (B3). Each item is a map (or struct) with
  `published_at` (clamped), `first_seen_at`, `canonical_url`, `tier`,
  `title_norm_hash` and `title_words`. Each story lists its `members` by
  the survivor key, its `representative` and its `earliest` member;
  the stories come ordered by their earliest member.

  Options: `window_hours` (default 72) and `similarity` (a `Decimal`,
  default 0.8).
  """
  @spec cluster([map()], keyword()) :: [story()]
  def cluster(items, opts \\ []) when is_list(items) do
    window = Keyword.get(opts, :window_hours, @default_window_hours) * 3_600_000_000
    ratio = ratio(Keyword.get_lazy(opts, :similarity, fn -> Decimal.new(@default_similarity) end))

    entries =
      items
      |> Enum.map(&entry/1)
      |> Enum.sort_by(&{&1.published, &1.key})
      |> List.to_tuple()

    entries
    |> adjacency(window, ratio)
    |> anchored_components(entries)
    |> Enum.map(fn indices -> story(Enum.map(indices, &elem(entries, &1))) end)
    |> Enum.sort_by(& &1.earliest_key)
    |> Enum.map(&Map.delete(&1, :earliest_key))
  end

  defp entry(item) do
    published = DateTime.to_unix(item.published_at, :microsecond)

    %{
      item: item,
      published: published,
      words: MapSet.new(item.title_words),
      hash: item.title_norm_hash,
      key: item_key(item),
      rank: {Map.fetch!(@tier_rank, item.tier), published, item.canonical_url, item_key(item)}
    }
  end

  # The survivor key and its continuation (see the moduledoc).
  defp item_key(item) do
    {DateTime.to_unix(item.first_seen_at, :microsecond), item.canonical_url,
     DateTime.to_unix(item.published_at, :microsecond), Map.fetch!(@tier_rank, item.tier),
     item.title_norm_hash, Map.get(item, :content_hash) || "", Map.get(item, :title) || ""}
  end

  # C2 (ADR-0056 amendment of 2026-11-08): the survivor key is the tier
  # first, then the earliest first sight and the smallest URL.
  defp survivor_key(item), do: {Map.fetch!(@tier_rank, item.tier), item_key(item)}

  # A threshold n / d as two integers, exact.
  defp ratio(%Decimal{} = similarity) do
    %Decimal{coef: coef, exp: exp} = Decimal.normalize(similarity)

    if exp >= 0,
      do: {coef * Integer.pow(10, exp), 1},
      else: {coef, Integer.pow(10, -exp)}
  end

  # Each item against those published within the window after it: the
  # entries are sorted by publication, so the walk stops at the first one
  # beyond the window.
  defp adjacency(entries, window, ratio) do
    count = tuple_size(entries)

    Enum.reduce(0..(count - 1)//1, %{}, fn i, acc ->
      link_following(entries, i, i + 1, {count, window, ratio}, acc)
    end)
  end

  defp link_following(entries, i, j, {count, window, ratio} = bounds, acc) when j < count do
    a = elem(entries, i)
    b = elem(entries, j)

    cond do
      b.published - a.published > window -> acc
      linked?(a, b, ratio) -> link_following(entries, i, j + 1, bounds, add_edges(acc, i, j))
      true -> link_following(entries, i, j + 1, bounds, acc)
    end
  end

  defp link_following(_entries, _i, _j, _bounds, acc), do: acc

  defp add_edges(adjacency, i, j),
    do: adjacency |> add_edge(i, j) |> add_edge(j, i)

  defp add_edge(adjacency, from, to), do: Map.update(adjacency, from, [to], &[to | &1])

  defp linked?(a, b, {numerator, denominator}) do
    cond do
      MapSet.size(a.words) == 0 or MapSet.size(b.words) == 0 ->
        false

      a.hash == b.hash ->
        true

      true ->
        shared = a.words |> MapSet.intersection(b.words) |> MapSet.size()
        union = MapSet.size(a.words) + MapSet.size(b.words) - shared
        shared * denominator >= numerator * union
    end
  end

  # C1 (ADR-0056 amendment of 2026-11-08): the components of the primary
  # items alone, and of the lower-tier items alone; a lower-tier component
  # the relation links to primary components joins the one whose survivor
  # key is smallest, so no chain of lower-tier items joins two primary
  # stories. Each list of indices is one story.
  defp anchored_components(adjacency, entries) do
    {primary, lower} =
      0..(tuple_size(entries) - 1)//1
      |> Enum.split_with(&(elem(entries, &1).item.tier == :primary))

    anchors = components(restrict(adjacency, primary), primary)
    anchor_of = for {members, n} <- Enum.with_index(anchors), i <- members, into: %{}, do: {i, n}

    anchor_keys =
      anchors
      |> Enum.with_index()
      |> Map.new(fn {members, n} ->
        {n, members |> Enum.map(&survivor_key(elem(entries, &1).item)) |> Enum.min()}
      end)

    {joined, alone} =
      adjacency
      |> restrict(lower)
      |> components(lower)
      |> Enum.reduce({%{}, []}, fn members, {joined, alone} ->
        linked =
          members
          |> Enum.flat_map(&Map.get(adjacency, &1, []))
          |> Enum.flat_map(&List.wrap(Map.get(anchor_of, &1)))
          |> Enum.uniq()

        case linked do
          [] ->
            {joined, [members | alone]}

          anchors ->
            n = Enum.min_by(anchors, &Map.fetch!(anchor_keys, &1))
            {Map.update(joined, n, members, &(members ++ &1)), alone}
        end
      end)

    anchors
    |> Enum.with_index()
    |> Enum.map(fn {members, n} -> members ++ Map.get(joined, n, []) end)
    |> Kernel.++(alone)
  end

  # The adjacency between `indices` only.
  defp restrict(adjacency, indices) do
    keep = MapSet.new(indices)

    Map.new(Map.take(adjacency, indices), fn {i, links} ->
      {i, Enum.filter(links, &MapSet.member?(keep, &1))}
    end)
  end

  # Connected components of `indices` by a depth-first walk, each a list of
  # indices.
  defp components(adjacency, indices) do
    {components, _seen} =
      Enum.reduce(indices, {[], MapSet.new()}, fn start, {acc, seen} ->
        if MapSet.member?(seen, start) do
          {acc, seen}
        else
          {members, seen} = walk([start], adjacency, MapSet.put(seen, start), [])
          {[members | acc], seen}
        end
      end)

    components
  end

  defp walk([], _adjacency, seen, members), do: {members, seen}

  defp walk([index | rest], adjacency, seen, members) do
    next = adjacency |> Map.get(index, []) |> Enum.reject(&MapSet.member?(seen, &1))
    walk(next ++ rest, adjacency, Enum.into(next, seen), [index | members])
  end

  defp story(entries) do
    members = Enum.sort_by(entries, & &1.key)
    earliest = hd(members)
    representative = Enum.min_by(entries, & &1.rank)

    %{
      members: Enum.map(members, & &1.item),
      representative: representative.item,
      earliest: earliest.item,
      earliest_key: earliest.key
    }
  end

  # --- recluster ----------------------------------------------------------

  @doc """
  Rewrites the stories of one security (`{:security, id}`) or category
  (`{:category, id}`) and `language`, as the moduledoc's "Recluster" says.
  `now` is the server's clock; `full: true` reads every item of the scope
  and language. `window_hours` and `similarity` default to the settings.
  """
  @spec recluster(scope(), String.t(), DateTime.t(), keyword()) ::
          {:ok, summary()} | {:error, Ecto.Changeset.t()}
  def recluster({kind, id} = scope, language, %DateTime{} = now, opts \\ [])
      when kind in [:security, :category] and is_integer(id) and is_binary(language) do
    Repo.transaction(fn ->
      lock_scope(scope, language)

      case recluster_locked(scope, language, now, opts) do
        {:ok, summary} -> summary
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp lock_scope({kind, id}, language) do
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [
      @lock_key,
      :erlang.phash2({kind, id, language})
    ])
  end

  defp recluster_locked(scope, language, now, opts) do
    options = [
      window_hours: Keyword.get_lazy(opts, :window_hours, &Settings.news_cluster_window_hours/0),
      similarity: Keyword.get_lazy(opts, :similarity, &Settings.news_cluster_similarity/0)
    ]

    window = options[:window_hours] * 3_600_000_000
    base = scope_items(scope, language)

    case read_items(base, now, {window, ratio(options[:similarity])}, opts[:full] == true) do
      {[], []} -> {:ok, %{stories: 0, created: 0, merged: 0, moved: 0}}
      {items, old} -> write(cluster(items, options), old, scope, language)
    end
  end

  # --- removing items -----------------------------------------------------

  @doc """
  Deletes the items of `doomed` (an `Item` query; the retention run's
  rule) that belong to one scope and language, and keeps the scope's
  stories whole (ADR-0056 §12: stories follow their items). In one
  transaction under the scope and language's advisory lock, the one
  `recluster/4` takes, so the two never interleave:

    1. the doomed items of the scope and language are read and locked in
       one statement (`FOR UPDATE`): an item promoted or linked to a note
       meanwhile is checked again, no longer matches and stays;
    2. they leave their stories; a story left without a member is deleted;
       a story whose representative is doomed points at the best remaining
       member by the representative rule (N2's restrict keys: an item named
       as a representative cannot be deleted);
    3. the doomed items are deleted;
    4. the scope and language are reclustered in full (`full: true`), so a
       story that lost a member is recounted and its earliest fields and
       representative recomputed, and one an expired item held together
       splits into its components, each old story going with its earliest
       remaining member (B3).

  Answers `{:ok, %{items: deleted, stories_deleted: emptied}}`.
  """
  @spec remove(scope(), String.t(), Ecto.Query.t(), DateTime.t(), keyword()) ::
          {:ok, %{items: non_neg_integer(), stories_deleted: non_neg_integer()}}
          | {:error, Ecto.Changeset.t()}
  def remove(scope, language, doomed, %DateTime{} = now, opts \\ []) do
    Repo.transaction(fn ->
      lock_scope(scope, language)

      # Read and locked in one statement: a row changed meanwhile (promoted,
      # linked to a note) is checked again and, no longer doomed, skipped.
      items =
        Repo.all(
          from(i in doomed,
            where: ^scope_filter(scope, language),
            lock: "FOR UPDATE",
            select: %{id: i.id, cluster_id: i.cluster_id}
          )
        )

      case Enum.map(items, & &1.id) do
        [] -> %{items: 0, stories_deleted: 0}
        ids -> remove_locked(scope, language, ids, story_ids(items), now, opts)
      end
    end)
  end

  defp remove_locked(scope, language, ids, affected, now, opts) do
    Repo.update_all(from(i in Item, where: i.id in ^ids), set: [cluster_id: nil])

    remaining =
      Repo.all(from(i in Item, where: i.cluster_id in ^affected))
      |> Enum.group_by(& &1.cluster_id)

    emptied = Enum.reject(affected, &Map.has_key?(remaining, &1))
    {stories_deleted, _} = Repo.delete_all(from(c in Cluster, where: c.id in ^emptied))

    from(c in Cluster, where: c.id in ^Map.keys(remaining) and c.representative_item_id in ^ids)
    |> Repo.all()
    |> Enum.each(fn story ->
      best = remaining |> Map.fetch!(story.id) |> Enum.min_by(&entry(&1).rank)

      Repo.update_all(from(c in Cluster, where: c.id == ^story.id),
        set: [representative_item_id: best.id]
      )
    end)

    {deleted, _} = Repo.delete_all(from(i in Item, where: i.id in ^ids))

    case recluster_locked(scope, language, now, Keyword.put(opts, :full, true)) do
      {:ok, _summary} -> %{items: deleted, stories_deleted: stories_deleted}
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp scope_items(scope, language), do: from(i in Item, where: ^scope_filter(scope, language))

  defp scope_filter({:security, id}, language),
    do:
      dynamic(
        [i],
        i.security_id == ^id and i.language == ^language and i.assignment == :assigned
      )

  defp scope_filter({:category, id}, language),
    do:
      dynamic(
        [i],
        i.category_id == ^id and i.language == ^language and i.assignment == :assigned
      )

  # The seeds, their neighbours and every member of the stories they touch;
  # with `full`, every item of the scope. Answers {items, old stories}.
  defp read_items(base, _now, _relation, true = _full) do
    items = Repo.all(base)
    {items, old_stories(items)}
  end

  defp read_items(base, now, {window, _ratio} = relation, false) do
    since = DateTime.add(now, -window, :microsecond)

    seeds =
      Repo.all(from(i in base, where: is_nil(i.cluster_id) or i.first_seen_at >= ^since))

    if seeds == [] do
      {[], []}
    else
      neighbours =
        Repo.all(from(i in base, where: not is_nil(i.cluster_id), where: ^within(seeds, window)))

      touched = story_ids(seeds ++ neighbours)
      members = Repo.all(from(i in base, where: i.cluster_id in ^touched))
      items = Enum.uniq_by(seeds ++ neighbours ++ members, & &1.id)
      items = linked_stories(base, items, items, relation)
      {items, old_stories(items)}
    end
  end

  # C1: a stored story may be linked to another (a lower-tier component
  # joins only the primary story with the smallest survivor key), so the
  # read is closed over the relation: every story linked to an item read is
  # read whole, until none is left. The components read are then whole,
  # and C1's choice is made with every primary story it could join.
  defp linked_stories(_base, items, [], _relation), do: items

  defp linked_stories(base, items, frontier, {window, ratio} = relation) do
    read = MapSet.new(items, & &1.id)
    frontier_entries = Enum.map(frontier, &entry/1)

    linked =
      from(i in base,
        where: not is_nil(i.cluster_id) and i.id not in ^MapSet.to_list(read),
        where: ^within(frontier, window)
      )
      |> Repo.all()
      |> Enum.filter(fn candidate ->
        candidate = entry(candidate)

        Enum.any?(frontier_entries, fn item ->
          abs(item.published - candidate.published) <= window and
            linked?(item, candidate, ratio)
        end)
      end)

    case story_ids(linked) do
      [] ->
        items

      ids ->
        added =
          from(i in base, where: i.cluster_id in ^ids)
          |> Repo.all()
          |> Enum.reject(&MapSet.member?(read, &1.id))

        linked_stories(base, items ++ added, added, relation)
    end
  end

  defp story_ids(items),
    do: items |> Enum.map(& &1.cluster_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp old_stories(items),
    do: Repo.all(from(c in Cluster, where: c.id in ^story_ids(items)))

  # Published within one window of a seed: the seeds' ranges, merged.
  defp within(seeds, window) do
    ranges =
      seeds
      |> Enum.map(&DateTime.to_unix(&1.published_at, :microsecond))
      |> Enum.sort()
      |> Enum.map(&{&1 - window, &1 + window})
      |> merge_ranges([])

    ranges =
      if length(ranges) > @ranges_max,
        do: [{elem(hd(ranges), 0), elem(List.last(ranges), 1)}],
        else: ranges

    Enum.reduce(ranges, dynamic(false), fn {from, to}, acc ->
      from = DateTime.from_unix!(from, :microsecond)
      to = DateTime.from_unix!(to, :microsecond)
      dynamic([i], ^acc or (i.published_at >= ^from and i.published_at <= ^to))
    end)
  end

  defp merge_ranges([], merged), do: Enum.reverse(merged)

  defp merge_ranges([{from, to} | rest], [{last_from, last_to} | merged]) when from <= last_to,
    do: merge_ranges(rest, [{last_from, max(to, last_to)} | merged])

  defp merge_ranges([range | rest], merged), do: merge_ranges(rest, [range | merged])

  defp write(stories, old, scope, language) do
    old_by_id = Map.new(old, &{&1.id, &1})
    survivors = survivors(stories)

    stories
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {story, index}, {:ok, written} ->
      attrs = story_attrs(story, scope, language)

      result =
        case Map.fetch(survivors, index) do
          {:ok, id} -> update_story(Map.fetch!(old_by_id, id), attrs)
          :error -> Repo.insert(Cluster.changeset(%Cluster{}, attrs))
        end

      case result do
        {:ok, cluster} -> {:cont, {:ok, [{story, cluster.id} | written]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, written} ->
        moved = Enum.reduce(written, 0, fn {story, id}, acc -> acc + move(story, id) end)
        merged = Map.keys(old_by_id) -- Map.values(survivors)
        Repo.delete_all(from(c in Cluster, where: c.id in ^merged))

        {:ok,
         %{
           stories: length(stories),
           created: length(stories) - map_size(survivors),
           merged: length(merged),
           moved: moved
         }}

      error ->
        error
    end
  end

  # B3 and C2: each old story goes with its survivor member (best tier, then
  # earliest first sight, then smallest URL); a new story keeps the old one
  # whose survivor member is smallest by that key. Answers
  # %{story index => old story id}.
  defp survivors(stories) do
    story_of =
      for {story, index} <- Enum.with_index(stories), member <- story.members, into: %{} do
        {member.id, index}
      end

    stories
    |> Enum.flat_map(& &1.members)
    |> Enum.reject(&is_nil(&1.cluster_id))
    |> Enum.group_by(& &1.cluster_id)
    |> Enum.map(fn {id, members} ->
      survivor = Enum.min_by(members, &survivor_key/1)
      {Map.fetch!(story_of, survivor.id), {survivor_key(survivor), id}}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {index, claims} -> {index, claims |> Enum.min() |> elem(1)} end)
  end

  defp update_story(cluster, attrs) do
    changeset = Cluster.changeset(cluster, attrs)
    if changeset.changes == %{}, do: {:ok, cluster}, else: Repo.update(changeset)
  end

  defp story_attrs(story, {kind, id}, language) do
    %{
      security_id: if(kind == :security, do: id),
      category_id: if(kind == :category, do: id),
      language: language,
      representative_item_id: story.representative.id,
      member_count: length(story.members),
      earliest_first_seen_at: story.earliest.first_seen_at,
      earliest_published_at:
        Enum.min_by(story.members, &DateTime.to_unix(&1.published_at, :microsecond)).published_at,
      earliest_url: story.earliest.canonical_url,
      best_tier: story.representative.tier
    }
  end

  defp move(story, cluster_id) do
    case for(member <- story.members, member.cluster_id != cluster_id, do: member.id) do
      [] ->
        0

      ids ->
        {count, _} =
          Repo.update_all(from(i in Item, where: i.id in ^ids),
            set: [cluster_id: cluster_id, updated_at: DateTime.utc_now()]
          )

        count
    end
  end
end
