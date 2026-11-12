defmodule Portfolixir.Crashes do
  @moduledoc """
  Crash windows (FR-54, idea I24; ADR-0058): declines of 10 % or more in
  the stored closes of one benchmark security the operator chooses, the
  **crash benchmark** (`Portfolixir.Settings.crash_benchmark_security_id/0`,
  §1). The rule fixes a window's dates and is derived at read, never stored
  (§2), so every agent and the screen read the same windows.

  Unset, the rule detects nothing, and the read says why:
  `detected: []` with `reason: "no_crash_benchmark"` (§1); a chosen
  benchmark that is no benchmark any more (merged away since) answers
  `reason: "crash_benchmark_unavailable"`, never its survivor by a guess.

  The windows are `Portfolixir.Crashes.PeakTrough`'s over the benchmark's
  stored closes up to today, in its own currency and the current display
  basis (`Portfolixir.Catalog.Quotes.adjusted_range/3`, ADR-0028 §2), each
  keyed `d:<benchmark_security_id>:<start>` and of kind `"detected"`.
  Nothing is cached: the same closes give the same windows.
  """

  alias Portfolixir.Catalog.BenchmarkSecurity
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Crashes.PeakTrough
  alias Portfolixir.Settings

  # The floor of the series read, as the per-security metrics read it.
  @series_floor ~D[1900-01-01]

  @typedoc "The detected windows over the crash benchmark, or why there are none."
  @type detection :: %{
          benchmark: Security.t() | nil,
          detected: [map()],
          reason: String.t() | nil,
          basis: map()
        }

  @doc """
  The windows the rule detects over the crash benchmark's closes (ADR-0058
  §1, §2). With no crash benchmark chosen: `detected: []`, `reason:
  "no_crash_benchmark"`, `benchmark: nil`.
  """
  @spec detected() :: detection()
  def detected do
    case Settings.crash_benchmark_security_id() do
      nil -> none("no_crash_benchmark")
      id -> detected_for(id)
    end
  end

  defp detected_for(id) do
    case BenchmarkSecurity.resolve(id) do
      {:ok, security} ->
        %{
          benchmark: security,
          detected: windows(security),
          reason: nil,
          basis: basis(security)
        }

      {:error, _refusal} ->
        none("crash_benchmark_unavailable")
    end
  end

  defp windows(%Security{id: id}) do
    id
    |> Quotes.adjusted_range(@series_floor, Clock.today())
    |> PeakTrough.detect()
    |> Enum.map(&Map.merge(&1, %{key: PeakTrough.key(id, &1.start), kind: "detected"}))
  end

  defp none(reason), do: %{benchmark: nil, detected: [], reason: reason, basis: basis(nil)}

  # ADR-0058 §6: the parts of the computation basis the detection owns.
  defp basis(security) do
    %{
      rule: PeakTrough.rule(),
      threshold: PeakTrough.threshold(),
      comparison:
        "a window opens on the first close for which (peak - close) / peak >= 0.10, " <>
          "compared exactly in Decimal as (peak - close) x 10 >= peak, no rounding before it",
      peak_ties:
        "among equal highs the latest is the peak: the decline starts on the last day at the high",
      trough_ties: "among equal lows the earliest is the trough",
      input_series:
        "the crash benchmark's stored closes up to today, positive closes only, in date " <>
          "order; detected at read and never stored",
      currency: security && security.currency_code,
      currency_note: "the benchmark's own currency, never converted",
      split_adjustment:
        "closes in the current display basis: a booked split divides the raw closes " <>
          "before its effective date (ADR-0028 §2), so a split is not a fall",
      gaps:
        "a day without a close is skipped, never interpolated: a fall inside a gap shows " <>
          "on the first close after it, and each window names max_gap_days, the longest " <>
          "span in calendar days between two consecutive closes from its start to its " <>
          "recovery, or to the last close while it is provisional",
      recovery:
        "a window closes on the first close at or above its peak (recovered_on) and the " <>
          "walk continues from it; a window not recovered by the last close is " <>
          "provisional, its trough the lowest close so far"
    }
  end
end
