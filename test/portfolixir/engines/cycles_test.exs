defmodule Portfolixir.Engines.CyclesTest do
  # ADR-0060 §1, §2, §3, §12, §13 (Sprint 29 H4, FR-58, idea I12): the cycles
  # read's past — the halving windows, each window's top and low as the peak
  # and the trough of its maximum drawdown, and the six intervals with n, min
  # and max.
  #
  # Risk tier: analytics. Every series, date and halving below is synthetic;
  # the shapes reproduce the cycles ADR-0060 describes (a partial first
  # window, a late rally above the top inside one window, an open window),
  # never a real price. Every expected figure was recomputed independently
  # with Python's `decimal` module at precision 28 (Elixir Decimal's default
  # context) and ROUND_HALF_UP at scale 6, the maximum drawdown by brute force
  # over every pair of closes, the tie rules applied to the brute-force
  # result, and the days as calendar days (`date - date`). The recomputation
  # is quoted beside each assertion as "py:".
  use ExUnit.Case, async: true

  alias Portfolixir.Engines.Cycles

  defp series(rows),
    do: Enum.map(rows, fn {date, close} -> %{date: date, close: Decimal.new(close)} end)

  defp confirmed(height, date), do: %{height: height, date: date, date_end: nil, confirmed: true}

  # Four confirmed halvings and the next one, unconfirmed, as a window.
  defp halvings do
    [
      confirmed(840_000, ~D[2013-01-10]),
      confirmed(1_680_000, ~D[2015-01-10]),
      confirmed(2_520_000, ~D[2017-01-10]),
      confirmed(3_360_000, ~D[2019-01-10]),
      %{height: 4_200_000, date: ~D[2021-01-05], date_end: ~D[2021-01-20], confirmed: false}
    ]
  end

  # The four windows' closes, gaps skipped (a close every few months).
  defp cycle_series do
    series([
      # 2013–2015: the series begins 50 days after the halving → partial.
      {~D[2013-03-01], "50"},
      {~D[2013-06-01], "80"},
      {~D[2013-09-01], "20"},
      {~D[2014-03-01], "30"},
      {~D[2014-09-01], "10"},
      {~D[2014-12-01], "15"},
      # 2015–2017: the halving day's close (9) is this window's; equal
      # highest closes (the later one is the top) and equal lowest drawdowns
      # (the earlier one is the low).
      {~D[2015-01-10], "9"},
      {~D[2015-06-01], "40"},
      {~D[2015-12-01], "200"},
      {~D[2016-03-01], "200"},
      {~D[2016-06-01], "60"},
      {~D[2016-09-01], "30"},
      {~D[2016-11-01], "30"},
      {~D[2016-12-20], "45"},
      # 2017–2019: the 2020–2024 shape — a late rally (520) closes above the
      # window's top (500) after its low, a month before the next halving.
      {~D[2017-01-10], "50"},
      {~D[2017-05-01], "300"},
      {~D[2017-08-01], "500"},
      {~D[2017-11-01], "350"},
      {~D[2018-02-01], "120"},
      {~D[2018-05-01], "100"},
      {~D[2018-08-01], "250"},
      {~D[2018-12-01], "520"},
      {~D[2019-01-09], "480"},
      # Since 2019: open, its top 1500 fallen more than 20 % → anchored.
      {~D[2019-01-10], "470"},
      {~D[2019-06-01], "900"},
      {~D[2019-10-01], "1500"},
      {~D[2020-01-01], "1100"},
      {~D[2020-03-01], "1300"},
      {~D[2020-05-01], "1000"}
    ])
  end

  # `Decimal.equal?/2` ignores the scale; the payload's scale is part of
  # what is pinned, so the string is asserted.
  defp assert_dec(actual, expected), do: assert(Decimal.to_string(actual, :normal) == expected)

  defp point(nil), do: nil
  defp point(%{date: date, close: close}), do: {date, Decimal.to_string(close, :normal)}

  defp window(result, start), do: Enum.find(result.windows, &(&1.start == start))

  # User story (ADR-0060 §2, the Context's first finding; plan row H4):
  # As the operator reading a security's halving cycles,
  # I want a window's top to be the high its bear market fell from,
  # so that a late rally above the old top a month before the next halving
  # is not taken for the cycle's top (the March 2024 close above the
  # November 2021 top, in 2020–2024).
  #
  # Acceptance criteria:
  # - In the 2017–2019 window (the 2020–2024 shape) the top is the
  #   2017-08-01 close of 500, the peak of the window's maximum drawdown,
  #   not the 2018-12-01 close of 520, the window's highest close, which
  #   lies after the low.
  # - The low is the trough of that drawdown, 2018-05-01 at 100, and the
  #   drawdown is -0.800000.
  test "2020–2024's shape: the top is the maximum drawdown's peak, not the highest close" do
    result = Cycles.compute(cycle_series(), halvings())
    w = window(result, ~D[2017-01-10])

    # py: brute-force mdd over the window → (-0.8, peak 2017-08-01 500,
    # trough 2018-05-01 100); highest close 2018-12-01 520, after the low.
    assert point(w.top) == {~D[2017-08-01], "500"}
    assert point(w.low) == {~D[2018-05-01], "100"}
    assert_dec(w.max_drawdown, "-0.800000")
    assert Date.compare(w.top.date, w.low.date) == :lt
  end

  # User story (ADR-0060 §1, §2, §12):
  # As the operator or the agent reading the cycles,
  # I want each window from one confirmed halving to the next, with its
  # kind, its top and its low,
  # so that the cycles reproduce from the stored closes and the halvings.
  #
  # Acceptance criteria:
  # - Four windows, from each confirmed halving; the unconfirmed one forms
  #   none and is the next halving.
  # - The halving day's close belongs to the window that starts there:
  #   9 on 2015-01-10 is the 2015 window's, so the 2013 window's low stays
  #   10 (with it, it would be 9 at -0.8875).
  # - The first window starts 50 days before the first stored close: it is
  #   partial, with no top (`before_first_close`) and its low marked
  #   partial.
  # - Ties: equal highest closes give the latest peak (2016-03-01, not
  #   2015-12-01); equal maximum drawdowns the earliest trough (2016-09-01,
  #   not 2016-11-01).
  # - Closed windows are final; the open one's top is not final, anchored
  #   after a fall of at least 20 %, and its low is only `low_so_far`.
  # - The counts: two complete, one partial, one open.
  test "the windows, their kinds, tops and lows, with the tie rules and the halving-day close" do
    result = Cycles.compute(cycle_series(), halvings())

    assert Enum.map(result.windows, &{&1.start, &1.end, &1.kind}) == [
             {~D[2013-01-10], ~D[2015-01-10], :partial},
             {~D[2015-01-10], ~D[2017-01-10], :complete},
             {~D[2017-01-10], ~D[2019-01-10], :complete},
             {~D[2019-01-10], nil, :open}
           ]

    assert result.next_halving == %{
             height: 4_200_000,
             date: ~D[2021-01-05],
             date_end: ~D[2021-01-20]
           }

    # py: window 2013 → n 6, partial (first close 50 days after start),
    # mdd -0.875 from 2013-06-01 80 to 2014-09-01 10, max gap 184 days.
    partial = window(result, ~D[2013-01-10])
    assert partial.top == nil
    assert partial.top_reason == :before_first_close
    assert point(partial.low) == {~D[2014-09-01], "10"}
    assert partial.low.partial
    assert partial.low.final
    assert partial.partial
    assert partial.final
    assert_dec(partial.max_drawdown, "-0.875000")
    assert partial.closes == 6
    assert partial.first_close == ~D[2013-03-01]
    assert partial.last_close == ~D[2014-12-01]
    assert partial.max_gap_days == 184

    # py: window 2015 → mdd -0.85, latest peak 2016-03-01 200 (the
    # highest close's first occurrence is 2015-12-01), earliest trough
    # 2016-09-01 30; the halving-day close 9 is its first close.
    w2015 = window(result, ~D[2015-01-10])
    assert point(w2015.top) == {~D[2016-03-01], "200"}
    assert point(w2015.low) == {~D[2016-09-01], "30"}
    assert w2015.top.final and w2015.top.anchor
    assert w2015.low.final
    refute w2015.low.partial
    assert_dec(w2015.max_drawdown, "-0.850000")
    assert w2015.first_close == ~D[2015-01-10]
    assert w2015.closes == 8
    assert w2015.max_gap_days == 183

    # py: window 2019 (open) → mdd -0.333333 from 2019-10-01 1500 to
    # 2020-05-01 1000; 1000 <= 0.80 × 1500 → anchored.
    open = window(result, ~D[2019-01-10])
    assert point(open.top) == {~D[2019-10-01], "1500"}
    refute open.top.final
    assert open.top.anchor
    assert open.low == nil
    assert open.low_reason == :window_open
    assert point(open.low_so_far) == {~D[2020-05-01], "1000"}
    refute open.final
    assert_dec(open.max_drawdown, "-0.333333")
    assert open.max_gap_days == 142

    assert result.counts == %{cycles_complete: 2, cycles_partial: 1, cycle_open: true}
  end

  # User story (ADR-0060 §3, §12):
  # As the operator comparing the current cycle with the past ones,
  # I want the six intervals with their days, their change and n, min and
  # max,
  # so that the comparison is level (b) with nothing averaged or fitted.
  #
  # Acceptance criteria:
  # - halving_to_top: 416, 203 and 264 (the open window's anchored top,
  #   provisional) days; n 3.
  # - top_to_low: 184 days at -0.850000 and 273 days at -0.800000; n 2.
  # - low_to_top: ×20 (from the partial low, marked partial), ×16.666667
  #   and ×15 (to the open top, provisional); n 3.
  # - top_to_top: ×2.5 and ×3 (provisional); n 2.
  # - low_to_low: ×3 (partial) and ×3.333333; n 2.
  # - low_to_next_halving: 131 (partial), 131 and 254 days; n 3.
  # - The open window's low is no end of any observation.
  test "the six intervals with n, min and max, provisional and partial marked" do
    %{intervals: i} = Cycles.compute(cycle_series(), halvings())

    assert Map.keys(i) |> Enum.sort() ==
             Enum.sort(~w(halving_to_top top_to_low low_to_top top_to_top low_to_low
                          low_to_next_halving)a)

    # py: halving_to_top [416, 203, 264]
    assert i.halving_to_top.n == 3
    assert Enum.map(i.halving_to_top.observations, & &1.days) == [416, 203, 264]
    assert Enum.map(i.halving_to_top.observations, & &1.provisional) == [false, false, true]
    assert i.halving_to_top.days == %{min: 203, max: 416}
    assert i.halving_to_top.factor == nil
    assert i.halving_to_top.change == nil

    # py: top_to_low [(184, -0.850000), (273, -0.800000)]
    assert i.top_to_low.n == 2
    assert Enum.map(i.top_to_low.observations, & &1.days) == [184, 273]

    assert Enum.map(i.top_to_low.observations, &Decimal.to_string(&1.change, :normal)) ==
             ["-0.850000", "-0.800000"]

    assert i.top_to_low.days == %{min: 184, max: 273}
    assert_dec(i.top_to_low.change.min, "-0.850000")
    assert_dec(i.top_to_low.change.max, "-0.800000")
    assert i.top_to_low.factor == nil

    # py: low_to_top [(547, 20.000000), (334, 16.666667), (518, 15.000000)]
    assert i.low_to_top.n == 3
    assert Enum.map(i.low_to_top.observations, & &1.days) == [547, 334, 518]

    assert Enum.map(i.low_to_top.observations, &Decimal.to_string(&1.factor, :normal)) ==
             ["20.000000", "16.666667", "15.000000"]

    assert Enum.map(i.low_to_top.observations, &{&1.partial, &1.provisional}) ==
             [{true, false}, {false, false}, {false, true}]

    assert i.low_to_top.days == %{min: 334, max: 547}
    assert_dec(i.low_to_top.factor.min, "15.000000")
    assert_dec(i.low_to_top.factor.max, "20.000000")

    first = hd(i.low_to_top.observations)

    assert first.from == %{
             event: :low,
             window_start: ~D[2013-01-10],
             date: ~D[2014-09-01],
             close: Decimal.new("10")
           }

    assert first.to == %{
             event: :top,
             window_start: ~D[2015-01-10],
             date: ~D[2016-03-01],
             close: Decimal.new("200")
           }

    # py: top_to_top [(518, 2.500000), (791, 3.000000)]
    assert i.top_to_top.n == 2
    assert Enum.map(i.top_to_top.observations, & &1.days) == [518, 791]

    assert Enum.map(i.top_to_top.observations, &Decimal.to_string(&1.factor, :normal)) ==
             ["2.500000", "3.000000"]

    assert Enum.map(i.top_to_top.observations, & &1.provisional) == [false, true]

    # py: low_to_low [(731, 3.000000), (607, 3.333333)]
    assert i.low_to_low.n == 2
    assert Enum.map(i.low_to_low.observations, & &1.days) == [731, 607]

    assert Enum.map(i.low_to_low.observations, &Decimal.to_string(&1.factor, :normal)) ==
             ["3.000000", "3.333333"]

    assert Enum.map(i.low_to_low.observations, & &1.partial) == [true, false]
    assert i.low_to_low.days == %{min: 607, max: 731}
    assert_dec(i.low_to_low.factor.min, "3.000000")
    assert_dec(i.low_to_low.factor.max, "3.333333")

    # py: low_to_next_halving [131, 131, 254]
    assert i.low_to_next_halving.n == 3
    assert Enum.map(i.low_to_next_halving.observations, & &1.days) == [131, 131, 254]
    assert Enum.map(i.low_to_next_halving.observations, & &1.partial) == [true, false, false]
    assert i.low_to_next_halving.days == %{min: 131, max: 254}

    last = List.last(i.low_to_next_halving.observations)

    assert last.to == %{
             event: :halving,
             window_start: ~D[2017-01-10],
             date: ~D[2019-01-10],
             close: nil
           }

    for {_relation, %{reason: reason}} <- i, do: assert(reason == nil)
  end

  # Three confirmed halvings, the last one's window open, and the closes
  # given: the open window's anchor threshold in isolation.
  defp open_case(open_closes) do
    rows =
      [{~D[2020-01-01], "40"}, {~D[2020-06-01], "60"}, {~D[2020-12-01], "30"}] ++
        [{~D[2021-01-01], "50"}, {~D[2021-06-01], "90"}, {~D[2021-12-01], "45"}] ++
        Enum.map(open_closes, fn {date, close} -> {date, close} end)

    Cycles.compute(series(rows), [
      confirmed(1, ~D[2020-01-01]),
      confirmed(2, ~D[2021-01-01]),
      confirmed(3, ~D[2022-01-01])
    ])
  end

  # User story (ADR-0060 §2, §13 item 4):
  # As the operator reading the open cycle,
  # I want its top to anchor the intervals only once a close has been at
  # least 20 % below it, and to stay anchored through a recovery until a
  # deeper fall replaces it,
  # so that a dip in the first week after a halving anchors nothing, and a
  # replaced top is shown as replaced.
  #
  # Acceptance criteria:
  # - 125 then 100: exactly -20 % (compared exactly in Decimal) anchors.
  # - 125 then 100.01: -0.199920 does not; the top is shown with
  #   `anchor: false`, the relations that need it answer `no_top_yet` and
  #   count no observation of it.
  # - A recovery to 130 after the 100 leaves 125 the anchored top.
  # - A fall from 130 to 90 (-0.307692, deeper) replaces the top with 130.
  test "the open window's top anchors at a 20 % fall, a recovery keeps it, a deeper fall replaces it" do
    # py: 100 <= 0.80 × 125 → True, 100/125 − 1 = -0.200000
    exact = open_case([{~D[2022-01-01], "110"}, {~D[2022-03-01], "125"}, {~D[2022-05-01], "100"}])
    open = List.last(exact.windows)
    assert point(open.top) == {~D[2022-03-01], "125"}
    assert open.top.anchor
    assert_dec(open.max_drawdown, "-0.200000")
    assert exact.intervals.halving_to_top.n == 3
    assert exact.intervals.top_to_top.n == 2
    assert exact.intervals.low_to_top.n == 2
    assert exact.intervals.halving_to_top.reason == nil

    # py: 100.01 <= 0.80 × 125 → False, 100.01/125 − 1 = -0.199920
    short =
      open_case([{~D[2022-01-01], "110"}, {~D[2022-03-01], "125"}, {~D[2022-05-01], "100.01"}])

    open = List.last(short.windows)
    assert point(open.top) == {~D[2022-03-01], "125"}
    refute open.top.anchor
    assert open.anchor_reason == :no_top_yet
    assert_dec(open.max_drawdown, "-0.199920")
    assert short.intervals.halving_to_top.n == 2
    assert short.intervals.top_to_top.n == 1
    assert short.intervals.low_to_top.n == 1

    for relation <- ~w(halving_to_top top_to_top low_to_top)a,
        do: assert(short.intervals[relation].reason == :no_top_yet)

    for relation <- ~w(top_to_low low_to_low low_to_next_halving)a,
        do: assert(short.intervals[relation].reason == nil)

    recovered =
      open_case([
        {~D[2022-01-01], "110"},
        {~D[2022-03-01], "125"},
        {~D[2022-05-01], "100"},
        {~D[2022-08-01], "130"}
      ])

    open = List.last(recovered.windows)
    assert point(open.top) == {~D[2022-03-01], "125"}
    assert open.top.anchor

    # py: 90/130 − 1 = -0.307692, deeper than -0.2 → the top is 130.
    replaced =
      open_case([
        {~D[2022-01-01], "110"},
        {~D[2022-03-01], "125"},
        {~D[2022-05-01], "100"},
        {~D[2022-08-01], "130"},
        {~D[2022-10-01], "90"}
      ])

    open = List.last(replaced.windows)
    assert point(open.top) == {~D[2022-08-01], "130"}
    assert point(open.low_so_far) == {~D[2022-10-01], "90"}
    assert_dec(open.max_drawdown, "-0.307692")
  end

  # User story (ADR-0060 §1, §2):
  # As the agent reading an incomplete series,
  # I want the edge windows named rather than guessed,
  # so that an absent figure is never a zero.
  #
  # Acceptance criteria:
  # - A closed window without a close is `no_closes`, with no top and no
  #   low, and counts as neither complete nor partial.
  # - A window whose closes never fall below their running peak has no top
  #   and no low (`no_decline`), not a top and low on one day.
  # - An open window without a close yet has no top (`no_closes`).
  # - A close of zero or below is not a price and is skipped.
  test "a window without closes, without a decline, and non-positive closes" do
    result =
      Cycles.compute(
        series([
          {~D[2021-01-05], "10"},
          {~D[2021-03-01], "0"},
          {~D[2021-04-01], "20"},
          {~D[2021-05-01], "-5"},
          {~D[2021-06-01], "30"}
        ]),
        [
          confirmed(1, ~D[2019-01-01]),
          confirmed(2, ~D[2020-01-01]),
          confirmed(3, ~D[2021-01-01]),
          confirmed(4, ~D[2022-01-01])
        ]
      )

    [empty, before, rising, open] = result.windows

    # The first two windows end before the first stored close.
    assert empty.kind == :no_closes

    assert {empty.top, empty.low, empty.top_reason, empty.low_reason} ==
             {nil, nil, :no_closes, :no_closes}

    assert before.kind == :no_closes

    assert rising.kind == :complete
    assert rising.closes == 3
    assert {rising.top, rising.low} == {nil, nil}
    assert {rising.top_reason, rising.low_reason} == {:no_decline, :no_decline}
    assert_dec(rising.max_drawdown, "0.000000")

    assert open.kind == :open
    assert open.closes == 0
    assert {open.top, open.low_so_far, open.top_reason} == {nil, nil, :no_closes}

    assert result.counts == %{cycles_complete: 1, cycles_partial: 0, cycle_open: true}
  end
end
