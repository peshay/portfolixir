defmodule Portfolixir.Portfolios.SnapshotComparisonNonPositiveCloseTest do
  # #1473, ADR-0051's amendment of 2026-11-21, item 1: "One rule for every
  # price read in the app". The snapshot comparison values the frozen
  # holdings "exactly [by] the pricing semantics of the daily performance
  # walk", so a stored close of 0 or below is no price there either. Every
  # expected figure was recomputed in Python's `decimal` with
  # `getcontext().prec = 34`:
  #
  #   as-of value   2 * 12      = 24
  #   current value 2 * 15      = 30
  #   return        30 / 24 - 1 = 0.25
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Portfolios.SnapshotComparison
  alias Portfolixir.Portfolios.Snapshots

  @as_of ~D[2026-02-15]
  @today ~D[2026-03-10]

  defp legacy_close!(security, date, close) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {1, _rows} =
      Repo.insert_all(SecurityQuote, [
        %{
          security_id: security.id,
          date: date,
          close: Decimal.new(close),
          source: "manual",
          inserted_at: now,
          updated_at: now
        }
      ])

    :ok
  end

  defp world!(name, quotes) do
    world = base_world(name: name, cash_name: "#{name} Cash", depot_name: "#{name} Depot")
    fund = create_security!(name: "#{name} Fund", ticker: nil)
    deposit!(world, "100", ~D[2026-01-02])
    buy!(world, fund, quantity: "2", price: "10", date: ~D[2026-01-05])
    put_quotes!(fund, quotes)

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "#{name} snapshot", as_of: @as_of})

    {world, fund, snapshot}
  end

  defp compare!(world, snapshot) do
    {:ok, comparison} =
      SnapshotComparison.for_snapshot(snapshot.id, world.portfolio.id, today: @today)

    comparison
  end

  # User story (#1473):
  # As the operator asking whether I would have done better keeping what I
  # had,
  # I want a stored close of 0 or below read as no price on the snapshot
  # side, as the walk reads it,
  # so that a feed's placeholder never reads as a total loss of the frozen
  # holdings.
  #
  # Acceptance criteria:
  # - A legacy 0 between two positive closes after the as-of date, a
  #   negative one, and a 0 on the as-of date itself leave the comparison
  #   exactly as the same series without those rows: the close before each
  #   carries (as-of value 24, current 30, return 0.25).
  test "a close of 0 or below is no price on the snapshot side" do
    {world, fund, snapshot} =
      world!("Snap", [{~D[2026-01-05], "10"}, {~D[2026-02-14], "12"}, {@today, "15"}])

    before = compare!(world, snapshot)
    assert Decimal.equal?(before.as_of_value, Decimal.new("24"))
    assert Decimal.equal?(before.current_value, Decimal.new("30"))
    assert Decimal.equal?(before.snapshot_return, Decimal.new("0.25"))

    legacy_close!(fund, @as_of, "0")
    legacy_close!(fund, ~D[2026-02-20], "0")
    legacy_close!(fund, ~D[2026-03-01], "-1")

    assert compare!(world, snapshot) == before
  end

  # Acceptance criteria:
  # - A position whose only close on or before the as-of date is 0 has no
  #   usable close there: it is a gap (no_quote_at_as_of), never valued at
  #   0 inside the totals.
  test "a position whose only close by the as-of date is 0 is a gap" do
    {world, fund, snapshot} = world!("Gap", [{@today, "15"}])
    legacy_close!(fund, ~D[2026-02-10], "0")

    comparison = compare!(world, snapshot)
    fund_id = fund.id

    assert [%{security_id: ^fund_id, reason: :no_quote_at_as_of}] =
             comparison.gaps.unvalued_securities
  end

  # User story (AGENTS.md, "Every metric … must state its computation basis",
  # the treatment of gaps, review-blocking; Sprint 31 closing act, A3):
  # As the agent checking the comparison,
  # I want its basis to say how a day without a price is treated, a stored
  # close of 0 or below among them,
  # so that I can tell why such a day carries the close before it and why a
  # position is a gap.
  #
  # Acceptance criteria:
  # - basis.gaps says prices carry the most recent close forward, that a
  #   stored close of 0 or below is not a price, and that a position with no
  #   usable close or rate path at the as-of date is excluded and listed in
  #   gaps.unvalued_securities, never valued at 0.
  test "the basis states the treatment of gaps, a close of 0 or below among them" do
    {world, _fund, snapshot} = world!("Basis", [{~D[2026-02-14], "12"}, {@today, "15"}])
    gaps = compare!(world, snapshot).basis.gaps

    assert gaps =~ "(a stored close of 0 or below is not a price)"
    assert gaps =~ "carried forward"
    assert gaps =~ "gaps.unvalued_securities"
    assert gaps =~ "never valued at 0"
  end
end
