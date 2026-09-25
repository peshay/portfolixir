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
  """

  alias Portfolixir.Repo

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
end
