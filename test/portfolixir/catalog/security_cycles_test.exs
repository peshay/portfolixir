defmodule Portfolixir.Catalog.SecurityCyclesTest do
  # ADR-0060 §1, §9, §12 (Sprint 29 H4, FR-58): the cycles read's shell —
  # the security's split-adjusted closes in its own currency, its confirmed
  # halving events, and the computation basis in the payload.
  #
  # Risk tier: analytics. The security, its halvings (heights k × Litecoin's
  # registered interval, written by hand as a chain without a source allows)
  # and its closes are synthetic. Every expected figure was recomputed
  # independently with Python's `decimal` module at precision 28 and
  # ROUND_HALF_UP at scale 6: the stored raw closes, the closes dated before
  # the split's effective date divided by its ratio of 2, the maximum
  # drawdown by brute force over every pair with the tie rules, the days as
  # calendar days. The recomputation is quoted as "py:".
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.SecurityCycles
  alias Portfolixir.Derived.Registry
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger.Splits

  @interval 840_000

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  defp bound_security!(name) do
    security = create_security!(name: name, ticker: nil, asset_class: "crypto")
    {:ok, bound} = Catalog.update_security(agent(), security, %{halving_chain: :litecoin})
    bound
  end

  defp halving!(security, k, date, attrs \\ %{}) do
    {:ok, event} =
      Events.create_event(
        agent(),
        Map.merge(
          %{
            "security_id" => security.id,
            "kind" => "halving",
            "chain_height" => k * @interval,
            "date" => Date.to_iso8601(date),
            "timing" => "exact",
            "confirmed" => true,
            "source_quality" => "secondary_multi"
          },
          attrs
        )
      )

    event
  end

  defp closes!(security, rows) do
    rows =
      Enum.map(rows, fn {date, close} ->
        %{date: date, close: Decimal.new(close), source: "manual"}
      end)

    {:ok, _count} = Quotes.upsert_many(security.id, rows)
    :ok
  end

  defp assert_dec(actual, expected), do: assert(Decimal.to_string(actual, :normal) == expected)

  defp point(%{date: date, close: close}),
    do: {date, Decimal.to_string(Decimal.normalize(close), :normal)}

  # Three confirmed halvings and an unconfirmed one, a 2:1 split inside the
  # second window, stored raw closes (before 2021-05-01 in the unsplit unit).
  defp synthetic_coin! do
    security = bound_security!("Synthetic Coin")
    world = base_world(name: "Cycle World", cash_name: "CW Cash", depot_name: "CW Depot")
    buy!(world, security, quantity: "2", price: "100", date: ~D[2021-02-01])

    {:ok, _txs} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2021-05-01],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    halving!(security, 1, ~D[2020-01-10])
    halving!(security, 2, ~D[2021-01-10])
    halving!(security, 3, ~D[2022-01-10])

    halving!(security, 4, ~D[2023-01-05], %{
      "confirmed" => false,
      "timing" => "window",
      "date_end" => "2023-01-20",
      "source_quality" => "unverified"
    })

    # Stored raw closes; before 2021-05-01 in the unsplit unit.
    closes!(security, [
      {~D[2020-01-10], "100"},
      {~D[2020-04-01], "400"},
      {~D[2020-07-01], "100"},
      {~D[2020-10-01], "150"},
      {~D[2021-01-10], "160"},
      {~D[2021-03-01], "600"},
      {~D[2021-04-30], "600"},
      {~D[2021-05-01], "300"},
      {~D[2021-07-01], "450"},
      {~D[2021-09-01], "225"},
      {~D[2021-12-01], "300"},
      {~D[2022-01-10], "310"},
      {~D[2022-06-01], "900"},
      {~D[2022-09-01], "700"},
      {~D[2022-11-01], "800"}
    ])

    security
  end

  # User story (ADR-0060 §1, §9; plan row H4):
  # As the operator's agent reading a bound security's halving cycles,
  # I want them computed over its split-adjusted closes in its own currency
  # and its confirmed halvings, with the computation basis in the answer,
  # so that a split is never read as a fall and every figure can be checked.
  #
  # Acceptance criteria:
  # - Three confirmed halvings give two closed windows and an open one; the
  #   unconfirmed halving forms none and is the next halving.
  # - A 2:1 split inside the second window does not move its top: read
  #   raw, the top would be 2021-04-30 at 600 and the drawdown -0.625; read
  #   adjusted, it is 2021-07-01 at 450 and -0.500000.
  # - The intervals match the recomputation, n included.
  # - The basis names the series (security, currency, display basis,
  #   positive closes, first and last close, gaps), the halvings, the rules
  #   (`halving_to_halving_v1`, `max_drawdown_v1` with its ties,
  #   `anchor_threshold` "0.20", the 7-day rule) and the counts.
  test "reads the cycles over the split-adjusted closes and the confirmed halvings, with the basis" do
    security = synthetic_coin!()

    assert {:ok, payload} = SecurityCycles.for_security(security.id)

    assert payload.security_id == security.id
    assert payload.currency_code == "EUR"
    assert payload.chain == "litecoin"
    assert payload.reason == nil

    assert Enum.map(payload.halvings, &{&1.height, &1.date, &1.confirmed}) == [
             {840_000, ~D[2020-01-10], true},
             {1_680_000, ~D[2021-01-10], true},
             {2_520_000, ~D[2022-01-10], true},
             {3_360_000, ~D[2023-01-05], false}
           ]

    assert Enum.all?(payload.halvings, &(&1.chain == "litecoin"))
    assert List.last(payload.halvings).date_end == ~D[2023-01-20]
    assert hd(payload.halvings).source_quality == :secondary_multi

    assert payload.next_halving == %{
             height: 3_360_000,
             date: ~D[2023-01-05],
             date_end: ~D[2023-01-20]
           }

    assert Enum.map(payload.cycles, &{&1.start, &1.end, &1.kind}) == [
             {~D[2020-01-10], ~D[2021-01-10], :complete},
             {~D[2021-01-10], ~D[2022-01-10], :complete},
             {~D[2022-01-10], nil, :open}
           ]

    [first, second, open] = payload.cycles

    # py: adjusted 2020 → top 2020-04-01 200, low 2020-07-01 50, -0.75.
    assert point(first.top) == {~D[2020-04-01], "200"}
    assert point(first.low) == {~D[2020-07-01], "50"}
    assert_dec(first.max_drawdown, "-0.750000")

    # py: raw 2021 → top 2021-04-30 600, -0.625; adjusted → top 2021-07-01
    # 450, low 2021-09-01 225, -0.5.
    assert point(second.top) == {~D[2021-07-01], "450"}
    assert point(second.low) == {~D[2021-09-01], "225"}
    assert_dec(second.max_drawdown, "-0.500000")

    # py: open 2022 → top 2022-06-01 900, low so far 2022-09-01 700,
    # -0.222222, 700 <= 0.80 × 900 → anchored.
    assert point(open.top) == {~D[2022-06-01], "900"}
    assert open.top.anchor
    assert point(open.low_so_far) == {~D[2022-09-01], "700"}
    assert_dec(open.max_drawdown, "-0.222222")

    i = payload.intervals
    # py: halving_to_top [82, 172, 142]; top_to_low [(91, -0.75), (62, -0.5)];
    # low_to_top [(365, 9), (273, 4)]; top_to_top [(456, 2.25), (335, 2)];
    # low_to_low [(427, 4.5)]; low_to_next_halving [193, 131].
    assert Enum.map(i.halving_to_top.observations, & &1.days) == [82, 172, 142]

    assert Enum.map(i.top_to_low.observations, &{&1.days, Decimal.to_string(&1.change)}) ==
             [{91, "-0.750000"}, {62, "-0.500000"}]

    assert Enum.map(i.low_to_top.observations, &{&1.days, Decimal.to_string(&1.factor)}) ==
             [{365, "9.000000"}, {273, "4.000000"}]

    assert Enum.map(i.top_to_top.observations, &{&1.days, Decimal.to_string(&1.factor)}) ==
             [{456, "2.250000"}, {335, "2.000000"}]

    assert Enum.map(i.low_to_low.observations, &{&1.days, Decimal.to_string(&1.factor)}) ==
             [{427, "4.500000"}]

    assert Enum.map(i.low_to_next_halving.observations, & &1.days) == [193, 131]
    assert {i.halving_to_top.n, i.low_to_low.n} == {3, 1}

    basis = payload.computation_basis
    assert basis.series.security_id == security.id
    assert basis.series.currency_code == "EUR"
    assert basis.series.display_basis == "split_adjusted"
    assert basis.series.first_close == ~D[2020-01-10]
    assert basis.series.last_close == ~D[2022-11-01]
    assert basis.series.closes =~ "positive"
    assert basis.series.gaps =~ "never filled"
    assert basis.halvings =~ "confirmed"
    assert basis.window == "halving_to_halving_v1"
    assert basis.window_rule =~ "halving day"
    assert basis.extremes == "max_drawdown_v1"
    assert basis.extremes_rule =~ "latest"
    assert basis.extremes_rule =~ "earliest"
    assert_dec(basis.anchor_threshold, "0.20")
    assert basis.anchor_rule =~ "final"
    assert basis.partial_days == 7
    assert basis.counts == %{cycles_complete: 2, cycles_partial: 0, cycle_open: true}
    assert basis.intervals =~ "calendar days"
    assert basis.ladder =~ "(b)"
  end

  # User story (ADR-0060 §1):
  # As the agent asking for a security's cycles,
  # I want a reason where there are none,
  # so that an empty answer is never mistaken for "no cycle happened".
  #
  # Acceptance criteria:
  # - An unbound security answers `cycles: []` with `no_halving_chain`.
  # - A bound security with one confirmed halving (and an unconfirmed one)
  #   answers `too_few_halvings`.
  # - Two confirmed halvings but no close on or after the first answers
  #   `no_closes`.
  # - An unknown or malformed id is `{:error, :not_found}`.
  test "no halving chain, too few halvings, no closes, not found" do
    unbound = create_security!(name: "Unbound Coin", ticker: nil, asset_class: "crypto")

    assert {:ok, %{cycles: [], intervals: nil, reason: :no_halving_chain}} =
             SecurityCycles.for_security(unbound.id)

    few = bound_security!("Few Coin")
    halving!(few, 1, ~D[2020-01-10])
    halving!(few, 2, ~D[2024-01-10], %{"confirmed" => false})
    closes!(few, [{~D[2020-02-01], "10"}])

    assert {:ok, %{cycles: [], reason: :too_few_halvings} = payload} =
             SecurityCycles.for_security(few.id)

    assert length(payload.halvings) == 2
    assert payload.computation_basis.window == "halving_to_halving_v1"

    early = bound_security!("Early Coin")
    halving!(early, 1, ~D[2020-01-10])
    halving!(early, 2, ~D[2021-01-10])
    closes!(early, [{~D[2019-06-01], "10"}, {~D[2020-01-09], "12"}])

    assert {:ok, %{cycles: [], reason: :no_closes}} = SecurityCycles.for_security(early.id)
    assert {:ok, %{reason: :no_closes}} = SecurityCycles.for_security(Integer.to_string(early.id))

    assert SecurityCycles.for_security(-1) == {:error, :not_found}
    assert SecurityCycles.for_security("12x") == {:error, :not_found}
  end

  # --- Sprint 29 H5 begin ---

  defp range(nil), do: nil
  defp range(%{from: %Date{} = from, to: to}), do: {from, to}

  defp range(%{from: from, to: to}),
    do: {Decimal.to_string(from, :normal), Decimal.to_string(to, :normal)}

  defp part(event, relation), do: Enum.find(event.parts, &(&1.relation == relation))

  # User story (ADR-0060 §4 to §9, §11; plan row H5):
  # As the operator's agent reading a bound security's cycles,
  # I want the next low's and the next top's analog band in the same read,
  # with its parts, n, both ends, its state and its computation basis,
  # so that the projection reproduces from the stored closes and says that
  # it is not a forecast.
  #
  # Acceptance criteria:
  # - Over H4's split-adjusted Synthetic Coin (open top 900 on 2022-06-01,
  #   anchored): the next low is top → low alone (low → low has one
  #   observation), 2022-08-02..2022-08-31, 450..636.3963, missed by the
  #   last close; the next top is the hull of halving → top and top → top,
  #   2023-03-28..2023-08-31, 1627.6068..1800, open, one price relation.
  # - `projection.kind` "analog_band", `not_a_forecast: true`.
  # - The basis states the time and price rules with the log step and its
  #   fallback, the minimum data, the hull and agree, the states, the cones,
  #   the float island, and what is not computed (no point, no fit, no
  #   past cycle's band, no as_of).
  test "the projection travels in the read, with its parts, states and basis" do
    security = synthetic_coin!()

    assert {:ok, payload} = SecurityCycles.for_security(security.id)
    projection = payload.projection
    assert {projection.kind, projection.not_a_forecast} == {:analog_band, true}

    low = projection.next_low
    tl = part(low, :top_to_low)
    # py: factors 0.25, 0.5 (1 + change); math.pow(0.5, 0.5) = 0.7071067811865476
    # → 0.707107; 900 × 0.5 = 450.000000, 900 × 0.707107 = 636.396300; days [91, 62]
    assert {range(tl.window), range(tl.price)} ==
             {{~D[2022-08-02], ~D[2022-08-31]}, {"450.000000", "636.396300"}}

    assert {tl.price_rule, tl.n_time, tl.n_price} == {:log_step_v1, 2, 2}

    assert {part(low, :low_to_low).reason, part(low, :low_to_low).n_time} ==
             {:too_few_observations, 1}

    assert {range(low.band.window), range(low.band.price)} == {range(tl.window), range(tl.price)}
    assert {low.agree, low.agree_reason} == {nil, :one_price_relation}
    # py: last close 2022-11-01 after 2022-08-31; no close in the window → missed
    assert {low.state, low.window_ended} == {:missed, true}

    top = projection.next_top
    tt = part(top, :top_to_top)
    # py: factors 2.25, 2; math.pow(2.0, 0.8547556456757274) = 1.8084524252442167
    # → 1.808452; 900 × … = 1627.606800, 1800.000000; days [456, 335]
    assert {range(tt.window), range(tt.price)} ==
             {{~D[2023-05-02], ~D[2023-08-31]}, {"1627.606800", "1800.000000"}}

    # py: halving window 2023-01-05..2023-01-20, days [82, 172, 142]
    assert range(part(top, :halving_to_top).window) == {~D[2023-03-28], ~D[2023-07-11]}
    assert part(top, :low_to_top).reason == :low_not_final

    assert {range(top.band.window), range(top.band.price)} ==
             {{~D[2023-03-28], ~D[2023-08-31]}, {"1627.606800", "1800.000000"}}

    assert {top.state, top.agree_reason} == {:open, :one_price_relation}
    assert Enum.map(projection.cones, & &1.relation) == [:top_to_low, :top_to_top, :low_to_low]

    basis = payload.computation_basis.projection
    assert basis.kind == "analog_band"
    assert basis.not_a_forecast == true
    assert basis.time_rule == "min_max"
    assert basis.price_rule == "log_step_v1"
    assert basis.price_rule_text =~ "ln f₂ / ln f₁"
    assert basis.price_fallback =~ "no_log_step"
    assert basis.minimum_data =~ "too_few_observations"
    assert basis.minimum_data =~ "zero_width"
    assert basis.band =~ "hull"
    assert basis.agree =~ "one_price_relation"
    assert basis.agree =~ "parts_disjoint"
    assert basis.state =~ "input_after_window"
    assert basis.state =~ "last stored close"
    assert basis.cones =~ "anchor"
    assert basis.float_island =~ ":math.log/1"
    assert basis.not_computed =~ "no point"
    assert basis.not_computed =~ "as_of"
    assert payload.computation_basis.ladder =~ "analog band"
  end

  # User story (ADR-0060 §8, §13 item 12; plan row H5):
  # As the maintainer keeping level (d) out,
  # I want the cycles read to refuse `as_of` and every other parameter,
  # so that nobody can compute what a past cycle's band would have said from
  # that cycle's data, and the API (H6) answers 422 naming the parameter.
  #
  # Acceptance criteria:
  # - `as_of`, as a query parameter or a keyword, is refused with
  #   `{:error, {:invalid_params, %{"as_of" => [message]}}}`, the message
  #   naming the replay; any other parameter is refused the same way.
  # - The refusal comes before the lookup: an unknown id with `as_of` is
  #   refused, not "not found".
  # - Without parameters (an empty map or list) the read answers as before.
  test "as_of and every other parameter are refused, naming them" do
    security = synthetic_coin!()

    assert {:error, {:invalid_params, %{"as_of" => [message]}}} =
             SecurityCycles.for_security(security.id, %{"as_of" => "2021-06-01"})

    assert message =~ "as_of"
    assert message =~ "ADR-0060 §8"

    assert {:error, {:invalid_params, %{"as_of" => [_message]}}} =
             SecurityCycles.for_security(security.id, as_of: ~D[2021-06-01])

    assert {:error, {:invalid_params, %{"as_of" => [_], "window" => [_]}}} =
             SecurityCycles.for_security(-1, %{"as_of" => "2021-06-01", "window" => "1y"})

    assert {:ok, %{reason: nil}} = SecurityCycles.for_security(security.id, %{})
    assert {:ok, %{reason: nil}} = SecurityCycles.for_security(security.id, [])
  end

  # User story (ADR-0060 §10, ADR-0039 §2; plan row H5):
  # As the maintainer of the derived-value registry,
  # I want the cycles read registered at lifetime `:none` under the
  # security's own basis, as `security_metrics` is,
  # so that it is computed at every read, never stored, and any later move
  # off `:none` is a measured decision.
  #
  # Acceptance criteria:
  # - `security_cycles` is registered, at `:none`, computation version 1.
  # - Where the view does not exist the payload still carries the projection
  #   header with `not_a_forecast: true` and no band.
  test "registered at :none, and an empty view still says not a forecast" do
    assert Registry.registered?(:security_cycles)
    assert Registry.lifetime(:security_cycles) == :none
    assert Registry.computation_version!(:security_cycles) == 1

    unbound = create_security!(name: "Unbound Band Coin", ticker: nil, asset_class: "crypto")
    assert {:ok, payload} = SecurityCycles.for_security(unbound.id)

    assert payload.projection == %{
             kind: :analog_band,
             not_a_forecast: true,
             next_low: nil,
             next_top: nil,
             cones: []
           }

    assert payload.computation_basis.projection.not_a_forecast == true
  end

  # --- Sprint 29 H5 end ---
end
