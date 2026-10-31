defmodule Portfolixir.DeltaCursor do
  @moduledoc """
  The `as_of` a delta read (`?since=`, FR-38) hands back as the next cut
  (E25 S6, G06).

  A row's `updated_at` is stamped when its transaction writes it, not when
  that transaction commits, and the next poll delivers only rows stamped
  strictly after this `as_of`. An `as_of` taken as "the read instant" loses
  every row a transaction still open during the read stamped before that
  instant and commits after it. So the cursor is bounded, in the database, by
  the start of the oldest transaction that has written and is still in
  flight: a row it commits later carries a stamp no earlier than that start.
  The instant is the earlier of the database's clock and the application's,
  which stamps the rows; then the existing margin of one second covers the
  second-precision stamps and a small skew between the two clocks.

  The price is overlap, never loss: while a long transaction is open, polls
  keep re-delivering the rows changed since it began. Transactions of
  another database role are not visible to this read without the
  `pg_read_all_stats` privilege; the documented deployment runs one role.
  Commit-ordered cursors are the long-term design (issue #897).

  **A capped delta read is a page (K17).** A read bounded by `limit` takes
  its rows oldest change first, by the change stamp and then the id, and
  starts after a cursor `{cut, after_id}`: a row qualifies when its stamp
  lies after `cut`, or on `cut` with an id after `after_id`. A full page
  hands back the cursor at its last row, so the next page continues there
  and rows sharing one stamp (an import writes thousands within a second)
  are neither skipped nor re-read in a loop. `page/3` is that filter and
  order; the API's `SinceParam` writes and reads the cursor.
  """

  import Ecto.Query, only: [dynamic: 2, order_by: 2, where: 2]

  alias Portfolixir.Repo

  @typedoc "Where a paged delta read starts: after `cut`, or on `cut` after `after_id`."
  @type cursor :: %{cut: NaiveDateTime.t(), after_id: pos_integer() | nil}

  @margin_seconds 1

  @doc "The cursor a delta read returns as `as_of`, see the moduledoc."
  @spec as_of() :: DateTime.t()
  def as_of do
    app_now = DateTime.utc_now()

    %{rows: [[db_now, oldest_writer]]} =
      Repo.query!("""
      SELECT clock_timestamp(), min(a.xact_start)
      FROM pg_stat_activity a
      WHERE a.backend_xid IS NOT NULL
        AND a.pid <> pg_backend_pid()
        AND a.datname = current_database()
      """)

    [app_now, db_now, oldest_writer]
    |> Enum.reject(&is_nil/1)
    |> Enum.min(DateTime)
    |> DateTime.truncate(:second)
    |> DateTime.add(-@margin_seconds, :second)
  end

  @doc """
  Narrows `query` to the rows after `cursor` and orders them by the change
  stamp, then the id, ascending. `stamp` is the dynamic expression of the
  row's change stamp over the query's first binding (a column, or a computed
  stamp such as a rule's latest version write).
  """
  @spec page(Ecto.Queryable.t(), Ecto.Query.dynamic_expr(), cursor()) :: Ecto.Query.t()
  def page(query, stamp, %{cut: %NaiveDateTime{}} = cursor) do
    query
    |> where(^after_cursor(stamp, cursor))
    |> order_by(^[asc: stamp, asc: dynamic([r], r.id)])
  end

  defp after_cursor(stamp, %{cut: cut, after_id: nil}),
    do: dynamic([r], ^stamp > type(^cut, :naive_datetime))

  defp after_cursor(stamp, %{cut: cut, after_id: id}) when is_integer(id) do
    dynamic(
      [r],
      ^stamp > type(^cut, :naive_datetime) or
        (^stamp == type(^cut, :naive_datetime) and r.id > ^id)
    )
  end
end
