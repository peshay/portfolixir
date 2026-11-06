defmodule PortfolixirWeb.PredictionLabel do
  @moduledoc """
  The words a prediction is read in on a page (ADR-0055 §5; Sprint 26 V1
  and V2, board `ux-design-2026-11-06-sprint26-f1`): its claim in one
  sentence, its status as a badge, an unresolved call's reason as a word
  and as a sentence, and its author with the model an agent named.

  Everything here formats what the read answered
  (`Portfolixir.Predictions.list_with_resolution/2`, the API's own read);
  nothing derives a status, a return or a date again. The security's tab
  and the calibration report's list both read through it, so a call reads
  the same in both places.

  Stored text — a benchmark security's name, a model an agent stated — is
  set in `<bdi>` (`PortfolixirWeb.StoredText`). Every closed-set value has
  its clause and there is no fallback: a raw enum value never reaches a
  page (EXPERIENCE.md, Voice and Tone).
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Phoenix.HTML
  alias Portfolixir.Predictions.Prediction
  alias Portfolixir.Predictions.Resolution
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.StoredText

  @zero Decimal.new(0)

  @typedoc "The state a call is drawn in: its status, with an open call past its day apart."
  @type state :: :open | :waiting | :hit | :miss | :unresolved

  @doc """
  The state a call is drawn in: `:waiting` is an open call whose
  resolution day has passed (it waits for its end close, ADR-0055
  amendment of 2026-11-05, §2); a resolved call is `:hit` or `:miss`.
  """
  @spec state(Prediction.t(), Resolution.t(), Date.t()) :: state()
  def state(%Prediction{resolves_on: on}, %Resolution{status: :open}, %Date{} = today) do
    if Date.compare(today, on) == :gt, do: :waiting, else: :open
  end

  def state(_prediction, %Resolution{status: :resolved, outcome: :hit}, _today), do: :hit
  def state(_prediction, %Resolution{status: :resolved, outcome: :miss}, _today), do: :miss
  def state(_prediction, %Resolution{status: :unresolved}, _today), do: :unresolved

  @doc "The badge class of a state: open neutral, hit outlined green, missed muted, unresolved dashed."
  @spec badge_class(state()) :: String.t()
  def badge_class(state) when state in [:open, :waiting], do: "badge badge--neutral"
  def badge_class(:hit), do: "badge badge--thesis-intact"
  # A miss is an expected outcome, not a data fault: muted, never red
  # (board 02, judgment call 4).
  def badge_class(:miss), do: "badge badge--retired"
  def badge_class(:unresolved), do: "badge badge--undetermined"

  @doc "The badge's words: `open · 145 days left`, `open · waiting for the close`, `Hit`, …"
  @spec status(state(), Prediction.t(), Date.t()) :: String.t()
  def status(:open, %Prediction{resolves_on: on}, %Date{} = today) do
    days = Date.diff(on, today)
    ngettext("open · %{count} day left", "open · %{count} days left", days)
  end

  def status(:waiting, _prediction, _today), do: gettext("open · waiting for the close")
  def status(:hit, _prediction, _today), do: gettext("Hit")
  def status(:miss, _prediction, _today), do: gettext("missed")
  def status(:unresolved, _prediction, _today), do: gettext("not resolved")

  @doc "An unresolved call's reason, as a word."
  @spec reason(Resolution.reason()) :: String.t()
  def reason(:no_start_close), do: gettext("no start close")
  def reason(:no_end_close), do: gettext("no end close")
  def reason(:no_benchmark_close), do: gettext("no benchmark close")
  def reason(:no_fx_rate), do: gettext("no exchange rate")

  @doc """
  An unresolved call's reason as a sentence, with the days its closes stand
  for and the staleness bound of the read's `computation_basis`. The read
  names which side lacks a close only for the security, so the
  benchmark's sentence names both days.
  """
  @spec reason_sentence(Resolution.t(), pos_integer()) :: String.t()
  def reason_sentence(%Resolution{reason: :no_start_close, start_on: on}, days),
    do:
      gettext("The security has no close on or up to %{days} days before %{date}.",
        days: days,
        date: Format.date(on)
      )

  def reason_sentence(%Resolution{reason: :no_end_close, end_on: on}, days),
    do:
      gettext("The security has no close on or up to %{days} days before %{date}.",
        days: days,
        date: Format.date(on)
      )

  def reason_sentence(%Resolution{reason: :no_benchmark_close} = resolution, days),
    do:
      gettext("The benchmark has no close on or up to %{days} days before %{start} or %{end}.",
        days: days,
        start: Format.date(resolution.start_on),
        end: Format.date(resolution.end_on)
      )

  def reason_sentence(%Resolution{reason: :no_fx_rate}, _days),
    do: gettext("No exchange rate to EUR is stored for the day of a close the call needs.")

  @doc """
  The claim in one sentence, the benchmark security's name isolated:
  "Outperforms Index by 31.03.2027", "Rises by …" for `rate:0`,
  "Outperforms 2.0 % a year by …" for a fixed rate.
  """
  @spec claim(Prediction.t()) :: HTML.safe()
  def claim(%Prediction{benchmark_kind: :security} = prediction) do
    name = prediction.benchmark_security.name
    date = Format.date(prediction.resolves_on)
    slot = StoredText.slot(:benchmark)

    case prediction.direction do
      :outperform ->
        gettext("Outperforms %{benchmark} by %{date}", benchmark: slot, date: date)

      :underperform ->
        gettext("Underperforms %{benchmark} by %{date}", benchmark: slot, date: date)
    end
    |> StoredText.isolate(benchmark: name)
  end

  def claim(%Prediction{benchmark_kind: :rate, benchmark_rate: rate} = prediction) do
    date = Format.date(prediction.resolves_on)

    text =
      case {prediction.direction, Decimal.equal?(rate, @zero)} do
        {:outperform, true} ->
          gettext("Rises by %{date}", date: date)

        {:underperform, true} ->
          gettext("Falls by %{date}", date: date)

        {:outperform, false} ->
          gettext("Outperforms %{rate} a year by %{date}", rate: rate_text(rate), date: date)

        {:underperform, false} ->
          gettext("Stays below %{rate} a year by %{date}", rate: rate_text(rate), date: date)
      end

    StoredText.isolate(text, [])
  end

  defp rate_text(rate), do: Format.percent(rate) <> " %"

  @doc """
  The stated probability as a whole percent: `65 %`. A percentage, so it
  stays in the privacy mode (P1).
  """
  @spec probability(Prediction.t()) :: String.t()
  def probability(%Prediction{probability: probability}),
    do: Format.plain_decimal(Decimal.mult(probability, 100), 0) <> " %"

  @doc "The author, with the model an agent named isolated: `Agent · model-x`, `Operator`."
  @spec author(Prediction.t()) :: HTML.safe()
  def author(%Prediction{author: :agent, model: model}) when is_binary(model),
    do: StoredText.isolate(gettext("Agent") <> " · " <> StoredText.slot(:model), model: model)

  def author(%Prediction{author: :agent}), do: StoredText.isolate(gettext("Agent"), [])
  def author(%Prediction{author: :operator}), do: StoredText.isolate(gettext("Operator"), [])

  # A resolved call's three figures — its return, the benchmark's and the
  # excess — show two decimals, so the rounded parts add up within the last
  # digit (closing act, the UAT persona: „+2,4 % − +0,2 % = +2,3 Pp“ read as
  # a wrong sum at one decimal). A percentage: it stays in the privacy mode.
  @places 2

  @doc "A signed return as a two-decimal percent: `+10.00 %`."
  @spec return(Decimal.t()) :: String.t()
  def return(%Decimal{} = value), do: points(value) <> " %"

  @doc "The excess in percentage points, two decimals: `+7.00 pp`."
  @spec excess(Decimal.t()) :: String.t()
  def excess(%Decimal{} = value), do: gettext("%{value} pp", value: points(value))

  defp points(fraction),
    do: fraction |> Decimal.mult(100) |> Format.plain_signed_decimal(@places)

  @doc "The sign colour of a return as displayed, or nil for one that reads zero."
  @spec sign_class(Decimal.t() | nil) :: String.t() | nil
  def sign_class(%Decimal{} = value) do
    case value |> Decimal.mult(100) |> Format.displayed_sign(@places) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      _zero -> nil
    end
  end

  def sign_class(_value), do: nil
end
