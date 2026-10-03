defmodule Portfolixir.Portfolios.RealizedGainsNewestTest do
  # #1030 (Sprint 18 F7): the Overview card's read of the newest closed
  # trades — the realized report's own projection, computed without the rest
  # of the report.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.RealizedGains

  # Closed trades whose order the read must keep exactly as the report has
  # it: a close-date tie across two securities, two sells of one security on
  # one day, a sell consuming two lots, a pound sale with no stored rate
  # (excluded and named), a sale of delivered-in shares (no trade) and
  # trades older than the cut.
  defp seed! do
    world = base_world(name: "Newest World", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "100000", ~D[2023-01-02])

    gbp =
      Map.merge(
        world,
        add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Konto",
          depot_name: "GBP Depot"
        )
      )

    old = create_security!(name: "Oldmoor Paper", ticker: nil)
    buy!(world, old, quantity: "3", price: "100", date: ~D[2023-02-01])
    sell!(world, old, quantity: "3", price: "110", date: ~D[2023-03-01])

    long = create_security!(name: "Longacre Rail", ticker: nil)
    buy!(world, long, quantity: "10", price: "100", date: ~D[2024-01-02])
    sell!(world, long, quantity: "10", price: "144", date: ~D[2026-01-01])

    tie_a = create_security!(name: "Tie Alpha", ticker: nil)
    buy!(world, tie_a, quantity: "5", price: "100", date: ~D[2024-03-01])
    buy!(world, tie_a, quantity: "5", price: "110", date: ~D[2024-09-02])
    sell!(world, tie_a, quantity: "10", price: "120", date: ~D[2026-03-10])

    tie_b = create_security!(name: "Tie Bravo", ticker: nil)
    buy!(world, tie_b, quantity: "4", price: "50", date: ~D[2026-02-02])
    sell!(world, tie_b, quantity: "4", price: "45", date: ~D[2026-03-10])

    twice = create_security!(name: "Twice Sold Co", ticker: nil)
    buy!(world, twice, quantity: "10", price: "10", date: ~D[2025-01-06])
    sell!(world, twice, quantity: "4", price: "12", date: ~D[2026-04-01])
    sell!(world, twice, quantity: "6", price: "9", date: ~D[2026-04-01])

    pound = create_security!(name: "Unrated Pound plc", ticker: nil, currency: "GBP")
    buy!(gbp, pound, quantity: "2", price: "10", date: ~D[2026-01-09], currency: "GBP")
    sell!(gbp, pound, quantity: "2", price: "30", date: ~D[2026-04-20], currency: "GBP")

    delivered = create_security!(name: "Delivered Only AG", ticker: nil)

    {:ok, _delivery} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: delivered.id,
        type: "inbound_delivery",
        date: ~D[2026-01-10],
        quantity: "5",
        currency_code: "EUR"
      })

    sell!(world, delivered, quantity: "5", price: "20", date: ~D[2026-05-01])

    world
  end

  # One more security sold at a gain, held a year and a half.
  defp sold_security!(world, n) do
    security = create_security!(name: "Extra Holdings #{n}", ticker: nil)
    buy!(world, security, quantity: "10", price: "100", date: ~D[2024-06-03])
    sell!(world, security, quantity: "10", price: "105", date: ~D[2025-12-01])
  end

  # The repository queries `fun` runs, its own and those of the processes it
  # starts (an Ecto preload of several associations runs in tasks).
  defp queries(fun) do
    handler = "newest-trades-queries-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, _metadata, _config ->
          if self() == test_pid or test_pid in Process.get(:"$callers", []),
            do: send(test_pid, :query)
        end,
        nil
      )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    drain(0)
  end

  defp drain(count) do
    receive do
      :query -> drain(count + 1)
    after
      0 -> count
    end
  end

  # User story (#1030):
  # As a local portfolio maintainer landing on the Overview,
  # I want the closed-trades card read to be the realized report's newest
  # rows, computed without the rest of the report,
  # so that the card is cheaper and never a different card.
  #
  # Acceptance criteria:
  # - The newest `limit` converted trades, in the report's order (ties
  #   included), with the same fields and figures, the annualized return
  #   among them.
  # - The same exclusions: count and named securities, over every trade.
  # - The same base currency.
  test "the newest trades are the report's own, cut to the limit" do
    seed!()
    report = RealizedGains.report()

    for limit <- [1, 3, 5, 50] do
      assert RealizedGains.newest_trades(limit) == %{
               base_currency: report.base_currency,
               trades: Enum.take(report.trades, limit),
               excluded: report.excluded
             }
    end

    newest = RealizedGains.newest_trades(5)

    assert Enum.map(newest.trades, &{&1.security_name, &1.close_date}) == [
             {"Twice Sold Co", ~D[2026-04-01]},
             {"Twice Sold Co", ~D[2026-04-01]},
             {"Tie Bravo", ~D[2026-03-10]},
             {"Tie Alpha", ~D[2026-03-10]},
             {"Longacre Rail", ~D[2026-01-01]}
           ]

    assert newest.excluded == %{count: 1, securities: ["Unrated Pound plc"]}
    assert Enum.all?(newest.trades, &Map.has_key?(&1, :annualized_return))
  end

  test "with no sell the newest trades are empty" do
    base_world(name: "Quiet World", cash_name: "Girokonto", depot_name: "Depot 1")

    assert RealizedGains.newest_trades(5) == %{
             base_currency: "EUR",
             trades: [],
             excluded: %{count: 0, securities: []}
           }
  end

  # Acceptance criteria (the cost, #1030):
  # - The read's query count does not grow with the number of sold
  #   securities: the transactions are read once, not per security, and no
  #   latest close or open-lot rate is looked up. (The whole report's count
  #   does grow — about eight queries per sold security in the issue's probe.)
  test "the read's queries do not grow with the sold securities" do
    world = seed!()

    before_newest = queries(fn -> RealizedGains.newest_trades(5) end)
    before_report = queries(fn -> RealizedGains.report() end)

    for n <- 1..6, do: sold_security!(world, n)

    after_newest = queries(fn -> RealizedGains.newest_trades(5) end)
    after_report = queries(fn -> RealizedGains.report() end)

    assert after_newest == before_newest
    assert after_report > before_report
    assert after_newest < after_report
  end
end
