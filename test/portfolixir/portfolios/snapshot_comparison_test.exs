defmodule Portfolixir.Portfolios.SnapshotComparisonTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, deposit!: 4]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.SnapshotComparison
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.WorldFixtures

  # User story (Andi, 2026-07-16, ADR-0027):
  # As a local portfolio maintainer who restructured my strategy,
  # I want the holdings frozen by a snapshot valued buy-and-hold over the real
  # stored quote history and compared against my real TTWROR since that date,
  # so that I can see whether I would have done better keeping what I had.
  #
  # Acceptance criteria:
  # - The snapshot side is the exact position set at the as-of date (scope-
  #   filtered), valued daily: last close on-or-before each day, converted to
  #   the base currency through the EUR hub at that day's stored rate.
  # - No trades, no flows enter the snapshot side: it is pure buy-and-hold.
  # - Trades after the as-of date change only the real side.
  # - The real side is the scope's TTWROR chained since the as-of date.
  # - Securities without any usable quote are excluded and surfaced as gaps
  #   (AR-4), never silently valued at zero inside the totals.
  # - All money math is Decimal-exact; the result labels its basis (gross,
  #   price-return only).

  defp rate!(quote_ccy, date, rate) do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: quote_ccy,
          date: date,
          rate: rate,
          source: "manual"
        }
      ])
  end

  defp setup_world do
    world = base_world(name: "Snapshot world", currency: "EUR")
    eur_sec = create_security!(name: "EUR Stock", ticker: "EURS", currency: "EUR")
    usd_sec = create_security!(name: "US Stock", ticker: "USDS", currency: "USD")

    deposit!(world, "10000", ~D[2026-01-02], [])

    # Position build-up before the snapshot: 10 EURS bought, 5 sold again;
    # 5 USDS bought. At the 2026-02-15 snapshot: 5 EURS + 5 USDS.
    WorldFixtures.buy!(world, eur_sec, quantity: "10", price: "100", date: ~D[2026-01-05])
    WorldFixtures.sell!(world, eur_sec, quantity: "5", price: "105", date: ~D[2026-02-01])
    WorldFixtures.buy!(world, usd_sec, quantity: "5", price: "50", date: ~D[2026-01-10])

    # Quotes: EURS 110 just before the as-of date, 120 at "today";
    # USDS 60 at the as-of date, 66 at "today".
    WorldFixtures.put_quote!(eur_sec, ~D[2026-02-14], "110")
    WorldFixtures.put_quote!(eur_sec, ~D[2026-03-10], "120")
    WorldFixtures.put_quote!(usd_sec, ~D[2026-02-15], "60")
    WorldFixtures.put_quote!(usd_sec, ~D[2026-03-10], "66")

    # EUR-hub USD rates: 1 EUR = 1.20 USD around the as-of date, 1.10 later.
    rate!("USD", ~D[2026-02-13], "1.20")
    rate!("USD", ~D[2026-03-09], "1.10")

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{
        name: "Before restructuring",
        as_of: ~D[2026-02-15]
      })

    Map.merge(world, %{eur_sec: eur_sec, usd_sec: usd_sec, snapshot: snapshot})
  end

  test "values the frozen holdings buy-and-hold and compares against real TTWROR" do
    world = setup_world()

    # A post-snapshot trade: changes the real portfolio, never the snapshot side.
    WorldFixtures.buy!(world, world.eur_sec, quantity: "10", price: "115", date: ~D[2026-03-01])

    {:ok, comparison} =
      SnapshotComparison.for_snapshot(world.snapshot.id, world.portfolio.id,
        today: ~D[2026-03-10]
      )

    # As-of: 5 × 110 EUR + (5 × 60 USD) / 1.20 = 550 + 250 = 800 EUR.
    assert Decimal.equal?(comparison.as_of_value, Decimal.new("800"))

    # Today: 5 × 120 EUR + (5 × 66 USD) / 1.10 = 600 + 300 = 900 EUR.
    assert Decimal.equal?(comparison.current_value, Decimal.new("900"))

    # Price return of the frozen set: 900 / 800 − 1 = 0.125, Decimal-exact.
    assert Decimal.equal?(comparison.snapshot_return, Decimal.new("0.125"))

    # The real side chains the scope's TTWROR from the as-of date on. The
    # expected value re-derives the chain independently from the daily walk:
    # baseline = value on the as-of day, then r_d = V_d / (V_{d−1} + F_d) − 1.
    analysis = Performance.analysis(world.portfolio.id, today: ~D[2026-03-10])

    {up_to, since} =
      Enum.split_with(analysis.daily, &(Date.compare(&1.date, ~D[2026-02-15]) != :gt))

    baseline = List.last(up_to).value

    {expected_growth, _prev} =
      Enum.reduce(since, {Decimal.new(1), baseline}, fn point, {growth, prev} ->
        denominator = Decimal.add(prev, point.flow)

        factor =
          if Decimal.compare(denominator, Decimal.new(0)) == :gt,
            do: Decimal.div(point.value, denominator),
            else: Decimal.new(1)

        {Decimal.mult(growth, factor), point.value}
      end)

    expected_real = Decimal.sub(expected_growth, Decimal.new(1))
    assert Decimal.equal?(comparison.real_ttwror, expected_real)
    # Sanity: the real side actually moved (quotes rose after the as-of date).
    assert Decimal.compare(comparison.real_ttwror, Decimal.new(0)) == :gt

    # The daily series is indexed to 1 on the as-of date on both sides and
    # spans as-of..today.
    assert %{date: ~D[2026-02-15]} = List.first(comparison.series)
    assert %{date: ~D[2026-03-10]} = List.last(comparison.series)

    first = List.first(comparison.series)
    assert Decimal.equal?(first.snapshot_indexed, Decimal.new(1))
    assert Decimal.equal?(first.real_indexed, Decimal.new(1))

    last = List.last(comparison.series)
    assert Decimal.equal?(last.snapshot_indexed, Decimal.new("1.125"))
    assert Decimal.equal?(last.snapshot_value, Decimal.new("900"))

    # The basis is self-describing (FR-13 / UX-DR11).
    assert comparison.basis.gross
    assert comparison.basis.price_return_only
    assert comparison.base_currency == "EUR"
    assert comparison.gaps.unvalued_securities == []
  end

  test "a security without any usable quote is excluded and surfaced as a gap" do
    world = setup_world()

    ghost = create_security!(name: "Unquoted", ticker: "GHST", currency: "EUR")
    WorldFixtures.buy!(world, ghost, quantity: "3", price: "10", date: ~D[2026-01-20])

    {:ok, comparison} =
      SnapshotComparison.for_snapshot(world.snapshot.id, world.portfolio.id,
        today: ~D[2026-03-10]
      )

    # Totals unchanged: the unquoted security never leaks a zero into them.
    assert Decimal.equal?(comparison.as_of_value, Decimal.new("800"))
    assert Decimal.equal?(comparison.current_value, Decimal.new("900"))

    assert [gap] = comparison.gaps.unvalued_securities
    assert gap.security_name == "Unquoted"
  end

  test "a snapshot with no holdings in scope reports empty, not an error" do
    world = base_world(name: "Empty world", currency: "EUR")

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Empty", as_of: ~D[2026-02-15]})

    {:ok, comparison} =
      SnapshotComparison.for_snapshot(snapshot.id, world.portfolio.id, today: ~D[2026-03-10])

    assert Decimal.equal?(comparison.as_of_value, Decimal.new(0))
    assert comparison.snapshot_return == nil
    assert comparison.series == []
  end
end

# Regression tests from the ADR-0026 adversarial review round (2026-07-16).
defmodule Portfolixir.Portfolios.SnapshotComparisonReviewTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios.SnapshotComparison
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.WorldFixtures

  # Review finding (HIGH): a position denominated in a non-EUR base currency
  # passed the valuability gate (Fx.rate short-circuits from == to) but the
  # walk's converter had no same-currency shortcut and zeroed it silently —
  # the exact "silent zero" AR-4 forbids. Gate and walk now share one path.
  test "values a same-currency position in a non-EUR-base portfolio without FX rates" do
    world = WorldFixtures.base_world(name: "USD world", currency: "USD", cash_currency: "USD")

    sec = WorldFixtures.create_security!(name: "US Stock", ticker: "USDS", currency: "USD")
    WorldFixtures.deposit!(world, "10000", ~D[2026-01-02], currency: "USD")

    WorldFixtures.buy!(world, sec,
      quantity: "10",
      price: "100",
      date: ~D[2026-01-05],
      currency: "USD"
    )

    WorldFixtures.put_quote!(sec, ~D[2026-02-14], "110")
    WorldFixtures.put_quote!(sec, ~D[2026-03-10], "120")

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "USD marker", as_of: ~D[2026-02-15]})

    {:ok, comparison} =
      SnapshotComparison.for_snapshot(snapshot.id, world.portfolio.id, today: ~D[2026-03-10])

    assert comparison.base_currency == "USD"
    assert Decimal.equal?(comparison.as_of_value, Decimal.new("1100"))
    assert Decimal.equal?(comparison.current_value, Decimal.new("1200"))
    assert comparison.gaps.unvalued_securities == []
  end
end
