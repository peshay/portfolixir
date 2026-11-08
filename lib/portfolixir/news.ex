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
  alias Portfolixir.News.Feed
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Fetcher
  alias Portfolixir.News.Health
  alias Portfolixir.News.Item
  alias Portfolixir.News.Matcher
  alias Portfolixir.News.Scheduler
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
          scope_at: scope_at(item, {assignment, security_id}, now),
          updated_at: now()
        ]
      )
    end
  end

  # C3: an item that enters another scope (assigned to a security, or moved
  # between the unassigned and ambiguous remainders) enters it now, never
  # before its first sight; one whose scope stays keeps its time.
  defp scope_at(%Item{assignment: assignment, security_id: id} = item, {assignment, id}, _now),
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
  each feed's freshness and yield, and the day's unassigned, ambiguous,
  dropped and blocked counts. See `Portfolixir.News.Health`.
  """
  @spec health(DateTime.t()) :: Health.t()
  def health(%DateTime{} = now), do: Health.report(now)

  # --- end N6 -----------------------------------------------------------------
end
