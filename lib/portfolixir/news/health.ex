defmodule Portfolixir.News.Health do
  @moduledoc """
  The news layer's health (ADR-0056 §6, §14 item 5, A3): a dead collector
  is visibly dead within a day, and a feed nobody reads shows it. Read at
  the server's clock `now`; every window counts `first_seen_at` (B4), and
  the windows' counts follow `Portfolixir.News.FeedDay`'s "where each count
  is read from".

  ## Per feed (in id order)

    * `id`, `class`, `enabled`, and `last_ok_at` and `last_error` as the
      fetcher recorded them.
    * `items_24h` — the feed's items first seen within the 24 hours before
      `now` (an item first seen exactly 24 hours ago is out, as the cap of
      A3 counts).
    * `err_24h` — the errors of the feed's day rows of today and yesterday
      (server days): every error of the last 24 hours and possibly older
      ones, never fewer.
    * `stale` — **true when the feed has had no successful fetch for 24
      hours** (§6): `now` is 24 hours or more after `last_ok_at`, so it
      flips at exactly 24 hours. A feed never fetched successfully counts
      from its registration: stale once it was registered 24 hours ago or
      more, not before — a feed added an hour ago has not had its chance,
      one added yesterday that never answered is as dead as one that
      stopped. **A disabled feed is never stale**: nobody asked it to
      fetch, and `enabled: false` says so; flagging it would bury a dead
      feed among deliberate pauses.
    * `items_30d` — the feed's items first seen within 30 days.
    * `promoted_30d` — **the promoted stories** those items are in (A3:
      "promoted stories over items"): a story is promoted once any member
      is (§8 promotes a story), an item outside a story is a story of its
      own, and each story counts once. A story counts for every feed with
      an item in it, so a feed that carried a story someone kept gets the
      credit whichever member was promoted.
    * `yield_30d` — `promoted_30d / items_30d` as a `Decimal` rounded half
      up to four places (`0.0200`), a decimal string in the API and MCP
      (ADR-0003); nil for a feed without items in 30 days (no ratio).
      Each counted story holds one of the feed's items, so it is at most 1.
    * `low_yield` — true at 50 items or more in 30 days with none promoted
      (A3). Nothing disables a feed by itself: the operator decides.

  ## The day (`day`)

  The server's day of `now` (`Portfolixir.Clock.local_date/1`, the day the
  day rows are kept by):

    * `unassigned`, `ambiguous` — the items first seen that day, up to
      `now`, that are still unassigned or ambiguous;
    * `dropped` — that day's drops over every feed, by reason: `cap`
      (A3), `no_source` (§2), `old` (B4);
    * `blocked` — that day's items dropped from a blocked domain (§3).

  The labels of §7 (the unlabelled stories, the last label) are Sprint
  28's and are not reported yet.
  """

  import Ecto.Query

  alias Portfolixir.Clock
  alias Portfolixir.News.Feed
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Item
  alias Portfolixir.Repo

  @day_seconds 24 * 60 * 60
  @month_days 30
  @low_yield_items 50
  @yield_places 4

  @type feed_health :: %{
          id: pos_integer(),
          class: atom(),
          enabled: boolean(),
          last_ok_at: DateTime.t() | nil,
          last_error: String.t() | nil,
          items_24h: non_neg_integer(),
          err_24h: non_neg_integer(),
          stale: boolean(),
          items_30d: non_neg_integer(),
          promoted_30d: non_neg_integer(),
          yield_30d: Decimal.t() | nil,
          low_yield: boolean()
        }

  @type day :: %{
          date: Date.t(),
          unassigned: non_neg_integer(),
          ambiguous: non_neg_integer(),
          dropped: %{cap: non_neg_integer(), no_source: non_neg_integer(), old: non_neg_integer()},
          blocked: non_neg_integer()
        }

  @type t :: %{as_of: DateTime.t(), feeds: [feed_health()], day: day()}

  @doc "The health at the server's clock `now`; see the moduledoc."
  @spec report(DateTime.t()) :: t()
  def report(%DateTime{} = now) do
    day_ago = DateTime.add(now, -@day_seconds, :second)
    month_ago = DateTime.add(now, -@month_days, :day)
    today = Clock.local_date(now)

    items_24h = item_counts(day_ago)
    items_30d = item_counts(month_ago)
    promoted_30d = promoted_counts(month_ago)
    errors = errors_since(Date.add(today, -1))

    feeds =
      from(f in Feed, order_by: f.id)
      |> Repo.all()
      |> Enum.map(fn feed ->
        items = Map.get(items_30d, feed.id, 0)
        promoted = Map.get(promoted_30d, feed.id, 0)

        %{
          id: feed.id,
          class: feed.class,
          enabled: feed.enabled,
          last_ok_at: feed.last_ok_at,
          last_error: feed.last_error,
          items_24h: Map.get(items_24h, feed.id, 0),
          err_24h: Map.get(errors, feed.id, 0),
          stale: stale?(feed, day_ago),
          items_30d: items,
          promoted_30d: promoted,
          yield_30d: yield(promoted, items),
          low_yield: items >= @low_yield_items and promoted == 0
        }
      end)

    %{as_of: now, feeds: feeds, day: day(today, now)}
  end

  # §6: no successful fetch for 24 hours; never fetched, counted from the
  # registration. A disabled feed is not asked to fetch.
  defp stale?(%Feed{enabled: false}, _day_ago), do: false

  defp stale?(%Feed{last_ok_at: nil, inserted_at: inserted_at}, day_ago),
    do: DateTime.compare(inserted_at, day_ago) != :gt

  defp stale?(%Feed{last_ok_at: last_ok_at}, day_ago),
    do: DateTime.compare(last_ok_at, day_ago) != :gt

  defp yield(_promoted, 0), do: nil

  defp yield(promoted, items),
    do: promoted |> Decimal.new() |> Decimal.div(items) |> Decimal.round(@yield_places, :half_up)

  defp item_counts(since) do
    from(i in Item,
      where: not is_nil(i.feed_id) and i.first_seen_at > ^since,
      group_by: i.feed_id,
      select: {i.feed_id, count(i.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # A3: the promoted stories a feed's items are in, each once. A story's
  # key is its id; an item outside a story is its own (its id, negated, so
  # the two never meet: both are positive).
  defp promoted_counts(since) do
    promoted_stories =
      from(m in Item,
        where: m.status == :promoted and not is_nil(m.cluster_id),
        distinct: true,
        select: %{cluster_id: m.cluster_id}
      )

    from(i in Item,
      left_join: p in subquery(promoted_stories),
      on: p.cluster_id == i.cluster_id,
      where: not is_nil(i.feed_id) and i.first_seen_at > ^since,
      where: i.status == :promoted or not is_nil(p.cluster_id),
      group_by: i.feed_id,
      select: {i.feed_id, count(fragment("DISTINCT coalesce(?, -?)", i.cluster_id, i.id))}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp errors_since(first_day) do
    from(d in FeedDay,
      where: d.day >= ^first_day,
      group_by: d.feed_id,
      select: {d.feed_id, type(sum(d.errors), :integer)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp day(today, now) do
    start = day_start(today)

    open =
      from(i in Item,
        where: i.assignment in [:unassigned, :ambiguous],
        where: i.first_seen_at >= ^start and i.first_seen_at <= ^now,
        group_by: i.assignment,
        select: {i.assignment, count(i.id)}
      )
      |> Repo.all()
      |> Map.new()

    dropped =
      from(d in FeedDay,
        where: d.day == ^today,
        select: %{
          cap: type(coalesce(sum(d.dropped_cap), 0), :integer),
          no_source: type(coalesce(sum(d.dropped_no_source), 0), :integer),
          old: type(coalesce(sum(d.dropped_old), 0), :integer),
          blocked: type(coalesce(sum(d.dropped_blocked), 0), :integer)
        }
      )
      |> Repo.one()

    %{
      date: today,
      unassigned: Map.get(open, :unassigned, 0),
      ambiguous: Map.get(open, :ambiguous, 0),
      dropped: Map.take(dropped, [:cap, :no_source, :old]),
      blocked: dropped.blocked
    }
  end

  # The first instant of the server's day `date`, in UTC: the host's local
  # midnight (the zone `Portfolixir.Clock.local_date/1` reads), the earlier
  # one where a clock change repeats it, the first hour that exists where a
  # change skips it.
  defp day_start(date) do
    {year, month, day} = Date.to_erl(date)

    [{{year, month, day}, {0, 0, 0}}, {{year, month, day}, {1, 0, 0}}]
    |> Enum.find_value(fn local ->
      case :calendar.local_time_to_universal_time_dst(local) do
        [] -> nil
        utc -> Enum.min(utc)
      end
    end)
    |> NaiveDateTime.from_erl!()
    |> DateTime.from_naive!("Etc/UTC")
  end
end
