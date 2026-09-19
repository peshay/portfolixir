defmodule Portfolixir.Portfolios.RealizedTradesTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3]

  alias Portfolixir.Portfolios.RealizedGains

  # User story (#807; review C10 and Part 5 Q2, signed by D-3 of the Sprint 13
  # plan; the 2026-08-15 triage's A3 — the Portfolio Performance "Trades"
  # comparison named concretely):
  # As a local portfolio maintainer,
  # I want the Realized gains facet to list the closed round-trips it
  # aggregates — per position, buy → sell, holding period, result —
  # so that the facet shows the trades its name promises instead of one
  # number in a matrix.
  #
  # Acceptance criteria:
  # - The report carries the matcher's closed trades across all portfolios on
  #   the facet's FX basis, newest close first, each naming its security.
  # - It carries the three summary figures: the realised total, the hit rate
  #   and the average holding period.
  # - A sale with no stored close-date rate is excluded from BOTH — the
  #   figures and the list — the same way it is excluded from the matrix,
  #   and stays named in `excluded`.
  test "the report lists the closed trades and the three figures on the facet's FX basis" do
    world = base_world(name: "Trades World", cash_name: "TW Cash", depot_name: "TW Depot")
    winner = create_security!(name: "Winner Co", ticker: "WIN")
    loser = create_security!(name: "Loser Co", ticker: "LOS")

    deposit!(world, "100000", ~D[2026-01-01])

    buy!(world, winner, quantity: "10", price: "100", date: ~D[2026-01-05])
    sell!(world, winner, quantity: "10", price: "150", date: ~D[2026-03-06])

    buy!(world, loser, quantity: "10", price: "100", date: ~D[2026-02-01])
    sell!(world, loser, quantity: "10", price: "80", date: ~D[2026-02-11])

    report = RealizedGains.report()

    assert [first, second] = report.trades
    # Newest close first.
    assert first.close_date == ~D[2026-03-06]
    assert first.security_name == "Winner Co"
    assert first.security_id == winner.id
    assert first.open_date == ~D[2026-01-05]
    assert first.holding_period_days == 60
    assert Decimal.equal?(first.quantity, Decimal.new("10"))
    assert Decimal.equal?(first.basis, Decimal.new("1000"))
    assert Decimal.equal?(first.proceeds, Decimal.new("1500"))
    assert Decimal.equal?(first.realized_base, Decimal.new("500"))
    assert Decimal.equal?(first.realized_pnl_pct, Decimal.new("0.5"))

    assert second.security_name == "Loser Co"
    assert Decimal.equal?(second.realized_base, Decimal.new("-200"))

    # Realised total, hit rate, average holding period.
    assert Decimal.equal?(report.summary.realized_total, Decimal.new("300"))
    assert Decimal.equal?(report.summary.hit_rate, Decimal.new("0.5"))
    assert report.summary.trade_count == 2
    assert report.summary.average_holding_period_days == 35

    # The basis is in the payload, not only on a page (AGENTS.md metric rule).
    assert report.computation_basis.summary =~ "hit rate"
    assert report.computation_basis.summary =~ "excluded"
  end

  # Acceptance criteria (#724's D-1, carried to the new figures):
  # - With no closed trades at all the figures are an honest empty state: a
  #   zero total, and NO hit rate or holding period, because the average of
  #   nothing is not zero.
  test "with no closed trades the derived figures refuse rather than answer zero" do
    _world = base_world(name: "Empty World", cash_name: "EW Cash", depot_name: "EW Depot")

    report = RealizedGains.report()

    assert report.trades == []
    assert report.summary.trade_count == 0
    assert Decimal.equal?(report.summary.realized_total, Decimal.new("0"))
    assert report.summary.hit_rate == nil
    assert report.summary.average_holding_period_days == nil
  end
end
