defmodule Portfolixir.Catalog.QuoteAdjustment do
  @moduledoc """
  Pure split-adjustment engine for stored quote history (ADR-0028 §2).

  A booked split never mutates stored quotes (NFR-2); instead this engine
  derives append-only adjustment factors at read time from the split events
  (`%{date: effective_date, ratio: {p, q}}`, the normalized integer pair of
  ADR-0028 §1) and the per-row **basis** of each stored close:

    * `:raw` — as-traded prices: manual rows, and the latest-own-trade-price
      fallback (always raw, §2). For dates strictly before an effective date
      the displayed close is the stored close divided by the cumulative ratio
      of all strictly-later splits; a close dated **on** the effective date is
      already post-split basis.
    * `:provider_mirror` — provider-synced rows (`auto`, `coingecko`,
      `portfolio_performance`): the sync refetches the full, back-adjusted
      history every cycle, so the stored series is already continuous and
      gets **no** additional factor — applying one would double-adjust
      (the Portfolio Performance #4223 trap).

  The basis mapping is total and has deliberately **no catch-all clause**
  (AR-7 spirit): a new quote source without a declared basis raises. The
  per-security `treat_quotes_as_raw` flag (ADR-0028 §2 escape hatch) forces
  the raw basis for providers that never back-adjust.

  Everything here is a pure function of `(closes incl. source, split
  events)` — no Repo, no clock, no config (AR-2: engines compute, the shell
  loads; the loading side lives in `Portfolixir.Catalog.Quotes`). Factors are
  exact integer-pair products; the single division happens at full `Decimal`
  precision (ADR-0016 — round only at display/persistence boundaries).
  """

  alias Portfolixir.Catalog.Security

  @typedoc "A security-level split event: effective date plus normalized ratio."
  @type split_event :: %{date: Date.t(), ratio: {pos_integer(), pos_integer()}}
  @type basis :: :raw | :provider_mirror

  # The preview basis guard looks this many days around the effective date for
  # a close on each side; without one per side the check reports
  # `:insufficient_quotes` instead of implying a clean verification (§2).
  @basis_check_window_days 14

  @doc "The day window the preview basis guard inspects around the effective date."
  def basis_check_window_days, do: @basis_check_window_days

  @doc """
  The storage basis of one close. Total over every pricing source the read
  models merge — all `Portfolixir.Catalog.Quote.sources/0` values plus the
  `:trade` fallback — with **no catch-all**: an undeclared source raises.
  """
  @spec basis(String.t() | :trade, Security.t() | nil) :: basis()
  def basis(source, security \\ nil)
  def basis("manual", _security), do: :raw
  def basis(:trade, _security), do: :raw
  def basis("auto", security), do: mirror_unless_forced_raw(security)
  def basis("coingecko", security), do: mirror_unless_forced_raw(security)
  def basis("portfolio_performance", security), do: mirror_unless_forced_raw(security)

  defp mirror_unless_forced_raw(%Security{treat_quotes_as_raw: true}), do: :raw
  defp mirror_unless_forced_raw(_security), do: :provider_mirror

  @doc """
  The cumulative split ratio of all events **strictly after** `date`, as an
  exact integer pair `{p, q}` (product of the per-event pairs).
  """
  @spec cumulative_ratio_after([split_event()], Date.t()) :: {pos_integer(), pos_integer()}
  def cumulative_ratio_after(events, %Date{} = date) do
    events
    |> Enum.filter(&(Date.compare(&1.date, date) == :gt))
    |> ratio_product()
  end

  defp ratio_product(events) do
    Enum.reduce(events, {1, 1}, fn %{ratio: {p, q}}, {pn, qn} -> {pn * p, qn * q} end)
  end

  @doc """
  The display (current-basis) value of one stored close: raw closes divide by
  the cumulative ratio of strictly-later splits, provider-mirror closes pass
  through unchanged.
  """
  @spec display_close(Decimal.t(), Date.t(), basis(), [split_event()]) :: Decimal.t()
  def display_close(%Decimal{} = close, _date, :provider_mirror, _events), do: close

  def display_close(%Decimal{} = close, %Date{} = date, :raw, events),
    do: divide_by_ratio(close, cumulative_ratio_after(events, date))

  @doc """
  The as-traded (raw, own-date basis) value of one stored close — the inverse
  direction: provider-mirror closes multiply back up by the cumulative ratio
  of strictly-later splits, raw closes are already as-traded.
  """
  @spec raw_close(Decimal.t(), Date.t(), basis(), [split_event()]) :: Decimal.t()
  def raw_close(%Decimal{} = close, _date, :raw, _events), do: close

  def raw_close(%Decimal{} = close, %Date{} = date, :provider_mirror, events),
    do: multiply_by_ratio(close, cumulative_ratio_after(events, date))

  @doc """
  Moves a carried as-traded price from the basis era of `from_date` into the
  era of `to_date`: divides by every ratio effective within `(from, to]` —
  the carry step a daily walk applies when it crosses an effective date.
  """
  @spec rebase_close(Decimal.t(), Date.t(), Date.t(), [split_event()]) :: Decimal.t()
  def rebase_close(%Decimal{} = close, %Date{} = from_date, %Date{} = to_date, events) do
    events
    |> Enum.filter(fn %{date: eff} ->
      Date.compare(eff, from_date) == :gt and Date.compare(eff, to_date) != :gt
    end)
    |> ratio_product()
    |> then(&divide_by_ratio(close, &1))
  end

  @doc """
  The current-basis value of a trade-price fallback (§2: fallback trade
  prices are **always** raw basis): the booked price divided by the
  cumulative ratio of splits effective after the trade's date.
  """
  @spec display_trade_price(Decimal.t(), Date.t(), [split_event()]) :: Decimal.t()
  def display_trade_price(%Decimal{} = price, %Date{} = trade_date, events),
    do: display_close(price, trade_date, :raw, events)

  @doc """
  Adjusts a stored quote series (rows of `%{date, close, source}`) to the
  display basis. Each output row keeps the stored value reachable:
  `%{date, close, stored_close, source, basis, adjusted?}`.
  """
  @spec adjust_series([map()], [split_event()], Security.t() | nil) :: [map()]
  def adjust_series(quotes, events, security) when is_list(quotes) do
    Enum.map(quotes, fn row ->
      row_basis = basis(row.source, security)
      display = display_close(row.close, row.date, row_basis, events)

      %{
        date: row.date,
        close: display,
        stored_close: row.close,
        source: row.source,
        basis: row_basis,
        adjusted?: not Decimal.equal?(display, row.close)
      }
    end)
  end

  @doc """
  The overall basis of an adjusted series (UX-DR11 chart/table label):
  `:raw`, `:provider_mirror`, `:mixed` or `:empty`.
  """
  @spec series_basis([%{basis: basis()}]) :: :raw | :provider_mirror | :mixed | :empty
  def series_basis([]), do: :empty

  def series_basis(rows) when is_list(rows) do
    case rows |> Enum.map(& &1.basis) |> Enum.uniq() do
      [single] -> single
      _mixed -> :mixed
    end
  end

  @doc """
  The booking-preview misclassification guard (ADR-0028 §2): compares the
  stored closes around `effective_date` against the classification the
  per-row `source` implies. A visible jump indicates a raw basis, a
  continuous series an adjusted one; a contradiction warns instead of
  silently adjusting. With no close within #{@basis_check_window_days} days
  on either side the status is `:insufficient_quotes`.

  `quotes` are stored rows (`%{date, close, source}`) around the effective
  date; `ratio` is the normalized `{p, q}` pair being booked. Returns
  `%{status: :consistent | :contradiction | :insufficient_quotes,
  expected_basis: basis() | nil, observed: :jump | :continuous | nil}`.
  """
  @spec basis_check([map()], Date.t(), {pos_integer(), pos_integer()}, Security.t() | nil) ::
          %{status: atom(), expected_basis: basis() | nil, observed: atom() | nil}
  def basis_check(quotes, %Date{} = effective_date, {p, q}, security) do
    before_row = last_close_before(quotes, effective_date)
    after_row = first_close_from(quotes, effective_date)

    case {before_row, after_row} do
      {%{} = before_quote, %{} = after_quote} ->
        compare_bases(before_quote, after_quote, {p, q}, security)

      _missing_side ->
        %{status: :insufficient_quotes, expected_basis: nil, observed: nil}
    end
  end

  defp last_close_before(quotes, effective_date) do
    window_start = Date.add(effective_date, -@basis_check_window_days)

    quotes
    |> Enum.filter(fn %{date: date} ->
      Date.compare(date, effective_date) == :lt and Date.compare(date, window_start) != :lt
    end)
    |> Enum.max_by(& &1.date, Date, fn -> nil end)
  end

  defp first_close_from(quotes, effective_date) do
    window_end = Date.add(effective_date, @basis_check_window_days)

    quotes
    |> Enum.filter(fn %{date: date} ->
      Date.compare(date, effective_date) != :lt and Date.compare(date, window_end) != :gt
    end)
    |> Enum.min_by(& &1.date, Date, fn -> nil end)
  end

  # The observed jump factor is close_before / close_after; the expected raw
  # jump is the ratio p/q, the expected mirror factor is 1. The classifier
  # splits at the geometric midpoint sqrt(p/q) between the two expectations,
  # so ordinary day-to-day moves stay on the "continuous" side while a real
  # unadjusted split lands on the "jump" side — deterministic Decimal math.
  defp compare_bases(before_quote, after_quote, {p, q}, security) do
    expected = basis(before_quote.source, security)

    if Decimal.equal?(after_quote.close, 0) do
      %{status: :insufficient_quotes, expected_basis: expected, observed: nil}
    else
      observed = observe_jump(Decimal.div(before_quote.close, after_quote.close), {p, q})
      %{status: check_status(expected, observed), expected_basis: expected, observed: observed}
    end
  end

  defp observe_jump(factor, {p, q}) do
    ratio = Decimal.div(Decimal.new(p), Decimal.new(q))
    midpoint = Decimal.sqrt(ratio)

    jump? =
      case Decimal.compare(ratio, 1) do
        :gt -> Decimal.compare(factor, midpoint) == :gt
        _lt -> Decimal.compare(factor, midpoint) == :lt
      end

    if jump?, do: :jump, else: :continuous
  end

  defp check_status(:raw, :jump), do: :consistent
  defp check_status(:provider_mirror, :continuous), do: :consistent
  defp check_status(_expected, _observed), do: :contradiction

  defp divide_by_ratio(close, {1, 1}), do: close
  defp divide_by_ratio(close, {p, q}), do: close |> Decimal.mult(q) |> Decimal.div(p)

  defp multiply_by_ratio(close, {1, 1}), do: close
  defp multiply_by_ratio(close, {p, q}), do: close |> Decimal.mult(p) |> Decimal.div(q)
end
