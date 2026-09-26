defmodule Portfolixir.Catalog.Quotes do
  @moduledoc """
  Sub-context for security price history.

  Quotes are stored as an append/upsert log keyed by `(security_id, date)`.
  This module provides the read paths used by the list and detail views
  (latest, last-two, range, performance) and the two write paths: the
  journaled **authored** writes (`upsert_authored/3`, `release_manual/4`) and
  the unjournaled market-data writer of the background sync
  (`upsert_many/3`, ADR-0017 as amended by T-9).

  Since ADR-0028 §2 this module is also the **loading shell** for the pure
  split-adjustment engine (`Portfolixir.Catalog.QuoteAdjustment`): the
  `adjusted_*` read paths serve closes in the current display basis (raw rows
  divided by the cumulative ratio of later splits, provider mirrors passed
  through), derived at read time from the booked split events. The raw
  `latest`/`range`/`at_or_before` reads stay available for surfaces that need
  the stored values (audit, upsert) and for the daily walks, which apply the
  engine themselves per day. Split events are read from the `transactions`
  table via the `Portfolixir.Ledger.Transaction` schema — the same read-only
  reach `Portfolixir.Catalog.list_securities/1`'s holding filter already
  takes — so the Catalog shell needs no call into the Ledger context module.

  All Decimal arithmetic is performed via `Decimal` — no floats — so values
  round-trip losslessly to charts and downstream calculations.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.MarketDataBounds
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.QuoteAdjustment
  alias Portfolixir.Catalog.QuoteWrite
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecurityWithMetrics
  alias Portfolixir.Clock
  alias Portfolixir.Derived.Invalidation
  alias Portfolixir.Journal
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  # Rows per INSERT, below PostgreSQL's 65,535 bind parameters per statement
  # at six parameters a row (E25 S3, F28): a provider's whole daily history is
  # written in chunks inside one transaction.
  @insert_chunk 5_000

  @doc """
  Most recent quote for the security, or nil. Like every latest read here, it
  never serves a row dated past `MarketDataBounds.latest_date/0` (E25 S3, F26).
  """
  def latest(security_id) when is_integer(security_id) do
    SecurityQuote
    |> where([q], q.security_id == ^security_id)
    |> plausibly_dated()
    |> order_by([q], desc: q.date)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Most recent quote per security for `security_ids`, as a map
  `%{security_id => %Quote{}}`; securities without quotes are absent.

  One `DISTINCT ON` query regardless of list size (#481 slice 2a fix round):
  the allocation breakdown prices its unheld SOLL rows from this instead of a
  per-security `latest/1` loop.
  """
  def latest_by_security_ids([]), do: %{}

  def latest_by_security_ids(security_ids) when is_list(security_ids) do
    SecurityQuote
    |> where([q], q.security_id in ^security_ids)
    |> plausibly_dated()
    |> distinct([q], q.security_id)
    |> order_by([q], asc: q.security_id, desc: q.date)
    |> Repo.all()
    |> Map.new(&{&1.security_id, &1})
  end

  @doc "Up to the two most recent quotes, descending by date."
  def latest_two(security_id) when is_integer(security_id) do
    SecurityQuote
    |> where([q], q.security_id == ^security_id)
    |> plausibly_dated()
    |> order_by([q], desc: q.date)
    |> limit(2)
    |> Repo.all()
  end

  # The latest reads' cap (F26): a row stored before the bound existed and
  # dated past it is never the latest quote.
  defp plausibly_dated(query) do
    latest = MarketDataBounds.latest_date()
    where(query, [q], q.date <= ^latest)
  end

  @doc "Closest quote on or before `date`, or nil."
  def at_or_before(security_id, %Date{} = date) when is_integer(security_id) do
    SecurityQuote
    |> where([q], q.security_id == ^security_id and q.date <= ^date)
    |> order_by([q], desc: q.date)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Quotes between `from` and `to` inclusive, ascending by date."
  def range(security_id, %Date{} = from, %Date{} = to, opts \\ [])
      when is_integer(security_id) do
    query =
      SecurityQuote
      |> where([q], q.security_id == ^security_id and q.date >= ^from and q.date <= ^to)

    # A limit keeps the newest rows of the window (#771), like the transaction
    # and rate lists; the result stays ascending.
    case Keyword.get(opts, :limit) do
      n when is_integer(n) and n > 0 ->
        query |> order_by([q], desc: q.date) |> limit(^n) |> Repo.all() |> Enum.reverse()

      _ ->
        query |> order_by([q], asc: q.date) |> Repo.all()
    end
  end

  @doc """
  The security-level split events (ADR-0028), ascending by effective date:
  `[%{date: Date.t(), ratio: {p, q}}]`. The per-portfolio fan-out rows of one
  booking share `(security_id, date, normalized ratio)`, so they deduplicate
  into one event here.
  """
  def split_events(security_id) when is_integer(security_id) do
    security_id
    |> split_events_by_security()
    |> Map.get(security_id, [])
  end

  @doc """
  Security-level split events for many securities in one query:
  `%{security_id => [event]}`; securities without splits are absent. Pass
  `:all` for every security with a booked split.
  """
  def split_events_by_security(security_ids) do
    Transaction
    |> where([t], t.type == "split")
    |> scope_split_securities(security_ids)
    |> distinct(true)
    |> select([t], {t.security_id, t.date, t.split_ratio_numerator, t.split_ratio_denominator})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_id, date, p, q} -> %{date: date, ratio: {p, q}} end)
    |> Map.new(fn {security_id, events} ->
      {security_id, Enum.sort_by(events, & &1.date, Date)}
    end)
  end

  defp scope_split_securities(query, :all), do: query

  defp scope_split_securities(query, security_id) when is_integer(security_id),
    do: where(query, [t], t.security_id == ^security_id)

  defp scope_split_securities(query, security_ids) when is_list(security_ids),
    do: where(query, [t], t.security_id in ^security_ids)

  @doc """
  `range/3` in the current display basis (ADR-0028 §2): each row is
  `%{date, close, stored_close, source, basis, adjusted?}` with `close`
  split-adjusted per the row's own basis and the stored value kept reachable.
  """
  def adjusted_range(security_id, %Date{} = from, %Date{} = to)
      when is_integer(security_id) do
    security_id
    |> range(from, to)
    |> adjust_rows(Repo.get(Security, security_id))
  end

  @doc """
  The display-basis view of already-loaded stored rows (`%{date, close,
  source}` or `%Quote{}`), one adjusted row per input row in order. Read
  paths that pair stored and adjusted values MUST derive both from the same
  fetched list through this function — two independent queries can interleave
  with a concurrent upsert and misalign the pairing (E17 review, finding 6).
  """
  def adjust_rows(rows, %Security{} = security) when is_list(rows) do
    rows
    |> Enum.map(&Map.take(&1, [:date, :close, :source]))
    |> QuoteAdjustment.adjust_series(split_events(security.id), security)
  end

  @doc """
  `latest/1` in the current display basis (ADR-0028 §2), or nil: a stale raw
  close from before an effective date is divided by the cumulative later
  ratio, so it never prices a post-split quantity at the unsplit value.
  Returns `%{date, close, stored_close, source, basis, adjusted?}`.
  """
  def adjusted_latest(security_id) when is_integer(security_id) do
    case latest(security_id) do
      %SecurityQuote{} = quote_row ->
        events = split_events(security_id)
        security = Repo.get(Security, security_id)

        [row] =
          QuoteAdjustment.adjust_series(
            [Map.take(quote_row, [:date, :close, :source])],
            events,
            security
          )

        row

      nil ->
        nil
    end
  end

  @doc """
  `latest_by_security_ids/1` in the current display basis (ADR-0028 §2):
  `%{security_id => %{date, close, stored_close, source, basis, adjusted?}}`.
  """
  def adjusted_latest_by_security_ids([]), do: %{}

  def adjusted_latest_by_security_ids(security_ids) when is_list(security_ids) do
    events_by_security = split_events_by_security(security_ids)

    securities =
      Security
      |> where([s], s.id in ^security_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    security_ids
    |> latest_by_security_ids()
    |> Map.new(fn {security_id, quote_row} ->
      [row] =
        QuoteAdjustment.adjust_series(
          [Map.take(quote_row, [:date, :close, :source])],
          Map.get(events_by_security, security_id, []),
          Map.get(securities, security_id)
        )

      {security_id, row}
    end)
  end

  @doc """
  The **authored** quote write (E25 S6, G27 and F20 under decision T-9): the
  path the API takes, and the MCP companion and the demo seeds through it.

  Every row is stored with source `"manual"`, whatever source it names — a
  provenance value is the system's to state, and a close someone typed is a
  manual close. A manual row still wins over provider data (ADR-0028), so an
  authored write may replace a stored row of any source; the rows it replaces
  are therefore kept, as the before-image of one journal entry
  (`resource_type: "security_quotes"`, filed under the security's id,
  operation `upsert`) written in the same transaction as the rows, under
  `actor`. The security row is locked first, so a concurrent writer of the
  same security's quotes — authored or the sync — cannot slip a row between
  the read of the before-image and the write.

  Rows validated as in `upsert_many/3`; a row that fails is
  `{:error, changeset}` and nothing is written. A row equal to the stored
  manual row is left alone, and a call that changes nothing writes no row and
  no journal entry.

  Returns `{:ok, %{upserted: n, replaced: dates}}`: `upserted` is the number
  of rows now stored as given, `replaced` the ascending dates whose stored row
  the write changed (a new date is not one of them).
  """
  @spec upsert_authored(Actor.t(), integer(), list()) ::
          {:ok, %{upserted: non_neg_integer(), replaced: [Date.t()]}}
          | {:error, Ecto.Changeset.t() | :not_found}
  def upsert_authored(%Actor{} = actor, security_id, rows)
      when is_integer(security_id) and is_list(rows) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    with {:ok, prepared} <- prepare_rows(security_id, Enum.map(rows, &authored_row/1), now) do
      locked(security_id, fn ->
        prior =
          security_id
          |> stored_rows_for_update(dates: Enum.map(prepared, & &1.date))
          |> Map.new(&{&1.date, &1})

        changed = Enum.reject(prepared, &unchanged?(&1, prior))
        replaced = for row <- changed, stored = prior[row.date], do: stored

        journaled(changed, fn ->
          Multi.new()
          |> Multi.run(:quotes, fn _repo, _changes ->
            # The journal seam bumps this write's radius (T-9).
            insert_in_chunks(changed, on_conflict(false), nil)
            {:ok, QuoteWrite.new(security_id, changed)}
          end)
          |> Journal.record(actor,
            resource_type: "security_quotes",
            resource_id: security_id,
            operation: :upsert,
            source: :quotes,
            before: QuoteWrite.new(security_id, replaced)
          )
        end)

        %{
          upserted: length(prepared),
          replaced: replaced |> Enum.map(& &1.date) |> Enum.sort(Date)
        }
      end)
    end
  end

  @doc """
  Releases a security's **manual** rows dated `from` through `to` back to
  provider data (E25 S6, decision T-9): the rows are removed, journaled under
  `actor` with the released rows as the before-image of one `delete` entry
  (`resource_type: "security_quotes"`, filed under the security's id), so the
  next quote sync can store the provider's close for those dates again. A
  provider row in the range is left alone, and a range without manual rows
  writes nothing and no entry.

  A security without a provider keeps no quote for a released date: the
  release removes the pin, and only a sync puts a provider close back.

  Returns `{:ok, %{released: dates}}` (ascending), `{:error, :not_found}` for
  an unknown security, or `{:error, :invalid_range}` when `from` is after `to`.
  """
  @spec release_manual(Actor.t(), integer(), Date.t(), Date.t()) ::
          {:ok, %{released: [Date.t()]}} | {:error, :not_found | :invalid_range}
  def release_manual(%Actor{} = actor, security_id, %Date{} = from, %Date{} = to)
      when is_integer(security_id) do
    if Date.compare(from, to) == :gt do
      {:error, :invalid_range}
    else
      locked(security_id, fn ->
        released = stored_rows_for_update(security_id, from: from, to: to, source: "manual")
        ids = Enum.map(released, & &1.id)

        journaled(released, fn ->
          Multi.new()
          |> Multi.run(:quotes, fn repo, _changes ->
            {_count, _} = repo.delete_all(where(SecurityQuote, [q], q.id in ^ids))
            {:ok, QuoteWrite.new(security_id, [])}
          end)
          |> Journal.record(actor,
            resource_type: "security_quotes",
            resource_id: security_id,
            operation: :delete,
            source: :quotes,
            before: QuoteWrite.new(security_id, released)
          )
        end)

        %{released: Enum.map(released, & &1.date)}
      end)
    end
  end

  @doc """
  The **security merge's** quote writer (ADR-0050 §9, §13), the one writer
  besides the sync that ADR-0017's quote exemption names: `moved` are quotes
  of `source_id` dated where `target_id` has none, and each is re-pointed onto
  the target keeping its date, close and source (and so its ADR-0028 §2
  basis); `dropped` are the source's quotes on a date the target already has
  one, which wins, and each is deleted. Row by row, and **without a journal
  entry**: the merge manifest lists every quote this moves or drops, and the
  dropped rows' values are its before-image. Both securities' quote
  invalidation runs, in the caller's transaction.

  Called by `Portfolixir.Lifecycle.SecurityMerge` only (pinned by
  `test/portfolixir/catalog/quotes_authored_test.exs`), inside the merge's
  transaction with both securities locked and every row read `FOR UPDATE`.
  A row the database refuses answers `{:error, {:write_refused,
  "security_quote", id, changeset}}` and the caller rolls back.
  """
  @spec merge_gap_fill(integer(), integer(), [SecurityQuote.t()], [SecurityQuote.t()]) ::
          :ok | {:error, {:write_refused, String.t(), integer(), Ecto.Changeset.t()}}
  def merge_gap_fill(source_id, target_id, moved, dropped)
      when is_integer(source_id) and is_integer(target_id) and is_list(moved) and
             is_list(dropped) do
    with :ok <- each_quote(moved, &move_quote(&1, source_id, target_id)),
         :ok <- each_quote(dropped, &drop_quote(&1, source_id)) do
      Invalidation.after_quote_write(source_id, Repo)
      Invalidation.after_quote_write(target_id, Repo)
    end
  end

  defp each_quote(rows, fun) do
    Enum.reduce_while(rows, :ok, fn row, :ok ->
      case fun.(row) do
        {:ok, _row} ->
          {:cont, :ok}

        {:error, changeset} ->
          {:halt, {:error, {:write_refused, "security_quote", row.id, changeset}}}
      end
    end)
  end

  defp move_quote(%SecurityQuote{security_id: source_id} = row, source_id, target_id) do
    row
    |> Ecto.Changeset.change(security_id: target_id)
    |> Ecto.Changeset.unique_constraint([:security_id, :date],
      name: :security_quotes_security_id_date_index
    )
    |> Repo.update(stale_error_field: :id)
  end

  defp drop_quote(%SecurityQuote{security_id: source_id} = row, source_id),
    do: Repo.delete(row, stale_error_field: :id)

  # One transaction that first locks the security row: every quote insert
  # checks its foreign key under a key-share lock of that row, which this
  # lock excludes, so no writer of the security's quotes interleaves.
  defp locked(security_id, fun) do
    Repo.transaction(fn ->
      Security
      |> where([s], s.id == ^security_id)
      |> lock("FOR UPDATE")
      |> select([s], s.id)
      |> Repo.one()
      |> case do
        nil -> Repo.rollback(:not_found)
        _id -> fun.()
      end
    end)
  end

  # The journaled step runs only when there is something to journal (E25 S6,
  # G02): a write that changes nothing leaves no entry.
  defp journaled([], _multi_fun), do: :unchanged

  defp journaled(_rows, multi_fun) do
    case Repo.transaction(multi_fun.()) do
      {:ok, _changes} -> :journaled
      {:error, _step, reason, _changes} -> Repo.rollback(reason)
    end
  end

  defp stored_rows_for_update(security_id, filters) do
    SecurityQuote
    |> where([q], q.security_id == ^security_id)
    |> filter_stored(filters)
    |> order_by([q], asc: q.date)
    |> lock("FOR UPDATE")
    |> Repo.all()
  end

  defp filter_stored(query, []), do: query

  defp filter_stored(query, [{:dates, dates} | rest]),
    do: query |> where([q], q.date in ^dates) |> filter_stored(rest)

  defp filter_stored(query, [{:from, from} | rest]),
    do: query |> where([q], q.date >= ^from) |> filter_stored(rest)

  defp filter_stored(query, [{:to, to} | rest]),
    do: query |> where([q], q.date <= ^to) |> filter_stored(rest)

  defp filter_stored(query, [{:source, source} | rest]),
    do: query |> where([q], q.source == ^source) |> filter_stored(rest)

  defp unchanged?(row, prior) do
    case Map.fetch(prior, row.date) do
      {:ok, stored} -> stored.source == row.source and Decimal.equal?(stored.close, row.close)
      :error -> false
    end
  end

  # F20: an authored row is manual whatever it names. The key form follows
  # the row's own (the changeset casts string- or atom-keyed params, never a
  # mix), and a row that is not a map is left for `prepare_rows/3` to refuse.
  defp authored_row(row) when is_map(row) do
    row = Map.drop(row, [:source, "source"])

    if Enum.any?(Map.keys(row), &is_binary/1),
      do: Map.put(row, "source", "manual"),
      else: Map.put(row, :source, "manual")
  end

  defp authored_row(row), do: row

  @doc """
  Bulk upsert (insert-or-overwrite-close) keyed by `(security_id, date)`,
  **outside the journal**: the market-data writer ADR-0017 exempts, called by
  the quote sync (`protect_manual: true`) and by test fixtures. Every authored
  write goes through `upsert_authored/3` instead, and
  `test/portfolixir/catalog/quotes_authored_test.exs` pins that no other
  writer in `lib/` or the seeds calls this one (E25 S6, T-9).

  Returns `{:ok, count}` on success. Validates each row through the schema
  changeset first; if any row fails validation we return
  `{:error, changeset}` and write nothing.

  With `protect_manual: true` (the sync path) existing rows whose stored
  source is `"manual"` are left untouched — manual entries win over provider
  data — and the return shape becomes `{:ok, upserted, skipped_manual}`.
  Without the option every conflicting row is replaced.
  """
  def upsert_many(security_id, rows, opts \\ [])
      when is_integer(security_id) and is_list(rows) do
    protect_manual? = Keyword.get(opts, :protect_manual, false)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    case prepare_rows(security_id, rows, now) do
      {:ok, []} ->
        if protect_manual?, do: {:ok, 0, 0}, else: {:ok, 0}

      {:ok, prepared} ->
        count = insert_in_chunks(prepared, on_conflict(protect_manual?), security_id)

        if protect_manual? do
          {:ok, count, length(prepared) - count}
        else
          {:ok, count}
        end

      {:error, _} = err ->
        err
    end
  end

  # One transaction, several statements (F28): the counts are summed, and a
  # failing chunk rolls the whole history back. Quotes are allowlisted out of
  # the audit journal (market data), so they cannot ride the journal seam;
  # their bump runs in the same transaction as the rows (E25 S6, F47), so a
  # committed write always carries its bump and a rolled-back one none.
  defp insert_in_chunks(prepared, on_conflict, security_id) do
    {:ok, count} =
      Repo.transaction(fn ->
        count =
          prepared
          |> Enum.chunk_every(@insert_chunk)
          |> Enum.reduce(0, fn chunk, total ->
            {count, _} =
              Repo.insert_all(SecurityQuote, chunk,
                on_conflict: on_conflict,
                conflict_target: [:security_id, :date]
              )

            total + count
          end)

        if security_id, do: Invalidation.after_quote_write(security_id, Repo)
        count
      end)

    count
  end

  # Postgres counts a conflicting row only when the DO UPDATE actually ran,
  # so with the manual-protecting WHERE the difference between prepared rows
  # and the returned count is exactly the number of skipped manual rows.
  defp on_conflict(false), do: {:replace, [:close, :source, :updated_at]}

  defp on_conflict(true) do
    from(q in SecurityQuote,
      update: [
        set: [
          close: fragment("EXCLUDED.close"),
          source: fragment("EXCLUDED.source"),
          updated_at: fragment("EXCLUDED.updated_at")
        ]
      ],
      where: q.source != "manual"
    )
  end

  @doc """
  Returns the relative price change between today's most recent close and
  the close on/before `(today - days_back)`, as a Decimal in fraction form
  (e.g. `Decimal.new("0.10")` for +10 %). Returns nil when either side is
  missing.
  """
  def performance(security_id, days_back)
      when is_integer(security_id) and is_integer(days_back) and days_back > 0 do
    today = Clock.today()
    baseline_date = Date.add(today, -days_back)

    with %{close: latest_close} <- adjusted_latest(security_id),
         %SecurityQuote{} = baseline <- at_or_before(security_id, baseline_date),
         %Decimal{} = baseline_close <- adjusted_close(baseline, security_id),
         false <- Decimal.equal?(baseline_close, 0) do
      latest_close
      |> Decimal.sub(baseline_close)
      |> Decimal.div(baseline_close)
    else
      _ -> nil
    end
  end

  # One-off display-basis adjustment of a stored row (ADR-0028 §2), for read
  # paths that fetched the raw row themselves.
  defp adjusted_close(%SecurityQuote{} = quote_row, security_id) do
    [row] =
      QuoteAdjustment.adjust_series(
        [Map.take(quote_row, [:date, :close, :source])],
        split_events(security_id),
        Repo.get(Security, security_id)
      )

    row.close
  end

  @doc """
  Decorates a list of `%Security{}` with derived price metrics, preserving
  input order. Issues one SQL round-trip for the closes (LATERAL subqueries
  pulling latest/prev/1M/1Y close+date+source) plus one for the split events;
  each close is adjusted to the display basis (ADR-0028 §2) before the
  day-change/1M/1Y ratios, so a raw series spanning an effective date never
  shows a phantom split-sized move.

  When the input list is empty no query runs.
  """
  def attach_metrics([]), do: []

  # The SQL is a literal with positional parameters only ($1..$4); nothing is
  # interpolated into the query string. The latest and previous closes are
  # capped at MarketDataBounds.latest_date/0 like every latest read (F26), so a
  # row dated past it neither prices a security nor hides a stale quote.
  # sobelow_skip ["SQL.Query"]
  def attach_metrics(securities) when is_list(securities) do
    ids = Enum.map(securities, & &1.id)
    today = Clock.today()
    cutoff_1m = Date.add(today, -30)
    cutoff_1y = Date.add(today, -365)

    sql = """
    SELECT s.id,
           latest.close   AS latest_close,
           latest.date    AS latest_date,
           latest.source  AS latest_source,
           prev.close     AS prev_close,
           prev.date      AS prev_date,
           prev.source    AS prev_source,
           one_m.close    AS m_close,
           one_m.date     AS m_date,
           one_m.source   AS m_source,
           one_y.close    AS y_close,
           one_y.date     AS y_date,
           one_y.source   AS y_source
    FROM securities s
    LEFT JOIN LATERAL (
      SELECT q.close, q.date, q.source
      FROM security_quotes q
      WHERE q.security_id = s.id AND q.date <= $4
      ORDER BY q.date DESC
      LIMIT 1
    ) latest ON TRUE
    LEFT JOIN LATERAL (
      SELECT q.close, q.date, q.source
      FROM security_quotes q
      WHERE q.security_id = s.id AND q.date <= $4
      ORDER BY q.date DESC
      OFFSET 1 LIMIT 1
    ) prev ON TRUE
    LEFT JOIN LATERAL (
      SELECT q.close, q.date, q.source
      FROM security_quotes q
      WHERE q.security_id = s.id AND q.date <= $2
      ORDER BY q.date DESC
      LIMIT 1
    ) one_m ON TRUE
    LEFT JOIN LATERAL (
      SELECT q.close, q.date, q.source
      FROM security_quotes q
      WHERE q.security_id = s.id AND q.date <= $3
      ORDER BY q.date DESC
      LIMIT 1
    ) one_y ON TRUE
    WHERE s.id = ANY($1)
    """

    %Postgrex.Result{rows: result_rows} =
      Repo.query!(sql, [ids, cutoff_1m, cutoff_1y, MarketDataBounds.latest_date()])

    by_id = Map.new(result_rows, fn [id | _rest] = row -> {id, metrics_row(row)} end)
    events_by_security = split_events_by_security(ids)

    Enum.map(securities, fn security ->
      row = Map.get(by_id, security.id, %{})
      events = Map.get(events_by_security, security.id, [])
      %SecurityWithMetrics{security: security, metrics: metrics_from_row(row, events, security)}
    end)
  end

  defp metrics_row([id | closes]) do
    [latest_close, latest_date, latest_source, prev_close, prev_date, prev_source] =
      Enum.take(closes, 6)

    [m_close, m_date, m_source, y_close, y_date, y_source] = Enum.drop(closes, 6)

    %{
      id: id,
      latest: point(latest_close, latest_date, latest_source),
      latest_date: latest_date,
      prev: point(prev_close, prev_date, prev_source),
      one_m: point(m_close, m_date, m_source),
      one_y: point(y_close, y_date, y_source)
    }
  end

  defp point(close, date, source) do
    case decimal_or_nil(close) do
      nil -> nil
      decimal -> %{close: decimal, date: date, source: source}
    end
  end

  defp metrics_from_row(row, events, security) do
    latest_close = adjusted_point(row[:latest], events, security)
    prev_close = adjusted_point(row[:prev], events, security)
    m_close = adjusted_point(row[:one_m], events, security)
    y_close = adjusted_point(row[:one_y], events, security)

    %{
      latest_price: latest_close,
      latest_price_date: row[:latest_date],
      day_change_abs: diff(latest_close, prev_close),
      day_change_pct: ratio(latest_close, prev_close),
      performance_1m: ratio(latest_close, m_close),
      performance_1y: ratio(latest_close, y_close)
    }
  end

  defp adjusted_point(nil, _events, _security), do: nil

  defp adjusted_point(%{close: close, date: date, source: source}, events, security) do
    QuoteAdjustment.display_close(close, date, QuoteAdjustment.basis(source, security), events)
  end

  defp decimal_or_nil(nil), do: nil
  defp decimal_or_nil(%Decimal{} = d), do: d
  defp decimal_or_nil(other), do: Decimal.new(to_string(other))

  defp diff(nil, _), do: nil
  defp diff(_, nil), do: nil
  defp diff(latest, prev), do: Decimal.sub(latest, prev)

  defp ratio(nil, _), do: nil
  defp ratio(_, nil), do: nil

  defp ratio(latest, baseline) do
    if Decimal.equal?(baseline, 0) do
      nil
    else
      latest
      |> Decimal.sub(baseline)
      |> Decimal.div(baseline)
    end
  end

  # Every row is a quote object, and one date appears once (E25 S4, F13): a
  # row of another shape or a repeated date is the batch's changeset error,
  # never a raise in the insert (the upsert cannot write one row twice).
  defp prepare_rows(security_id, rows, now) do
    rows
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn
      row, {:ok, acc, seen} when is_map(row) ->
        changeset =
          SecurityQuote.changeset(%SecurityQuote{}, put_security_id(row, security_id))

        prepare_row(changeset, acc, seen, now)

      _not_a_row, _acc ->
        {:halt, {:error, batch_error(:quotes, "must be a list of quote objects")}}
    end)
    |> case do
      {:ok, prepared, _seen} -> {:ok, prepared}
      {:error, _changeset} = error -> error
    end
  end

  defp prepare_row(%Ecto.Changeset{valid?: false} = changeset, _acc, _seen, _now),
    do: {:halt, {:error, changeset}}

  defp prepare_row(changeset, acc, seen, now) do
    data = Ecto.Changeset.apply_changes(changeset)

    if MapSet.member?(seen, data.date) do
      message = "#{Date.to_iso8601(data.date)} is given more than once"
      {:halt, {:error, batch_error(:date, message)}}
    else
      row = %{
        security_id: data.security_id,
        date: data.date,
        close: data.close,
        source: data.source,
        inserted_at: now,
        updated_at: now
      }

      {:cont, {:ok, [row | acc], MapSet.put(seen, data.date)}}
    end
  end

  defp batch_error(field, message) do
    %SecurityQuote{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.add_error(field, message)
  end

  defp put_security_id(row, security_id) do
    if Enum.any?(Map.keys(row), &is_binary/1) do
      Map.put(row, "security_id", security_id)
    else
      Map.put(row, :security_id, security_id)
    end
  end
end
