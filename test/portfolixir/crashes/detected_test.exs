defmodule Portfolixir.Crashes.DetectedTest do
  # Sprint 29 C2 (FR-54, #1421; ADR-0058 §2, §6, §7): the detected windows
  # over the crash benchmark's stored closes, derived at read in the current
  # display basis. Risk tier: money math — exact Decimals. Every name and
  # figure is synthetic.
  # group: :crash_benchmark -- the async modules that choose the crash
  # benchmark never run at the same time (the closing act of Sprint 29). The
  # choice is one settings row for the instance (settings_key_index), taken
  # under an advisory lock on its key, and a sandboxed test never commits: a
  # module choosing beside another one waited on the other's lock and row
  # until that test ended, into the 15 s query timeout under load. The key
  # is the setting's, so no fixture of a test's own avoids it.
  use Portfolixir.DataCase, async: true, group: :crash_benchmark

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Crashes
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Settings

  defp choose!(security) do
    {:ok, _security} = Settings.set_crash_benchmark(Actor.owner_ui(), security.id)
  end

  defp window_shape(window) do
    %{
      key: window.key,
      kind: window.kind,
      start: window.start,
      peak_close: Decimal.to_string(window.peak_close),
      trough: window.trough,
      trough_close: Decimal.to_string(window.trough_close),
      decline: Decimal.to_string(window.decline),
      recovered_on: window.recovered_on,
      provisional: window.provisional,
      max_gap_days: window.max_gap_days
    }
  end

  # User story (ADR-0058 §2, §6):
  # As the agent the operator runs,
  # I want the crash windows derived at read from the crash benchmark's
  # stored closes, each with its key and the basis it was found on,
  # so that I name a window by a key every agent reads the same way.
  #
  # Acceptance criteria:
  # - With a crash benchmark chosen, the read answers it, reason nil, and
  #   each window with key d:<benchmark>:<start> and kind "detected".
  # - The basis states the rule peak_trough_v1, the threshold "0.10", the
  #   tie rules, the benchmark's own currency, the split adjustment and the
  #   treatment of gaps with max_gap_days.
  test "the windows of the chosen benchmark, keyed by benchmark and start, with their basis" do
    index = create_security!(name: "Synthetic Broad Index", ticker: "SBI", currency: "USD")

    put_quotes!(index, [
      {~D[2020-02-19], "3386.15"},
      {~D[2020-02-20], "3373.23"},
      {~D[2020-03-23], "2237.40"},
      {~D[2020-08-18], "3389.78"},
      {~D[2020-08-19], "3374.85"}
    ])

    choose!(index)

    key = "d:#{index.id}:2020-02-19"

    assert %{benchmark: %{id: id}, reason: nil, detected: [window], basis: basis} =
             Crashes.detected()

    assert id == index.id

    assert window_shape(window) == %{
             key: key,
             kind: "detected",
             start: ~D[2020-02-19],
             peak_close: "3386.150000",
             trough: ~D[2020-03-23],
             trough_close: "2237.400000",
             decline: "-0.3392495902426059093660942368176247",
             recovered_on: ~D[2020-08-18],
             provisional: false,
             max_gap_days: 148
           }

    assert %{rule: "peak_trough_v1", threshold: "0.10", currency: "USD"} = basis
    assert basis.peak_ties =~ "latest"
    assert basis.trough_ties =~ "earliest"
    assert basis.split_adjustment =~ "split"
    assert basis.gaps =~ "max_gap_days"
  end

  # ADR-0058 §2 and §7: a split inside a fall. The rule reads the display
  # basis (Quotes.adjust_rows/2), so a booked 2:1 split halving the stored
  # manual closes is no fall, and a real fall across the split is measured
  # in the adjusted basis.
  test "a split inside a fall is no fall of its own, and a fall across it is measured adjusted" do
    world = base_world(name: "Synthetic Split World")
    index = create_security!(name: "Synthetic Split Index", ticker: "SSI")
    buy!(world, index, quantity: "1", price: "100", date: ~D[2024-01-02])

    put_quotes!(index, [
      {~D[2024-01-02], "100"},
      {~D[2024-01-15], "98"},
      {~D[2024-02-02], "49"},
      {~D[2024-02-09], "48"}
    ])

    {:ok, _txs} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: index.id,
        date: ~D[2024-02-01],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    choose!(index)

    # Adjusted: 50, 49, 49, 48 — a 4 % decline, no window.
    assert %{detected: [], reason: nil} = Crashes.detected()

    put_quotes!(index, [{~D[2024-02-16], "44"}])

    # 50 (the adjusted 100 of 2 January) to 44: 12 %, one ongoing window.
    assert %{detected: [window]} = Crashes.detected()

    assert window_shape(window) == %{
             key: "d:#{index.id}:2024-01-02",
             kind: "detected",
             start: ~D[2024-01-02],
             peak_close: "50.000000",
             trough: ~D[2024-02-16],
             trough_close: "44.000000",
             decline: "-0.12",
             recovered_on: nil,
             provisional: true,
             max_gap_days: 18
           }
  end

  # The closing act (#1421; ADR-0058 §2, §7.7): "exactly 10.00 % opens a
  # window, no rounding before the comparison" holds across a split whose
  # ratio does not terminate. 100 stored before a 3:1 split reads 100/3,
  # 33.33… at 34 digits; 30 after it is exactly 90 % of 100/3. Compared on
  # the rounded 33.33…3 it read 9.99…9 %, and no window opened. The split
  # factor stays rational: the rule cross-multiplies the stored closes by
  # their integer ratios, so the comparison and the decline are exact.
  test "an exactly 10.00 % fall across a 3:1 split opens a window, measured exactly" do
    world = base_world(name: "Synthetic Split World")
    index = create_security!(name: "Synthetic Three Split Index", ticker: "S3I")
    buy!(world, index, quantity: "3", price: "100", date: ~D[2024-01-02])
    put_quotes!(index, [{~D[2024-01-02], "100"}, {~D[2024-02-05], "30"}])

    {:ok, _txs} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: index.id,
        date: ~D[2024-02-01],
        ratio_numerator: 3,
        ratio_denominator: 1
      })

    choose!(index)

    assert %{detected: [window]} = Crashes.detected()
    assert window.start == ~D[2024-01-02]
    assert window.trough == ~D[2024-02-05]
    # (30 × 3) / (100 × 1) − 1 = 0.9 − 1, one division of exact products.
    assert Decimal.to_string(window.decline) == "-0.1"

    # 9.99 % across the same split still opens none: 30.003 / (100/3) = 0.90009.
    put_quotes!(index, [{~D[2024-02-05], "30.003"}])
    assert %{detected: []} = Crashes.detected()
  end
end
