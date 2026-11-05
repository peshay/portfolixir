defmodule Portfolixir.Predictions.Calibration do
  @moduledoc """
  The calibration report's engine (ADR-0055 §4): pure, over predictions
  already resolved at read (`Portfolixir.Predictions.Resolution`), as
  `Portfolixir.Predictions.list_with_resolution/2` answers them. It reads
  no clock, no table and no close (AR-2); the context's
  `Portfolixir.Predictions.calibration_report/2` loads and resolves.

  ## The block

  The report is one block over every prediction it is given, and the same
  block per author and per model (`groups`):

    * `counts` — `total`, `open`, `resolved`, and `unresolved` by reason
      (every reason, 0 included). Open and unresolved predictions are
      counted here and enter no score.
    * `brier` — over the `n` resolved predictions, with `e = (p - o)^2`,
      `p` the stated probability and `o` 1 for a hit and 0 for a miss:
      `score = sum(e) / n`; `standard_error` the sample standard deviation
      of the `e` over `sqrt(n)`, computed as
      `sqrt((n * sum(e^2) - sum(e)^2) / (n^2 * (n - 1)))` (algebraically the
      same, with one division and one root instead of a rounded mean
      carried through a second sum); `reference` 0.25, the score of saying
      50 % to everything.
    * `sharpness` — `sum(p - 0.50) / n`: how far from a coin the calls are
      stated. Saying 50 % to everything is perfectly calibrated and has a
      sharpness of 0.
    * `hit_rate` — `hits / n` (`rate`), `hits`, the `mean_probability`
      `sum(p) / n` beside it, and its `standard_error`: the same estimator
      as the Brier score's, the sample standard deviation of the 0/1
      outcomes over `sqrt(n)`, `sqrt(hits * (n - hits) / (n^2 * (n - 1)))`.
      Not the binomial `sqrt(rate * (1 - rate) / n)`: one estimator reads
      both uncertainties alike, and with a single resolved call it is null
      instead of the binomial's 0, a certainty one call cannot carry.
    * `bands` — five, by stated probability: 0.50-0.59, 0.60-0.69,
      0.70-0.79, 0.80-0.89, 0.90-0.99 (`from` and `to`, inclusive). Each
      has its resolved `count` and `mean_probability` (nil when empty; it
      is what was said, not an estimate, so it is shown at any count), and
      its `hit_rate` from 20 resolved predictions on, `:too_few` below.

  **Small samples.** With no resolved prediction every score, the
  sharpness, the hit rate and the mean probability are nil, and both
  standard errors are nil with `standard_error_reason: :no_resolved`. With
  one, the scores are that call's own and both standard errors are nil
  with `standard_error_reason: :one_resolved` (a sample standard deviation
  divides by `n - 1`). Nothing divides by zero.

  ## Precision

  Every figure is a `Decimal` at the default context (34 significant
  digits, half-up), unrounded, as the resolution's returns are; the
  squared errors and the sums are exact (a probability has two places),
  so a figure rounds once at its division and once at its root
  (`Decimal.sqrt/1`, at the same precision). The payload carries each as a
  string.
  """

  alias Portfolixir.Portfolios.Performance.WindowReturn
  alias Portfolixir.Predictions.Prediction
  alias Portfolixir.Predictions.Resolution

  @minimum_band_count 20
  @reference Decimal.new("0.25")
  @half Decimal.new("0.50")
  @zero Decimal.new(0)
  @one Decimal.new(1)
  @ten Decimal.new(10)

  @bands [
    {Decimal.new("0.50"), Decimal.new("0.59")},
    {Decimal.new("0.60"), Decimal.new("0.69")},
    {Decimal.new("0.70"), Decimal.new("0.79")},
    {Decimal.new("0.80"), Decimal.new("0.89")},
    {Decimal.new("0.90"), Decimal.new("0.99")}
  ]

  @type entry :: %{prediction: Prediction.t(), resolution: Resolution.t()}
  @type standard_error_reason :: :no_resolved | :one_resolved | nil

  @type counts :: %{
          total: non_neg_integer(),
          open: non_neg_integer(),
          resolved: non_neg_integer(),
          unresolved: %{required(Resolution.reason()) => non_neg_integer()}
        }

  @type band :: %{
          from: Decimal.t(),
          to: Decimal.t(),
          count: non_neg_integer(),
          mean_probability: Decimal.t() | nil,
          hit_rate: Decimal.t() | :too_few
        }

  @type block :: %{
          counts: counts(),
          brier: %{
            score: Decimal.t() | nil,
            standard_error: Decimal.t() | nil,
            standard_error_reason: standard_error_reason(),
            reference: Decimal.t()
          },
          sharpness: Decimal.t() | nil,
          hit_rate: %{
            rate: Decimal.t() | nil,
            hits: non_neg_integer(),
            mean_probability: Decimal.t() | nil,
            standard_error: Decimal.t() | nil,
            standard_error_reason: standard_error_reason()
          },
          bands: [band()]
        }

  @type report :: %{
          counts: counts(),
          brier: map(),
          sharpness: Decimal.t() | nil,
          hit_rate: map(),
          bands: [band()],
          groups: %{
            author: [%{required(:author) => Prediction.author(), optional(atom()) => term()}],
            model: [%{required(:model) => String.t() | nil, optional(atom()) => term()}]
          }
        }

  @doc "The fewest resolved predictions a band shows its hit rate from: #{@minimum_band_count}."
  @spec minimum_band_count() :: pos_integer()
  def minimum_band_count, do: @minimum_band_count

  @doc "The Brier score of saying 50 % to everything: `0.25`."
  @spec reference() :: Decimal.t()
  def reference, do: @reference

  @doc """
  The report's `computation_basis` (ADR-0055 §4; the brief addendum's
  "Every metric documents its computation basis"): the resolution rule of
  §3, the formulas, the minimum band count, what is excluded and counted,
  that no distribution is counted, the small-sample rule, the groups and
  the precision. Text a reader checks a figure against, plus the three
  numbers it names (`minimum_band_count`, `reference`, `staleness_days`).
  """
  @spec computation_basis() :: %{atom() => String.t() | pos_integer() | Decimal.t()}
  def computation_basis do
    %{
      resolution:
        "Each prediction is resolved at read from stored closes; nothing is stored. It is open " <>
          "while the instance's calendar day is on or before resolves_on, then resolved (hit or " <>
          "miss) or unresolved with its reason: no_start_close, no_end_close, " <>
          "no_benchmark_close or no_fx_rate, never estimated.",
      start_close:
        "The security's last close strictly before the UTC day the prediction was made " <>
          "(standing for the day before it), and the benchmark security's for the same date; " <>
          "a close on the day made is never used.",
      end_close: "The last close on or before resolves_on, for the security and the benchmark.",
      staleness_days: WindowReturn.staleness_days(),
      currency:
        "Both closes are converted to EUR at the stored EUR-hub rate of each close's own date, " <>
          "as valuation does; each return is end EUR value / start EUR value - 1. A close more " <>
          "than staleness_days calendar days before the date it stands for is no close. Closes " <>
          "are read in the current split basis.",
      benchmark:
        "security:<id>: the benchmark security's return by the same rule and the same dates. " <>
          "rate:<r>: Benchmark.daily_rate_factor(r) compounded once per calendar day between the " <>
          "two dates the security's closes stand for; rate:0 is the absolute call.",
      outcome:
        "excess = security return - benchmark return; outperform hits when excess > 0, " <>
          "underperform when excess < 0; excess = 0 is a miss for both.",
      distributions:
        "Price returns only: dividends and other distributions are not counted, on either side.",
      brier_score:
        "Mean over the n resolved predictions of (p - o)^2, p the stated probability, o 1 for " <>
          "a hit and 0 for a miss. Lower is better; reference is the score of saying 0.50 to " <>
          "everything.",
      reference: @reference,
      brier_standard_error:
        "The sample standard deviation of the squared errors over sqrt(n), computed as " <>
          "sqrt((n * sum(e^2) - sum(e)^2) / (n^2 * (n - 1))).",
      sharpness:
        "Mean of (p - 0.50) over the resolved predictions: how far from a coin the calls are " <>
          "stated. Saying 0.50 to everything is perfectly calibrated and has sharpness 0.",
      hit_rate:
        "hits / n over the resolved predictions, beside mean_probability, the mean stated " <>
          "probability, which a calibrated author's hit rate matches.",
      hit_rate_standard_error:
        "The same estimator as the Brier score's: the sample standard deviation of the 0/1 " <>
          "outcomes over sqrt(n), sqrt(hits * (n - hits) / (n^2 * (n - 1))); not the binomial " <>
          "sqrt(rate * (1 - rate) / n), which reads 0 for a single call.",
      bands:
        "Five bands by stated probability, 0.50-0.59, 0.60-0.69, 0.70-0.79, 0.80-0.89 and " <>
          "0.90-0.99, each with its resolved count and mean stated probability. A band shows " <>
          "its hit rate from minimum_band_count resolved predictions; below, hit_rate is " <>
          "too_few. Expect too_few for a long time: the headline score with its standard error " <>
          "carries meaning from the first resolutions.",
      minimum_band_count: @minimum_band_count,
      excluded:
        "Open and unresolved predictions are excluded from every score and counted: open, and " <>
          "unresolved by reason.",
      small_samples:
        "With no resolved prediction every score is null and both standard errors are null with " <>
          "standard_error_reason no_resolved; with one, both standard errors are null with " <>
          "one_resolved (a sample standard deviation divides by n - 1).",
      groups:
        "The same block per author and per model; an operator's prediction names no model and " <>
          "is grouped under model null.",
      precision:
        "Every figure is a Decimal at 34 significant digits, rounded half-up, unrounded " <>
          "otherwise; square roots by Decimal.sqrt at the same precision."
    }
  end

  @doc """
  The report over `entries`: the block (see the module doc) over all of
  them, and `groups` — the same block per author (`:agent` before
  `:operator`) and per model (by name, the operator's calls, which carry
  none, last as `nil`), each only for the authors and models present.
  """
  @spec report([entry()]) :: report()
  def report(entries) when is_list(entries) do
    entries
    |> block()
    |> Map.put(:groups, %{
      author: groups(entries, :author, &author_order/1),
      model: groups(entries, :model, &model_order/1)
    })
  end

  @doc "The block of the module doc over `entries`."
  @spec block([entry()]) :: block()
  def block(entries) when is_list(entries) do
    resolved =
      for %{prediction: prediction, resolution: %Resolution{status: :resolved} = resolution} <-
            entries,
          do: {prediction.probability, outcome(resolution.outcome)}

    %{
      counts: counts(entries, length(resolved)),
      brier: brier(resolved),
      sharpness: sharpness(resolved),
      hit_rate: hit_rate(resolved),
      bands: bands(resolved)
    }
  end

  defp groups(entries, field, order) do
    entries
    |> Enum.group_by(&Map.fetch!(&1.prediction, field))
    |> Enum.sort_by(fn {key, _entries} -> order.(key) end)
    |> Enum.map(fn {key, group} -> Map.put(block(group), field, key) end)
  end

  defp author_order(:agent), do: 0
  defp author_order(:operator), do: 1

  defp model_order(nil), do: {1, ""}
  defp model_order(model), do: {0, model}

  defp counts(entries, resolved) do
    statuses = Enum.map(entries, & &1.resolution)

    %{
      total: length(entries),
      open: Enum.count(statuses, &(&1.status == :open)),
      resolved: resolved,
      unresolved:
        Map.new(Resolution.reasons(), fn reason ->
          {reason, Enum.count(statuses, &(&1.status == :unresolved and &1.reason == reason))}
        end)
    }
  end

  defp outcome(:hit), do: @one
  defp outcome(:miss), do: @zero

  defp brier(resolved) do
    errors = Enum.map(resolved, fn {p, o} -> square(Decimal.sub(p, o)) end)
    {standard_error, reason} = standard_error(errors)

    %{
      score: mean(errors),
      standard_error: standard_error,
      standard_error_reason: reason,
      reference: @reference
    }
  end

  defp sharpness(resolved),
    do: resolved |> Enum.map(fn {p, _o} -> Decimal.sub(p, @half) end) |> mean()

  defp hit_rate(resolved) do
    outcomes = Enum.map(resolved, fn {_p, o} -> o end)
    {standard_error, reason} = standard_error(outcomes)

    %{
      rate: mean(outcomes),
      hits: Enum.count(outcomes, &Decimal.equal?(&1, @one)),
      mean_probability: resolved |> Enum.map(fn {p, _o} -> p end) |> mean(),
      standard_error: standard_error,
      standard_error_reason: reason
    }
  end

  defp bands(resolved) do
    by_band = Enum.group_by(resolved, fn {p, _o} -> band_index(p) end)

    @bands
    |> Enum.with_index()
    |> Enum.map(fn {{from, to}, index} ->
      members = Map.get(by_band, index, [])
      count = length(members)

      %{
        from: from,
        to: to,
        count: count,
        mean_probability: members |> Enum.map(fn {p, _o} -> p end) |> mean(),
        hit_rate:
          if(count >= @minimum_band_count,
            do: members |> Enum.map(fn {_p, o} -> o end) |> mean(),
            else: :too_few
          )
      }
    end)
  end

  # 0.50-0.59 is band 0, ..., 0.90-0.99 band 4: floor((p - 0.50) x 10).
  defp band_index(probability) do
    probability
    |> Decimal.sub(@half)
    |> Decimal.mult(@ten)
    |> Decimal.round(0, :floor)
    |> Decimal.to_integer()
  end

  defp mean([]), do: nil
  defp mean(values), do: Decimal.div(sum(values), length(values))

  # The sample standard deviation of `values` over sqrt(n), as
  # sqrt((n * sum(x^2) - sum(x)^2) / (n^2 * (n - 1))). The numerator is
  # exact, and never below 0 for exact sums (Cauchy-Schwarz).
  defp standard_error([]), do: {nil, :no_resolved}
  defp standard_error([_one]), do: {nil, :one_resolved}

  defp standard_error(values) do
    n = length(values)

    numerator =
      Decimal.sub(Decimal.mult(n, sum(Enum.map(values, &square/1))), square(sum(values)))

    {Decimal.sqrt(Decimal.div(numerator, n * n * (n - 1))), nil}
  end

  defp sum(values), do: Enum.reduce(values, @zero, &Decimal.add/2)
  defp square(value), do: Decimal.mult(value, value)
end
