defmodule Portfolixir.Portfolios.ValuationNonPositiveCloseTest do
  # #1473, ADR-0051's amendment of 2026-11-21, item 1: "One rule for every
  # price read in the app." The live valuation reads the latest close; a
  # stored close of 0 or below is no price there either, so the last
  # positive close counts, and with none the valuation takes its existing
  # no-quote path. Figures (Python's decimal, getcontext().prec = 34): one
  # unit at the carried close, 1 * 10 = 10.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures

  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Valuation

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

  # User story (#1473):
  # As the operator reading my holdings' value,
  # I want a stored close of 0 or below skipped by the live valuation, as
  # the performance walk skips it,
  # so that the value I read today and the value the walk reads for today
  # agree, and a feed's placeholder never reads as a total loss.
  #
  # Acceptance criteria:
  # - With 10 stored, then a legacy 0 as the latest close, the live
  #   valuation's total equals the walk's last day: 10, priced by the
  #   quote of 10 November.
  test "a legacy 0 as the latest close: the live valuation agrees with the walk" do
    world = base_world(name: "Live", cash_name: "Live Cash", depot_name: "Live Depot")
    fund = create_security!(name: "Live Fund", ticker: nil)
    deliver_untraded!(world, fund, "1", date: ~D[2026-10-01])
    put_quotes!(fund, [{~D[2026-11-10], "10"}])
    legacy_close!(fund, ~D[2026-11-11], "0")
    today = ~D[2026-11-12]

    last = List.last(Performance.analysis(world.portfolio.id, today: today).daily)
    assert last.date == today
    assert Decimal.equal?(last.value, Decimal.new(10))

    live = Valuation.for_portfolio(world.portfolio.id)
    assert Decimal.equal?(live.total_value, last.value)

    assert [%{price_source: :quote, price_date: ~D[2026-11-10]}] =
             Enum.filter(live.positions, &(&1.security_id == fund.id))
  end

  # Acceptance criteria:
  # - Every latest read serves the last positive close; a security whose
  #   only closes are 0 or below has none (nil, or absent from the map).
  # - `positive: false` serves the stored newest row, for a surface that
  #   lists stored rows as they are.
  test "the latest reads serve the last positive close, the raw row on request" do
    fund = create_security!(name: "Latest Fund", ticker: nil)
    only_zero = create_security!(name: "Zero Fund", ticker: nil)
    put_quotes!(fund, [{~D[2026-11-10], "10"}])
    legacy_close!(fund, ~D[2026-11-11], "-2")
    legacy_close!(only_zero, ~D[2026-11-11], "0")

    assert %{date: ~D[2026-11-10]} = Quotes.latest(fund.id)
    assert %{date: ~D[2026-11-10]} = Quotes.adjusted_latest(fund.id)
    assert Quotes.latest(only_zero.id) == nil
    assert Quotes.adjusted_latest(only_zero.id) == nil

    ids = [fund.id, only_zero.id]
    assert %{date: ~D[2026-11-10]} = Quotes.latest_by_security_ids(ids)[fund.id]
    refute Map.has_key?(Quotes.latest_by_security_ids(ids), only_zero.id)
    assert %{date: ~D[2026-11-10]} = Quotes.adjusted_latest_by_security_ids(ids)[fund.id]
    refute Map.has_key?(Quotes.adjusted_latest_by_security_ids(ids), only_zero.id)

    assert %{date: ~D[2026-11-11]} = Quotes.latest(fund.id, positive: false)
    assert %{date: ~D[2026-11-11]} = Quotes.latest(only_zero.id, positive: false)
  end

  # Acceptance criteria:
  # - A held position whose only close is 0 takes the valuation's no-quote
  #   path (here no trade price either: unvalued, never valued at 0).
  test "a position whose only close is 0 takes the no-quote path" do
    world = base_world(name: "NoQ", cash_name: "NoQ Cash", depot_name: "NoQ Depot")
    fund = create_security!(name: "NoQ Fund", ticker: nil)
    deliver_untraded!(world, fund, "1", date: ~D[2026-10-01])
    legacy_close!(fund, ~D[2026-11-11], "0")

    live = Valuation.for_portfolio(world.portfolio.id)
    [position] = Enum.filter(live.positions, &(&1.security_id == fund.id))
    refute position.price_source == :quote
  end
end
