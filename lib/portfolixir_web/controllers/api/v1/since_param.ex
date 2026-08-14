defmodule PortfolixirWeb.Api.V1.SinceParam do
  @moduledoc """
  `?since=` delta reads (FR-38, issue #666), pull-only by design.

  Parses the `since` parameter into the naive-UTC cut the timestamp columns
  compare against. Accepted forms: an ISO8601 datetime with offset
  (converted to UTC), a naive ISO8601 datetime (taken as UTC), or a plain
  ISO date (start of that day, UTC). Anything else is a validation error.

  The delta covers creates and updates (`updated_at` strictly after the
  cut). Deletions are not represented — a caller that must detect deletions
  performs a full read. Push delivery stays gated (B3.7); this module is
  deliberately the whole of FR-38's change-propagation surface.
  """

  @delta_note "Rows created or updated strictly after `since` (UTC), by " <>
                "their updated_at. Deletions are not represented - a caller " <>
                "that must detect deletions performs a full read. Use this " <>
                "response's `as_of` as the next `since`."

  @doc "Parses `since`; `{:ok, nil}` when absent, `{:error, :since}` when invalid."
  def parse(params) do
    case Map.get(params, "since") do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      value when is_binary(value) -> parse_value(value)
      _other -> {:error, :since}
    end
  end

  defp parse_value(value) do
    with :error <- parse_datetime(value),
         :error <- parse_naive(value),
         :error <- parse_date(value) do
      {:error, :since}
    else
      {:ok, naive} -> {:ok, %{raw: value, cut: naive}}
    end
  end

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.to_naive(datetime)}
      _other -> :error
    end
  end

  defp parse_naive(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> {:ok, naive}
      _other -> :error
    end
  end

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, NaiveDateTime.new!(date, ~T[00:00:00])}
      _other -> :error
    end
  end

  @doc """
  Adds the delta envelope (`since`, `as_of`, `delta_note`) to a `%{data: _}`
  response when a delta cut is active; leaves the plain read untouched.
  """
  def put_envelope(response, nil), do: response

  def put_envelope(response, %{raw: raw}) do
    Map.merge(response, %{
      since: raw,
      as_of: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      delta_note: @delta_note
    })
  end
end
