defmodule Portfolixir.Predictions.Resolution do
  @moduledoc """
  A prediction's resolution, derived at read from stored closes in EUR
  (ADR-0055 §3). Nothing here is stored: every read derives the status, the
  outcome and the figures again, and names the closes it used, so a quote
  corrected later changes the outcome visibly rather than silently.

  Both returns come from `Portfolixir.Portfolios.Performance.WindowReturn`,
  the one function the sale hindsight read uses too, so the two cannot
  drift; this module adds the dates, the benchmark and the outcome rule.

  ## The status

    * `:open` — while today is **on or before** `resolves_on`. ADR-0055
      says a call is open "until `resolves_on` has passed", and its end
      close is the last close on or before `resolves_on`: on that day
      itself the day's close may not be stored yet (the quote sync fetches
      it after the market closes), so a read on the day could score the
      call on the day before's close and flip it once the day's close
      lands. From the day after, the end close is final. Nothing is read
      or computed for an open call. "Today" is the instance's calendar day
      (`Portfolixir.Clock.today/0`), the one every domain check reads
      (E25 S6, G08); the ADR names UTC only for the day a call is made.
    * `:resolved` — with `outcome` `:hit` or `:miss`;
    * `:unresolved` — with `reason` `:no_start_close`, `:no_end_close`,
      `:no_benchmark_close` or `:no_fx_rate`, never estimated.

  ## The dates

    * `start_on` — the day before the UTC day of `made_at`
      (`Portfolixir.Predictions.Prediction.made_on/1`): the start close is
      the last close **strictly before** the day the call was made, so a
      call made during a trading day is never measured from a close it
      could have seen coming. A close dated on the made day is never used.
    * `end_on` — `resolves_on`: the end close is the last close on or
      before it.

  Both sides are read for the same two dates, each close by S1's rule: the
  last positive close at most 7 calendar days before the date it stands
  for, in the current split basis, converted to EUR at the stored EUR-hub
  rate of the close's own date.

  ## The benchmark

    * `security:<id>` — the benchmark security's return by the same rule
      and the same two dates. Its missing close (start or end) is
      `:no_benchmark_close`; its missing rate path is `:no_fx_rate`.
    * `rate:<decimal>` — `WindowReturn.fixed_rate_return/3`, the daily
      factor of `Benchmark.daily_rate_factor/1` compounded once per
      calendar day from the date the security's start close stands for to
      the date its end close stands for (`start_on` to `end_on`, so
      `days = end_on - start_on`), not between the closes' own dates: the
      ADR's "the calendar days between the two dates the security's closes
      stand for". `rate:0` is exactly 0, the absolute call.

  The security's reasons come first, in S1's order (start close, end
  close, rate), then the benchmark's.

  ## The outcome

  `excess = security return - benchmark return`. An `outperform` call hits
  when `excess > 0`, an `underperform` call when `excess < 0`; an excess of
  exactly 0 is a miss for both. Price returns only: distributions are not
  counted on either side. Every figure is a `Decimal` at the default
  context (34 significant digits, half-up), unrounded, as S1's are.
  """

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Portfolios.Performance.WindowReturn
  alias Portfolixir.Predictions.Prediction
  alias Portfolixir.Repo

  @zero Decimal.new(0)

  @type status :: :open | :resolved | :unresolved
  @type outcome :: :hit | :miss
  @type reason :: :no_start_close | :no_end_close | :no_benchmark_close | :no_fx_rate

  @typedoc """
  The benchmark side of a resolution:

    * a security benchmark — `kind: :security`, its `security_id` and
      `currency_code`, its `start` and `end` closes
      (`t:Portfolixir.Portfolios.Performance.WindowReturn.window_end/0`)
      and its `return`;
    * a fixed rate — `kind: :rate`, the annual `rate`, the dates it is
      compounded `from` and `to`, the number of `days` and its `return`.
  """
  @type benchmark_side ::
          %{
            kind: :security,
            security_id: integer(),
            currency_code: String.t(),
            start: WindowReturn.window_end(),
            end: WindowReturn.window_end(),
            return: Decimal.t()
          }
          | %{
              kind: :rate,
              rate: Decimal.t(),
              from: Date.t(),
              to: Date.t(),
              days: non_neg_integer(),
              return: Decimal.t()
            }

  @typedoc """
  A resolution:

    * `status`, `outcome` (`nil` unless resolved), `reason` (`nil` unless
      unresolved);
    * `start_on`, `end_on` — the dates the start and end closes stand for;
    * `security` — `WindowReturn.price_return/3`'s result for the security
      (its `start` and `end` closes and its `return`), or `nil` when the
      call is open or the security's side has no answer;
    * `benchmark` — `t:benchmark_side/0`, or `nil` when the call is open or
      unresolved;
    * `excess` — `security.return - benchmark.return`, `nil` unless
      resolved.
  """
  @type t :: %__MODULE__{
          status: status(),
          outcome: outcome() | nil,
          reason: reason() | nil,
          start_on: Date.t(),
          end_on: Date.t(),
          security: WindowReturn.result() | nil,
          benchmark: benchmark_side() | nil,
          excess: Decimal.t() | nil
        }

  @enforce_keys [:status, :start_on, :end_on]
  defstruct [
    :status,
    :start_on,
    :end_on,
    outcome: nil,
    reason: nil,
    security: nil,
    benchmark: nil,
    excess: nil
  ]

  @doc "The unresolved reasons, in the order they are checked."
  @spec reasons() :: [reason()]
  def reasons, do: [:no_start_close, :no_end_close, :no_benchmark_close, :no_fx_rate]

  @doc """
  Resolves `prediction` as of `today` (the instance's calendar day; see
  the module doc for every rule). The security and a benchmark security are
  read unless preloaded.
  """
  @spec resolve(Prediction.t(), Date.t()) :: t()
  def resolve(%Prediction{} = prediction, %Date{} = today) do
    start_on = Date.add(Prediction.made_on(prediction), -1)
    end_on = prediction.resolves_on
    base = %__MODULE__{status: :open, start_on: start_on, end_on: end_on}

    if Date.compare(today, end_on) == :gt,
      do: resolve_passed(base, prediction),
      else: base
  end

  defp resolve_passed(base, prediction) do
    with {:ok, security} <- security_side(prediction, base),
         base = %{base | security: security},
         {:ok, benchmark} <- benchmark_side(prediction, base) do
      excess = Decimal.sub(security.return, benchmark.return)

      %{
        base
        | status: :resolved,
          outcome: outcome(prediction.direction, excess),
          benchmark: benchmark,
          excess: excess
      }
    else
      {:error, reason, base} -> %{base | status: :unresolved, reason: reason}
    end
  end

  defp security_side(prediction, base) do
    case WindowReturn.price_return(security(prediction), base.start_on, base.end_on) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason, base}
    end
  end

  defp benchmark_side(%Prediction{benchmark_kind: :rate, benchmark_rate: rate}, base) do
    from = base.security.start.stands_for
    to = base.security.end.stands_for

    {:ok,
     %{
       kind: :rate,
       rate: rate,
       from: from,
       to: to,
       days: Date.diff(to, from),
       return: WindowReturn.fixed_rate_return(rate, from, to)
     }}
  end

  defp benchmark_side(%Prediction{benchmark_kind: :security} = prediction, base) do
    case WindowReturn.price_return(benchmark_security(prediction), base.start_on, base.end_on) do
      {:ok, result} ->
        {:ok,
         %{
           kind: :security,
           security_id: result.security_id,
           currency_code: result.currency_code,
           start: result.start,
           end: result.end,
           return: result.return
         }}

      {:error, reason} when reason in [:no_start_close, :no_end_close] ->
        {:error, :no_benchmark_close, base}

      {:error, :no_fx_rate} ->
        {:error, :no_fx_rate, base}
    end
  end

  defp outcome(:outperform, excess), do: hit_if(Decimal.compare(excess, @zero) == :gt)
  defp outcome(:underperform, excess), do: hit_if(Decimal.compare(excess, @zero) == :lt)

  defp hit_if(true), do: :hit
  defp hit_if(false), do: :miss

  defp security(%Prediction{security: %Security{} = security}), do: security
  defp security(%Prediction{security_id: id}), do: Repo.get!(Security, id)

  defp benchmark_security(%Prediction{benchmark_security: %Security{} = security}), do: security
  defp benchmark_security(%Prediction{benchmark_security_id: id}), do: Repo.get!(Security, id)
end
