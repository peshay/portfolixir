defmodule Portfolixir.News.Stories do
  @moduledoc """
  Stories (ADR-0056 §4, B3 to B5): the items about one security — or one
  category — in one language that are one event.

  ## The rule (B3)

  Two items are **linked** when their `published_at` (the claim clamped to
  the first sight, B4) lie within the window of each other (72 hours,
  inclusive), **their first sights lie within the window of each other
  too** (F2, ADR-0056 amendment of 2026-11-24: the claim is the feed's,
  the clock is the operator's, and only the clock bounds how many items a
  window holds), and their titles are the same story: their normalized
  titles are equal, or the Jaccard similarity of their title words reaches
  the threshold (0.8). **A story is a connected component** of that relation:
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

    * **The representative** (B3, as F9 amends it: ADR-0056 amendment of
      2026-11-24) is the member of the best tier (`primary`, then
      `secondary`, then `awareness`), then the earliest `first_seen_at`,
      then the earliest clamped `published_at`, then the smallest canonical
      URL. An aggregator's item is at most `secondary` (B5), so it never
      stands for a story that has a true primary; within a tier the
      server's first sight decides before any claim (B4: the claim is the
      feed's, the clock is the operator's), so a story's title, link and
      time do not change when a later item claims an earlier publication.
      Among the items of one first sight the earliest claim decides.
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

  ## Cost (F2)

  `cluster/2` sorts the items by first sight and compares each item only
  with those first seen within the window after it, and with at most
  `compare_max/0` of them (800): O(n log n + n · k), k the most items of
  one scope and language **first seen** within one window, never more
  than 800. The fetcher keeps at most 200 items per feed and day (A3) by
  the server's clock, so one feed puts at most 200 · (window in days + 1)
  items into a window — for the default window about 800 — whatever
  publication times it claims; the cap on k holds the same for several
  feeds flooding one scope, whose farther items are then not compared.
  Two items of one component already are not compared again, and a
  comparison walks the two sorted word lists (at most 80 words each; a
  title has at most 160 characters) only until the threshold is out of
  reach. The components are kept as disjoint sets, so the memory is
  linear in n however many items link.

  A recluster reads no more than that needs: its seeds, the items first
  seen (and published) within one window of them, and the stories those
  belong to. Removing items (`remove/5`) recomputes the stories that lost
  a member, not the scope.

  ## Recluster (`recluster/4`)

  Rewrites the stories of one scope and language in one transaction,
  serialized per scope and language by an advisory lock, taken after the
  scope's security (or category) `FOR KEY SHARE`, as every news writer
  takes the securities before any news row (#1470; `Portfolixir.LockTable`,
  row 28). Which items it reads:

    1. **the seeds**: the scope's items in no story yet (new, or newly
       assigned), and those first seen within one window before `now` —
       so the recent window is recomputed on every run;
    2. **their neighbours**: the scope's items in a story whose
       `published_at` and whose first sight both lie within one window of
       a seed's — the only items a seed can link to;
    3. **every member of every story a seed or a neighbour belongs to.**

  A stored story is a component of the stored items, or (C1) part of one:
  a lower-tier component that joined one primary story may also be linked
  to another. So the read is closed over the relation: every story with an
  item linked to an item read is read whole, until no link runs between an
  item read and one not read. The components of what is read are then
  whole, C1 chooses with every primary story there is, and every other
  story stays as it is. With `full: true`
  every item of the scope and language is read: for a changed window or
  threshold, and where an item entered or left the scope by a write (a
  merge, an assignment, a rating). A removal (`remove/5`) names the
  stories that lost a member instead, and their remaining members are
  seeds.

  **Identity** (B3, C2): each old story goes with its survivor member to
  the new story that member is in. A new story that receives several keeps
  the one whose survivor member is smallest by the survivor key, and the
  others are deleted, merged into it; a new story that receives none is
  created. So a story's id keeps pointing at the story that holds its
  survivor member, as long as it lives, and a primary story's id is never
  given up for a lower tier's. The writes keep N2's restrict keys: stories
  are inserted or updated first (a representative is an existing item),
  then members move, then the merged stories, by then empty, are deleted.

  **An item filed late enters its scope then** (F5, ADR-0056 amendment of
  2026-11-24; C3's rule for a late assignment). An item is stored before
  its story is written, in a transaction of its own, so a recluster that
  failed leaves it assigned and in no story, and no read shows it. When a
  later recluster files it, and that recluster's clock is later than the
  item's `scope_at`, the item's `scope_at` becomes that clock: a reader
  whose `since`, or whose confirmed position, lies after the item's first
  sight still reads its story. `recluster_unfiled/1` is the sweep that
  finds such items: every scope and language that holds one is
  reclustered, each on its own.

  Stories and items are not journaled (B7): a staging area that retention
  empties, written by a system job.
  """
  import Ecto.Query

  require Logger

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications.Category
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

  # More disjoint ranges of one clock than this are read as one span.
  @ranges_max 50

  # The most items one item is compared with (`cluster/2`): what one feed
  # at A3's cap stores within the default window, 200 · (3 + 1).
  @compare_max 800

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

  @doc "The most items one item is compared with in `cluster/2` (F2)."
  @spec compare_max() :: pos_integer()
  def compare_max, do: @compare_max

  @doc """
  The stories of `items` — all of one scope and one language — as
  connected components (B3). Each item is a map (or struct) with
  `published_at` (clamped), `first_seen_at`, `canonical_url`, `tier`,
  `title_norm_hash` and `title_words`. Each story lists its `members` by
  the survivor key, its `representative` and its `earliest` member;
  the stories come ordered by their earliest member.

  Options: `window_hours` (default 72), `similarity` (a `Decimal`,
  default 0.8) and `compare_max` (default `compare_max/0`): an item is
  compared with at most that many items first seen after it.
  """
  @spec cluster([map()], keyword()) :: [story()]
  def cluster(items, opts \\ []) when is_list(items) do
    window = Keyword.get(opts, :window_hours, @default_window_hours) * 3_600_000_000
    ratio = ratio(Keyword.get_lazy(opts, :similarity, fn -> Decimal.new(@default_similarity) end))
    compare_max = Keyword.get(opts, :compare_max, @compare_max)

    # By first sight: the survivor key begins with it.
    entries =
      items
      |> Enum.map(&entry/1)
      |> Enum.sort_by(& &1.key)
      |> List.to_tuple()

    entries
    |> anchored_components({window, ratio, compare_max})
    |> Enum.map(fn indices -> story(Enum.map(indices, &elem(entries, &1))) end)
    |> Enum.sort_by(& &1.earliest_key)
    |> Enum.map(&Map.delete(&1, :earliest_key))
  end

  defp entry(item) do
    published = DateTime.to_unix(item.published_at, :microsecond)
    seen = DateTime.to_unix(item.first_seen_at, :microsecond)
    words = :lists.usort(item.title_words)
    key = item_key(item)

    %{
      item: item,
      published: published,
      seen: seen,
      primary?: item.tier == :primary,
      words: words,
      size: length(words),
      hash: item.title_norm_hash,
      key: key,
      rank: {Map.fetch!(@tier_rank, item.tier), seen, published, item.canonical_url, key}
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

  # F2: `fun` is called for each pair of `order`'s entries that the two
  # clocks admit: first seen within the window of each other (the entries
  # are sorted by first sight, so the walk stops at the first one beyond
  # it), published within it too, and at most `compare_max` entries apart.
  # `order` is a tuple of indices into `entries`, ascending.
  defp reduce_near(entries, order, {window, _ratio, compare_max}, acc, fun) do
    count = tuple_size(order)

    Enum.reduce(0..(count - 1)//1, acc, fn at, acc ->
      i = elem(order, at)
      stop = min(count, at + 1 + compare_max)
      near(entries, order, {elem(entries, i), i}, {at + 1, stop, window}, acc, fun)
    end)
  end

  defp near(entries, order, {a, _i} = from, {at, stop, window}, acc, fun) when at < stop do
    j = elem(order, at)
    b = elem(entries, j)
    next = {at + 1, stop, window}

    cond do
      b.seen - a.seen > window -> acc
      abs(b.published - a.published) > window -> near(entries, order, from, next, acc, fun)
      true -> near(entries, order, from, next, fun.(from, {b, j}, acc), fun)
    end
  end

  defp near(_entries, _order, _from, _walk, acc, _fun), do: acc

  defp linked?(a, b, {numerator, denominator}) do
    cond do
      a.size == 0 or b.size == 0 ->
        false

      a.hash == b.hash ->
        true

      true ->
        # |A ∩ B| · d ≥ n · |A ∪ B| with |A ∪ B| = |A| + |B| − |A ∩ B|,
        # so |A ∩ B| · (d + n) ≥ n · (|A| + |B|): exact, in integers.
        target = {numerator * (a.size + b.size), denominator + numerator}
        shares?(a.words, b.words, {a.size, b.size, 0}, target)
    end
  end

  # Whether two sorted lists of distinct words share enough words:
  # `shared · unit ≥ need`. The walk ends as soon as the words left cannot
  # reach it.
  defp shares?(a, b, {left_a, left_b, shared}, {need, unit} = target) do
    cond do
      (shared + min(left_a, left_b)) * unit < need -> false
      a == [] or b == [] -> true
      hd(a) == hd(b) -> shares?(tl(a), tl(b), {left_a - 1, left_b - 1, shared + 1}, target)
      hd(a) < hd(b) -> shares?(tl(a), b, {left_a - 1, left_b, shared}, target)
      true -> shares?(a, tl(b), {left_a, left_b - 1, shared}, target)
    end
  end

  # C1 (ADR-0056 amendment of 2026-11-08): the components of the primary
  # items alone, and of the lower-tier items alone; a lower-tier component
  # the relation links to primary components joins the one whose survivor
  # key is smallest, so no chain of lower-tier items joins two primary
  # stories. Each list of indices is one story.
  #
  # F2: the components are disjoint sets (`link/4`), never a list of every
  # link, and a lower-tier item keeps only the best primary component it
  # is linked to (`anchor/5`), so the memory is linear in the items
  # whatever they link to. The primary components are final before a
  # lower-tier item is compared, so "best" is the survivor key C1 names.
  defp anchored_components(entries, {_window, ratio, _max} = bounds) do
    {primary, lower} =
      0..(tuple_size(entries) - 1)//1
      |> Enum.split_with(&elem(entries, &1).primary?)

    anchor_of =
      entries
      |> reduce_near(List.to_tuple(primary), bounds, %{}, &link(&3, &1, &2, ratio))
      |> roots(primary)

    anchor_keys =
      primary
      |> Enum.group_by(&Map.fetch!(anchor_of, &1))
      |> Map.new(fn {root, members} ->
        {root, members |> Enum.map(&survivor_key(elem(entries, &1).item)) |> Enum.min()}
      end)

    all = List.to_tuple(Enum.to_list(0..(tuple_size(entries) - 1)//1))

    {lowers, best} =
      reduce_near(entries, all, bounds, {%{}, %{}}, fn
        {%{primary?: true}, _i}, {%{primary?: true}, _j}, acc ->
          acc

        {%{primary?: false}, _i} = a, {%{primary?: false}, _j} = b, {sets, best} ->
          {link(sets, a, b, ratio), best}

        {%{primary?: true} = a, i}, b, {sets, best} ->
          {sets, anchor(best, b, {a, Map.fetch!(anchor_of, i)}, anchor_keys, ratio)}

        a, {b, j}, {sets, best} ->
          {sets, anchor(best, a, {b, Map.fetch!(anchor_of, j)}, anchor_keys, ratio)}
      end)

    lower_of = roots(lowers, lower)

    {joined, alone} =
      lower
      |> Enum.group_by(&Map.fetch!(lower_of, &1))
      |> Map.values()
      |> Enum.reduce({%{}, []}, fn members, {joined, alone} ->
        case members |> Enum.flat_map(&List.wrap(Map.get(best, &1))) |> Enum.min(fn -> nil end) do
          nil -> {joined, [members | alone]}
          {_key, root} -> {Map.update(joined, root, members, &(members ++ &1)), alone}
        end
      end)

    primary
    |> Enum.group_by(&Map.fetch!(anchor_of, &1))
    |> Enum.map(fn {root, members} -> members ++ Map.get(joined, root, []) end)
    |> Kernel.++(alone)
  end

  # Two entries of one tier group: one component when linked. Two that are
  # one component already are not compared.
  defp link(sets, {a, i}, {b, j}, ratio) do
    {root_i, sets} = find(sets, i)
    {root_j, sets} = find(sets, j)

    cond do
      root_i == root_j -> sets
      linked?(a, b, ratio) -> Map.put(sets, max(root_i, root_j), min(root_i, root_j))
      true -> sets
    end
  end

  # A lower-tier entry and a primary one of the component `root`: the
  # lower one keeps the linked primary component with the smallest
  # survivor key. A component that cannot be better is not compared.
  defp anchor(best, {lower, l}, {primary, root}, anchor_keys, ratio) do
    candidate = {Map.fetch!(anchor_keys, root), root}

    case best do
      %{^l => kept} when kept <= candidate -> best
      _other -> if linked?(lower, primary, ratio), do: Map.put(best, l, candidate), else: best
    end
  end

  # Disjoint sets as a map from an index to its parent; a root has no
  # entry. `find/2` answers the root and the sets with the walked path
  # pointing at it.
  defp find(sets, index) do
    case sets do
      %{^index => parent} ->
        {root, sets} = find(sets, parent)
        {root, if(root == parent, do: sets, else: Map.put(sets, index, root))}

      _root ->
        {index, sets}
    end
  end

  # The root of each of `indices`.
  defp roots(sets, indices) do
    {root_of, _sets} =
      Enum.reduce(indices, {%{}, sets}, fn index, {root_of, sets} ->
        {root, sets} = find(sets, index)
        {Map.put(root_of, index, root), sets}
      end)

    root_of
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

  # The scope's lock. **Its parent first** (#1470; `Portfolixir.LockTable`,
  # row 28): the security (or category) of the scope `FOR KEY SHARE`, then
  # the advisory lock, then the stories and items. A security merge holds
  # both securities `FOR UPDATE` and then writes the source's items, its
  # stories and its items again (row 13), so a recluster that held a story
  # and then moved an item into it, or held its items (`remove/5`) and then
  # wrote a story, closed a cycle with it; holding the security first, the
  # two meet there, and the one that waits holds nothing the other asks
  # for. A recluster that waited on a merge of its security finds the
  # source's items moved to the target, and writes nothing. A caller that
  # holds the security already (`News.assign_item/4`, a rating, a
  # promotion, the merge's own recluster of its target) takes it again at
  # no wait.
  defp lock_scope({kind, id}, language) do
    lock_parent(kind, id)

    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [
      @lock_key,
      :erlang.phash2({kind, id, language})
    ])
  end

  defp lock_parent(:security, id),
    do: Repo.all(from(s in Security, where: s.id == ^id, lock: "FOR KEY SHARE", select: s.id))

  defp lock_parent(:category, id),
    do: Repo.all(from(c in Category, where: c.id == ^id, lock: "FOR KEY SHARE", select: c.id))

  defp recluster_locked(scope, language, now, opts) do
    options = [
      window_hours: Keyword.get_lazy(opts, :window_hours, &Settings.news_cluster_window_hours/0),
      similarity: Keyword.get_lazy(opts, :similarity, &Settings.news_cluster_similarity/0)
    ]

    window = options[:window_hours] * 3_600_000_000
    base = scope_items(scope, language)
    relation = {window, ratio(options[:similarity]), @compare_max}

    read =
      if opts[:full] == true,
        do: read_all(base),
        else: read_near(base, now, relation, Keyword.get(opts, :stories, []))

    case read do
      {[], []} -> {:ok, %{stories: 0, created: 0, merged: 0, moved: 0}}
      {items, old} -> write(cluster(items, options), old, {scope, language}, now)
    end
  end

  @doc """
  Reclusters every scope and language that holds an assigned item in no
  story (F5; see the moduledoc), at the server's clock `now`, each in a
  transaction of its own. A scope whose recluster raises, exits or is
  refused is named in the log and counted, and stops no other. Answers
  the scopes tried and how many of them failed.

  The news scheduler calls it on every tick, after that tick's fetches
  (`Portfolixir.News.Scheduler`).
  """
  @spec recluster_unfiled(DateTime.t()) :: %{
          scopes: non_neg_integer(),
          failed: non_neg_integer()
        }
  def recluster_unfiled(%DateTime{} = now) do
    from(i in Item,
      where: i.assignment == :assigned and is_nil(i.cluster_id),
      distinct: true,
      select: {i.security_id, i.category_id, i.language}
    )
    |> Repo.all()
    |> Enum.sort()
    |> Enum.reduce(%{scopes: 0, failed: 0}, fn {security_id, category_id, language}, acc ->
      scope = scope(%{security_id: security_id, category_id: category_id})

      case file(scope, language, now) do
        :ok ->
          %{acc | scopes: acc.scopes + 1}

        {:error, reason} ->
          Logger.warning(
            "news stories of #{inspect(scope)} (#{language}) not written, " <>
              "its items wait for the next sweep: #{reason}"
          )

          %{acc | scopes: acc.scopes + 1, failed: acc.failed + 1}
      end
    end)
  end

  defp file(scope, language, now) do
    case recluster(scope, language, now) do
      {:ok, _summary} -> :ok
      {:error, changeset} -> {:error, inspect(changeset.errors)}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  catch
    :exit, reason -> {:error, "exit: " <> inspect(reason)}
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
    4. the stories that lost a member are reclustered (their remaining
       members are seeds, beside those of a plain recluster), so each is
       recounted and its earliest fields and representative recomputed,
       and one an expired item held together splits into its components,
       each old story going with its earliest remaining member (B3). A
       story that lost no member is as it was and is not read again (F2):
       what a removal costs follows what it removes, not the scope.

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
    stories_deleted = detach_locked(ids, affected)

    {deleted, _} = Repo.delete_all(from(i in Item, where: i.id in ^ids))

    case recluster_locked(scope, language, now, Keyword.put(opts, :stories, affected)) do
      {:ok, _summary} -> %{items: deleted, stories_deleted: stories_deleted}
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  # Steps 2 of `remove/5`, and `detach/1`'s whole: the items `ids` leave
  # their stories `affected`; a story left without a member is deleted, one
  # whose representative left points at the best remaining member. Answers
  # the number of stories deleted.
  defp detach_locked(ids, affected) do
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

    stories_deleted
  end

  # --- S28 N4 begin ---

  @doc """
  Takes the scope and language's advisory lock, the one `recluster/4` and
  `remove/5` take, for the caller's open transaction: a write that moves an
  item between scopes (`Portfolixir.News.assign_item/4`) holds both scopes'
  locks before it locks the item, in the order `remove/5` takes them
  (scope, then items), so the two never wait on each other in a cycle.
  """
  @spec lock(scope(), String.t()) :: :ok
  def lock({kind, id} = scope, language)
      when kind in [:security, :category] and is_integer(id) and is_binary(language) do
    lock_scope(scope, language)
    :ok
  end

  @doc """
  Takes the item `item` out of its story, inside the caller's transaction
  and under its scope's lock (`lock/2`): the item's `cluster_id` is cleared,
  a story left without a member is deleted, and one whose representative
  left points at the best remaining member (the representative rule).
  The story's counts and earliest fields are the next full recluster's
  (`recluster/4` with `full: true`), as after `remove/5`. An item in no
  story is left as it is.
  """
  @spec detach(Item.t()) :: :ok
  def detach(%Item{cluster_id: nil}), do: :ok

  def detach(%Item{id: id, cluster_id: cluster_id}) do
    detach_locked([id], [cluster_id])
    :ok
  end

  # --- S28 N4 end ---

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

  # Every item of the scope (`full: true`). Answers {items, old stories}.
  defp read_all(base) do
    items = Repo.all(base)
    {items, old_stories(items)}
  end

  # The seeds, their neighbours and every member of the stories they touch.
  # A seed is an item in no story, one first seen within one window before
  # `now`, or a member of one of `stories` (`remove/5`: the stories that
  # lost a member). Answers {items, old stories}.
  defp read_near(base, now, {window, _ratio, _max} = relation, stories) do
    since = DateTime.add(now, -window, :microsecond)

    seeds =
      Repo.all(
        from(i in base,
          where: is_nil(i.cluster_id) or i.first_seen_at >= ^since or i.cluster_id in ^stories
        )
      )

    if seeds == [] do
      {[], []}
    else
      neighbours =
        Repo.all(from(i in base, where: not is_nil(i.cluster_id), where: ^nearby(seeds, window)))

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

  defp linked_stories(base, items, frontier, {window, _ratio, _max} = relation) do
    read = MapSet.new(items, & &1.id)

    candidates =
      Repo.all(
        from(i in base,
          where: not is_nil(i.cluster_id) and i.id not in ^MapSet.to_list(read),
          where: ^nearby(frontier, window)
        )
      )

    case story_ids(linked_to(frontier, candidates, relation)) do
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

  # The `candidates` the relation links to an item of `frontier`, found by
  # the walk `cluster/2` makes (F2): each item against those first seen
  # within the window after it, at most `compare_max` of them, so the work
  # is bounded as the clustering's is.
  defp linked_to(_frontier, [], _relation), do: []

  defp linked_to(frontier, candidates, {_window, ratio, _max} = relation) do
    entries =
      (Enum.map(frontier, &Map.put(entry(&1), :read?, true)) ++
         Enum.map(candidates, &Map.put(entry(&1), :read?, false)))
      |> Enum.sort_by(& &1.key)
      |> List.to_tuple()

    order = List.to_tuple(Enum.to_list(0..(tuple_size(entries) - 1)//1))

    entries
    |> reduce_near(order, relation, MapSet.new(), fn
      {%{read?: same}, _i}, {%{read?: same}, _j}, linked ->
        linked

      {a, i}, {b, j}, linked ->
        candidate = if a.read?, do: j, else: i

        if not MapSet.member?(linked, candidate) and linked?(a, b, ratio),
          do: MapSet.put(linked, candidate),
          else: linked
    end)
    |> Enum.map(&elem(entries, &1).item)
  end

  defp story_ids(items),
    do: items |> Enum.map(& &1.cluster_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp old_stories(items),
    do: Repo.all(from(c in Cluster, where: c.id in ^story_ids(items)))

  # Within one window of one of `items` on both clocks (F2): published
  # within a window of one's publication, and first seen within a window
  # of one's first sight. Only such an item can be linked to one of them.
  defp nearby(items, window) do
    dynamic(
      [i],
      ^spans(items, window, :published_at) and ^spans(items, window, :first_seen_at)
    )
  end

  # The ranges of `field` one window around each of `items`, merged.
  defp spans(items, window, field) do
    ranges =
      items
      |> Enum.map(&DateTime.to_unix(Map.fetch!(&1, field), :microsecond))
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
      dynamic([i], ^acc or (field(i, ^field) >= ^from and field(i, ^field) <= ^to))
    end)
  end

  defp merge_ranges([], merged), do: Enum.reverse(merged)

  defp merge_ranges([{from, to} | rest], [{last_from, last_to} | merged]) when from <= last_to,
    do: merge_ranges(rest, [{last_from, max(to, last_to)} | merged])

  defp merge_ranges([range | rest], merged), do: merge_ranges(rest, [range | merged])

  defp write(stories, old, {scope, language}, now) do
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
        moved = Enum.reduce(written, 0, fn {story, id}, acc -> acc + move(story, id, now) end)
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

  # The members that are not in the story yet move into it. F5: one that
  # sat in no story and entered its scope before this recluster's clock is
  # filed late, and enters its scope now (`scope_at`; never moved back).
  defp move(story, cluster_id, now) do
    {late, moving} =
      story.members
      |> Enum.filter(&(&1.cluster_id != cluster_id))
      |> Enum.split_with(&(is_nil(&1.cluster_id) and DateTime.compare(&1.scope_at, now) == :lt))

    updated_at = DateTime.utc_now()

    moved(moving, cluster_id: cluster_id, updated_at: updated_at) +
      moved(late, cluster_id: cluster_id, scope_at: now, updated_at: updated_at)
  end

  defp moved([], _set), do: 0

  defp moved(members, set) do
    ids = Enum.map(members, & &1.id)
    {count, _} = Repo.update_all(from(i in Item, where: i.id in ^ids), set: set)
    count
  end
end
