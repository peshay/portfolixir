defmodule Portfolixir.Portfolios.ValuationStaleQuoteTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Portfolios.Valuation

  # User story (#779 and #610, Sprint 11 Lane X step 3 — D-3 (c)):
  # As a local portfolio maintainer whose delisted holding still shows its
  # last close as if it were today's,
  # I want the valuation to say when each position's price is from and to
  # count the held positions whose quote is older than the staleness
  # threshold,
  # so that I learn which holdings to mark retired — the flag the walk's
  # rule keys on — instead of reading a stale price as a live one.
  #
  # Acceptance criteria:
  # - Every position carries price_date: the quote's date for a quoted
  #   position, the trade's date for a trade-priced one.
  # - stale_priced_count counts quoted positions whose quote is older than
  #   DataQuality.stale_days() before today; a trade-priced position is not
  #   counted twice (it is in trade_priced_count).
  # - The by-security rows carry price_date too.
  test "positions carry the date of their price and the stale-quoted ones are counted" do
    world = base_world(name: "SQ", cash_name: "SQ Cash", depot_name: "SQ Depot")
    fresh = create_security!(name: "Fresh Co", ticker: "FRS")
    stale = create_security!(name: "Stale Co", ticker: "STA")
    unquoted = create_security!(name: "Trade Priced Co", ticker: "TRP")

    today = Date.utc_today()
    trade_day = Date.add(today, -50)
    stale_day = Date.add(today, -(DataQuality.stale_days() + 1))

    deposit!(world, "10000", Date.add(today, -100))
    buy!(world, fresh, quantity: "1", price: "10", date: trade_day)
    buy!(world, stale, quantity: "1", price: "10", date: trade_day)
    buy!(world, unquoted, quantity: "1", price: "10", date: trade_day)
    put_quote!(fresh, today, "11")
    put_quote!(stale, stale_day, "9")

    valuation = Valuation.for_portfolio(world.portfolio.id)
    by_id = Map.new(valuation.positions, &{&1.security_id, &1})

    assert by_id[fresh.id].price_source == :quote
    assert by_id[fresh.id].price_date == today
    assert by_id[stale.id].price_date == stale_day
    assert by_id[unquoted.id].price_source == :trade
    assert by_id[unquoted.id].price_date == trade_day

    assert valuation.stale_priced_count == 1
    assert valuation.trade_priced_count == 1

    rows = Valuation.holdings_by_security()
    assert rows[stale.id].price_date == stale_day
    assert rows[unquoted.id].price_date == trade_day
  end

  test "a quote exactly at the threshold is not stale" do
    world = base_world(name: "SQT", cash_name: "SQT Cash", depot_name: "SQT Depot")
    edge = create_security!(name: "Edge Co", ticker: "EDG")
    today = Date.utc_today()

    deposit!(world, "1000", Date.add(today, -100))
    buy!(world, edge, quantity: "1", price: "10", date: Date.add(today, -50))
    put_quote!(edge, Date.add(today, -DataQuality.stale_days()), "9")

    assert Valuation.for_portfolio(world.portfolio.id).stale_priced_count == 0
  end
end
