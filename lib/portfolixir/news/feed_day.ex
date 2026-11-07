defmodule Portfolixir.News.FeedDay do
  @moduledoc """
  One feed's counters for one day of the server's clock
  (`Portfolixir.Clock.today/0`): the items stored, the failed fetches, and
  the items dropped at ingest — past the daily cap (`dropped_cap`, A3),
  without a `<source>` element (`dropped_no_source`, §2), with a claim older
  than the retention window (`dropped_old`, B4) and from a `blocked` domain
  (`dropped_blocked`, §3). One row per feed and day; every counter starts at
  zero and is never negative.

  ## Where each count of §6 and A3 is read from

  A dropped item is not stored, so what was dropped can only be counted
  here; what was stored is counted from the items themselves, which carry
  the server's clock:

    * `items_24h`, `items_30d` — the feed's rows in `news_items` with
      `first_seen_at` within the last 24 hours or 30 days: exact rolling
      windows. (`news_items` keeps 90 days, so both windows are complete.)
    * `promoted_30d` and so `yield_30d` — the promoted stories those rows
      are in, each once (A3: "promoted stories over items";
      `Portfolixir.News.Health`).
    * the cap of A3 (at most 200 items in 24 hours) — the same rolling
      count, read before each store.
    * `err_24h` — the `errors` of the feed's rows for today and yesterday.
      A day row cannot be cut at the hour, so this window is the last two
      server days: it counts every error of the last 24 hours and possibly
      some older ones, never fewer — overlap, never loss, as
      `Portfolixir.DeltaCursor` reads a window.
    * the day's dropped and blocked counts of the health read (§6) —
      today's row.

  `items_stored` keeps each day's count after the items it counted are
  gone; nothing rolling reads it. The retention run
  (`Portfolixir.News.Retention`) keeps a feed's rows of the last 30 server
  days before today and deletes older ones: the health read needs two.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.BoundedDate

  @counters ~w(items_stored errors dropped_cap dropped_no_source dropped_old dropped_blocked)a

  @type t :: %__MODULE__{}

  schema "news_feed_days" do
    belongs_to(:feed, Portfolixir.News.Feed)
    field(:day, :date)
    field(:items_stored, :integer, default: 0)
    field(:errors, :integer, default: 0)
    field(:dropped_cap, :integer, default: 0)
    field(:dropped_no_source, :integer, default: 0)
    field(:dropped_old, :integer, default: 0)
    field(:dropped_blocked, :integer, default: 0)
  end

  @doc "The counter columns."
  @spec counters() :: [atom()]
  def counters, do: @counters

  @doc "Casts and checks a feed's day row."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(day, attrs) do
    changeset =
      day
      |> cast(attrs, [:feed_id, :day | @counters])
      |> validate_required([:feed_id, :day | @counters])

    @counters
    |> Enum.reduce(changeset, &validate_number(&2, &1, greater_than_or_equal_to: 0))
    |> BoundedDate.validate([:day])
    |> unique_constraint(:day, name: :news_feed_days_feed_id_day_index)
    |> foreign_key_constraint(:feed_id, name: :news_feed_days_feed_id_fkey)
    |> check_constraint(:items_stored, name: :news_feed_days_counts_check, message: "is invalid")
  end
end
