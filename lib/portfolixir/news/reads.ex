defmodule Portfolixir.News.Reads do
  @moduledoc """
  The news layer's reads (ADR-0056 §9, §11, B4; Sprint 27, N7): a scope's
  stories, a story's items and the unassigned and ambiguous remainder, one
  story or item, and the digest. Compact by §9's rule: a list carries no
  link and no excerpt (only `story/1` and `item/1` do), names are short
  (`short_name/1`), and a page is capped with a `truncated` flag and a
  cursor. Titles and excerpts are cut by the width the companion spells
  them in (`clip_spelled/2`, C5): 160 for a title in a list and in a story
  or item, 100 in the digest, 600 for an excerpt. `news.get` holds §9's
  400 tokens on the companion's text, its link and members included: the
  link is cut at 300 characters (the whole link stays stored), every domain
  at 40, and the excerpt last, to what the rest of the answer leaves of the
  400 (`story/1`, `item/1`), every id counted at its widest so the cut does
  not move with the ids: a long answer gives up excerpt, never its source. No label is read:
  labels are Sprint 28's, and every read here answers without one (§7,
  fail-open).

  ## What is new: `since` and `as_of` (B4)

  `since` compares an item's `scope_at` (C3, ADR-0056 amendment of
  2026-11-08), the server's time it entered its scope — its first sight,
  or the time of a later assignment by the re-match, a merge or a
  candidate left alone — never the feed's claim: a story is new when any
  of its members entered its scope strictly after `since`. `as_of/0` is the `since` a reader passes next, by
  `Portfolixir.DeltaCursor`'s rule (overlap, never loss): no later than the
  start of the oldest write still in flight, and earlier again by
  `fetch_lag_seconds/0`, because the fetcher stamps an item's
  `first_seen_at` and `scope_at` with the clock it read **before** its request (up to the
  fetch's 30-second deadline and the per-host pace wait before the write
  begins). A story re-delivered is the price; a story lost is not paid.

  ## Ordering and pages

  Stories come newest first by their newest member's `scope_at`; items by
  their `scope_at`. Rows that entered their scope in the same microsecond —
  one scheduler tick stamps every item it stores alike — come by tier
  (primary first), then by publication (the representative's, clamped;
  newest first), then by link (the MD5 of the canonical URL), and only then
  by id (closing act, ORD4): an aggregator's flood stored after an issuer's
  release in one tick cannot push it off the first page. A page is `limit`
  rows; when more matched, `truncated` is true and `cursor` (those five
  keys of the page's last row) continues it in the same order, without
  loss or repeat. The ids decide no story and no representative (B3).
  """

  import Ecto.Query

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications.Category
  alias Portfolixir.DeltaCursor
  alias Portfolixir.Input.Text
  alias Portfolixir.Ledger
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Item
  alias Portfolixir.News.Universe
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  @fetch_lag_seconds 120
  @short_name_max 20
  @members_max 5
  @digest_title_max 100
  @certain_classes ["issuer", "regulatory"]
  @tier_rank %{primary: 3, secondary: 2, awareness: 1}

  # ORD4: a page's order within one `scope_at` is the tier first (0 for
  # primary), then the publication, newest first, then the link's key (its
  # MD5, so a cursor stays short however long the link), and the id last.
  @tier_order %{primary: 0, secondary: 1, awareness: 2}
  @rank_sql "CASE ? WHEN 'primary' THEN 0 WHEN 'secondary' THEN 1 ELSE 2 END"

  @type tier :: :primary | :secondary | :awareness
  @type selector ::
          {:security, pos_integer()}
          | {:category, pos_integer()}
          | {:cluster, pos_integer()}
          | {:assignment, :unassigned | :ambiguous}
  @type cursor ::
          {DateTime.t(), 0..2, DateTime.t(), String.t(), pos_integer()}
  @type list_opts :: [
          since: DateTime.t() | nil,
          tier_min: tier() | nil,
          limit: pos_integer(),
          cursor: cursor() | nil
        ]
  @type page :: %{
          kind: :stories | :items,
          rows: [map()],
          truncated: boolean(),
          cursor: cursor() | nil
        }

  @doc """
  How much earlier than `Portfolixir.DeltaCursor.as_of/0` the next `since`
  lies: the fetch's 30-second deadline and the pace wait before its write,
  with room to spare (see the moduledoc).
  """
  @spec fetch_lag_seconds() :: pos_integer()
  def fetch_lag_seconds, do: @fetch_lag_seconds

  @doc "The `since` a reader passes next; see the moduledoc."
  @spec as_of() :: DateTime.t()
  def as_of, do: DateTime.add(DeltaCursor.as_of(), -@fetch_lag_seconds, :second)

  @doc """
  A name of at most 20 characters (§9) as the companion spells them
  (`clip_spelled/2`): the name itself when it fits, else its first
  characters and an ellipsis. *Why spelled, not graphemes (Sprint 28, N1
  attack AT1):* a name of one letter and 254 combining marks is one
  grapheme and 255 characters on the wire, so a grapheme count would hand
  it whole to every read that names a security or a category.
  """
  @spec short_name(String.t()) :: String.t()
  def short_name(name) when is_binary(name), do: clip_spelled(name, @short_name_max)

  defp clip(text, max) do
    if String.length(text) <= max, do: text, else: String.slice(text, 0, max - 1) <> "…"
  end

  # --- closing act, Fix-2: the spelled width (AG1, C5) ----------------------

  @list_title_max 160
  @get_title_max 160
  @get_excerpt_max 600
  @get_url_max 300

  # --- closing act, AG1 rest: news.get's 400 tokens, link included ----------
  # §9's 400 tokens as characters of the companion's text (C5: four a
  # token), less what the controller adds around the answer Reads builds:
  # `{"data":…}`, `"kind":"story"` and the excerpt's quotes over its `null`.
  @get_chars 400 * 4
  @get_envelope 40
  @domain_max 40
  @widest_integer 9_223_372_036_854_775_807
  # --- end closing act, AG1 rest ---------------------------------------------

  @doc """
  `text` cut to at most `max` characters **as the companion spells it**
  (ADR-0056 amendment of 2026-11-08, C5; ADR-0054 §4): every code point
  counts one, an invisible one (`Portfolixir.Input.Text`) counts the
  length of its `[U+XXXX]` spelling, and one the JSON text escapes (`"`,
  `\\`, a control) the length of its escape. A cut ends in an ellipsis,
  inside the width. A grapheme count would read a run of tag characters as one
  character and a soft hyphen as none, and the agent would pay eight
  characters for each. Each code point is measured on its own, which
  spells a joiner or a selector that its neighbours would leave as it is:
  never less than the companion spells, so the width is a bound.
  """
  @spec clip_spelled(String.t() | nil, pos_integer()) :: String.t() | nil
  def clip_spelled(nil, _max), do: nil

  def clip_spelled(text, max) when is_binary(text) do
    widths = Enum.map(String.codepoints(text), &{&1, spelled_width(&1)})

    if Enum.sum_by(widths, &elem(&1, 1)) <= max do
      text
    else
      widths
      |> Enum.reduce_while({[], 0}, fn {point, width}, {kept, used} ->
        if used + width <= max - 1,
          do: {:cont, {[point | kept], used + width}},
          else: {:halt, {kept, used}}
      end)
      |> elem(0)
      |> Enum.reverse()
      |> Enum.join()
      |> Kernel.<>("…")
    end
  end

  defp spelled_width(point), do: point |> Text.escape_invisible() |> json_width()

  # The characters `text` takes inside a JSON string: `"` and `\\` two, a
  # control its escape (closing act, AG1 rest). Counted in code points, as
  # the companion counts (N1 attack AT1): a grapheme count would join a
  # combining mark to the quote before it and count it as nothing.
  defp json_width(text), do: code_points(Jason.encode!(text)) - 2

  defp code_points(text), do: text |> String.codepoints() |> length()

  # The excerpt last (closing act, AG1 rest): cut to what the answer without
  # it leaves of `@get_chars`, measured as the companion spells the JSON,
  # and never past `@get_excerpt_max`. Every integer counts as the widest
  # id (a bigint's 19 digits), so the cut does not move with the ids, and
  # times encoded with microseconds and the excerpt's own `null` count more
  # than the controller sends: the measure is a bound.
  defp fit_excerpt(answer, excerpt) do
    used = answer |> Map.put(:excerpt, nil) |> widest() |> spelled_json()
    room = @get_chars - @get_envelope - used
    Map.put(answer, :excerpt, clip_spelled(excerpt, room |> min(@get_excerpt_max) |> max(1)))
  end

  defp spelled_json(answer),
    do: answer |> Jason.encode!() |> Text.escape_invisible() |> code_points()

  defp widest(%DateTime{} = at), do: at
  defp widest(%{} = map), do: Map.new(map, fn {key, value} -> {key, widest(value)} end)
  defp widest(list) when is_list(list), do: Enum.map(list, &widest/1)
  defp widest(integer) when is_integer(integer), do: @widest_integer
  defp widest(other), do: other

  # --- end closing act, Fix-2 -------------------------------------------------

  @doc "The tiers at or above `tier` (every stored tier for nil)."
  @spec tiers_from(tier() | nil) :: [tier()]
  def tiers_from(nil), do: Map.keys(@tier_rank)

  def tiers_from(tier) when is_map_key(@tier_rank, tier),
    do: for({t, rank} <- @tier_rank, rank >= @tier_rank[tier], do: t)

  # -- the list ---------------------------------------------------------------

  @doc """
  One page of `selector`'s rows (`news.list`):

    * `{:security, id}` / `{:category, id}` — the scope's stories, one row
      each: `id`, `title` (the representative's), `tier` (the story's best),
      `at` (the representative's clamped publication), `count`, `url` (the
      representative's link) and `note_ids` (every member's notes);
    * `{:cluster, id}` — the story's items;
    * `{:assignment, :unassigned | :ambiguous}` — the aggregator items no
      security, or several, claim; an ambiguous one with its `candidates`.

  An item row is `id`, `title`, `tier`, `at`, `domain`, `candidates`,
  `url` and `note_ids`. `{:error, :not_found}` when the security, category
  or story does not exist. Options: `since`, `tier_min`, `limit`, `cursor`.
  """
  @spec list(selector(), list_opts()) :: {:ok, page()} | {:error, :not_found}
  def list(selector, opts) do
    if exists?(selector), do: {:ok, page(selector, opts)}, else: {:error, :not_found}
  end

  defp exists?({:security, id}), do: Repo.exists?(from(s in Security, where: s.id == ^id))
  defp exists?({:category, id}), do: Repo.exists?(from(c in Category, where: c.id == ^id))
  defp exists?({:cluster, id}), do: Repo.exists?(from(c in Cluster, where: c.id == ^id))
  defp exists?({:assignment, _assignment}), do: true

  defp page({scope, id} = selector, opts) when scope in [:security, :category] do
    limit = Keyword.fetch!(opts, :limit)

    seen =
      from(i in Item,
        where: not is_nil(i.cluster_id),
        group_by: i.cluster_id,
        select: %{cluster_id: i.cluster_id, seen: max(i.scope_at)}
      )
      |> where_scope(selector)

    rows =
      from(c in Cluster,
        join: s in subquery(seen),
        on: s.cluster_id == c.id,
        join: r in Item,
        on: r.id == c.representative_item_id,
        where: field(c, ^scope_field(scope)) == ^id,
        where: c.best_tier in ^tiers_from(opts[:tier_min]),
        order_by: [
          desc: s.seen,
          asc: fragment(@rank_sql, c.best_tier),
          desc: r.published_at,
          asc: fragment("md5(?)", r.canonical_url),
          desc: c.id
        ],
        limit: ^(limit + 1),
        select: %{
          id: c.id,
          title: r.title,
          tier: c.best_tier,
          at: r.published_at,
          count: c.member_count,
          url: r.canonical_url,
          seen: s.seen,
          link_key: fragment("md5(?)", r.canonical_url)
        }
      )
      |> since(opts[:since], dynamic([_c, s], s.seen))
      |> after_cursor(opts[:cursor], [
        dynamic([_c, s], s.seen),
        dynamic([c], fragment(@rank_sql, c.best_tier)),
        dynamic([_c, _s, r], r.published_at),
        dynamic([_c, _s, r], fragment("md5(?)", r.canonical_url)),
        dynamic([c], c.id)
      ])
      |> Repo.all()

    {rows, truncated} = Enum.split(rows, limit)
    rows = rows |> clip_titles() |> put_story_notes()

    %{kind: :stories, rows: rows, truncated: truncated != [], cursor: cursor(rows, truncated)}
  end

  defp page(selector, opts) do
    limit = Keyword.fetch!(opts, :limit)

    rows =
      from(i in Item,
        where: i.tier in ^tiers_from(opts[:tier_min]),
        order_by: [
          desc: i.scope_at,
          asc: fragment(@rank_sql, i.tier),
          desc: i.published_at,
          asc: fragment("md5(?)", i.canonical_url),
          desc: i.id
        ],
        limit: ^(limit + 1),
        select: %{
          id: i.id,
          title: i.title,
          tier: i.tier,
          at: i.published_at,
          domain: i.domain,
          candidates: i.candidates,
          url: i.canonical_url,
          note_ids: i.note_ids,
          seen: i.scope_at,
          link_key: fragment("md5(?)", i.canonical_url)
        }
      )
      |> where_items(selector)
      |> since(opts[:since], dynamic([i], i.scope_at))
      |> after_cursor(opts[:cursor], [
        dynamic([i], i.scope_at),
        dynamic([i], fragment(@rank_sql, i.tier)),
        dynamic([i], i.published_at),
        dynamic([i], fragment("md5(?)", i.canonical_url)),
        dynamic([i], i.id)
      ])
      |> Repo.all()

    {rows, truncated} = Enum.split(rows, limit)
    rows = clip_titles(rows)

    %{kind: :items, rows: rows, truncated: truncated != [], cursor: cursor(rows, truncated)}
  end

  defp clip_titles(rows),
    do:
      Enum.map(
        rows,
        &Map.update!(&1, :title, fn title -> clip_spelled(title, @list_title_max) end)
      )

  defp scope_field(:security), do: :security_id
  defp scope_field(:category), do: :category_id

  # A story's items carry its security (or category), so the newest sight is
  # read from the scope's items only.
  defp where_scope(query, {scope, id}),
    do: where(query, [i], field(i, ^scope_field(scope)) == ^id)

  defp where_items(query, {:cluster, id}), do: where(query, [i], i.cluster_id == ^id)

  defp where_items(query, {:assignment, assignment}),
    do: where(query, [i], i.assignment == ^assignment)

  defp since(query, nil, _stamp), do: query

  defp since(query, %DateTime{} = since, stamp),
    do: where(query, ^dynamic(^stamp > type(^since, :utc_datetime_usec)))

  # The rows after the cursor in the order (scope_at desc, tier, publication
  # desc, link's key, id desc): `keys` are those five expressions.
  defp after_cursor(query, nil, _keys), do: query

  defp after_cursor(query, {seen, rank, at, link_key, after_id}, [s, t, p, l, i]) do
    last = dynamic(^i < ^after_id)
    by_link = dynamic(^l > ^link_key or (^l == ^link_key and ^last))

    by_at =
      dynamic(
        ^p < type(^at, :utc_datetime_usec) or
          (^p == type(^at, :utc_datetime_usec) and ^by_link)
      )

    by_rank = dynamic(^t > ^rank or (^t == ^rank and ^by_at))

    where(
      query,
      ^dynamic(
        ^s < type(^seen, :utc_datetime_usec) or
          (^s == type(^seen, :utc_datetime_usec) and ^by_rank)
      )
    )
  end

  defp cursor(_rows, []), do: nil

  defp cursor(rows, _more) do
    last = List.last(rows)
    {last.seen, @tier_order[last.tier], last.at, last.link_key, last.id}
  end

  defp put_story_notes([]), do: []

  defp put_story_notes(rows) do
    notes = story_notes(Enum.map(rows, & &1.id))
    Enum.map(rows, &Map.put(&1, :note_ids, Map.get(notes, &1.id, [])))
  end

  # Every note a story's members were promoted to (§8), ascending.
  defp story_notes(cluster_ids) do
    from(i in Item,
      where: i.cluster_id in ^cluster_ids and fragment("cardinality(?) > 0", i.note_ids),
      select: {i.cluster_id, i.note_ids}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {id, lists} -> {id, lists |> List.flatten() |> Enum.uniq() |> Enum.sort()} end)
  end

  # -- one story, one item ----------------------------------------------------

  @doc """
  One story (`news.get` with a `cluster_id`): its representative's title,
  link, domain, excerpt and clamped publication, the story's best tier, its
  language, its earliest first sight, its count, at most five members
  (`id`, `domain`, `tier`, `at`; the representative first, then by B3's
  order: best tier, earliest publication, smallest link), the notes of
  every member, and its security or category (`id`, short `name`).
  """
  @spec story(pos_integer()) :: {:ok, map()} | {:error, :not_found}
  def story(cluster_id) when is_integer(cluster_id) do
    case Repo.get(Cluster, cluster_id) do
      nil -> {:error, :not_found}
      cluster -> {:ok, story_of(cluster)}
    end
  end

  defp story_of(%Cluster{} = cluster) do
    representative = Repo.get!(Item, cluster.representative_item_id)

    members =
      from(i in Item,
        where: i.cluster_id == ^cluster.id,
        select: %{
          id: i.id,
          domain: i.domain,
          tier: i.tier,
          at: i.published_at,
          url: i.canonical_url
        }
      )
      |> Repo.all()
      |> Enum.sort_by(
        &{&1.id != representative.id, -@tier_rank[&1.tier], DateTime.to_unix(&1.at, :microsecond),
         &1.url}
      )
      |> Enum.take(@members_max)
      |> Enum.map(
        &(&1
          |> Map.delete(:url)
          |> Map.update!(:domain, fn d -> clip_spelled(d, @domain_max) end))
      )

    %{
      id: cluster.id,
      title: clip_spelled(representative.title, @get_title_max),
      url: clip(representative.canonical_url, @get_url_max),
      domain: clip_spelled(representative.domain, @domain_max),
      tier: cluster.best_tier,
      language: cluster.language,
      published_at: representative.published_at,
      first_seen_at: cluster.earliest_first_seen_at,
      count: cluster.member_count,
      members: members,
      note_ids: Map.get(story_notes([cluster.id]), cluster.id, []),
      security: named(Security, cluster.security_id),
      category: named(Category, cluster.category_id)
    }
    |> fit_excerpt(representative.excerpt)
  end

  @doc """
  One item (`news.get` with a `news_id`): its story, title, link, domain,
  tier, class, language, times, excerpt, assignment, candidates, status,
  notes, and its security or category (`id`, short `name`).
  """
  @spec item(pos_integer()) :: {:ok, map()} | {:error, :not_found}
  def item(item_id) when is_integer(item_id) do
    case Repo.get(Item, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        {:ok,
         %{
           id: item.id,
           story_id: item.cluster_id,
           title: clip_spelled(item.title, @get_title_max),
           url: clip(item.canonical_url, @get_url_max),
           domain: clip_spelled(item.domain, @domain_max),
           tier: item.tier,
           class: item.class,
           language: item.language,
           published_at: item.published_at,
           first_seen_at: item.first_seen_at,
           assignment: item.assignment,
           candidates: item.candidates,
           status: item.status,
           note_ids: item.note_ids,
           security: named(Security, item.security_id),
           category: named(Category, item.category_id)
         }
         |> fit_excerpt(item.excerpt)}
    end
  end

  defp named(_schema, nil), do: nil

  defp named(schema, id) do
    case Repo.one(from(r in schema, where: r.id == ^id, select: r.name)) do
      nil -> nil
      name -> %{id: id, name: short_name(name)}
    end
  end

  # -- the digest -------------------------------------------------------------

  @doc """
  The securities a digest reads (§9): with a `view_id`, those the view
  holds — a position of any portfolio in the view's scope
  (`Portfolixir.Buckets.load_global_scope/1`) whose quantity summed over
  them is not zero; without one, the news universe
  (`Portfolixir.News.Universe`: held, targeted or watched).
  `{:error, :not_found}` for a view that does not exist.
  """
  @spec digest_securities(pos_integer() | nil) :: {:ok, [pos_integer()]} | {:error, :not_found}
  def digest_securities(nil), do: {:ok, Enum.map(Universe.members(), & &1.id)}

  def digest_securities(view_id) when is_integer(view_id) do
    case Buckets.load_global_scope(view_id) do
      {:error, :view_not_found} ->
        {:error, :not_found}

      scope ->
        held =
          Portfolios.list_portfolios()
          |> Enum.flat_map(fn portfolio ->
            portfolio.id
            |> Ledger.positions_for_portfolio()
            |> Enum.filter(fn {{account_id, security_id}, _quantity} ->
              Buckets.position_in_scope?(scope, account_id, security_id)
            end)
          end)
          |> Enum.reduce(%{}, fn {{_account_id, security_id}, quantity}, acc ->
            Map.update(acc, security_id, quantity, &Decimal.add(&1, quantity))
          end)
          |> Enum.reject(fn {_security_id, quantity} -> Decimal.eq?(quantity, 0) end)
          |> Enum.map(&elem(&1, 0))
          |> Enum.sort()

        {:ok, held}
    end
  end

  @doc """
  The digest (`news.digest`, §9, §11) of `security_ids` since `since`,
  without labels and without a consumer cursor:

    * `rows` — one per security with a story new since `since` (a member
      that entered its scope strictly after it, B4, C3): `id`, short `name`, `count` (its new
      stories) and `top` (`id`, `title`, `tier`, `at`): the best tier, then
      the newest publication, then the smallest link — never an id. Rows are
      ordered by their top story the same way, then by security id. The top
      story's title is cut to 100 characters (an ellipsis marks the cut), so
      a row costs at most about 60 tokens whatever the feed wrote; the whole
      title is in `list/2` and `story/1`.
    * **Which stories count** (§7): a story with an `issuer` or `regulatory`
      member always; a story of `aggregator` items only, and a `thematic`
      story, only with `include_unlabeled: true` — the flag acts on those
      two classes and never hides a primary story.
    * `categories` — with `include_unlabeled`, the thematic stories per
      category, rows of the same shape (a category is no security).
    * `hidden` (C5, ADR-0056 amendment of 2026-11-08) — the aggregator
      and thematic stories new since `since` that `include_unlabeled:
      false` left out (0 with the flag). A security whose only new stories
      are hidden is not quiet: news only from an aggregator must not read as
      the false calm §6 exists to prevent.
    * `quiet` — the securities without a row and without a hidden story;
      `unassigned` and `ambiguous`
      — the aggregator items that became so after `since` (`scope_at`) that
      no security, or several, claim.
    * **For a view** (`view: true`, closing act): a view holds securities,
      so `categories` and `unassigned` are left out (nil), `hidden` counts
      only the securities' stories, and `ambiguous` only the items naming
      one of them among their candidates.
    * `max_rows` caps `rows` and `categories` each; `truncated` and `more`
      (the rows left out) say so.
  """
  @spec digest([pos_integer()], DateTime.t(), boolean(), pos_integer(), keyword()) :: map()
  def digest(security_ids, %DateTime{} = since, include_unlabeled, max_rows, opts \\ [])
      when is_list(security_ids) and is_boolean(include_unlabeled) and is_integer(max_rows) do
    view? = Keyword.get(opts, :view, false)

    {stories, hidden} =
      security_ids
      |> new_stories(since)
      |> Enum.reject(&(view? and is_nil(&1.security_id)))
      |> Enum.split_with(&(&1.certain or include_unlabeled))

    {by_security, by_category} = Enum.split_with(stories, &(not is_nil(&1.security_id)))

    rows = digest_rows(by_security, :security_id, Security)

    # C5: a security with only hidden stories has news; it is not quiet.
    with_news =
      (by_security ++ hidden)
      |> Enum.map(& &1.security_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    categories =
      if include_unlabeled, do: digest_rows(by_category, :category_id, Category), else: []

    {shown_rows, left_rows} = Enum.split(rows, max_rows)
    {shown_categories, left_categories} = Enum.split(categories, max_rows)
    more = length(left_rows) + length(left_categories)
    open = open_counts(since, if(view?, do: security_ids))

    %{
      rows: shown_rows,
      categories: if(include_unlabeled and not view?, do: shown_categories),
      quiet: length(security_ids) - length(with_news),
      hidden: length(hidden),
      unassigned: if(not view?, do: Map.get(open, :unassigned, 0)),
      ambiguous: Map.get(open, :ambiguous, 0),
      truncated: more > 0,
      more: if(more > 0, do: more)
    }
  end

  # Every story of the securities and every category's story with a member
  # new since `since`, each marked `certain` when it has an issuer or
  # regulatory member.
  defp new_stories(security_ids, since) do
    news =
      from(i in Item,
        where: not is_nil(i.cluster_id),
        where: i.security_id in ^security_ids or not is_nil(i.category_id),
        group_by: i.cluster_id,
        having: max(i.scope_at) > type(^since, :utc_datetime_usec),
        select: %{
          cluster_id: i.cluster_id,
          certain:
            fragment("bool_or(? = ANY(?))", i.class, type(^@certain_classes, {:array, :string}))
        }
      )

    from(c in Cluster,
      join: n in subquery(news),
      on: n.cluster_id == c.id,
      join: r in Item,
      on: r.id == c.representative_item_id,
      select: %{
        certain: n.certain,
        security_id: c.security_id,
        category_id: c.category_id,
        id: c.id,
        title: r.title,
        tier: c.best_tier,
        at: r.published_at,
        url: r.canonical_url
      }
    )
    |> Repo.all()
  end

  defp digest_rows([], _key, _schema), do: []

  defp digest_rows(stories, key, schema) do
    grouped = Enum.group_by(stories, &Map.fetch!(&1, key))
    ids = Map.keys(grouped)
    names = Map.new(Repo.all(from(r in schema, where: r.id in ^ids, select: {r.id, r.name})))

    grouped
    |> Enum.map(fn {id, group} ->
      top = Enum.min_by(group, &top_key/1)

      %{
        id: id,
        name: short_name(Map.get(names, id, "")),
        count: length(group),
        top: %{
          id: top.id,
          title: clip_spelled(top.title, @digest_title_max),
          tier: top.tier,
          at: top.at
        },
        key: {top_key(top), id}
      }
    end)
    |> Enum.sort_by(& &1.key)
    |> Enum.map(&Map.delete(&1, :key))
  end

  # The best tier, then the newest publication, then the smallest link.
  defp top_key(story),
    do: {-@tier_rank[story.tier], -DateTime.to_unix(story.at, :microsecond), story.url}

  # Without a view, every unassigned and ambiguous aggregator item; for a
  # view, the ambiguous ones naming one of its securities.
  defp open_counts(since, nil) do
    from(i in Item,
      where: i.class == :aggregator and i.assignment in [:unassigned, :ambiguous],
      where: i.scope_at > type(^since, :utc_datetime_usec),
      group_by: i.assignment,
      select: {i.assignment, count(i.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp open_counts(since, security_ids) do
    ambiguous =
      from(i in Item,
        where: i.class == :aggregator and i.assignment == :ambiguous,
        where: i.scope_at > type(^since, :utc_datetime_usec),
        where: fragment("? && ?", i.candidates, type(^security_ids, {:array, :integer}))
      )
      |> Repo.aggregate(:count)

    %{ambiguous: ambiguous}
  end
end
