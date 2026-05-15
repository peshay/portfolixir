defmodule Portfolixir.Catalog.Quotes do
  @moduledoc """
  Sub-context for security price history.

  Quotes are stored as an append/upsert log keyed by `(security_id, date)`.
  This module provides the read paths used by the list and detail views
  (latest, last-two, range, performance) and the write path used by both
  manual entries and the background sync (`upsert_many/2`).

  All Decimal arithmetic is performed via `Decimal` — no floats — so values
  round-trip losslessly to charts and downstream calculations.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.SecurityWithMetrics
  alias Portfolixir.Repo

  @doc "Most recent quote for the security, or nil."
  def latest(security_id) when is_integer(security_id) do
    SecurityQuote
    |> where([q], q.security_id == ^security_id)
    |> order_by([q], desc: q.date)
    |> limit(1)
    |> Repo.one()
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
  Bulk upsert (insert-or-overwrite-close) keyed by `(security_id, date)`.

  Returns `{:ok, count}` on success. Validates each row through the schema
  changeset first; if any row fails validation we return
  `{:error, changeset}` and write nothing.
  """
  def upsert_many(security_id, rows) when is_integer(security_id) and is_list(rows) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    case prepare_rows(security_id, rows, now) do
      {:ok, []} ->
        {:ok, 0}

      {:ok, prepared} ->
        {count, _} =
          Repo.insert_all(SecurityQuote, prepared,
            on_conflict: {:replace, [:close, :source, :updated_at]},
            conflict_target: [:security_id, :date]
          )

        {:ok, count}

      {:error, _} = err ->
        err
    end
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

    with %SecurityQuote{close: latest_close} <- latest(security_id),
         %SecurityQuote{close: baseline_close} <- at_or_before(security_id, baseline_date),
         false <- Decimal.equal?(baseline_close, 0) do
      latest_close
      |> Decimal.sub(baseline_close)
      |> Decimal.div(baseline_close)
    else
      _ -> nil
    end
  end

  @doc """
  Decorates a list of `%Security{}` with derived price metrics, preserving
  input order. Issues a single SQL round-trip per call regardless of list
  size (one query with LATERAL subqueries pulling latest/prev/1M/1Y closes).

  When the input list is empty no query runs.
  """
  def attach_metrics([]), do: []

  def attach_metrics(securities) when is_list(securities) do
    ids = Enum.map(securities, & &1.id)
    today = Date.utc_today()
    cutoff_1m = Date.add(today, -30)
    cutoff_1y = Date.add(today, -365)

    sql = """
    SELECT s.id,
           latest.close   AS latest_close,
           latest.date    AS latest_date,
           prev.close     AS prev_close,
           one_m.close    AS m_close,
           one_y.close    AS y_close
    FROM securities s
    LEFT JOIN LATERAL (
      SELECT q.close, q.date
      FROM security_quotes q
      WHERE q.security_id = s.id
      ORDER BY q.date DESC
      LIMIT 1
    ) latest ON TRUE
    LEFT JOIN LATERAL (
      SELECT q.close
      FROM security_quotes q
      WHERE q.security_id = s.id
      ORDER BY q.date DESC
      OFFSET 1 LIMIT 1
    ) prev ON TRUE
    LEFT JOIN LATERAL (
      SELECT q.close
      FROM security_quotes q
      WHERE q.security_id = s.id AND q.date <= $2
      ORDER BY q.date DESC
      LIMIT 1
    ) one_m ON TRUE
    LEFT JOIN LATERAL (
      SELECT q.close
      FROM security_quotes q
      WHERE q.security_id = s.id AND q.date <= $3
      ORDER BY q.date DESC
      LIMIT 1
    ) one_y ON TRUE
    WHERE s.id = ANY($1)
    """

    %Postgrex.Result{rows: result_rows} =
      Repo.query!(sql, [ids, cutoff_1m, cutoff_1y])

    rows =
      Enum.map(result_rows, fn [id, latest_close, latest_date, prev_close, m_close, y_close] ->
        %{
          id: id,
          latest_close: latest_close,
          latest_date: latest_date,
          prev_close: prev_close,
          m_close: m_close,
          y_close: y_close
        }
      end)

    by_id = Map.new(rows, fn row -> {row.id, row} end)

    Enum.map(securities, fn security ->
      row = Map.get(by_id, security.id, %{})
      %SecurityWithMetrics{security: security, metrics: metrics_from_row(row)}
    end)
  end

  defp metrics_from_row(row) do
    latest_close = decimal_or_nil(row[:latest_close])
    prev_close = decimal_or_nil(row[:prev_close])
    m_close = decimal_or_nil(row[:m_close])
    y_close = decimal_or_nil(row[:y_close])

    %{
      latest_price: latest_close,
      latest_price_date: row[:latest_date],
      day_change_abs: diff(latest_close, prev_close),
      day_change_pct: ratio(latest_close, prev_close),
      performance_1m: ratio(latest_close, m_close),
      performance_1y: ratio(latest_close, y_close)
    }
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
