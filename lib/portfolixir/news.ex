defmodule Portfolixir.News do
  @moduledoc """
  The news layer (ADR-0056): registered feeds fetched, their items matched
  to a security or a category by rule, deduplicated into stories, rated by
  a hand-kept source tier, and served compactly. No model runs here, and
  nothing stored is an article: excerpts are capped at 600 characters and
  items are kept 90 days (§12).

  The tables and their rules are `Portfolixir.News.Feed`,
  `Portfolixir.News.Source`, `Portfolixir.News.Item`,
  `Portfolixir.News.Cluster` and `Portfolixir.News.FeedDay` (where each
  rolling count of §6 is read from). Later stories of the sprint fill this
  context: the fetcher, the matcher, the clustering, retention and health,
  the reads and the writes.

  ## What a security merge does with news rows (ADR-0050 §9, §14)

  `reassign_security/3` moves every news row of a merge's source onto its
  target, inside the merge's transaction, before the source is deleted:

    * the source's feeds are re-bound to the target, one journaled update
      each (`resource_type: "news_feed"`; feeds are master data, B7);
    * its stories and items move without a journal entry (B7: a staging
      area written by a system job); a story carries its items' security
      with it (the items' composite key follows it);
    * an ambiguous item that listed the source lists the target instead;
      one that listed both now has one candidate, so it is `assigned` to
      the target, out of any story — exactly one hit assigns (§2).

  Then the target's stories are reclustered in full for every language
  moved, in the same transaction (closing act, ORD2): stories of the source
  and the target that are one event are one story when the merge commits,
  and each moved item enters the target's scope at the merge (`scope_at`,
  C3), its first sight unchanged.
  """
  import Ecto.Query

  require Logger

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Journal
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.DigestConsumer
  alias Portfolixir.News.DigestCursor
  alias Portfolixir.News.Dossier
  alias Portfolixir.News.Feed
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Fetcher
  alias Portfolixir.News.Health
  alias Portfolixir.News.Item
  alias Portfolixir.News.Label
  alias Portfolixir.News.Labels
  alias Portfolixir.News.Matcher
  alias Portfolixir.News.Promotion
  alias Portfolixir.News.Scheduler
  alias Portfolixir.News.Source
  alias Portfolixir.News.Stories
  alias Portfolixir.News.Universe
  alias Portfolixir.Repo

  @type moved :: %{
          feeds: [pos_integer()],
          stories: non_neg_integer(),
          items: non_neg_integer(),
          candidates: non_neg_integer()
        }

  @doc """
  Moves every news row of security `source_id` onto `target_id`, for a
  security merge holding both rows' locks. See the moduledoc.
  """
  @spec reassign_security(Actor.t(), pos_integer(), pos_integer()) ::
          {:ok, moved()}
          | {:error, :raced | {:write_refused, String.t(), integer(), Ecto.Changeset.t()}}
  def reassign_security(%Actor{} = actor, source_id, target_id)
      when is_integer(source_id) and is_integer(target_id) and source_id != target_id do
    feeds = Repo.all(from(f in Feed, where: f.security_id == ^source_id, order_by: f.id))

    with :ok <- reassign_feeds(actor, feeds, target_id) do
      languages = enter_target_scope(source_id, target_id, now())
      # Counted first: a story's items follow it through their composite key,
      # so the items' own update below reaches only those outside a story.
      items = Repo.aggregate(from(i in Item, where: i.security_id == ^source_id), :count)

      {stories, _} =
        Repo.update_all(from(c in Cluster, where: c.security_id == ^source_id),
          set: [security_id: target_id, updated_at: now()]
        )

      Repo.update_all(from(i in Item, where: i.security_id == ^source_id),
        set: [security_id: target_id, updated_at: now()]
      )

      candidates = collapse_candidates(source_id, target_id)

      with :ok <- recluster_merged(target_id, languages, now()) do
        {:ok,
         %{
           feeds: Enum.map(feeds, & &1.id),
           stories: stories,
           items: items,
           candidates: candidates
         }}
      end
    end
  end

  defp reassign_feeds(actor, feeds, target_id) do
    Enum.reduce_while(feeds, :ok, fn feed, :ok ->
      Multi.new()
      |> Multi.update(:feed, fn changes ->
        changes |> Journal.locked_row() |> Ecto.Changeset.change(security_id: target_id)
      end)
      |> Journal.record(actor,
        resource_type: "news_feed",
        operation: :update,
        source: :feed,
        before: feed
      )
      |> Repo.transaction()
      |> case do
        {:ok, _changes} ->
          {:cont, :ok}

        {:error, :feed, changeset, _changes} ->
          {:halt, {:error, {:write_refused, "news_feed", feed.id, changeset}}}

        {:error, _step, _reason, _changes} ->
          {:halt, {:error, :raced}}
      end
    end)
  end

  # §2: exactly one hit assigns. An item that listed both securities now has
  # one; any other lists the target where it listed the source.
  defp collapse_candidates(source_id, target_id) do
    {collapsed, _} =
      Repo.update_all(
        from(i in Item,
          where:
            i.assignment == :ambiguous and ^source_id in i.candidates and
              ^target_id in i.candidates and fragment("cardinality(?) = 2", i.candidates)
        ),
        set: [assignment: :assigned, security_id: target_id, candidates: [], updated_at: now()]
      )

    {listed, _} =
      Repo.update_all(
        from(i in Item,
          where: ^source_id in i.candidates,
          update: [
            set: [
              candidates:
                fragment(
                  "ARRAY(SELECT DISTINCT c FROM unnest(array_replace(?, ?, ?)) AS c ORDER BY c)",
                  i.candidates,
                  ^source_id,
                  ^target_id
                ),
              updated_at: ^now()
            ]
          ]
        ),
        []
      )

    collapsed + listed
  end

  defp now, do: DateTime.utc_now()

  # --- N4 ---

  @rematch_days 7
  @open_assignments [:unassigned, :ambiguous]

  @type assigned_counts :: %{
          assigned: non_neg_integer(),
          unassigned: non_neg_integer(),
          ambiguous: non_neg_integer()
        }

  @doc """
  Matches aggregator items against the universe (ADR-0056 §2) and writes
  each one's `assignment`, `security_id` and `candidates`: one security
  named is `assigned` to it, none `unassigned`, several `ambiguous` with the
  candidates sorted. Returns the count of each outcome over the items
  matched.

  **What is matched:** the item's **title**, and not its excerpt. A title
  names the item's subject; an aggregator's excerpt often lists other
  headlines and their publishers, so matching it would file an item under
  every company its neighbours name. The title is split into sentences for
  the context words (`Portfolixir.News.Matcher`).

  **Which items:** only `aggregator` items that are `unassigned` or
  `ambiguous`; any other id is skipped and left exactly as it is. An
  `issuer`, `regulatory` or `thematic` item is bound by construction to its
  feed's security or category (§2), and the matcher never moves it. An
  assigned aggregator item keeps its assignment (it may sit in a story,
  whose items belong to the story's security, and a later hand assignment
  must not be undone by a machine); an unassigned or ambiguous item is in
  no story (`Portfolixir.News.Item`), so writing one never breaks a story's
  key.

  **A security that vanished:** `candidates` carries no foreign key, so an
  id may name a security deleted since. The matched securities are locked
  `FOR KEY SHARE` in the write's transaction and any that no longer exist
  are dropped before the outcome is decided; an item is never assigned to,
  or listed with, a security that is gone.

  **Stories follow** (B3): once the outcomes are written, every item this
  call assigned is folded into the stories of its security and language
  (`Portfolixir.News.Stories.recluster/4` at `now:`, the server's clock,
  default now), each scope and language once. An item it leaves
  `unassigned` or `ambiguous` sits in no story. A failed recluster is
  logged and leaves the item in no story; the next recluster of its scope
  reads it as a seed.

  **One at a time, with the aliases of the moment** (closing act, ORD5):
  every call — the ingest's match and an identity change's re-match — runs
  under one advisory lock, and compiles the universe only after it has
  locked its items. An alias change committed before that point is matched
  with; its re-match, waiting on the lock, reads what this call wrote. No
  call writes an outcome read from aliases older than a re-match that
  already ran, so no index is passed in.

  Items are a staging area written by a system job (B7), so nothing here is
  journaled.
  """
  @spec assign_aggregator_items([Item.t() | pos_integer()], keyword()) ::
          {:ok, assigned_counts()}
  def assign_aggregator_items(items_or_ids, opts \\ []) when is_list(items_or_ids) do
    ids = items_or_ids |> Enum.map(&item_id/1) |> Enum.uniq()

    if ids == [] do
      {:ok, %{assigned: 0, unassigned: 0, ambiguous: 0}}
    else
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      {:ok, {counts, scopes}} = Repo.transaction(fn -> assign_locked(ids, now) end)
      Enum.each(scopes, fn {scope, language} -> recluster(scope, language, now) end)
      {:ok, counts}
    end
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

  @doc """
  Re-matches the `unassigned` and `ambiguous` aggregator items first seen
  within the 7 days before `now` (ADR-0056 §2), by `first_seen_at` (the
  server's clock, B4). Called after a security's news identity changes
  (`Portfolixir.Catalog`); an item older than the window keeps what it has.
  """
  @spec rematch_recent(DateTime.t()) :: {:ok, assigned_counts()}
  def rematch_recent(%DateTime{} = now) do
    since = DateTime.add(now, -@rematch_days * 86_400, :second)

    from(i in Item,
      where:
        i.class == ^:aggregator and i.assignment in ^@open_assignments and
          i.first_seen_at >= ^since,
      order_by: i.id,
      select: i.id
    )
    |> Repo.all()
    |> assign_aggregator_items(now: now)
  end

  defp item_id(%Item{id: id}), do: id
  defp item_id(id) when is_integer(id), do: id

  # The matcher's advisory lock (ORD5), distinct from the app's others: every
  # match and re-match runs under it, one at a time.
  @matcher_lock 727_227_006

  defp assign_locked(ids, now) do
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [@matcher_lock])

    items =
      Repo.all(
        from(i in Item,
          where:
            i.id in ^ids and i.class == ^:aggregator and i.assignment in ^@open_assignments and
              is_nil(i.cluster_id),
          order_by: i.id,
          lock: "FOR UPDATE"
        )
      )

    # ORD5: compiled after the items are locked, so the aliases read are
    # those committed by then; an identity change committed earlier has had
    # its re-match, which this match can no longer overwrite.
    index = Universe.aggregator_index()
    matched = Enum.map(items, &{&1, Matcher.matches(&1.title, index)})
    existing = existing_securities(matched)

    initial = {%{assigned: 0, unassigned: 0, ambiguous: 0}, MapSet.new()}

    Enum.reduce(matched, initial, fn {item, hits}, {counts, scopes} ->
      outcome = hits |> Enum.filter(&MapSet.member?(existing, &1)) |> Matcher.outcome()
      write_outcome(item, outcome, now)
      {Map.update!(counts, outcome_name(outcome), &(&1 + 1)), scope_of(outcome, item, scopes)}
    end)
  end

  # The scope and language whose stories an assignment changes.
  defp scope_of({:assigned, id}, item, scopes),
    do: MapSet.put(scopes, {{:security, id}, item.language})

  defp scope_of(_outcome, _item, scopes), do: scopes

  defp existing_securities(matched) do
    case matched |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq() do
      [] ->
        MapSet.new()

      ids ->
        from(s in Security, where: s.id in ^ids, lock: "FOR KEY SHARE", select: s.id)
        |> Repo.all()
        |> MapSet.new()
    end
  end

  defp write_outcome(item, outcome, now) do
    {assignment, security_id, candidates} =
      case outcome do
        {:assigned, id} -> {:assigned, id, []}
        :unassigned -> {:unassigned, nil, []}
        {:ambiguous, ids} -> {:ambiguous, nil, ids}
      end

    unless {item.assignment, item.security_id, item.candidates} ==
             {assignment, security_id, candidates} do
      Repo.update_all(from(i in Item, where: i.id == ^item.id),
        set: [
          assignment: assignment,
          security_id: security_id,
          candidates: candidates,
          scope_at: scope_at(item, {assignment, security_id, candidates}, now),
          updated_at: now()
        ]
      )
    end
  end

  # C3: an item that enters another scope (assigned to a security, or moved
  # between the unassigned and ambiguous remainders) enters it now, never
  # before its first sight; one whose scope stays keeps its time. An
  # ambiguous item whose candidates change enters the remainder of each new
  # one, which a view's digest counts (closing act, AT8), so it enters now
  # too.
  defp scope_at(
         %Item{assignment: assignment, security_id: id, candidates: candidates} = item,
         {assignment, id, candidates},
         _now
       ),
       do: item.scope_at

  defp scope_at(%Item{first_seen_at: first_seen_at}, _scope, now),
    do: Enum.max([first_seen_at, now], DateTime)

  defp outcome_name({:assigned, _id}), do: :assigned
  defp outcome_name(:unassigned), do: :unassigned
  defp outcome_name({:ambiguous, _ids}), do: :ambiguous

  # --- N3 ---------------------------------------------------------------------
  # The fetcher's on-demand entries (ADR-0056 §5): the scheduler's run, for the
  # API and the agent. See `Portfolixir.News.Scheduler`.

  @doc """
  Fetches every enabled feed due at the server's clock `now`, each in its
  own task; `[{feed_id, {:ok, summary} | {:error, code}}]`. Options go to
  `Portfolixir.News.Scheduler.run_due/2`.
  """
  @spec fetch_due(DateTime.t(), keyword()) :: [{pos_integer(), Scheduler.result()}]
  def fetch_due(%DateTime{} = now, opts \\ []), do: Scheduler.run_due(now, opts)

  @doc """
  Fetches the enabled feed `feed_id` now, due or not: `{:ok, summary}`,
  `{:error, code}` as the fetch recorded it, or `{:error, :not_found}` /
  `{:error, :disabled}`.
  """
  @spec fetch_now(integer(), keyword()) ::
          Scheduler.result() | {:error, :not_found | :disabled}
  def fetch_now(feed_id, opts \\ []) when is_integer(feed_id),
    do: Scheduler.run_one(feed_id, opts)

  # --- end N3 -----------------------------------------------------------------

  # --- N8 ---------------------------------------------------------------------
  # The upkeep writes (ADR-0056 §9, B1, B2, B7): a feed registered, changed or
  # removed, each journaled as `news_feed` under the writer's actor. A source's
  # tier is `Portfolixir.News.Sources.put_source/4`; a security's news identity
  # is `Portfolixir.Catalog.update_security/3`.

  @feed_class_kept "cannot change while the feed has stored items: their class is the feed's"

  @doc """
  Registers a feed, or changes one, on behalf of `actor` (`news.feeds_put`).

  **Which feed:** with `id:` that feed (`{:error, :not_found}` when none);
  without, the feed registered under the URL in `attrs`, else a new one. On
  a stored feed a key not in `attrs` keeps its value. `attrs` is what
  `Portfolixir.News.Feed.changeset/2` casts: class, url, security_id,
  category_id, enabled, interval_minutes, language.

  **The URL, at once (B2):** a URL new to the feed — on a create, or a
  changed URL — passes `Portfolixir.News.Fetcher.check_url/2` with name
  resolution before anything is written; a refusal is an error on `url`
  naming its code (`url_not_allowed:private_address`, ...). An update that
  keeps the URL is not checked here, so a feed whose name has since turned
  private can still be disabled; the fetcher checks it before every fetch.
  Options go to the check (a test's `:resolver`).

  **The class of a feed with stored items does not change** (their class is
  the feed's, a key of the database): an error on `class`. **Nor do its
  binding and its language** (closing act, COR1: the items carry them): an
  error on `security_id`, `category_id` or `language`, checked under the
  feed's row lock, which an ingest takes too.

  Answers `{:ok, :created | :updated, feed}`; an update that changes nothing
  records no entry.
  """
  @spec put_feed(Actor.t(), map(), keyword()) ::
          {:ok, :created | :updated, Feed.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def put_feed(%Actor{} = actor, attrs, opts \\ []) when is_map(attrs) do
    {id, check_opts} = Keyword.pop(opts, :id)

    with {:ok, prior} <- prior_feed(id, attrs) do
      changeset =
        (prior || %Feed{})
        |> feed_changeset(attrs)
        |> check_feed_url(prior, check_opts)

      cond do
        not changeset.valid? -> {:error, %{changeset | action: :insert}}
        is_nil(prior) -> insert_feed(actor, changeset)
        true -> update_feed(actor, prior, attrs)
      end
    end
  end

  defp prior_feed(nil, attrs) do
    case attr(attrs, :url) do
      url when is_binary(url) -> {:ok, Repo.get_by(Feed, url: String.trim(url))}
      _none -> {:ok, nil}
    end
  end

  defp prior_feed(id, _attrs) when is_integer(id) do
    case Repo.get(Feed, id) do
      nil -> {:error, :not_found}
      feed -> {:ok, feed}
    end
  end

  defp attr(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp feed_changeset(feed, attrs) do
    feed
    |> Feed.changeset(attrs)
    |> Ecto.Changeset.foreign_key_constraint(:class,
      name: :news_items_feed_class_fkey,
      message: @feed_class_kept
    )
  end

  defp check_feed_url(changeset, prior, opts) do
    url = Ecto.Changeset.get_field(changeset, :url)

    cond do
      Keyword.has_key?(changeset.errors, :url) or not is_binary(url) -> changeset
      prior && prior.url == url -> changeset
      true -> refuse_url(changeset, Fetcher.check_url(url, opts))
    end
  end

  defp refuse_url(changeset, :ok), do: changeset

  defp refuse_url(changeset, {:error, {:url_not_allowed, reason}}),
    do:
      Ecto.Changeset.add_error(
        changeset,
        :url,
        "is not allowed (url_not_allowed:#{reason}): #{url_refusal(reason)}"
      )

  defp url_refusal(:private_address),
    do: "the name resolves to a private, loopback, link-local or reserved address"

  defp url_refusal(:unresolvable), do: "the name does not resolve"
  defp url_refusal(:scheme), do: "only https is fetched"
  defp url_refusal(:userinfo), do: "a user name or password in the URL is refused"
  defp url_refusal(:host), do: "the URL names no host that can be fetched"
  defp url_refusal(:host_not_allowed), do: "the host is not allowed"

  defp insert_feed(actor, changeset) do
    Multi.new()
    |> Multi.insert(:feed, changeset)
    |> Journal.record(actor, resource_type: "news_feed", operation: :create, source: :feed)
    |> Repo.transaction()
    |> feed_written(:created)
  end

  defp update_feed(actor, prior, attrs) do
    Multi.new()
    |> Multi.update(:feed, &(&1 |> Journal.locked_row() |> feed_changeset(attrs) |> keep_fed()))
    |> Journal.record(actor,
      resource_type: "news_feed",
      operation: :update,
      source: :feed,
      before: prior
    )
    |> Repo.transaction()
    |> feed_written(:updated)
  end

  defp feed_written({:ok, %{feed: feed}}, written), do: {:ok, written, feed}

  defp feed_written({:error, {:journal_lock, _}, :not_found, _changes}, _),
    do: {:error, :not_found}

  defp feed_written({:error, :feed, changeset, _changes}, _written), do: {:error, changeset}

  @doc """
  Removes the feed `feed_id` on behalf of `actor` (`news.feeds_delete`),
  journaled as a `news_feed` delete.

  Its items stay (§12): each is detached (`feed_id` null, nothing else
  changed), so it ages out by retention and a promoted one stays for good.
  Its day counters, its record of the day's drops and retention's
  tombstones of its items go with it. Neither is journaled (B7). Answers
  `{:ok, %{feed: feed, items_detached: n}}` or `{:error, :not_found}`.
  """
  @spec delete_feed(Actor.t(), pos_integer()) ::
          {:ok, %{feed: Feed.t(), items_detached: non_neg_integer()}} | {:error, :not_found}
  def delete_feed(%Actor{} = actor, feed_id) when is_integer(feed_id) do
    case Repo.get(Feed, feed_id) do
      nil ->
        {:error, :not_found}

      feed ->
        Multi.new()
        |> Multi.run(:detached, fn repo, _changes ->
          {detached, _} =
            repo.update_all(from(i in Item, where: i.feed_id == ^feed.id),
              set: [feed_id: nil, updated_at: now()]
            )

          {:ok, detached}
        end)
        |> Multi.delete_all(:days, from(d in FeedDay, where: d.feed_id == ^feed.id))
        |> Multi.delete_all(
          :tombstones,
          from(t in "news_item_tombstones", where: t.feed_id == ^feed.id)
        )
        |> Multi.delete_all(:drops, from(d in "news_feed_drops", where: d.feed_id == ^feed.id))
        |> Multi.delete(:feed, &Journal.locked_row/1)
        |> Journal.record(actor,
          resource_type: "news_feed",
          operation: :delete,
          source: :feed,
          before: feed
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{feed: deleted, detached: detached}} ->
            {:ok, %{feed: deleted, items_detached: detached}}

          {:error, {:journal_lock, _}, :not_found, _changes} ->
            {:error, :not_found}
        end
    end
  end

  # --- end N8 -----------------------------------------------------------------

  # --- closing act, Fix-1 -----------------------------------------------------

  @doc """
  Drops the security `security_id`, being deleted, from every item's
  candidates, inside the delete's transaction (closing act, EDGE2;
  `Portfolixir.Lifecycle.Delete`). An item left with one candidate is
  `assigned` to it, out of any story, as a merge's collapse assigns it
  (§2: exactly one hit assigns), and folded into that security's stories
  of its language (B3); one left with more stays `ambiguous` between them.
  Answers the number of items changed.
  """
  @spec forget_security(pos_integer(), DateTime.t()) :: {:ok, non_neg_integer()}
  def forget_security(security_id, %DateTime{} = now \\ DateTime.utc_now())
      when is_integer(security_id) do
    listing = from(i in Item, where: ^security_id in i.candidates)

    # C3: an item assigned here enters its security's scope now, never
    # before its first sight (`scope_at`).
    {assigned, collapsed} =
      Repo.update_all(
        from(i in listing,
          where: i.assignment == :ambiguous and fragment("cardinality(?) = 2", i.candidates),
          select: {i.security_id, i.language},
          update: [
            set: [
              assignment: :assigned,
              security_id: fragment("(array_remove(?, ?))[1]", i.candidates, ^security_id),
              candidates: ^[],
              cluster_id: nil,
              scope_at: fragment("GREATEST(?, ?)", i.first_seen_at, ^now),
              updated_at: ^now
            ]
          ]
        ),
        []
      )

    {listed, _} =
      Repo.update_all(
        from(i in listing,
          update: [
            set: [
              candidates: fragment("array_remove(?, ?)", i.candidates, ^security_id),
              updated_at: ^now
            ]
          ]
        ),
        []
      )

    collapsed
    |> Enum.uniq()
    |> Enum.each(fn {target_id, language} ->
      case Stories.recluster({:security, target_id}, language, now) do
        {:ok, _summary} ->
          :ok

        {:error, changeset} ->
          Logger.warning(
            "news stories of security #{target_id} (#{language}) not written after a " <>
              "candidate's delete: #{inspect(changeset.errors)}"
          )
      end
    end)

    {:ok, assigned + listed}
  end

  @feed_fed_kept "cannot change while the feed has stored items: they carry it"

  # COR1: a feed's items carry its security, category and language; while it
  # has any, none of them changes. Read under the feed's row lock
  # (`Journal.locked_row/1`), which an ingest takes before it inserts.
  defp keep_fed(%Ecto.Changeset{data: %Feed{id: id}} = changeset) do
    changed =
      Enum.filter([:security_id, :category_id, :language], &Map.has_key?(changeset.changes, &1))

    if changed != [] and Repo.exists?(from(i in Item, where: i.feed_id == ^id)) do
      Enum.reduce(changed, changeset, &Ecto.Changeset.add_error(&2, &1, @feed_fed_kept))
    else
      changeset
    end
  end

  # --- closing act, Fix-2 -----------------------------------------------------

  # C3 (ADR-0056 amendment of 2026-11-08): a merge moves the source's items
  # into the target's scope, and an item ambiguous between the two is left
  # with one candidate: each enters the target's scope now (`scope_at`),
  # never before its first sight. Called before the moves, while the items
  # still name the source.
  # Answers the languages of the items moved.
  defp enter_target_scope(source_id, target_id, now) do
    {_count, languages} =
      Repo.update_all(
        from(i in Item,
          where:
            i.security_id == ^source_id or
              (i.assignment == :ambiguous and ^source_id in i.candidates and
                 ^target_id in i.candidates and fragment("cardinality(?) = 2", i.candidates)),
          select: i.language,
          update: [set: [scope_at: fragment("GREATEST(?, ?)", i.first_seen_at, ^now)]]
        ),
        []
      )

    languages |> Enum.uniq() |> Enum.sort()
  end

  # ORD2 (B3): the source's stories and items moved onto the target keep
  # their stories; one event reported for both securities would stay two
  # stories until a full recluster. So the target is reclustered in full
  # for each language moved, inside the merge's transaction and under the
  # scope's lock (`Portfolixir.News.Stories.recluster/4` takes it and holds
  # it to the merge's commit); a refusal fails the merge.
  defp recluster_merged(target_id, languages, now) do
    Enum.reduce_while(languages, :ok, fn language, :ok ->
      case Stories.recluster({:security, target_id}, language, now, full: true) do
        {:ok, _summary} ->
          {:cont, :ok}

        {:error, changeset} ->
          {:halt, {:error, {:write_refused, "news_cluster", target_id, changeset}}}
      end
    end)
  end

  # --- end closing act, Fix-2 -------------------------------------------------

  # --- N6 ---------------------------------------------------------------------

  @doc """
  The news layer's health at the server's clock `now` (ADR-0056 §6, A3):
  each feed's freshness and 30-day counts, and the day's unassigned, ambiguous,
  dropped and blocked counts. See `Portfolixir.News.Health`.
  """
  @spec health(DateTime.t()) :: Health.t()
  def health(%DateTime{} = now), do: Health.report(now)

  # --- end N6 -----------------------------------------------------------------

  # Sprint 28, Lane N (ADR-0056 §7 to §10): each story adds its public
  # functions between its own markers, so stories built side by side merge
  # without touching each other's lines (plan D-8).

  # --- S28 N1 begin ---
  # The labels of §7, written from outside by a model through its own named
  # token (`Portfolixir.News.Labels`).

  @doc """
  Stores a label on behalf of `actor` (`news.label_put`, ADR-0056 §7): a
  closed write of exactly §7's fields, idempotent per `(cluster_id, model,
  prompt_version)` — a second put of the triple replaces the label in place
  — and journaled under the actor. See `Portfolixir.News.Labels.put/2`.
  """
  @spec put_label(Actor.t(), map()) ::
          {:ok, Labels.written(), Label.t()}
          | {:error, %{String.t() => [String.t()]}}
          | {:error, Ecto.Changeset.t()}
  def put_label(%Actor{} = actor, attrs) when is_map(attrs), do: Labels.put(actor, attrs)

  @doc """
  The labeller's read (`news.unlabeled`, ADR-0056 §7): at most `limit`
  stories without a label of `prompt_version`, with the universe and the
  rows' theses split into numbered clauses. See
  `Portfolixir.News.Labels.unlabeled/2`.
  """
  @spec unlabeled(String.t(), pos_integer()) :: Labels.unlabeled()
  def unlabeled(prompt_version, limit), do: Labels.unlabeled(prompt_version, limit)

  # --- S28 N1 end ---

  # --- S28 N2 begin ---
  # The labels in the agent's reads (§7, §9): one prompt version a read.

  @doc """
  The prompt version the news reads use when the caller names none: the
  version of the label created last, `nil` without labels. See
  `Portfolixir.News.Labels.newest_prompt_version/0`.
  """
  @spec newest_prompt_version() :: String.t() | nil
  def newest_prompt_version, do: Labels.newest_prompt_version()

  # --- S28 N2 end ---

  # --- S28 N3 begin ---
  # The digest's consumer cursor (§9): at least once, the confirmed position
  # kept per consumer (`Portfolixir.News.DigestCursor`).

  @doc """
  The digest consumer `name` after confirming `ack_cursor` (`nil` for no
  confirmation) at the server's clock `now`, created at its first call;
  `key` signs and checks the cursors (at least 32 bytes, the caller's):
  `{:ok, consumer}` with its confirmed position, `{:error, :not_issued}`
  for a cursor the server did not issue to `name`, `{:error, {:cap, n}}`
  for a new consumer beyond the cap. See `Portfolixir.News.DigestCursor`.
  """
  @spec digest_consumer(String.t(), String.t() | nil, DateTime.t(), binary()) ::
          {:ok, DigestConsumer.t()} | {:error, :not_issued | {:cap, pos_integer()}}
  def digest_consumer(name, ack_cursor, %DateTime{} = now, key),
    do: DigestCursor.consumer(name, ack_cursor, now, key)

  @doc "The cursor a digest of `consumer` answers, at `position`, signed with `key`."
  @spec issue_digest_cursor(DigestConsumer.t(), DateTime.t(), binary()) :: String.t()
  def issue_digest_cursor(%DigestConsumer{} = consumer, %DateTime{} = position, key),
    do: DigestCursor.issue(consumer, position, key)

  # --- closing act, AT5 begin ---

  @doc """
  The page token of `consumer`'s truncated digest, read until `until`, after
  the rows of the page keys `keys`, signed with `key`. See
  `Portfolixir.News.DigestCursor.issue_page/4`.
  """
  @spec issue_digest_page(DigestConsumer.t(), DateTime.t(), [String.t()], binary()) ::
          String.t()
  def issue_digest_page(%DigestConsumer{} = consumer, %DateTime{} = until, keys, key),
    do: DigestCursor.issue_page(consumer, until, keys, key)

  @doc "The page token `token` checked for `consumer`; see `DigestCursor.verify_page/3`."
  @spec verify_digest_page(DigestConsumer.t(), String.t(), binary()) ::
          {:ok, %{position: DateTime.t(), until: DateTime.t(), keys: [String.t()]}} | :error
  def verify_digest_page(%DigestConsumer{} = consumer, token, key),
    do: DigestCursor.verify_page(consumer, token, key)

  # --- closing act, AT5 end ---

  # --- S28 N3 end ---

  # --- S28 N4 begin ---
  # news.assign (§9): an aggregator item assigned by hand, or given back to
  # the matcher.

  # AT4: a security the first step did not hold (the item moved between the
  # unlocked read and its lock) rolls the attempt back, releasing every
  # lock, and the next attempt holds it in order.
  @assign_attempts 3

  @doc """
  Assigns the aggregator item `item_id` to the security `security_id` by
  hand, or with `nil` gives it back to the matcher, on behalf of `actor`
  (`news.assign`, ADR-0056 §9). `now:` is the server's clock.

  **What it moves.** The item leaves the story it is in and its scope; it
  enters the target's scope at `now` (`scope_at`, C3, never before its
  first sight), read once the write holds its locks (closing act, AT8), so
  a write that waited stamps the time it wrote, assigned with no
  candidates. **`nil` is the matcher's
  answer now** (§2: the item's title against the universe and its aliases
  of the moment): one security named assigns it there, none leaves it
  `unassigned`, several `ambiguous` with them, out of any story. *Why not
  "the assignment before the hand's":* nothing stores who assigned an item,
  and the matcher's answer is a function of the title and the aliases, so
  undoing needs no memory of it; the journal keeps every before-image.

  **Stories follow in the same transaction** (ORD2's rule, as a merge
  does): the scope the item left and the scope it entered are reclustered
  in full, each under its advisory lock, so the story it left is recounted
  (and splits if the item held it together) and the item joins the
  target's story of the same event before the write commits. A refusal
  of the recluster fails the assignment.

  **Only an aggregator item.** An issuer or regulatory item is its feed's
  security's, a thematic item its feed's category's, by construction
  (§2); assigning one answers an error on `news_id`. **Never a kept
  item** (closing act, NL2): one `promoted` or naming a note in
  `note_ids` is a research note's source and stays with its security
  (§8, §12), so it answers an error on `news_id` too. A security that does
  not exist answers an error on `security_id` (it is held `FOR KEY SHARE`
  until the write commits, so it cannot be deleted beneath it).

  **One at a time with the matcher, and on the item as it is** (plan D-8,
  the order lens; closing act, AT4): the write first holds `FOR KEY SHARE`,
  in id order, every security it may touch — the item's own, its
  candidates, and the target (or, for `nil`, the securities the matcher
  names now) — **before** any other lock, as a security merge takes both
  securities `FOR UPDATE` before its news rows and may re-match under the
  matcher's lock while it holds them (`Portfolixir.LockTable`, row 21).
  Then the matcher's advisory lock (ORD5), so a match or a re-match never
  interleaves with it; then the lock of the scope the item is in, then the
  item's row lock, and it acts on the item as read under that lock. An
  item a merge or a candidate's delete moved meanwhile is acted on where it
  now is (its scope locked too); should it now name a security the first
  step did not hold, the transaction is rolled back and run again (at most
  three times, then an error on `news_id`), never a security locked out of
  order. One retention removed answers `{:error, :not_found}`. The scopes
  are locked before the item, as retention locks them
  (`Portfolixir.News.Stories.remove/5`), so the two never wait on each
  other in a cycle.

  **Journaled** (B7's exception for a hand write): one `news_item` update
  under `actor`, with the item before and after; an assignment the item
  already has writes and records nothing. Answers `{:ok, item}`,
  `{:error, :not_found}`, `{:error, %{field => [message]}}` or
  `{:error, {:write_refused, changeset}}`.
  """
  @spec assign_item(Actor.t(), pos_integer(), pos_integer() | nil, keyword()) ::
          {:ok, Item.t()}
          | {:error, :not_found}
          | {:error, %{String.t() => [String.t()]}}
          | {:error, {:write_refused, Ecto.Changeset.t()}}
  def assign_item(%Actor{} = actor, item_id, security_id, opts \\ [])
      when is_integer(item_id) and (is_integer(security_id) or is_nil(security_id)) do
    assign_attempt(actor, item_id, security_id, opts, @assign_attempts)
  end

  defp assign_attempt(_actor, _item_id, _security_id, _opts, 0) do
    {:error,
     %{"news_id" => ["moved while it was being assigned, three times running: try again"]}}
  end

  defp assign_attempt(actor, item_id, security_id, opts, attempts) do
    Multi.new()
    |> Multi.run(:held, fn _repo, _changes -> hold_for_assign(item_id, security_id) end)
    |> Multi.run(:prior, fn _repo, %{held: {read, held}} -> lock_for_assign(read, held) end)
    |> Multi.run(:item, fn _repo, %{prior: prior, held: {_read, held}} ->
      # AT8: the clock is read once every lock is held, so an item that
      # waited enters its scope after what it waited for, never before.
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      assign_locked(prior, security_id, held, now)
    end)
    |> Journal.record(actor,
      resource_type: "news_item",
      operation: :update,
      source: :item,
      before_step: :prior
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{item: item}} ->
        {:ok, item}

      {:error, step, :not_found, _changes} when step in [:held, :prior] ->
        {:error, :not_found}

      {:error, step, :moved, _changes} when step in [:prior, :item] ->
        assign_attempt(actor, item_id, security_id, opts, attempts - 1)

      {:error, :item, {:refused, errors}, _changes} ->
        {:error, errors}

      {:error, :item, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, {:write_refused, changeset}}
    end
  end

  # AT4 (Portfolixir.LockTable, row 21): the securities first, in id order,
  # off an unlocked read of the item; then the matcher's lock, the scope and
  # the item, as the moduledoc says.
  defp hold_for_assign(item_id, security_id) do
    case Repo.get(Item, item_id) do
      nil -> {:error, :not_found}
      read -> {:ok, {read, hold_securities(securities_touched(read, security_id))}}
    end
  end

  defp lock_for_assign(read, held) do
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [@matcher_lock])
    :ok = lock_scope_of(read)

    case lock_item(read.id) do
      nil ->
        {:error, :not_found}

      %Item{} = locked ->
        # A merge or a candidate's delete may have moved it between the
        # read and the lock (neither takes the matcher's lock): its scope
        # now is locked too, before anything is written.
        if story_scope(locked) != story_scope(read), do: lock_scope_of(locked)
        if held?(securities_of(locked), held), do: {:ok, locked}, else: {:error, :moved}
    end
  end

  defp held?(ids, held), do: MapSet.subset?(MapSet.new(ids), held)

  # The securities an assignment may touch: the item's own and its
  # candidates, and the target, or for `nil` the matcher's names now.
  defp securities_touched(item, security_id) when is_integer(security_id),
    do: [security_id | securities_of(item)]

  defp securities_touched(item, nil),
    do: Matcher.matches(item.title, Universe.aggregator_index()) ++ securities_of(item)

  defp securities_of(%Item{security_id: id, candidates: candidates}),
    do: Enum.reject([id | candidates || []], &is_nil/1)

  # FOR KEY SHARE, in id order (one statement, rows locked as returned):
  # the ids that exist, held to commit.
  defp hold_securities(ids) do
    ids = ids |> Enum.uniq() |> Enum.sort()

    from(s in Security,
      where: s.id in ^ids,
      order_by: s.id,
      lock: "FOR KEY SHARE",
      select: s.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp lock_item(item_id),
    do: Repo.one(from(i in Item, where: i.id == ^item_id, lock: "FOR UPDATE"))

  defp lock_scope_of(item) do
    case story_scope(item) do
      nil -> :ok
      scope -> Stories.lock(scope, item.language)
    end
  end

  # The scope whose stories an item may sit in: an assigned item's.
  defp story_scope(%Item{assignment: :assigned} = item), do: Stories.scope(item)
  defp story_scope(_item), do: nil

  # --- closing act, NL2 begin ---
  # §8, §12: an item kept as a research note's source stays with the note's
  # security; moving it would carry the note's link to another security's
  # story, and `nil` would put it in the queue for good.
  defp assign_locked(%Item{class: :aggregator} = prior, _security_id, _held, _now)
       when prior.status == :promoted or prior.note_ids != [] do
    {:error,
     {:refused,
      %{
        "news_id" => [
          "is kept in the research log as a note's source (ADR-0056 §8, §12): " <>
            "it stays with that note's security"
        ]
      }}}
  end

  # --- closing act, NL2 end ---

  defp assign_locked(%Item{class: :aggregator} = prior, security_id, held, now) do
    with {:ok, outcome} <- assign_outcome(prior, security_id, held) do
      {assignment, target_id, candidates} = assignment_of(outcome)

      if {prior.assignment, prior.security_id, prior.candidates} ==
           {assignment, target_id, candidates} do
        {:ok, prior}
      else
        move_item(prior, {assignment, target_id, candidates}, now)
      end
    end
  end

  defp assign_locked(%Item{class: class}, _security_id, _held, _now) do
    {:error,
     {:refused,
      %{
        "news_id" => [
          "is an #{class} item: bound to its feed's #{bound_to(class)} by construction " <>
            "(ADR-0056 §2); only an aggregator item is assigned"
        ]
      }}}
  end

  defp bound_to(:thematic), do: "category"
  defp bound_to(_class), do: "security"

  # The target is held FOR KEY SHARE since the first step (AT4): one that
  # did not exist then is not held.
  defp assign_outcome(_prior, security_id, held) when is_integer(security_id) do
    if MapSet.member?(held, security_id),
      do: {:ok, {:assigned, security_id}},
      else: {:error, {:refused, %{"security_id" => ["does not exist"]}}}
  end

  # §2 and ORD5: the matcher's answer, from the aliases committed by now
  # (read under the matcher's lock), its securities held FOR KEY SHARE
  # since the first step (AT4); a security it names now that the first
  # step's match did not (an alias committed in between) runs the attempt
  # again.
  defp assign_outcome(prior, nil, held) do
    hits = Matcher.matches(prior.title, Universe.aggregator_index())
    if held?(hits, held), do: {:ok, Matcher.outcome(hits)}, else: {:error, :moved}
  end

  defp assignment_of({:assigned, id}), do: {:assigned, id, []}
  defp assignment_of(:unassigned), do: {:unassigned, nil, []}
  defp assignment_of({:ambiguous, ids}), do: {:ambiguous, nil, ids}

  defp move_item(prior, {assignment, target_id, candidates}, now) do
    target = if assignment == :assigned, do: {:security, target_id}
    left = story_scope(prior)

    if target, do: Stories.lock(target, prior.language)
    Stories.detach(prior)

    {1, _} =
      Repo.update_all(from(i in Item, where: i.id == ^prior.id),
        set: [
          assignment: assignment,
          security_id: target_id,
          candidates: candidates,
          scope_at: scope_at(prior, {assignment, target_id, candidates}, now),
          updated_at: now()
        ]
      )

    [left, target]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, Repo.get!(Item, prior.id)}, fn scope, acc ->
      case Stories.recluster(scope, prior.language, now, full: true) do
        {:ok, _summary} -> {:cont, acc}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, _item} -> {:ok, Repo.get!(Item, prior.id)}
      error -> error
    end
  end

  # --- S28 N4 end ---

  # --- S28 N5 begin ---

  @doc """
  Appends a research note written from the story `cluster_id`
  (`notes.append` with a `cluster_id`, ADR-0056 §8): the server pre-fills
  what the story knows, the story is promoted and links the note. See
  `Portfolixir.News.Promotion`, the one place a story becomes a note;
  `shown:` is the proposal the operator's form showed (closing act, NL1).
  """
  @spec append_note_from_story(Actor.t(), map(), pos_integer(), keyword()) ::
          {:ok, Portfolixir.Knowledge.SecurityNote.t()}
          | {:error, %{String.t() => [String.t()]} | Ecto.Changeset.t() | :story_changed}
  def append_note_from_story(%Actor{} = actor, attrs, cluster_id, opts \\ []),
    do: Promotion.append_note(actor, attrs, cluster_id, opts)

  @doc """
  The source an event of `security_id` takes from the item `news_id`
  (`events.create` with a `news_id`); see `Portfolixir.News.Promotion`.
  """
  @spec event_source(pos_integer(), pos_integer()) ::
          {:ok, map()} | {:error, %{String.t() => [String.t()]}}
  def event_source(security_id, news_id), do: Promotion.event_source(security_id, news_id)

  # --- S28 N5 end ---

  # --- S28 N6 begin ---

  @doc """
  The news block of `securities.dossier` for the security `security_id` at
  the server's clock `now` (ADR-0056 §9's extension); see
  `Portfolixir.News.Dossier`.
  """
  @spec dossier_block(pos_integer(), DateTime.t()) :: Dossier.t()
  def dossier_block(security_id, %DateTime{} = now), do: Dossier.block(security_id, now)

  # --- S28 N6 end ---

  # --- S28 N7 begin ---
  # The news page (ADR-0056 §10): what its regions show beside the reads
  # the API answers from (`health/1`, `Portfolixir.News.Reads`).

  @type feed_registration :: %{
          id: pos_integer(),
          url: String.t(),
          class: atom(),
          enabled: boolean(),
          language: String.t(),
          security_id: pos_integer() | nil,
          security_name: String.t() | nil,
          category_id: pos_integer() | nil,
          category_name: String.t() | nil
        }

  @type registry_cursor :: {:feed, pos_integer()} | {:source, String.t()}

  @type registry :: %{
          feeds: [feed_registration()],
          sources: [Source.t()],
          truncated: boolean(),
          cursor: registry_cursor() | nil
        }

  @doc """
  The news registry (ADR-0056 §10; the coverage rule, N7): every
  registered feed — URL, class, binding (its security's or category's id
  and name), language, enabled — by id, then every rated source (§3) by
  domain. What the page's „Feeds“ and „Quellen“ tabs show, and what `GET
  /api/v1/news/registry` (`news.registry`) lists to the agent: one read
  for both (plan D-1, criterion 6). Registration stays the API's and the
  agent's (`news.feeds_put`, `news.sources_put`); the page only shows it.

  Options: `limit` (rows per page, feeds and sources counted together;
  `nil`, the default, answers all) and `after` (a page's `cursor`). A page
  with rows behind it answers `truncated: true` and `cursor`, the last row's
  key, `{:feed, id}` or `{:source, domain}`: the next page starts after it,
  so a walk returns every row once (a feed or source written meanwhile
  behind the cursor is read on the walk; one before it on the next walk).
  """
  @spec registry(keyword()) :: registry()
  def registry(opts \\ []) do
    limit = Keyword.get(opts, :limit)
    after_key = Keyword.get(opts, :after)

    feeds = registry_feeds(after_key, limit && limit + 1)

    if limit && length(feeds) > limit do
      feeds = Enum.take(feeds, limit)
      %{feeds: feeds, sources: [], truncated: true, cursor: {:feed, List.last(feeds).id}}
    else
      room = limit && limit - length(feeds)
      sources = registry_sources(after_key, room && room + 1)

      cond do
        is_nil(limit) or length(sources) <= room ->
          %{feeds: feeds, sources: sources, truncated: false, cursor: nil}

        room == 0 ->
          %{feeds: feeds, sources: [], truncated: true, cursor: {:feed, List.last(feeds).id}}

        true ->
          sources = Enum.take(sources, room)

          %{
            feeds: feeds,
            sources: sources,
            truncated: true,
            cursor: {:source, List.last(sources).domain}
          }
      end
    end
  end

  defp registry_feeds({:source, _domain}, _limit), do: []

  defp registry_feeds(after_key, max) do
    from(f in Feed,
      left_join: s in assoc(f, :security),
      left_join: c in assoc(f, :category),
      order_by: f.id,
      select: %{
        id: f.id,
        url: f.url,
        class: f.class,
        enabled: f.enabled,
        language: f.language,
        security_id: f.security_id,
        security_name: s.name,
        category_id: f.category_id,
        category_name: c.name
      }
    )
    |> then(fn query ->
      case after_key do
        {:feed, id} -> where(query, [f], f.id > ^id)
        nil -> query
      end
    end)
    |> then(&if(max, do: limit(&1, ^max), else: &1))
    |> Repo.all()
  end

  defp registry_sources(after_key, max) do
    from(s in Source, order_by: s.domain)
    |> then(fn query ->
      case after_key do
        {:source, domain} -> where(query, [s], s.domain > ^domain)
        _feed_or_start -> query
      end
    end)
    |> then(&if(max, do: limit(&1, ^max), else: &1))
    |> Repo.all()
  end

  @doc """
  The securities an item may be assigned to on the page (`assign_item/4`
  takes any security; the picker offers the news universe, §2), as maps of
  `id`, `name` and `isin` sorted by name; the page tells same-named ones
  apart by `isin` (the closing act's UAT line).
  """
  @spec assign_choices() :: [%{id: pos_integer(), name: String.t(), isin: String.t() | nil}]
  def assign_choices do
    Universe.members()
    |> Enum.map(&Map.take(&1, [:id, :name, :isin]))
    |> Enum.sort_by(&{String.downcase(&1.name), &1.id})
  end

  # --- S28 N7 end ---

  # --- S28 N8 begin ---

  @doc """
  What `append_note_from_story/3` would pre-fill for the story `cluster_id`
  of the security `security_id`, read without a write: the security's tab
  „Nachrichten“ opens its note form with it (ADR-0056 §8, NFR-10). See
  `Portfolixir.News.Promotion.proposal/2`.
  """
  @spec story_proposal(pos_integer(), pos_integer()) ::
          {:ok, map()} | {:error, %{String.t() => [String.t()]}}
  def story_proposal(cluster_id, security_id), do: Promotion.proposal(cluster_id, security_id)

  # --- S28 N8 end ---
end
