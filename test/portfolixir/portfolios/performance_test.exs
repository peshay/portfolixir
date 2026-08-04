defmodule Portfolixir.Portfolios.PerformanceTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.WorldFixtures

  # User story:
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want the portfolio's true time-weighted return (TTWROR) like Portfolio
  # Performance computes it,
  # so that I can judge my investments' performance independently of when I
  # deposited or withdrew money.
  #
  # Acceptance criteria:
  # - Daily returns chain geometrically; deposits/removals are neutralised.
  # - A balance snapshot's jump is an external flow, not return.
  # - Dividends count as return.
  # - Periods (ytd/1y/3y/5y/max) chain only the days inside the period,
  #   starting from the value just before the period.
  # - A security without quotes is priced at the latest own trade price until
  #   a quote exists, so imported portfolios are not valued at zero.
  # - Bookings with implausible dates (before 1970, e.g. a 0217 import typo)
  #   are applied on the first plausible day instead of walking centuries,
  #   and are reported as suspect_dates.
  # - A day with a zero-or-negative return base contributes no return.
  # - analysis/2 + summarise/2 equals for_portfolio/2, so the UI can cache
  #   the daily walk and switch periods without recomputing.

  defp setup_world do
    world = base_world(name: "P", cash_name: "Cash", depot_name: "Depot")
    security = create_security!(name: "Index Fund", ticker: "IDX", asset_class: "etf")
    Map.put(world, :security, security)
  end

  defp buy!(world, qty, price, date) do
    WorldFixtures.buy!(world, world.security, quantity: qty, price: price, date: date)
  end

  defp quote!(world, close, date) do
    WorldFixtures.put_quote!(world.security, date, close)
  end

  defp rounded(decimal, places), do: Decimal.round(decimal, places)

  # User story:
  # As a local portfolio maintainer,
  # I want the performance of a chosen view (a slice of my holdings), while the
  # default stays my whole-portfolio TTWROR, so that I can judge a slice on its
  # own — with money crossing the view's edge treated as a deposit/withdrawal to
  # the slice (ADR-0019, #444).
  test "scopes the TTWROR to a view and treats boundary transfers as flows" do
    world = setup_world()
    other = create_security!(name: "Other ETF", ticker: "OTH", asset_class: "etf")

    deposit!(world, "2000", ~D[2026-01-01])
    WorldFixtures.buy!(world, world.security, quantity: "10", price: "100", date: ~D[2026-01-01])
    WorldFixtures.buy!(world, other, quantity: "10", price: "100", date: ~D[2026-01-01])
    quote!(world, "100", ~D[2026-01-01])
    quote!(world, "120", ~D[2026-01-10])
    WorldFixtures.put_quote!(other, ~D[2026-01-01], "100")
    WorldFixtures.put_quote!(other, ~D[2026-01-10], "100")

    {:ok, excl} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Excl"})
    {:ok, no_other} = Buckets.create_view(Actor.owner_ui(), %{name: "NoOther", include_all: true})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), no_other, [], [excl.id])
    :ok = Buckets.set_position_override(Actor.owner_ui(), world.depot, other, [excl.id])
    {:ok, everything} = Buckets.create_view(Actor.owner_ui(), %{name: "All", include_all: true})

    {:ok, unscoped} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10])

    {:ok, permissive} =
      Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10], view: everything.id)

    {:ok, scoped} =
      Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10], view: no_other.id)

    # An include-everything view is byte-for-byte identical to no view.
    assert permissive == unscoped

    # Whole portfolio: both bought at 100 (value 2000), day 10 -> 1200 + 1000 = 2200 (+10%).
    assert rounded(unscoped.ttwror, 6) |> Decimal.equal?(Decimal.new("0.1"))
    assert Decimal.equal?(unscoped.net_external_flows, Decimal.new("2000"))

    # View = only the index fund: +20% on its own. Buying "Other" with in-view cash
    # is a 1000 outflow at the boundary, so the deposit nets to 1000 for the slice.
    assert rounded(scoped.ttwror, 6) |> Decimal.equal?(Decimal.new("0.2"))
    assert Decimal.equal?(scoped.net_external_flows, Decimal.new("1000"))
    assert Decimal.equal?(scoped.end_value, Decimal.new("1200"))
  end

  # A delivery into an in-view position, and a buy of an in-view security funded
  # from out-of-view cash, are both boundary inflows to the view (ADR-0019).
  test "scoped flow: delivery and a buy funded from out-of-view cash are inflows" do
    world = setup_world()
    {:ok, mine} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Mine"})
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "MineA", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [mine.id], [])
    # Security is in view; cash is untagged, so it is out of an include-set view.
    :ok = Buckets.set_position_override(Actor.owner_ui(), world.depot, world.security, [mine.id])

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: world.security.id,
        type: "inbound_delivery",
        date: ~D[2026-01-01],
        quantity: "5",
        currency_code: "EUR"
      })

    WorldFixtures.buy!(world, world.security, quantity: "5", price: "100", date: ~D[2026-01-01])
    quote!(world, "100", ~D[2026-01-01])
    quote!(world, "110", ~D[2026-01-10])

    {:ok, scoped} =
      Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10], view: view.id)

    # Day 1: delivery 5@100 (500) + buy 5@100 from out-of-view cash (500) = 1000 in,
    # value 1000. Day 10: 10 @ 110 = 1100 -> +10%.
    assert rounded(scoped.ttwror, 6) |> Decimal.equal?(Decimal.new("0.1"))
    assert Decimal.equal?(scoped.net_external_flows, Decimal.new("1000"))
    assert Decimal.equal?(scoped.end_value, Decimal.new("1100"))
  end

  # A security transfer from an out-of-view depot into an in-view depot is a
  # cashless boundary inflow, valued at market (ADR-0019).
  test "scoped flow: a security transfer into the view is a market-valued inflow" do
    world = setup_world()
    extra = WorldFixtures.add_depot(world.portfolio, depot_name: "Depot B", cash_name: "Cash B")

    {:ok, mine} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Mine"})
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "MineB", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [mine.id], [])
    # Only the main-depot position is in view; the Depot-B position is untagged.
    :ok = Buckets.set_position_override(Actor.owner_ui(), world.depot, world.security, [mine.id])

    # Stock Depot B (out of view), then transfer into the main depot (in view).
    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: extra.depot.id,
        security_id: world.security.id,
        type: "inbound_delivery",
        date: ~D[2026-01-01],
        quantity: "5",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: extra.depot.id,
        counter_securities_account_id: world.depot.id,
        security_id: world.security.id,
        type: "security_transfer",
        date: ~D[2026-01-01],
        quantity: "5",
        gross_amount: "500",
        currency_code: "EUR"
      })

    quote!(world, "100", ~D[2026-01-01])
    quote!(world, "120", ~D[2026-01-10])

    {:ok, scoped} =
      Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10], view: view.id)

    # The view sees only the main-depot position: 5 units arrive (500 inflow at market),
    # day 10 at 120 -> 600 (+20%).
    assert rounded(scoped.ttwror, 6) |> Decimal.equal?(Decimal.new("0.2"))
    assert Decimal.equal?(scoped.net_external_flows, Decimal.new("500"))
    assert Decimal.equal?(scoped.end_value, Decimal.new("600"))
  end

  test "chains daily returns and neutralises deposits" do
    world = setup_world()

    # Day 1: 1000 in, all invested at 100. Day 10: quote 120 (+20%).
    # Day 11: 600 more in, invested at 120 (no gain that day).
    # Day 20: quote 130 (+8.33% on the 1800 invested).
    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, "10", "100", ~D[2026-01-01])
    quote!(world, "100", ~D[2026-01-01])
    quote!(world, "120", ~D[2026-01-10])
    deposit!(world, "600", ~D[2026-01-11])
    buy!(world, "5", "120", ~D[2026-01-11])
    quote!(world, "130", ~D[2026-01-20])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-20])

    # 1.2 * (130/120) - 1 = 0.3 — money-weighting would differ.
    assert rounded(result.ttwror, 6) |> Decimal.equal?(Decimal.new("0.3"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("1600"))
    assert Decimal.equal?(result.start_value, Decimal.new("0"))
    assert Decimal.equal?(result.end_value, Decimal.new("1950"))
    assert length(result.series) == 20

    last = List.last(result.series)
    assert Decimal.equal?(last.cumulative_ttwror, result.ttwror)

    # The money-weighted return (IRR) is solved from the same dated flows and
    # terminal value; with two contributions and a gain it is a positive rate.
    assert %Decimal{} = result.irr
    assert Decimal.compare(result.irr, Decimal.new("0")) == :gt
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a money-weighted return (IRR) next to the TTWROR,
  # so that I can also judge the timing of my own deposits and withdrawals.
  #
  # Acceptance criteria:
  # - A single deposit invested for a full year that ends 10% higher yields an
  #   IRR of 10%, computed from the same series and external flows.
  # - A portfolio with no flows to weight has no IRR (nil), never a crash.
  test "computes a money-weighted IRR over a full-year holding" do
    world = setup_world()

    start = ~D[2025-06-13]
    today = ~D[2026-06-13]

    deposit!(world, "1000", start)
    buy!(world, "10", "100", start)
    quote!(world, "100", start)
    quote!(world, "110", today)

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: today)

    assert Decimal.equal?(result.end_value, Decimal.new("1100"))
    assert rounded(result.irr, 6) |> Decimal.equal?(Decimal.new("0.1"))
  end

  test "has no IRR for an empty portfolio" do
    world = setup_world()

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-20])

    assert result.series == []
    assert result.irr == nil
  end

  test "a balance snapshot's jump is an external flow, not return" do
    world = setup_world()

    deposit!(world, "1000", ~D[2026-01-01])

    {:ok, _} =
      Ledger.set_cash_balance(
        Portfolixir.Actor.owner_ui(),
        Portfolios.get_cash_account(world.cash.id),
        %{
          "date" => "2026-01-05",
          "amount" => "1500"
        }
      )

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10])

    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
    assert Decimal.equal?(result.end_value, Decimal.new("1500"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("1500"))
  end

  test "dividends count as return" do
    world = setup_world()

    deposit!(world, "1000", ~D[2026-01-01])

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: world.security.id,
        type: "dividend",
        date: ~D[2026-01-05],
        gross_amount: "50",
        currency_code: "EUR"
      })

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10])

    assert Decimal.equal?(result.ttwror, Decimal.new("0.05"))
  end

  test "a period chains only its own days, from the value just before it" do
    world = setup_world()

    # 2025: +10% (100 -> 110). 2026 so far: +10% (110 -> 121).
    deposit!(world, "1000", ~D[2025-12-01])
    buy!(world, "10", "100", ~D[2025-12-01])
    quote!(world, "100", ~D[2025-12-01])
    quote!(world, "110", ~D[2025-12-31])
    quote!(world, "121", ~D[2026-01-20])

    {:ok, ytd} =
      Performance.for_portfolio(world.portfolio.id, period: "ytd", today: ~D[2026-01-20])

    {:ok, max} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-20])

    assert ytd.start_date == ~D[2026-01-01]
    assert Decimal.equal?(ytd.start_value, Decimal.new("1100"))
    assert rounded(ytd.ttwror, 6) |> Decimal.equal?(Decimal.new("0.1"))
    assert rounded(max.ttwror, 6) |> Decimal.equal?(Decimal.new("0.21"))
  end

  test "rejects an unknown period" do
    world = setup_world()

    assert {:error, :invalid_period} =
             Performance.for_portfolio(world.portfolio.id, period: "2w")
  end

  test "prices an unquoted security at the latest own trade price" do
    world = setup_world()

    # No quote exists: the buy itself is the price observation, so the
    # position is worth its cost and the chain shows no phantom loss.
    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, "10", "100", ~D[2026-01-01])

    {:ok, flat} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-05])

    assert Decimal.equal?(flat.end_value, Decimal.new("1000"))
    assert Decimal.equal?(flat.ttwror, Decimal.new("0"))

    # Once a quote appears it wins over the stale trade price.
    quote!(world, "120", ~D[2026-01-10])

    {:ok, quoted} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10])

    assert Decimal.equal?(quoted.end_value, Decimal.new("1200"))

    # The valuation jumps to 1,200 — but the 100 it jumped from was never a
    # market price, only the portfolio's own buy. The first quote ever for a
    # trade-priced position is therefore a basis step, not a one-day +20 %
    # (issue #545, ADR-0010 amendment rule 2). Before that rule this read
    # 0.2, and on a real forward-only quote load — the normal shape, where
    # the feed only covers recent dates — the same mechanism discharged years
    # of accumulated drift as a four-digit percentage in one day.
    assert Decimal.equal?(quoted.ttwror, Decimal.new("0"))
  end

  test "applies implausibly dated bookings on the first plausible day" do
    world = setup_world()

    # A PP export typo: year 0217 instead of 2017. Walking from year 0217
    # would mean ~660,000 daily steps — the walk must start at the first
    # plausible booking instead, with the ancient cash effect preserved.
    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "removal",
        date: ~D[0217-12-05],
        gross_amount: "300",
        currency_code: "EUR"
      })

    deposit!(world, "1000", ~D[2026-01-01])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-10])

    assert result.start_date == ~D[2026-01-01]
    assert length(result.series) == 10
    assert result.suspect_dates == [~D[0217-12-05]]
    # Both flows land on the first day: 1000 in, 300 out, no return.
    assert Decimal.equal?(result.end_value, Decimal.new("700"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("700"))
    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
  end

  test "a day with a zero-or-negative return base contributes no return" do
    world = setup_world()

    deposit!(world, "100", ~D[2026-01-01])

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "removal",
        date: ~D[2026-01-02],
        gross_amount: "200",
        currency_code: "EUR"
      })

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-05])

    # Overdrawn data (value -100) must not explode the chain.
    assert Decimal.equal?(result.end_value, Decimal.new("-100"))
    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
  end

  # User story (#563):
  # As a local portfolio maintainer,
  # I want to chain the performance over a previous year (any single year with
  # data) or a custom from/to date range,
  # so that I can answer "how was 2025?" without reading it off the max chart.
  #
  # Acceptance criteria:
  # - `{:year, y}` chains exactly that calendar year, starting from the value
  #   just before Jan 1 and ending Dec 31 (clamped to today for the current
  #   year, and to the available history when the year starts earlier).
  # - `{:range, from, to}` chains exactly the days from..to (same clamping).
  # - A range with from > to is rejected as `{:error, :invalid_period}`.
  # - Both stay pure re-chains of the cached analysis — no new daily walk.
  test "chains a single calendar year from the value just before it" do
    world = setup_world()

    # 2024: 1000 in at 100. 2024-12-31: 110. 2025-12-31: 121 (+10% in 2025).
    # 2026-01-20: 133.1 (+10% in 2026 so far).
    deposit!(world, "1000", ~D[2024-06-01])
    buy!(world, "10", "100", ~D[2024-06-01])
    quote!(world, "100", ~D[2024-06-01])
    quote!(world, "110", ~D[2024-12-31])
    quote!(world, "121", ~D[2025-12-31])
    quote!(world, "133.1", ~D[2026-01-20])

    analysis = Performance.analysis(world.portfolio.id, today: ~D[2026-01-20])

    {:ok, year_2025} = Performance.summarise(analysis, {:year, 2025})

    assert year_2025.start_date == ~D[2025-01-01]
    assert year_2025.end_date == ~D[2025-12-31]
    assert Decimal.equal?(year_2025.start_value, Decimal.new("1100"))
    assert Decimal.equal?(year_2025.end_value, Decimal.new("1210"))
    assert rounded(year_2025.ttwror, 6) |> Decimal.equal?(Decimal.new("0.1"))
    assert length(year_2025.series) == 365

    # The current year clamps to today and equals ytd.
    {:ok, year_2026} = Performance.summarise(analysis, {:year, 2026})
    {:ok, ytd} = Performance.summarise(analysis, "ytd")

    assert year_2026.end_date == ~D[2026-01-20]
    assert Decimal.equal?(year_2026.ttwror, ytd.ttwror)
    assert Decimal.equal?(year_2026.end_value, ytd.end_value)

    # A year fully before the history clamps to nothing, honestly: no days,
    # no return, never an invented number.
    {:ok, year_2023} = Performance.summarise(analysis, {:year, 2023})

    assert year_2023.series == []
    assert Decimal.equal?(year_2023.ttwror, Decimal.new("0"))

    # for_portfolio accepts the same period term (same validate + re-chain).
    {:ok, direct} =
      Performance.for_portfolio(world.portfolio.id, period: {:year, 2025}, today: ~D[2026-01-20])

    assert direct == year_2025
  end

  # Fix round (#563 review): a bounded period whose window contains no walked
  # day must be the same honest emptiness as "nothing to walk yet" — never a
  # window with inverted dates carrying the portfolio's current value as both
  # start and end.
  test "a bounded period outside the walked history is empty, not invented" do
    world = setup_world()

    deposit!(world, "1000", ~D[2024-06-01])
    buy!(world, "10", "100", ~D[2024-06-01])
    quote!(world, "100", ~D[2024-06-01])
    quote!(world, "121", ~D[2025-12-31])

    analysis = Performance.analysis(world.portfolio.id, today: ~D[2026-01-20])

    for period <- [
          {:year, 2027},
          {:year, 2023},
          {:range, ~D[2026-06-01], ~D[2026-09-01]},
          {:range, ~D[2023-01-01], ~D[2023-12-31]}
        ] do
      {:ok, result} = Performance.summarise(analysis, period)

      assert result.series == []
      assert is_nil(result.start_date)
      assert Decimal.equal?(result.start_value, Decimal.new("0"))
      assert Decimal.equal?(result.end_value, Decimal.new("0"))
      assert Decimal.equal?(result.ttwror, Decimal.new("0"))
      assert is_nil(result.irr)
    end
  end

  test "chains a custom from/to range and rejects a backwards one" do
    world = setup_world()

    deposit!(world, "1000", ~D[2024-06-01])
    buy!(world, "10", "100", ~D[2024-06-01])
    quote!(world, "100", ~D[2024-06-01])
    quote!(world, "110", ~D[2024-12-31])
    quote!(world, "121", ~D[2025-12-31])

    analysis = Performance.analysis(world.portfolio.id, today: ~D[2026-01-20])

    # A range spelling out 2025 equals the year period.
    {:ok, range} = Performance.summarise(analysis, {:range, ~D[2025-01-01], ~D[2025-12-31]})
    {:ok, year} = Performance.summarise(analysis, {:year, 2025})

    assert Decimal.equal?(range.ttwror, year.ttwror)
    assert Decimal.equal?(range.start_value, year.start_value)
    assert Decimal.equal?(range.end_value, year.end_value)
    assert range.start_date == year.start_date
    assert range.end_date == year.end_date

    # An end date in the future clamps to today; a start before the history
    # clamps to the first walked day.
    {:ok, clamped} = Performance.summarise(analysis, {:range, ~D[2020-01-01], ~D[2030-01-01]})
    {:ok, max} = Performance.summarise(analysis, "max")

    assert clamped.start_date == ~D[2024-06-01]
    assert clamped.end_date == ~D[2026-01-20]
    assert Decimal.equal?(clamped.ttwror, max.ttwror)

    # from > to is invalid, never a silent empty chain.
    assert {:error, :invalid_period} =
             Performance.summarise(analysis, {:range, ~D[2025-06-01], ~D[2025-01-01]})

    assert {:error, :invalid_period} =
             Performance.for_portfolio(world.portfolio.id,
               period: {:range, ~D[2025-06-01], ~D[2025-01-01]},
               today: ~D[2026-01-20]
             )
  end

  test "analysis plus summarise equals for_portfolio for every period" do
    world = setup_world()

    deposit!(world, "1000", ~D[2025-12-01])
    buy!(world, "10", "100", ~D[2025-12-01])
    quote!(world, "100", ~D[2025-12-01])
    quote!(world, "110", ~D[2025-12-31])
    quote!(world, "121", ~D[2026-01-20])

    analysis = Performance.analysis(world.portfolio.id, today: ~D[2026-01-20])

    for period <- Performance.periods() do
      {:ok, from_analysis} = Performance.summarise(analysis, period)

      {:ok, direct} =
        Performance.for_portfolio(world.portfolio.id, period: period, today: ~D[2026-01-20])

      assert from_analysis == direct
    end

    assert {:error, :invalid_period} = Performance.summarise(analysis, "2w")
  end
end
