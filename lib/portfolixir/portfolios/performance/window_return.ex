defmodule Portfolixir.Portfolios.Performance.WindowReturn do
  @moduledoc """
  A window's price return in EUR, from stored closes and stored EUR-hub
  rates (ADR-0055 §3; the Sprint 25 plan's D-3). It is the one function the
  sale hindsight read (`GET /api/v1/sales/hindsight`) and the prediction
  resolution both call, so the two cannot drift. Nothing is stored: every
  read derives the figure from what the catalogue holds at that moment.

  ## The close lookup (`close_on_or_before/2`)

  The close that **stands for** a date `D` is the security's last stored
  close dated on or before `D`, and only a positive one: a stored close of 0
  or below is no price (a release before the plausibility bounds could store
  one), as in the benchmark comparison (ADR-0046). A close dated after `D`
  never stands for it.

  **Staleness:** a close more than 7 calendar days before `D` is no close.
  A close dated `D - 7` stands for `D`; one dated `D - 8` does not.

  The close is read in the **current display basis** (ADR-0028 §2,
  `Portfolixir.Catalog.Quotes.adjust_rows/2`): a raw close before a booked
  split is divided by the cumulative ratio of the later splits, so a split
  inside a window is not a move. Both closes of one window are adjusted from
  one read of the split events, and the stored value is named beside the
  adjusted one.

  Which `D` a caller passes is the caller's rule, not this module's:

    * the prediction resolution (ADR-0055 §3, as amended on 2026-11-05)
      passes the UTC day of `made_at` for the start, because the start
      close is the last one **on or before** the day the call was made, and
      `resolves_on` for the end;
    * the sale hindsight read (D-3) passes the sale day for the start and
      each span's end date for the end.

  ## The conversion

  Each close converts to EUR at the stored EUR-hub rate **of the close's own
  date**, by valuation's rule: the most recent stored rate on or before that
  date, carried forward without a bound, never a later one
  (`Portfolixir.Fx.hub_rate/2`; the displayed `fx_rate` is
  `Portfolixir.Fx.rate/3`'s, which the daily valuation walk and the
  benchmark comparison compute alike: `fx_rate = 1 / the hub rate`, GBX
  through `GBP × 100`). A EUR close converts at exactly 1. A currency with no stored
  rate on or before the close's date is `:no_fx_rate`. The rate carries no
  staleness bound of its own, as in valuation; the close date it is read for
  does.

  ## The return and its precision

  `return = end EUR value / start EUR value - 1`, computed as **one
  division of exact products** from the stored hub rates
  (`Portfolixir.Fx.hub_rate/2`, units of the currency per 1 EUR):

      return = (end.close × start_hub) / (start.close × end_hub) - 1

  which is `(end.close / end_hub) / (start.close / start_hub) - 1`. The two
  products are exact (a stored close and a stored rate have few digits);
  the quotient is rounded once, at `Decimal`'s default context, 34
  significant digits half-up (IEEE 754 decimal128), and the subtraction of
  1 is exact. GBX's factor of 100 (`GBP × 100`) cancels in the ratio; EUR's
  hub rate is 1.

  **Why not the quotient of the EUR values:** each EUR value multiplies a
  close by a 34-digit-rounded inverse rate, so two identical moves in the
  same non-EUR currency read returns differing by 1E-33, and an excess
  that is exactly 0 (a miss, ADR-0055 §3) read as a hit (the Sprint 25
  closing act's money lens: USD 123 -> 135.3 against USD 17 -> 18.7 while
  EUR/USD moved 1.07 -> 1.13). With one division, equal ratios give equal
  returns to the last digit. The displayed `fx_rate` and `eur_value` stay
  as before (`fx_rate = 1 / hub`, `eur_value = close × fx_rate`, each at 34
  digits), for reading, not for the return. Nothing else is rounded on
  purpose (ADR-0003, ADR-0007); a payload carries the Decimal as a string,
  unrounded.

  It is a **price return**: distributions are not counted, on either side.

  ## The answer

  `price_return/3` answers `{:ok, result}` (`t:result/0`) or
  `{:error, reason}`, checked in this order and the first that applies
  returned:

    * `:invalid_window` — the end date is before the start date;
    * `:no_start_close` — no close stands for the start date;
    * `:no_end_close` — no close stands for the end date;
    * `:no_fx_rate` — either close has no stored rate path to EUR.

  It takes any catalogue security, a benchmark security too; a caller
  measuring a benchmark renames the two close reasons (ADR-0055 §3:
  `:no_benchmark_close`).

  ## A fixed-rate benchmark (`fixed_rate_return/3`)

  ADR-0055 §3's `rate:<decimal>` benchmark: the fixed annual rate's return
  over the calendar days between two dates, compounded by
  `Portfolixir.Portfolios.Performance.Benchmark.daily_rate_factor/1` once a
  day from a base of 1, one multiplication a day, exactly as the benchmark
  comparison's fixed-rate series compounds. Rate 0 is exactly 0.
  """

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Fx
  alias Portfolixir.Portfolios.Performance.Benchmark

  @staleness_days 7
  @eur "EUR"
  @zero Decimal.new(0)
  @one Decimal.new(1)

  @typedoc """
  The close that stands for a date:

    * `stands_for` — the date asked for (`D`);
    * `date` — the close's own date, on or before `D` and at most
      #{@staleness_days} days before it;
    * `close` — the close in the current display basis (ADR-0028 §2), in
      the security's currency;
    * `stored_close` — the close as stored;
    * `source` — the stored row's source (`manual`, `auto`, ...).
  """
  @type close :: %{
          stands_for: Date.t(),
          date: Date.t(),
          close: Decimal.t(),
          stored_close: Decimal.t(),
          source: String.t()
        }

  @typedoc """
  One end of a window: `t:close/0` plus

    * `fx_rate` — EUR per one unit of the security's currency, at the most
      recent stored EUR-hub rate on or before `date` (`1` for EUR);
    * `eur_value` — `close × fx_rate`.
  """
  @type window_end :: %{
          stands_for: Date.t(),
          date: Date.t(),
          close: Decimal.t(),
          stored_close: Decimal.t(),
          source: String.t(),
          fx_rate: Decimal.t(),
          eur_value: Decimal.t()
        }

  @typedoc "What `price_return/3` answers: both ends and the return."
  @type result :: %{
          security_id: integer(),
          currency_code: String.t(),
          start: window_end(),
          end: window_end(),
          return: Decimal.t()
        }

  @type reason :: :invalid_window | :no_start_close | :no_end_close | :no_fx_rate

  @doc "The staleness bound in calendar days: a close older than this before its date is no close."
  @spec staleness_days() :: pos_integer()
  def staleness_days, do: @staleness_days

  @doc """
  The close that stands for `on`: the last positive stored close dated on or
  before it and at most #{@staleness_days} calendar days before it, in the
  current display basis. `{:error, :no_close}` when there is none.
  """
  @spec close_on_or_before(Security.t(), Date.t()) :: {:ok, close()} | {:error, :no_close}
  def close_on_or_before(%Security{} = security, %Date{} = on) do
    case stored_close(security, on) do
      nil ->
        {:error, :no_close}

      row ->
        [adjusted] = Quotes.adjust_rows([row], security)
        {:ok, close_entry(adjusted, on)}
    end
  end

  @doc """
  Whether a positive close dated **on or after** `on` is stored for the
  security: the evidence that the data of `on` is in (ADR-0055 amendment
  of 2026-11-05, §2, finality). It never stands for `on`; the close that
  does is `close_on_or_before/2`'s. Positive closes only, as that lookup
  counts them.
  """
  @spec close_dated_on_or_after?(Security.t(), Date.t()) :: boolean()
  def close_dated_on_or_after?(%Security{id: id}, %Date{} = on),
    do: Quotes.positive_close_on_or_after?(id, on)

  @doc """
  The security's price return in EUR from the close standing for `start_on`
  to the close standing for `end_on` (see the module doc for each rule).

  `{:ok, result}` (`t:result/0`) or `{:error, reason}`, the first of
  `:invalid_window`, `:no_start_close`, `:no_end_close` and `:no_fx_rate`
  that applies.
  """
  @spec price_return(Security.t(), Date.t(), Date.t()) :: {:ok, result()} | {:error, reason()}
  def price_return(%Security{} = security, %Date{} = start_on, %Date{} = end_on) do
    with :ok <- ordered(start_on, end_on),
         {:ok, start_row} <- stored_close(security, start_on) |> found(:no_start_close),
         {:ok, end_row} <- stored_close(security, end_on) |> found(:no_end_close),
         # One read of the split events for both ends: one basis.
         [start_adjusted, end_adjusted] <- Quotes.adjust_rows([start_row, end_row], security),
         {:ok, opening, start_hub} <- in_eur(close_entry(start_adjusted, start_on), security),
         {:ok, closing, end_hub} <- in_eur(close_entry(end_adjusted, end_on), security) do
      {:ok,
       %{
         security_id: security.id,
         currency_code: security.currency_code,
         start: opening,
         end: closing,
         return: ratio_return(opening.close, start_hub, closing.close, end_hub)
       }}
    end
  end

  @doc """
  The return of a fixed annual `rate` (a decimal fraction, `0.05` is 5 %
  p.a.) over the calendar days from `from` to `to`:
  `Benchmark.daily_rate_factor(rate)` multiplied into 1 once per day, minus
  1. Rate 0 and a span of 0 days are exactly 0. The rate is taken as the
  caller parsed it (the API's `benchmark=` parser bounds it by
  `Benchmark.valid_rate?/1`); `to` must not be before `from`.

  ADR-0055 §3 measures a call against it over the calendar days between the
  two dates the security's closes stand for (`start.stands_for` and
  `end.stands_for` of `price_return/3`).
  """
  @spec fixed_rate_return(Decimal.t(), Date.t(), Date.t()) :: Decimal.t()
  def fixed_rate_return(%Decimal{} = rate, %Date{} = from, %Date{} = to) do
    days = Date.diff(to, from)
    compound(Benchmark.daily_rate_factor(rate), days)
  end

  defp compound(factor, days) when is_integer(days) and days >= 0 do
    1..days//1
    |> Enum.reduce(@one, fn _day, acc -> Decimal.mult(acc, factor) end)
    |> Decimal.sub(@one)
  end

  defp ordered(start_on, end_on) do
    if Date.compare(end_on, start_on) == :lt, do: {:error, :invalid_window}, else: :ok
  end

  defp found(nil, reason), do: {:error, reason}
  defp found(row, _reason), do: {:ok, row}

  # The candidates are the stored rows of the seven days up to
  # `on`, read through the catalogue's own range read; the last positive one
  # stands for `on`.
  defp stored_close(%Security{id: id}, on) do
    id
    |> Quotes.range(Date.add(on, -@staleness_days), on)
    |> Enum.filter(&positive?(&1.close))
    |> List.last()
  end

  defp positive?(%Decimal{} = close), do: Decimal.compare(close, @zero) == :gt
  defp positive?(_close), do: false

  defp close_entry(adjusted, stands_for) do
    %{
      stands_for: stands_for,
      date: adjusted.date,
      close: adjusted.close,
      stored_close: adjusted.stored_close,
      source: adjusted.source
    }
  end

  # One division of exact products (see "The return and its precision").
  defp ratio_return(start_close, start_hub, end_close, end_hub) do
    Decimal.mult(end_close, start_hub)
    |> Decimal.div(Decimal.mult(start_close, end_hub))
    |> Decimal.sub(@one)
  end

  # The displayed fx_rate is Fx.rate(currency, "EUR", date): 1 / the hub
  # rate, the same division rate/3 makes; EUR is exactly 1.
  defp in_eur(entry, %Security{currency_code: currency}) do
    case Fx.hub_rate(currency, entry.date) do
      {:ok, hub} ->
        rate = fx_rate(currency, hub)
        {:ok, Map.merge(entry, %{fx_rate: rate, eur_value: Decimal.mult(entry.close, rate)}), hub}

      {:error, :no_rate} ->
        {:error, :no_fx_rate}
    end
  end

  defp fx_rate(@eur, _hub), do: @one
  defp fx_rate(_currency, hub), do: Decimal.div(@one, hub)
end
