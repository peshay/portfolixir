defmodule Portfolixir.Crashes.PeakTrough do
  @moduledoc """
  The crash detection rule `peak_trough_v1` (ADR-0058 §2): a pure function
  of one close series, no Repo, no clock, no config. The caller hands it the
  crash benchmark's closes in its own currency and the current display basis
  (`Portfolixir.Catalog.Quotes.adjust_rows/2`, so a split is not a fall).

  The walk, over the positive closes in date order (a close of zero or below
  is no price and is skipped; a day without a close is skipped, never
  interpolated):

    1. Keep the **running peak**, the highest close so far; among equal
       highs the **latest**, so the decline starts on the last day at the
       high.
    2. A window **opens** on the first close for which
       `(peak − close) / peak ≥ 0.10`, compared exactly: as
       `(peak − close) × 10 ≥ peak`, a `Decimal` product with no division
       and no rounding before the comparison. Its `start` is the peak's date.
    3. Its **trough** is the lowest close after `start` and before the
       series first closes at or above the peak again; among equal lows the
       **earliest**.
    4. It **closes** on the first close at or above the peak
       (`recovered_on`), and the walk continues with that close as the new
       running peak, so windows never overlap.
    5. A window not recovered by the last close is **ongoing**:
       `provisional: true`, its trough the lowest close so far.

  A decline in several legs with no recovery in between is one window.
  Each window names `max_gap_days`, the longest span in calendar days
  between two consecutive closes the walk read from `start` to its recovery
  (or to the last close while it is ongoing), so a window drawn over a stale
  stretch reads as such (§7.8). Its `decline` is `(trough_close −
  peak_close) / peak_close`, the one division, at `Decimal`'s working
  precision.

  Order: the series is sorted by date before the walk, so any read order of
  the same closes gives the same windows (§7.1); a series holds one close
  per date, as the quote table stores them.
  """

  @rule "peak_trough_v1"
  @threshold "0.10"
  # (peak − close) / peak ≥ 1/10  ⇔  (peak − close) × 10 ≥ peak, for peak > 0.
  @threshold_inverse Decimal.new(10)

  @type point :: %{required(:date) => Date.t(), required(:close) => Decimal.t()}

  @type window :: %{
          start: Date.t(),
          peak_close: Decimal.t(),
          trough: Date.t(),
          trough_close: Decimal.t(),
          decline: Decimal.t(),
          recovered_on: Date.t() | nil,
          provisional: boolean(),
          max_gap_days: pos_integer()
        }

  @doc "The rule's name, as the computation basis states it."
  @spec rule() :: String.t()
  def rule, do: @rule

  @doc "The fixed threshold (ADR-0058 §2), as the computation basis states it."
  @spec threshold() :: String.t()
  def threshold, do: @threshold

  @doc "A detected window's key: `d:<benchmark_security_id>:<start>` (ADR-0058 §2)."
  @spec key(pos_integer(), Date.t()) :: String.t()
  def key(benchmark_security_id, %Date{} = start) when is_integer(benchmark_security_id),
    do: "d:#{benchmark_security_id}:#{Date.to_iso8601(start)}"

  @doc """
  The windows `points` hold, oldest first. `points` is a list of
  `%{date, close}` in any order; other keys are ignored.
  """
  @spec detect([point()]) :: [window()]
  def detect(points) when is_list(points) do
    points
    |> Enum.filter(&positive?(&1.close))
    |> Enum.map(&%{date: &1.date, close: &1.close})
    |> Enum.sort_by(& &1.date, Date)
    |> walk()
  end

  defp walk([]), do: []
  defp walk([first | rest]), do: watch(rest, %{peak: first, last: first, gap: 0}, [])

  # No window open: the running peak moves up, or on an equal close to the
  # later day; a close 10 % or more below it opens a window. The longest gap
  # since the peak is kept, because a window's span starts at its peak.
  defp watch([], _state, windows), do: Enum.reverse(windows)

  defp watch([close | rest], %{peak: peak} = state, windows) do
    cond do
      at_or_above?(close, peak) ->
        watch(rest, %{peak: close, last: close, gap: 0}, windows)

      opens?(peak, close) ->
        fall(rest, Map.put(step(state, close), :trough, close), windows)

      true ->
        watch(rest, step(state, close), windows)
    end
  end

  # A window open: a close at or above the peak recovers it and becomes the
  # running peak; a strictly lower close is the new trough, so the earliest
  # of equal lows stays.
  defp fall([], open, windows), do: Enum.reverse([window(open, nil) | windows])

  defp fall([close | rest], open, windows) do
    open = step(open, close)

    cond do
      at_or_above?(close, open.peak) ->
        watch(rest, %{peak: close, last: close, gap: 0}, [window(open, close.date) | windows])

      Decimal.compare(close.close, open.trough.close) == :lt ->
        fall(rest, %{open | trough: close}, windows)

      true ->
        fall(rest, open, windows)
    end
  end

  defp step(state, close),
    do: %{state | last: close, gap: max(state.gap, Date.diff(close.date, state.last.date))}

  defp window(open, recovered_on) do
    %{peak: peak, trough: trough} = open

    %{
      start: peak.date,
      peak_close: peak.close,
      trough: trough.date,
      trough_close: trough.close,
      decline: Decimal.div(Decimal.sub(trough.close, peak.close), peak.close),
      recovered_on: recovered_on,
      provisional: is_nil(recovered_on),
      max_gap_days: open.gap
    }
  end

  defp at_or_above?(close, peak), do: Decimal.compare(close.close, peak.close) != :lt

  defp opens?(peak, close) do
    peak.close
    |> Decimal.sub(close.close)
    |> Decimal.mult(@threshold_inverse)
    |> Decimal.compare(peak.close) != :lt
  end

  defp positive?(%Decimal{} = close), do: Decimal.compare(close, 0) == :gt
  defp positive?(_not_a_decimal), do: false
end
