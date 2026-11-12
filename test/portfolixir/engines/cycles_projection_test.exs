defmodule Portfolixir.Engines.CyclesProjectionTest do
  # ADR-0060 §4 to §8, §13 items 7 and 8 (Sprint 29 H5, FR-58, idea I12):
  # the analog band — one part per relation, its time side from the minimum
  # to the maximum of the relation's days, its price side from the last
  # factor f₂ to f₂^(ln f₂ / ln f₁) (the minimum to the maximum of the stored
  # factors where no step is defined), at least two observations per part.
  #
  # Risk tier: analytics. Every series, date and halving below is synthetic.
  # Every expected figure was recomputed independently in Python:
  # `decimal` at precision 34 with ROUND_HALF_UP (the app's Decimal context,
  # read from `Decimal.Context.get/0`), scale 6 on the way out; where the
  # log step is taken, `math.log` and `math.pow` on IEEE doubles mirror
  # `:math.log/1` and `:math.pow/2`, and `Decimal(repr(g))` mirrors
  # `Decimal.from_float/1` (both the shortest round-trip form). The days are
  # calendar days (`date + timedelta`). The recomputation is quoted beside
  # each assertion as "py:".
  use ExUnit.Case, async: true

  alias Portfolixir.Engines.Cycles

  defp series(rows),
    do: Enum.map(rows, fn {date, close} -> %{date: date, close: Decimal.new(close)} end)

  defp confirmed(height, date), do: %{height: height, date: date, date_end: nil, confirmed: true}

  defp assert_dec(actual, expected), do: assert(Decimal.to_string(actual, :normal) == expected)

  defp range(nil), do: nil
  defp range(%{from: %Date{} = from, to: to}), do: {from, to}

  defp range(%{from: from, to: to}),
    do: {Decimal.to_string(from, :normal), Decimal.to_string(to, :normal)}

  defp part(event, relation), do: Enum.find(event.parts, &(&1.relation == relation))

  # Fixture A: H4's four windows (a partial first one, two complete, an open
  # one whose top of 1500 is anchored by its fall to 1000) and the next
  # halving as a window. Tops 200, 500, 1500; lows 10 (partial), 30, 100.
  defp halvings_a do
    [
      confirmed(840_000, ~D[2013-01-10]),
      confirmed(1_680_000, ~D[2015-01-10]),
      confirmed(2_520_000, ~D[2017-01-10]),
      confirmed(3_360_000, ~D[2019-01-10]),
      %{height: 4_200_000, date: ~D[2021-01-05], date_end: ~D[2021-01-20], confirmed: false}
    ]
  end

  defp rows_a do
    [
      {~D[2013-03-01], "50"},
      {~D[2013-06-01], "80"},
      {~D[2013-09-01], "20"},
      {~D[2014-03-01], "30"},
      {~D[2014-09-01], "10"},
      {~D[2014-12-01], "15"},
      {~D[2015-01-10], "9"},
      {~D[2015-06-01], "40"},
      {~D[2015-12-01], "200"},
      {~D[2016-03-01], "200"},
      {~D[2016-06-01], "60"},
      {~D[2016-09-01], "30"},
      {~D[2016-11-01], "30"},
      {~D[2016-12-20], "45"},
      {~D[2017-01-10], "50"},
      {~D[2017-05-01], "300"},
      {~D[2017-08-01], "500"},
      {~D[2017-11-01], "350"},
      {~D[2018-02-01], "120"},
      {~D[2018-05-01], "100"},
      {~D[2018-08-01], "250"},
      {~D[2018-12-01], "520"},
      {~D[2019-01-09], "480"},
      {~D[2019-01-10], "470"},
      {~D[2019-06-01], "900"},
      {~D[2019-10-01], "1500"},
      {~D[2020-01-01], "1100"},
      {~D[2020-03-01], "1300"},
      {~D[2020-05-01], "1000"}
    ]
  end

  # Fixture B: four yearly windows from the series' first close, so every
  # closed one is complete. Lows 10, 10, 15 (low → low's older factor is
  # exactly 1); top → low's last two factors are equal (0.125, 0.125) over
  # equal days (122, 122, 122); tops 40, 80, 120 and the open 200, anchored
  # by its fall to 100.
  defp halvings_b do
    [
      confirmed(840_000, ~D[2010-01-01]),
      confirmed(1_680_000, ~D[2011-01-01]),
      confirmed(2_520_000, ~D[2012-01-01]),
      confirmed(3_360_000, ~D[2013-01-01]),
      %{height: 4_200_000, date: ~D[2014-01-01], date_end: ~D[2014-01-10], confirmed: false}
    ]
  end

  defp rows_b do
    [
      {~D[2010-01-01], "10"},
      {~D[2010-04-01], "40"},
      {~D[2010-08-01], "10"},
      {~D[2010-12-01], "12"},
      {~D[2011-01-01], "20"},
      {~D[2011-04-01], "80"},
      {~D[2011-08-01], "10"},
      {~D[2011-12-01], "15"},
      {~D[2012-01-01], "30"},
      {~D[2012-04-01], "120"},
      {~D[2012-08-01], "15"},
      {~D[2012-12-01], "20"},
      {~D[2013-01-01], "40"},
      {~D[2013-04-01], "200"},
      {~D[2013-06-01], "100"}
    ]
  end

  # --- Sprint 29 H5 commit 1: the parts ---

  # User story (ADR-0060 §4; AR-3 as amended 2026-11-12):
  # As the maintainer holding the float island,
  # I want the band's one new float operation, the log step, total and
  # exact against an independent recomputation,
  # so that a factor of exactly 1, a factor that crossed 1, a step out of
  # the double range or a factor that is no price never raises and never
  # passes as a figure.
  #
  # Acceptance criteria:
  # - f₂^(ln f₂ / ln f₁), through `:math.log/1` and `:math.pow/2`, then
  #   `Decimal.from_float/1` and `Decimal.round/2` at scale 6.
  # - A step that grows the factor (|ln f₂| > |ln f₁|) is taken as it comes.
  # - Undefined (`nil`): f₁ or f₂ exactly 1 (ln = 0, §13 item 7), the two
  #   logarithms of different signs, a factor of zero or below, a factor
  #   outside the double range, a step that overflows or underflows to 0.
  test "the log step is f₂^(ln f₂ / ln f₁), total, nil where no step is defined" do
    d = &Decimal.new/1

    # py: math.pow(0.2, log(0.2)/log(0.15)) = 0.25528355435939054 → 0.255284
    assert_dec(Cycles.log_step(d.("0.150000"), d.("0.200000")), "0.255284")
    # py: math.pow(3.0, log(3)/log(2.5)) → 3.732998
    assert_dec(Cycles.log_step(d.("2.500000"), d.("3.000000")), "3.732998")
    # py: |b| > |a|: math.pow(1.666667, 1.2598514978253064) = 1.9032532888097424 → 1.903253
    assert_dec(Cycles.log_step(d.("1.500000"), d.("1.666667")), "1.903253")
    # py: equal factors, b / a = 1.0 → 2.000000
    assert_dec(Cycles.log_step(d.("2"), d.("2")), "2.000000")

    for {f1, f2} <- [
          # f₁ = 1, f₂ = 1: ln = 0
          {"1.000000", "3"},
          {"3", "1.000000"},
          # the factor crossed 1: different signs
          {"0.8", "1.25"},
          {"1.25", "0.8"},
          # py: OverflowError, math.pow(100.0, ~4607.5)
          {"1.001", "100"},
          # py: math.pow(1e-06, ~13809) = 0.0 → rounds to 0, no price
          {"0.999", "0.000001"},
          # no price
          {"0", "2"},
          {"2", "-1"},
          # outside the double range
          {"1E+400", "2"},
          {"2", "1E-400"}
        ] do
      assert Cycles.log_step(d.(f1), d.(f2)) == nil, "#{f1}, #{f2}"
    end
  end

  # User story (ADR-0060 §4; plan row H5):
  # As the operator or the agent reading the next low and the next top,
  # I want each part read from one relation alone and applied to that
  # relation's current anchor,
  # so that every end of the band traces back to stored tops, lows and
  # halvings by one stated rule.
  #
  # Acceptance criteria:
  # - Next low: `top_to_low` from the open window's anchored top (1500 on
  #   2019-10-01), `low_to_low` from the last final low (100 on 2018-05-01).
  # - Next top (the open window's top is anchored, so the next window's):
  #   `halving_to_top` from the next halving's window, its price side
  #   borrowed from `top_to_top`; `top_to_top` from the last anchored top;
  #   `low_to_top` absent with `low_not_final` (it waits for the open
  #   window's low).
  # - Time: anchor + the relation's minimum to maximum days; for
  #   `halving_to_top` the window's first day + the minimum to its last day
  #   + the maximum.
  # - Price: anchor × f₂ to anchor × f₂^(ln f₂ / ln f₁), in either order,
  #   at scale 6; `top_to_low` uses 1 + change. The two factors used,
  #   `n_time`, `n_price`, `time_rule`, `price_rule` on every part.
  test "the parts of the next low and the next top, time min to max, price by the log step" do
    result = Cycles.compute(series(rows_a()), halvings_a())
    low = result.projection.next_low
    top = result.projection.next_top

    assert Enum.map(low.parts, & &1.relation) == [:top_to_low, :low_to_low]
    assert Enum.map(top.parts, & &1.relation) == [:halving_to_top, :top_to_top, :low_to_top]

    tl = part(low, :top_to_low)
    assert {tl.anchor.event, tl.anchor.date, tl.anchor.final} == {:top, ~D[2019-10-01], false}
    # py: days [184, 273] → 2019-10-01 + 184 = 2020-04-02, + 273 = 2020-06-30
    assert range(tl.window) == {~D[2020-04-02], ~D[2020-06-30]}
    # py: factors 1 + (-0.85), 1 + (-0.8) = 0.15, 0.2; step 0.255284;
    # 1500 × 0.2 = 300.000000, 1500 × 0.255284 = 382.926000
    assert range(tl.factor) == {"0.200000", "0.255284"}
    assert range(tl.price) == {"300.000000", "382.926000"}
    assert Enum.map(tl.factors_used, &Decimal.to_string/1) == ["0.150000", "0.200000"]

    assert {tl.n_time, tl.n_price, tl.time_rule, tl.price_rule, tl.price_reason} ==
             {2, 2, :min_max, :log_step_v1, nil}

    assert {tl.own_price, tl.price_from, tl.provisional, tl.partial, tl.reason} ==
             {true, nil, true, false, nil}

    ll = part(low, :low_to_low)
    assert {ll.anchor.event, ll.anchor.date, ll.anchor.final} == {:low, ~D[2018-05-01], true}
    # py: days [731, 607] → 2018-05-01 + 607 = 2019-12-29, + 731 = 2020-05-01
    assert range(ll.window) == {~D[2019-12-29], ~D[2020-05-01]}
    # py: factors 3.000000, 3.333333; step 3.741316; 100 × … = 333.333300, 374.131600
    assert range(ll.factor) == {"3.333333", "3.741316"}
    assert range(ll.price) == {"333.333300", "374.131600"}
    # the first low is partial (before the series), so the part is too
    assert {ll.n_time, ll.n_price, ll.provisional, ll.partial} == {2, 2, false, true}

    tt = part(top, :top_to_top)
    assert {tt.anchor.event, tt.anchor.date} == {:top, ~D[2019-10-01]}
    # py: days [518, 791] → 2021-03-02 to 2021-11-30
    assert range(tt.window) == {~D[2021-03-02], ~D[2021-11-30]}
    # py: factors 2.5, 3.0; step 3.732998; 1500 × … = 4500.000000, 5599.497000
    assert range(tt.factor) == {"3.000000", "3.732998"}
    assert range(tt.price) == {"4500.000000", "5599.497000"}
    assert {tt.n_time, tt.n_price, tt.own_price} == {2, 2, true}

    ht = part(top, :halving_to_top)

    assert {ht.anchor.event, ht.anchor.date, ht.anchor.date_end, ht.anchor.confirmed} ==
             {:halving, ~D[2021-01-05], ~D[2021-01-20], false}

    # py: days [416, 203, 264] → 2021-01-05 + 203 = 2021-07-27, 2021-01-20 + 416 = 2022-03-12
    assert range(ht.window) == {~D[2021-07-27], ~D[2022-03-12]}
    assert range(ht.price) == range(tt.price)
    assert {ht.n_time, ht.n_price, ht.own_price, ht.price_from} == {3, 2, false, :top_to_top}

    lt = part(top, :low_to_top)

    assert {lt.reason, lt.window, lt.price, lt.n_time, lt.n_price} ==
             {:low_not_final, nil, nil, 3, 3}
  end

  # User story (ADR-0060 §4, §13 items 7 and 8; plan row H5):
  # As the operator reading a band built on very few cycles,
  # I want a factor of exactly 1 to fall back to the minimum to the maximum,
  # stated, and a part that would be a single date or price to be absent,
  # so that the band never divides by zero and never names one figure.
  #
  # Acceptance criteria:
  # - Low → low's factors 1.000000, 1.500000: ln f₁ = 0, so the price side is
  #   the minimum to the maximum of the stored factors, `price_rule: :min_max`
  #   and `price_reason: :no_log_step`.
  # - Top → low's last two factors are equal and its days all 122: the part
  #   would be one date and one price, so it is absent with `zero_width`.
  # - A step that grows the factor (top → top 1.5 then 1.666667) is taken.
  test "f₁ = 1 falls back to min to max, stated; a part of one date and one price is absent" do
    result = Cycles.compute(series(rows_b()), halvings_b())
    low = result.projection.next_low
    top = result.projection.next_top

    ll = part(low, :low_to_low)
    # py: ln(1.0) = 0 → min_max over [1.000000, 1.500000]; 15 × … = 15.000000, 22.500000
    assert {ll.price_rule, ll.price_reason} == {:min_max, :no_log_step}
    assert Enum.map(ll.factors_used, &Decimal.to_string/1) == ["1.000000", "1.500000"]
    assert range(ll.price) == {"15.000000", "22.500000"}
    # py: days [365, 366] from 2012-08-01
    assert range(ll.window) == {~D[2013-08-01], ~D[2013-08-02]}

    tl = part(low, :top_to_low)

    # py: factors [0.25, 0.125, 0.125] → step 0.125^1.0 = 0.125: 25..25; days 122 → 2013-08-01 twice
    assert {tl.reason, tl.window, tl.price, tl.n_time, tl.n_price} ==
             {:zero_width, nil, nil, 3, 3}

    tt = part(top, :top_to_top)
    # py: 200 × 1.666667 = 333.333400, 200 × 1.903253 = 380.650600; days [365, 366, 365]
    assert range(tt.price) == {"333.333400", "380.650600"}
    assert range(tt.window) == {~D[2014-04-01], ~D[2014-04-02]}
    assert tt.price_rule == :log_step_v1

    ht = part(top, :halving_to_top)
    # py: days [90, 90, 91, 90] → 2014-01-01 + 90 = 2014-04-01, 2014-01-10 + 91 = 2014-04-11
    assert range(ht.window) == {~D[2014-04-01], ~D[2014-04-11]}
  end

  # User story (ADR-0060 §4 "Minimum data"; board 07 ⑥):
  # As the operator reading a security with one cycle behind it,
  # I want a part with fewer than two observations absent with its n,
  # so that a band is never drawn through a single past cycle.
  #
  # Acceptance criteria:
  # - Three windows, the open one not anchored (no fall yet): top → low
  #   answers `no_top_yet`; low → low, top → top and low → top answer
  #   `too_few_observations` with their n (1, 0, 1).
  # - `halving_to_top` (from the open window's own halving, its top being
  #   the next one) borrows top → top's absence and its n_price.
  test "a part with one observation is absent with its n, and a borrowed side with its lender" do
    halvings =
      Enum.take(halvings_a(), 3) ++
        [%{height: 3_360_000, date: ~D[2019-01-05], date_end: ~D[2019-01-20], confirmed: false}]

    rows = Enum.filter(rows_a(), &(Date.compare(elem(&1, 0), ~D[2017-06-01]) == :lt))
    result = Cycles.compute(series(rows), halvings)
    low = result.projection.next_low
    top = result.projection.next_top

    assert Enum.map(low.parts, &{&1.relation, &1.reason, &1.n_time, &1.n_price}) == [
             {:top_to_low, :no_top_yet, 1, 1},
             {:low_to_low, :too_few_observations, 1, 1}
           ]

    assert Enum.map(top.parts, &{&1.relation, &1.reason, &1.n_time, &1.n_price}) == [
             {:halving_to_top, :too_few_observations, 1, 0},
             {:top_to_top, :too_few_observations, 0, 0},
             {:low_to_top, :too_few_observations, 1, 1}
           ]

    ht = part(top, :halving_to_top)

    assert {ht.anchor.event, ht.anchor.date, ht.price_from} ==
             {:halving, ~D[2017-01-10], :top_to_top}

    for part <- low.parts ++ top.parts do
      assert {part.window, part.price} == {nil, nil}
    end
  end

  # --- Sprint 29 H5 commit 1 end ---
end
