defmodule Portfolixir.Catalog.Quotes do
  @moduledoc """
  Sub-context for security price history.

  Quotes are stored as an append/upsert log keyed by `(security_id, date)`.
  This module provides the read paths used by the list and detail views
  (latest, last-two, range, performance) and the write path used by both
  manual entries and the background sync (`upsert_many/2`).

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

  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.QuoteAdjustment
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecurityWithMetrics
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @doc "Most recent quote for the security, or nil."
  def latest(security_id) when is_integer(security_id) do
    SecurityQuote
    |> where([q], q.security_id == ^security_id)
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
    |> distinct([q], q.security_id)
    |> order_by([q], asc: q.security_id, desc: q.date)
    |> Repo.all()
    |> Map.new(&{&1.security_id, &1})
  end

  @doc "Up to the two most recent quotes, descending by date."
  def latest_two(security_id) when is_integer(security_id) do
    SecurityQuote
    |> where([q], q.security_id == ^security_id)
    |> order_by([q], desc: q.date)
    |> limit(2)
    |> Repo.all()
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
  def range(security_id, %Date{} = from, %Date{} = to) when is_integer(security_id) do
    SecurityQuote
    |> where([q], q.security_id == ^security_id and q.date >= ^from and q.date <= ^to)
    |> order_by([q], asc: q.date)
    |> Repo.all()
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
    events = split_events(security_id)
    security = Repo.get(Security, security_id)

    security_id
    |> range(from, to)
    |> Enum.map(&Map.take(&1, [:date, :close, :source]))
    |> QuoteAdjustment.adjust_series(events, security)
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
  Bulk upsert (insert-or-overwrite-close) keyed by `(security_id, date)`.

  Returns `{:ok, count}` on success. Validates each row through the schema
  changeset first; if any row fails validation we return
  `{:error, changeset}` and write nothing.

  With `protect_manual: true` (the sync path) existing rows whose stored
  source is `"manual"` are left untouched — manual entries win over provider
  data — and the return shape becomes `{:ok, upserted, skipped_manual}`.
  Without the option (the manual entry path) every conflicting row is
  replaced, so a human correcting a value can still overwrite anything.
  """
  def upsert_many(security_id, rows, opts \\ [])
      when is_integer(security_id) and is_list(rows) do
    protect_manual? = Keyword.get(opts, :protect_manual, false)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    case prepare_rows(security_id, rows, now) do
      {:ok, []} ->
        if protect_manual?, do: {:ok, 0, 0}, else: {:ok, 0}

      {:ok, prepared} ->
        {count, _} =
          Repo.insert_all(SecurityQuote, prepared,
            on_conflict: on_conflict(protect_manual?),
            conflict_target: [:security_id, :date]
          )

        if protect_manual? do
          {:ok, count, length(prepared) - count}
        else
          {:ok, count}
        end

      {:error, _} = err ->
        err
    end
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
    today = Date.utc_today()
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

  # The SQL is a literal with positional parameters only ($1..$3); nothing is
  # interpolated into the query string.
  # sobelow_skip ["SQL.Query"]
  def attach_metrics(securities) when is_list(securities) do
    ids = Enum.map(securities, & &1.id)
    today = Date.utc_today()
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
      WHERE q.security_id = s.id
      ORDER BY q.date DESC
      LIMIT 1
    ) latest ON TRUE
    LEFT JOIN LATERAL (
      SELECT q.close, q.date, q.source
      FROM security_quotes q
      WHERE q.security_id = s.id
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
      Repo.query!(sql, [ids, cutoff_1m, cutoff_1y])

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

  defp prepare_rows(security_id, rows, now) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      changeset =
        SecurityQuote.changeset(%SecurityQuote{}, put_security_id(row, security_id))

      if changeset.valid? do
        data = Ecto.Changeset.apply_changes(changeset)

        {:cont,
         {:ok,
          [
            %{
              security_id: data.security_id,
              date: data.date,
              close: data.close,
              source: data.source,
              inserted_at: now,
              updated_at: now
            }
            | acc
          ]}}
      else
        {:halt, {:error, changeset}}
      end
    end)
  end

  defp put_security_id(row, security_id) do
    if Enum.any?(Map.keys(row), &is_binary/1) do
      Map.put(row, "security_id", security_id)
    else
      Map.put(row, :security_id, security_id)
    end
  end
end
