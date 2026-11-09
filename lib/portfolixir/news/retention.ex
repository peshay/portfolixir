defmodule Portfolixir.News.Retention do
  @moduledoc """
  The retention run (ADR-0056 §12, §14 item 9, B4, B7), the system job
  `news_retention`: what keeps the news layer a staging area and never an
  archive.

  **Which items go.** Every item first seen more than 90 days before the
  server's clock `now` (`first_seen_at < now − 90 days`, B4: the server's
  clock, never the feed's claim), **unless** it is `promoted` or names a
  note (`note_ids` not empty): what became knowledge keeps its source
  (§8, §12). The window is the ingest's (`Portfolixir.News.Ingest.retention_days/0`),
  so a claim older than it is never stored (`dropped_old`) and retention
  never has to remove what a feed keeps listing.

  **Stories follow their items** (§12). The expired items that sit on a
  security or a category are removed one scope and language at a time by
  `Portfolixir.News.Stories.remove/5`, under the lock the clustering takes:
  a story left without a member is deleted, one that lost members is
  recomputed (count, earliest fields, representative), and one an expired
  item held together splits, each old story going with its earliest
  remaining member (B3). An `unassigned` or `ambiguous` item sits in no
  story and is deleted directly; one that a re-match assigned meanwhile no
  longer matches the delete and waits for the next run.

  **Tombstones** (closing act, COR2). Each removed item that has a feed
  leaves a row in `news_item_tombstones`: the feed and a SHA-256 of its
  canonical URL, never the URL. The ingest drops an item a tombstone of its
  feed names (`dropped_old`), so a feed that keeps listing a dateless item
  does not refill it as new (B4). A tombstone is kept 90 days after the
  removal, then pruned here.

  **Day rows** (`news_feed_days`) older than 30 days before the server's
  day of `now` are deleted: the health read (§6, A3) reads at most the
  last two days of them, and 30 days keep a month of drop and error counts
  for a look back. The 30-day figures of a feed come from its items. The
  record of which items each day dropped (`news_feed_drops`, closing act
  COR4) is pruned with them.

  **Digest consumers** (`news_digest_consumers`; Sprint 28, N3's open
  question 2) whose last confirmation — or, never confirmed, creation:
  the row's `updated_at`, which only a confirmation moves — is more than
  90 days before `now` are deleted. *Why:* the server keeps at most 32
  consumers (`Portfolixir.News.DigestCursor.cap/0`) and nothing else
  removes one, so names an agent stopped using would hold the cap shut for
  good. A consumer that has not confirmed for 90 days has read nothing it
  kept; named again, it starts as a new one, 24 hours back.

  **When.** Once a server day, from the news scheduler's tick
  (`Portfolixir.News.Scheduler`), after that tick's fetches, in the same
  task: so it runs exactly where the fetcher runs (B6), never in tests, and
  never beside a run of the fetcher started by the same scheduler.

  Items, stories and day rows are a staging area, not journaled (B7,
  `Portfolixir.Journal.Allowlist`); this is the registered system job that
  empties it.
  """

  import Ecto.Query

  require Logger

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.News.DigestConsumer
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Stories
  alias Portfolixir.Repo

  @feed_days_kept 30
  @tombstone_days 90
  @consumer_days 90

  @type summary :: %{
          items: non_neg_integer(),
          stories_deleted: non_neg_integer(),
          feed_days: non_neg_integer(),
          consumers: non_neg_integer()
        }

  @doc "The retention window in days, the ingest's (§12, B4)."
  @spec days() :: pos_integer()
  def days, do: Ingest.retention_days()

  @doc "How many server days of `news_feed_days` rows are kept before today."
  @spec feed_days_kept() :: pos_integer()
  def feed_days_kept, do: @feed_days_kept

  @doc """
  Runs the retention at the server's clock `now`; see the moduledoc.
  `{:ok, summary}`: the items deleted, the stories deleted because they
  were emptied, and the day rows pruned.
  """
  @spec run(DateTime.t()) :: {:ok, summary()}
  def run(%DateTime{} = now) do
    %Actor{label: job} = Actor.system_job("news_retention")
    expired = expired(now)
    prune_tombstones(now)
    tombstone(expired, now)
    scoped = remove_scoped(job, expired, now)

    {open, _} =
      Repo.delete_all(from(i in expired, where: i.assignment in [:unassigned, :ambiguous]))

    days = prune_days(now)
    consumers = prune_consumers(now)

    summary =
      Map.merge(scoped, %{items: scoped.items + open, feed_days: days, consumers: consumers})

    Logger.info(
      "#{job}: #{summary.items} items, #{summary.stories_deleted} emptied stories, " <>
        "#{days} day rows, #{consumers} digest consumers"
    )

    {:ok, summary}
  end

  # §12: older than the window by first sight, neither promoted nor linked.
  defp expired(now) do
    cutoff = DateTime.add(now, -days(), :day)

    from(i in Item,
      where:
        i.first_seen_at < ^cutoff and i.status != :promoted and
          fragment("cardinality(?) = 0", i.note_ids)
    )
  end

  # One scope and language at a time; one that fails keeps its items until
  # the next run and stops no other.
  defp remove_scoped(job, expired, now) do
    from(i in expired,
      where: i.assignment == :assigned,
      distinct: true,
      select: {i.security_id, i.category_id, i.language}
    )
    |> Repo.all()
    |> Enum.sort()
    |> Enum.reduce(%{items: 0, stories_deleted: 0, feed_days: 0}, fn
      {security_id, category_id, language}, acc ->
        scope = Stories.scope(%{security_id: security_id, category_id: category_id})

        case Stories.remove(scope, language, expired, now) do
          {:ok, removed} ->
            %{
              acc
              | items: acc.items + removed.items,
                stories_deleted: acc.stories_deleted + removed.stories_deleted
            }

          {:error, changeset} ->
            Logger.warning(
              "#{job}: #{inspect(scope)} (#{language}) kept for the next run: " <>
                inspect(changeset.errors)
            )

            acc
        end
    end)
  end

  # --- closing act, Fix-1 (COR2) ----------------------------------------------

  # A tombstone of each expiring item that has a feed: the feed and a hash of
  # its canonical URL, so the ingest does not store it again (B4). Written
  # before the removal; an item a failed scope keeps is still `known`.
  defp tombstone(expired, now) do
    from(i in expired, where: not is_nil(i.feed_id), select: {i.feed_id, i.canonical_url})
    |> Repo.all()
    |> Enum.map(fn {feed_id, url} ->
      %{feed_id: feed_id, url_hash: Ingest.url_hash(url), removed_at: now}
    end)
    |> Enum.chunk_every(1_000)
    |> Enum.each(fn rows ->
      Repo.insert_all("news_item_tombstones", rows,
        on_conflict: {:replace, [:removed_at]},
        conflict_target: [:feed_id, :url_hash]
      )
    end)
  end

  defp prune_tombstones(now) do
    cutoff = DateTime.add(now, -@tombstone_days, :day)
    Repo.delete_all(from(t in "news_item_tombstones", where: t.removed_at < ^cutoff))
  end

  # --- end closing act, Fix-1 (COR2) ------------------------------------------

  # --- S28 N3 OQ2 begin ---
  # A consumer nobody confirmed for 90 days frees its place under the cap.
  defp prune_consumers(now) do
    cutoff = DateTime.add(now, -@consumer_days, :day)
    {count, _} = Repo.delete_all(from(c in DigestConsumer, where: c.updated_at < ^cutoff))
    count
  end

  # --- S28 N3 OQ2 end ---

  defp prune_days(now) do
    oldest = now |> Clock.local_date() |> Date.add(-@feed_days_kept)
    {count, _} = Repo.delete_all(from(d in FeedDay, where: d.day < ^oldest))
    # COR4: the record of which items a day dropped goes with the day's row.
    Repo.delete_all(from(d in "news_feed_drops", where: d.day < ^oldest))
    count
  end
end
