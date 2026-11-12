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
end
