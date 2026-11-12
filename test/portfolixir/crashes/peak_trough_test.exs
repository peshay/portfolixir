defmodule Portfolixir.Crashes.PeakTroughTest do
  # Sprint 29 C2 (FR-54, #1421; ADR-0058 §2, §7): the detection rule
  # peak_trough_v1, a pure function of one close series. Risk tier: money
  # math — every figure is an exact Decimal. Every series is synthetic.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Portfolixir.Crashes.PeakTrough

  defp d(iso), do: Date.from_iso8601!(iso)

  defp series(points), do: Enum.map(points, fn {iso, close} -> point(iso, close) end)

  defp point(iso, close), do: %{date: d(iso), close: Decimal.new(close)}

  # Compares a window's fields as strings, so 90.00 and 90 never pass for
  # each other and a float could never match.
  defp shape(window) do
    %{
      start: Date.to_iso8601(window.start),
      peak_close: Decimal.to_string(window.peak_close),
      trough: Date.to_iso8601(window.trough),
      trough_close: Decimal.to_string(window.trough_close),
      decline: Decimal.to_string(window.decline),
      recovered_on: window.recovered_on && Date.to_iso8601(window.recovered_on),
      provisional: window.provisional,
      max_gap_days: window.max_gap_days
    }
  end

  defp detect(points), do: points |> PeakTrough.detect() |> Enum.map(&shape/1)

  # User story (ADR-0058 §2):
  # As the operator, and every agent I run,
  # I want a crash window found by one rule from the benchmark's closes,
  # so that two agents asking about "the crash" read the same dates.
  #
  # Acceptance criteria:
  # - A window opens on the first close at least 10 % below the running
  #   peak; its start is the peak's date, its trough the lowest close
  #   before the series closes at or above the peak again, and it closes
  #   on that close (recovered_on).
  # - Its decline is (trough − peak) / peak, an exact Decimal.
  # - The walk continues from the recovery close as the new running peak,
  #   so a second fall is a second window and windows never overlap.
  # - Closes of zero or below are not prices and are skipped.
  test "one window per fall, from the peak to the recovery" do
    points =
      series([
        {"2024-01-02", "100"},
        {"2024-01-03", "104"},
        {"2024-01-04", "98"},
        {"2024-01-05", "93.6"},
        {"2024-01-08", "0"},
        {"2024-01-09", "91"},
        {"2024-01-10", "97"},
        {"2024-01-11", "104"},
        {"2024-01-12", "110"},
        {"2024-01-15", "98"},
        {"2024-01-16", "99"},
        {"2024-01-17", "111"}
      ])

    assert detect(points) == [
             %{
               start: "2024-01-03",
               peak_close: "104",
               trough: "2024-01-09",
               trough_close: "91",
               decline: "-0.125",
               recovered_on: "2024-01-11",
               provisional: false,
               max_gap_days: 4
             },
             %{
               start: "2024-01-12",
               peak_close: "110",
               trough: "2024-01-15",
               trough_close: "98",
               decline: "-0.1090909090909090909090909090909091",
               recovered_on: "2024-01-17",
               provisional: false,
               max_gap_days: 3
             }
           ]
  end

  # ADR-0058 §7.7: can the threshold flap? A decline of exactly 10.00 %
  # opens a window, 9.99 % does not; exact Decimal, no float, no rounding
  # before the comparison — also where the peak has no exact binary form.
  test "exactly 10.00 % opens a window, 9.99 % does not" do
    assert [%{start: "2024-03-01", trough_close: "90.00", decline: "-0.1"}] =
             detect(series([{"2024-03-01", "100.00"}, {"2024-03-04", "90.00"}]))

    assert detect(series([{"2024-03-01", "100.00"}, {"2024-03-04", "90.01"}])) == []

    # 123.45 × 0.9 = 111.105 exactly; a float reads 0.1 as more than 0.1.
    assert [%{trough_close: "111.105", decline: "-0.1"}] =
             detect(series([{"2024-03-01", "123.45"}, {"2024-03-04", "111.105"}]))

    assert detect(series([{"2024-03-01", "123.45"}, {"2024-03-04", "111.1050001"}])) == []
  end

  # ADR-0058 §2.1 and §2.3: ties are decided by dates and values alone.
  test "the latest of equal peaks starts the window, the earliest of equal lows is its trough" do
    points =
      series([
        {"2024-05-01", "100"},
        {"2024-05-02", "100"},
        {"2024-05-03", "95"},
        {"2024-05-06", "100"},
        {"2024-05-07", "88"},
        {"2024-05-08", "90"},
        {"2024-05-09", "88"},
        {"2024-05-10", "100"}
      ])

    assert [
             %{
               start: "2024-05-06",
               trough: "2024-05-07",
               trough_close: "88",
               recovered_on: "2024-05-10"
             }
           ] = detect(points)
  end

  # ADR-0058 §7.1: can the read order change a window? No: the walk is by
  # date over one series.
  test "a read in another order gives the same windows" do
    points =
      series([
        {"2024-05-01", "100"},
        {"2024-05-02", "100"},
        {"2024-05-03", "88"},
        {"2024-05-06", "88"},
        {"2024-05-07", "101"},
        {"2024-05-08", "90"}
      ])

    expected = detect(points)
    assert length(expected) == 2

    assert detect(Enum.reverse(points)) == expected
    assert detect(Enum.sort_by(points, &Decimal.to_string(&1.close))) == expected
  end

  property "any order of the same closes gives the same windows" do
    check all(
            closes <- list_of(integer(50..150), min_length: 2, max_length: 40),
            seed <- integer()
          ) do
      points =
        closes
        |> Enum.with_index()
        |> Enum.map(fn {close, i} ->
          %{date: Date.add(~D[2024-01-01], i), close: Decimal.new(close)}
        end)

      shuffled = Enum.sort_by(points, &:erlang.phash2({&1.date, seed}))

      assert PeakTrough.detect(shuffled) == PeakTrough.detect(points)
    end
  end

  # ADR-0058 §7.8: can a gap hide a fall? A fall inside a gap shows on the
  # first close after it, and the window names its longest gap.
  test "a fall over a gap shows on the first close after it, with max_gap_days" do
    points =
      series([
        {"2024-01-02", "100"},
        {"2024-02-15", "85"},
        {"2024-02-16", "86"},
        {"2024-03-01", "100"}
      ])

    assert detect(points) == [
             %{
               start: "2024-01-02",
               peak_close: "100",
               trough: "2024-02-15",
               trough_close: "85",
               decline: "-0.15",
               recovered_on: "2024-03-01",
               provisional: false,
               max_gap_days: 44
             }
           ]
  end

  # ADR-0058 §2: a decline in several legs with no recovery in between is
  # one window (the outbreak of a war folds into the bear market).
  test "a fall in two legs without a recovery is one window" do
    points =
      series([
        {"2022-01-03", "100"},
        {"2022-02-01", "88"},
        {"2022-03-01", "99.99"},
        {"2022-04-01", "80"},
        {"2022-05-02", "95"},
        {"2022-06-01", "75"},
        {"2022-09-01", "100"}
      ])

    assert [
             %{
               start: "2022-01-03",
               trough: "2022-06-01",
               trough_close: "75",
               decline: "-0.25",
               recovered_on: "2022-09-01",
               provisional: false
             }
           ] = detect(points)
  end

  # ADR-0058 §2.5, §7.5: a window not recovered at the series' last close
  # is ongoing; its trough is the lowest close so far, provisional, and it
  # moves while prices fall further.
  test "a series ending inside a fall is one provisional window whose trough moves" do
    points =
      series([
        {"2025-03-03", "100"},
        {"2025-03-04", "89"},
        {"2025-03-05", "85"},
        {"2025-03-06", "88"}
      ])

    assert detect(points) == [
             %{
               start: "2025-03-03",
               peak_close: "100",
               trough: "2025-03-05",
               trough_close: "85",
               decline: "-0.15",
               recovered_on: nil,
               provisional: true,
               max_gap_days: 1
             }
           ]

    assert [%{trough: "2025-03-07", trough_close: "84", provisional: true}] =
             detect(points ++ [point("2025-03-07", "84")])
  end

  test "no closes, one close, or no fall of 10 % detect nothing" do
    assert PeakTrough.detect([]) == []
    assert detect(series([{"2024-01-02", "100"}])) == []
    assert detect(series([{"2024-01-02", "100"}, {"2024-01-03", "95"}])) == []
  end

  # ADR-0058 §2: a detected window's key is d:<benchmark_security_id>:<start>.
  test "the key names the benchmark and the start" do
    assert PeakTrough.key(42, ~D[2020-02-19]) == "d:42:2020-02-19"
  end

  # ADR-0058 §2, §6: the rule's name and threshold, as the basis states them.
  test "the rule is peak_trough_v1 at a threshold of 0.10" do
    assert PeakTrough.rule() == "peak_trough_v1"
    assert PeakTrough.threshold() == "0.10"
  end
end
