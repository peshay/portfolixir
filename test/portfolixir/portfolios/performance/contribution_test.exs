defmodule Portfolixir.Portfolios.Performance.ContributionTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, create_security!: 1, deposit!: 3, deposit!: 4]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Derived.Registry
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Contribution
  alias Portfolixir.WorldFixtures

  # Every period the walk accepts (`Performance.validate_period/1`), the two
  # empty ones included: a year after today and a range before the history.
  @periods [
    "max",
    "ytd",
    "1y",
    "3y",
    "5y",
    {:year, 2025},
    {:year, 2026},
    {:year, 2027},
    {:range, ~D[2025-03-01], ~D[2026-02-28]},
    {:range, ~D[2024-01-01], ~D[2024-06-30]}
  ]

  @today ~D[2026-06-30]

  # -- the rich synthetic world -------------------------------------------------
  #
  # Invented figures only. One EUR-base portfolio with a EUR and a USD cash
  # account (each with its own depot), and a second small portfolio, so a view
  # can span two portfolios. EUR/USD moves 1.25 -> 1.6 -> 1.28, rates whose
  # reciprocals terminate (0.8, 0.625, 0.78125), so every figure below is
  # exact in Decimal and computable by hand.
  #
  #   2025-01-02  deposit 10000 EUR, deposit 2000 USD
  #               buy Euro Fund 50 @ 100 EUR, fees 5 (Depot A, Cash EUR)
  #               buy US Corp 10 @ 100 USD (Depot B, Cash USD)
  #   2025-02-03  buy US Tech 20 @ 50 USD through Cash EUR, settled 820 EUR
  #   2025-03-03  inbound delivery Gift Fund 10 @ 30 (booked price)
  #   2025-04-01  inbound delivery Ghost Fund 5, no price, never quoted
  #   2025-05-02  dividend Euro Fund 40 EUR
  #   2025-06-02  interest 12 EUR
  #   2025-07-01  custody fee 7 EUR naming Euro Fund (standalone)
  #   2025-08-01  split Euro Fund 2:1
  #   2025-10-01  transfer 40 Euro Fund from Depot A to Depot D
  #   2025-11-03  sell US Corp 4 @ 130 USD, fees 2 USD
  #   2025-12-01  removal 1000 EUR
  #   2026-01-15  interest 3 USD
  #               sell Euro Fund 10 @ 66, fees 2, from Depot D into Cash EUR
  #   2026-02-02  tax refund 6 EUR; delivery Yen Co 100 @ 1000 JPY (no JPY rate)
  #   2026-03-02  buy US Tech 4 @ 55 USD, fees 1 USD, into Depot C from Cash USD
  #   2026-04-01  dividend US Corp 8 USD
  #   2026-05-04  buy Flip Share 10 @ 20, fees 1 (never quoted)
  #   2026-05-15  balance snapshot Cash USD 1309 (a residual jump of 1 USD)
  #   2026-05-20  sell Flip Share 10 @ 25, fees 1
  #   2026-06-01  deposit 500 EUR
  #
  # Since #1055 the rich portfolio also holds a "Reserve CHF" account, 500 CHF
  # deposited on 2025-04-01, in a currency the instance never holds a rate
  # for: the walk counts it zero every day (its deposit is a flow of 0), so
  # no figure below moves, and every read whose scope holds it names it.
  #
  # Depot C settles through Cash USD, Depot D through Cash EUR. The side
  # portfolio deposits 1000 EUR and buys Euro Fund 5 @ 100 on 2025-01-02.
  # The view "Core" sees Depot A, Depot C, Cash EUR and the side portfolio's
  # two accounts; Depot B, Depot D and Cash USD are out of view, so the depot
  # transfer and the two 2026 trades straddle its boundary.
  defp rich_world do
    rich = base_world(name: "Rich", cash_name: "Cash EUR", depot_name: "Depot A")

    usd =
      rich.portfolio
      |> add_depot(cash_currency: "USD", cash_name: "Cash USD", depot_name: "Depot B")
      |> Map.put(:portfolio, rich.portfolio)

    depot_c = depot!(rich.portfolio, usd.cash, "Depot C")
    depot_d = depot!(rich.portfolio, rich.cash, "Depot D")
    side = base_world(name: "Side", cash_name: "Side Cash", depot_name: "Side Depot")

    euro = create_security!(name: "Euro Fund", ticker: "EUF", isin: "DE000CONTR01")
    us_corp = create_security!(name: "US Corp", ticker: "USC", currency: "USD")
    us_tech = create_security!(name: "US Tech", ticker: "UST", currency: "USD")
    gift = create_security!(name: "Gift Fund", ticker: "GFT")
    ghost = create_security!(name: "Ghost Fund", ticker: "GHO")
    flip = create_security!(name: "Flip Share", ticker: "FLP")
    yen = create_security!(name: "Yen Co", ticker: "YEN", currency: "JPY")

    rate!("USD", ~D[2025-01-01], "1.25")
    rate!("USD", ~D[2025-09-30], "1.6")
    rate!("USD", ~D[2026-03-31], "1.28")

    deposit!(rich, "10000", ~D[2025-01-02])
    deposit!(usd, "2000", ~D[2025-01-02], currency: "USD")
    deposit!(side, "1000", ~D[2025-01-02])

    {:ok, reserve} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: rich.portfolio.id,
        name: "Reserve CHF",
        currency_code: "CHF"
      })

    deposit!(%{portfolio: rich.portfolio, cash: reserve}, "500", ~D[2025-04-01], currency: "CHF")

    WorldFixtures.buy!(rich, euro, quantity: "50", price: "100", fees: "5", date: ~D[2025-01-02])
    WorldFixtures.buy!(side, euro, quantity: "5", price: "100", date: ~D[2025-01-02])

    WorldFixtures.buy!(usd, us_corp,
      quantity: "10",
      price: "100",
      date: ~D[2025-01-02],
      currency: "USD"
    )

    book!(%{
      portfolio_id: rich.portfolio.id,
      securities_account_id: rich.depot.id,
      cash_account_id: rich.cash.id,
      security_id: us_tech.id,
      type: "buy",
      date: ~D[2025-02-03],
      quantity: "20",
      price: "50",
      currency_code: "USD",
      security_amount: "1000",
      settlement_amount: "820",
      settlement_fx_rate: "0.82",
      gross_amount: "820"
    })

    delivery!(rich, gift, "10", ~D[2025-03-03], price: "30")
    delivery!(rich, ghost, "5", ~D[2025-04-01])
    cash!(rich, "dividend", "40", ~D[2025-05-02], security_id: euro.id)
    cash!(rich, "interest", "12", ~D[2025-06-02])
    cash!(rich, "fee", "7", ~D[2025-07-01], security_id: euro.id)
    split!(euro, ~D[2025-08-01], {2, 1})

    book!(%{
      portfolio_id: rich.portfolio.id,
      securities_account_id: rich.depot.id,
      counter_securities_account_id: depot_d.id,
      security_id: euro.id,
      type: "security_transfer",
      date: ~D[2025-10-01],
      quantity: "40",
      currency_code: "EUR"
    })

    WorldFixtures.sell!(usd, us_corp,
      quantity: "4",
      price: "130",
      fees: "2",
      date: ~D[2025-11-03],
      currency: "USD"
    )

    cash!(rich, "removal", "1000", ~D[2025-12-01])
    cash!(usd, "interest", "3", ~D[2026-01-15], currency: "USD")

    WorldFixtures.sell!(%{rich | depot: depot_d}, euro,
      quantity: "10",
      price: "66",
      fees: "2",
      date: ~D[2026-01-15]
    )

    cash!(rich, "tax_refund", "6", ~D[2026-02-02])
    delivery!(rich, yen, "100", ~D[2026-02-02], price: "1000", currency: "JPY")

    WorldFixtures.buy!(%{usd | depot: depot_c}, us_tech,
      quantity: "4",
      price: "55",
      fees: "1",
      date: ~D[2026-03-02],
      currency: "USD"
    )

    cash!(usd, "dividend", "8", ~D[2026-04-01], security_id: us_corp.id, currency: "USD")
    WorldFixtures.buy!(rich, flip, quantity: "10", price: "20", fees: "1", date: ~D[2026-05-04])
    snapshot!(usd.cash, "1309", ~D[2026-05-15])
    WorldFixtures.sell!(rich, flip, quantity: "10", price: "25", fees: "1", date: ~D[2026-05-20])
    deposit!(rich, "500", ~D[2026-06-01])

    WorldFixtures.put_quotes!(euro, [
      {~D[2025-01-02], "100"},
      {~D[2025-06-30], "110"},
      {~D[2025-07-31], "120"},
      {~D[2025-08-01], "60"},
      {~D[2025-12-31], "65"},
      {~D[2026-06-30], "70"}
    ])

    WorldFixtures.put_quotes!(us_corp, [
      {~D[2025-01-02], "100"},
      {~D[2025-06-30], "110"},
      {~D[2025-12-31], "120"},
      {~D[2026-06-30], "125"}
    ])

    WorldFixtures.put_quotes!(us_tech, [
      {~D[2025-02-03], "50"},
      {~D[2025-12-31], "55"},
      {~D[2026-06-30], "60"}
    ])

    WorldFixtures.put_quotes!(gift, [{~D[2025-03-03], "30"}, {~D[2026-06-30], "33"}])

    view = core_view!([rich.depot, depot_c, side.depot], [rich.cash, side.cash])

    %{
      rich: rich,
      usd: usd,
      side: side,
      reserve: reserve,
      view: view,
      securities: %{
        euro: euro,
        us_corp: us_corp,
        us_tech: us_tech,
        gift: gift,
        ghost: ghost,
        flip: flip,
        yen: yen
      }
    }
  end

  defp book!(attrs) do
    {:ok, tx} = Ledger.create_transaction(Actor.owner_ui(), attrs)
    tx
  end

  # A depot settling through an existing cash account.
  defp depot!(portfolio, cash, name) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: name
      })

    depot
  end

  defp cash!(world, type, amount, date, opts \\ []) do
    book!(%{
      portfolio_id: world.portfolio.id,
      cash_account_id: world.cash.id,
      security_id: Keyword.get(opts, :security_id),
      type: type,
      date: date,
      gross_amount: amount,
      currency_code: Keyword.get(opts, :currency, "EUR")
    })
  end

  defp delivery!(world, security, quantity, date, opts \\ []) do
    book!(%{
      portfolio_id: world.portfolio.id,
      securities_account_id: world.depot.id,
      security_id: security.id,
      type: Keyword.get(opts, :type, "inbound_delivery"),
      date: date,
      quantity: quantity,
      price: Keyword.get(opts, :price),
      currency_code: Keyword.get(opts, :currency, "EUR")
    })
  end

  defp split!(security, date, {numerator, denominator}) do
    {:ok, txs} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: date,
        ratio_numerator: numerator,
        ratio_denominator: denominator
      })

    txs
  end

  defp snapshot!(cash_account, amount, date) do
    {:ok, _} =
      Ledger.set_cash_balance(
        Actor.owner_ui(),
        Portfolios.get_cash_account(cash_account.id),
        %{"date" => Date.to_iso8601(date), "amount" => amount}
      )
  end

  defp rate!(quote_currency, date, rate) do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: quote_currency,
          date: date,
          rate: rate,
          source: "manual"
        }
      ])
  end

  defp core_view!(depots, cash_accounts) do
    {:ok, core} =
      Buckets.create_bucket(Actor.owner_ui(), %{
        name: "Core #{System.unique_integer([:positive])}"
      })

    for depot <- depots,
        do: :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [core.id])

    for cash <- cash_accounts,
        do: :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [core.id])

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{
        name: "Core #{System.unique_integer([:positive])}",
        include_all: false
      })

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [core.id], [])
    view
  end

  # -- I9 -------------------------------------------------------------------------

  # The four ways a walk is scoped: the portfolio, the portfolio narrowed by a
  # view, a view across all portfolios, and the Everything view. Each pairs the
  # plain walk with the walk that keeps the per-position figures apart.
  defp walk_pairs(pid, view) do
    [
      {"portfolio", fn -> Performance.analysis(pid, today: @today) end,
       &Performance.contribution_analysis(pid, :unscoped, &1, today: @today)},
      {"portfolio narrowed by a view",
       fn -> Performance.analysis(pid, view: view, today: @today) end,
       &Performance.contribution_analysis(pid, Buckets.load_scope(pid, view), &1, today: @today)},
      {"view across portfolios", fn -> Performance.view_analysis(view, today: @today) end,
       &Performance.view_contribution_analysis(view, Buckets.load_global_scope(view), &1,
         today: @today
       )},
      {"Everything view", fn -> Performance.view_analysis(nil, today: @today) end,
       &Performance.view_contribution_analysis(nil, :unscoped, &1, today: @today)}
    ]
  end

  # User story (FR-41, ADR-0051 §5):
  # As a local portfolio maintainer,
  # I want the performance walk to keep each position's figures apart inside a
  # period without changing anything it already computes,
  # so that a contribution table can stand beside my TTWROR without moving it.
  #
  # Acceptance criteria (ADR-0051 I9):
  # - With the accumulators on, the walk's daily series (value, flow, basis
  #   step, trade costs) is byte-identical to the walk without them, for every
  #   period and every scope: the portfolio, a view-narrowed portfolio, a view
  #   across portfolios and the Everything view.
  # - The summaries chained from either walk (TTWROR, IRR, MWR, series,
  #   values, flows, invested capital, wealth multiple, basis) are identical.
  # - The walk's computation version does not move.
  test "the walk's outputs are byte-identical with the accumulators on (I9)" do
    world = rich_world()

    for {scope, plain_walk, kept_walk} <- walk_pairs(world.rich.portfolio.id, world.view.id),
        period <- @periods do
      plain = plain_walk.()
      assert_walks_identical(plain, kept_walk.(period), period, "#{scope} #{inspect(period)}")

      # #1055: the reserve the walk counts zero rides in both walks alike
      # wherever the scope holds it, so the comparison above covers it.
      if scope in ["portfolio", "Everything view"],
        do: assert(Enum.any?(plain.daily, &Map.has_key?(&1, :unvalued_cash)))
    end

    # #1055 added keys to the stored walk payloads (each day's unvalued cash,
    # and the accounts' names beside it), so both computation versions moved
    # with them; no figure did. #1051 rides the same versions: of the walk's
    # figures, only a cross-currency trade's trade costs moved.
    assert Registry.computation_version!(:performance_analysis) == 4
    assert Registry.computation_version!(:performance_view_analysis) == 4
  end

  # I9 for one scope and period: the walk that keeps the figures apart
  # answers exactly what the plain walk answers.
  defp assert_walks_identical(plain, kept, period, label) do
    assert Map.has_key?(kept, :contribution), label
    assert kept.daily == plain.daily, label

    assert Map.drop(kept, [:contribution, :basis, :stale]) == Map.drop(plain, [:basis, :stale]),
           label

    assert Map.delete(kept.basis, :computed_at) == Map.delete(plain.basis, :computed_at)

    {:ok, plain_summary} = Performance.summarise(plain, period)
    {:ok, kept_summary} = Performance.summarise(kept, period)

    assert Map.drop(kept_summary, [:as_of, :stale]) ==
             Map.drop(plain_summary, [:as_of, :stale]),
           label

    # The figures really were kept wherever the window holds a walked day.
    assert is_map(kept.contribution) == not is_nil(plain_summary.start_date), label

    if is_map(kept.contribution), do: assert(kept.contribution.positions != %{})
  end

  # -- I2 to I7: one identity at a time, on small worlds ----------------------

  defp zero?(decimal), do: Decimal.equal?(decimal, Decimal.new("0"))
  defp equal?(decimal, expected), do: Decimal.equal?(decimal, Decimal.new(expected))

  defp row(result, security), do: Enum.find(result.positions, &(&1.security_id == security.id))

  defp assert_remainder_zero(result) do
    assert zero?(result.remainder.interest)
    assert zero?(result.remainder.standalone_fees_and_taxes)
    assert zero?(result.remainder.cash_currency_effect)
    assert zero?(result.totals.remainder)
  end

  # A EUR and a USD position bought before 2026, EUR/USD at 1.25 throughout.
  defp steady_world do
    world = base_world(name: "Steady", cash_name: "Cash EUR", depot_name: "Depot EUR")

    usd =
      world.portfolio
      |> add_depot(cash_currency: "USD", cash_name: "Cash USD", depot_name: "Depot USD")
      |> Map.put(:portfolio, world.portfolio)

    eur_fund = create_security!(name: "Steady EUR", ticker: "STE")
    usd_fund = create_security!(name: "Steady USD", ticker: "STU", currency: "USD")

    rate!("USD", ~D[2025-12-01], "1.25")
    deposit!(world, "3000", ~D[2025-12-01])
    deposit!(usd, "1000", ~D[2025-12-01], currency: "USD")
    WorldFixtures.buy!(world, eur_fund, quantity: "10", price: "100", date: ~D[2025-12-01])

    WorldFixtures.buy!(usd, usd_fund,
      quantity: "5",
      price: "80",
      date: ~D[2025-12-01],
      currency: "USD"
    )

    WorldFixtures.put_quotes!(eur_fund, [{~D[2025-12-01], "100"}, {~D[2026-03-02], "100"}])
    WorldFixtures.put_quotes!(usd_fund, [{~D[2025-12-01], "80"}, {~D[2026-03-02], "80"}])

    %{world: world, usd: usd, eur_fund: eur_fund, usd_fund: usd_fund}
  end

  # User story (FR-41, ADR-0051 §1):
  # As a local portfolio maintainer,
  # I want to see which position made how much of a period's money result,
  # so that I can tell what moved my wealth and what only sat there.
  #
  # Acceptance criteria (ADR-0051 I2):
  # - With unchanging prices and exchange rates, and no bookings inside the
  #   window except deposits and removals, every position contributes exactly
  #   0, and so does every remainder line.
  # - Each position held across the window is listed with equal start and end
  #   values (base currency, a USD position at the day's rate), held at both
  #   ends, with no flows, income or costs.
  test "nothing moves: every position and every remainder line contributes 0 (I2)" do
    %{world: world, usd: usd, eur_fund: eur_fund, usd_fund: usd_fund} = steady_world()

    # Inside the window: money in and out, in both currencies, and a rate
    # point that restates the same rate.
    deposit!(world, "500", ~D[2026-02-02])
    cash!(world, "removal", "200", ~D[2026-03-02])
    deposit!(usd, "100", ~D[2026-04-01], currency: "USD")
    cash!(usd, "removal", "50", ~D[2026-05-04], currency: "USD")
    rate!("USD", ~D[2026-03-02], "1.25")

    {:ok, result} =
      Contribution.for_portfolio(world.portfolio.id, period: "ytd", today: @today)

    assert result.start_date == ~D[2026-01-01]
    assert result.end_date == @today
    assert result.base_currency == "EUR"
    assert length(result.positions) == 2

    eur_row = row(result, eur_fund)
    usd_row = row(result, usd_fund)

    assert eur_row.name == "Steady EUR"
    assert equal?(eur_row.start_value, "1000")
    assert equal?(eur_row.end_value, "1000")
    # 5 x 80 USD at 0.8 EUR per USD.
    assert equal?(usd_row.start_value, "320")
    assert equal?(usd_row.end_value, "320")

    for position <- result.positions do
      assert zero?(position.contribution)
      assert zero?(position.net_flows)
      assert zero?(position.income)
      assert zero?(position.costs)
      assert position.held_at_start
      assert position.held_at_end
    end

    assert_remainder_zero(result)
    assert zero?(result.totals.positions)
    assert zero?(result.totals.result)
  end

  # User story (FR-41, ADR-0051 §1, §4):
  # As a local portfolio maintainer,
  # I want a position I opened and closed inside the period to show what it
  # made, in money I can check against the two bookings,
  # so that a round trip is not lost just because I hold nothing at either end.
  #
  # Acceptance criteria (ADR-0051 I3):
  # - A position in the base currency, bought and sold entirely inside the
  #   window with no quote in between, contributes exactly
  #   (sell price − buy price) × quantity − costs.
  # - It appears in the table although it is held at neither end: start and
  #   end value 0, net flows buy minus sell value, costs the fees and taxes
  #   of both trades.
  test "a round trip inside the window contributes its trade result (I3)" do
    world = base_world(name: "Round", cash_name: "Cash", depot_name: "Depot")
    share = create_security!(name: "Round Trip", ticker: "RTP")

    deposit!(world, "1000", ~D[2026-01-05])

    WorldFixtures.buy!(world, share,
      quantity: "10",
      price: "20",
      fees: "1.5",
      taxes: "0.5",
      date: ~D[2026-02-02]
    )

    WorldFixtures.sell!(world, share,
      quantity: "10",
      price: "26",
      fees: "1.5",
      taxes: "0.75",
      date: ~D[2026-04-01]
    )

    {:ok, result} = Contribution.for_portfolio(world.portfolio.id, period: "ytd", today: @today)

    assert [position] = result.positions
    assert position.security_id == share.id
    refute position.held_at_start
    refute position.held_at_end
    assert zero?(position.start_value)
    assert zero?(position.end_value)
    # 10 x 20 bought, 10 x 26 sold.
    assert equal?(position.net_flows, "-60")
    assert equal?(position.costs, "4.25")
    assert zero?(position.income)
    # (26 - 20) x 10 - 4.25
    assert equal?(position.contribution, "55.75")

    assert_remainder_zero(result)
    assert equal?(result.totals.result, "55.75")
  end

  # User story (FR-41, ADR-0051 §3):
  # As a local portfolio maintainer,
  # I want money I pay in or take out to leave every position's contribution
  # and every remainder line alone,
  # so that topping up my account never reads as a position earning money.
  #
  # Acceptance criteria (ADR-0051 I4):
  # - A deposit or a removal changes no contribution and no remainder line,
  #   with prices and exchange rates moving around it.
  # - It leaves the money result alone too: it is an external flow.
  # - A deposit into a foreign-currency account contributes nothing either
  #   (booked after the window's last rate move, so no later revaluation of
  #   the larger balance enters the comparison).
  test "a deposit or a removal changes no contribution and no remainder line (I4)" do
    %{world: world, usd: usd, eur_fund: eur_fund, usd_fund: usd_fund} = steady_world()
    WorldFixtures.put_quote!(eur_fund, ~D[2026-03-02], "110")
    WorldFixtures.put_quote!(usd_fund, ~D[2026-03-02], "90")
    rate!("USD", ~D[2026-04-01], "1.6")

    {:ok, before} = Contribution.for_portfolio(world.portfolio.id, period: "ytd", today: @today)

    deposit!(world, "700", ~D[2026-02-02])
    cash!(world, "removal", "300", ~D[2026-05-04])
    deposit!(usd, "40", ~D[2026-04-15], currency: "USD")
    cash!(usd, "removal", "25", ~D[2026-06-01], currency: "USD")

    {:ok, later} = Contribution.for_portfolio(world.portfolio.id, period: "ytd", today: @today)

    assert later.positions == before.positions
    assert later.remainder == before.remainder
    assert later.totals == before.totals
    # The prices did move: 10 x (110 - 100) and 5 x 90 x 0.625 - 5 x 80 x 0.8.
    assert equal?(row(later, eur_fund).contribution, "100")
    assert equal?(row(later, usd_fund).contribution, "-38.75")
  end

  # User story (FR-41, ADR-0051 §5, ADR-0028):
  # As a local portfolio maintainer,
  # I want a stock split inside the period to leave the position's
  # contribution exactly where the market move puts it,
  # so that doubling my share count never reads as a gain or a loss.
  #
  # Acceptance criteria (ADR-0051 I5):
  # - A split inside the window changes no contribution: a position that
  #   splits 2:1 contributes exactly what the same position without a split
  #   contributes over the same prices.
  # - The split is no flow: net flows stay 0, and the end value counts the
  #   post-split units at the post-split price.
  test "a split inside the window changes no contribution (I5)" do
    world = base_world(name: "Split", cash_name: "Cash", depot_name: "Depot")
    plain = create_security!(name: "Plain Share", ticker: "PLN")
    splitter = create_security!(name: "Split Share", ticker: "SPL")

    deposit!(world, "3000", ~D[2025-12-01])
    WorldFixtures.buy!(world, plain, quantity: "10", price: "100", date: ~D[2025-12-01])
    WorldFixtures.buy!(world, splitter, quantity: "10", price: "100", date: ~D[2025-12-01])

    WorldFixtures.put_quotes!(plain, [
      {~D[2025-12-01], "100"},
      {~D[2026-02-02], "110"},
      {~D[2026-05-04], "120"}
    ])

    # As-traded closes: 110 before the split, 60 after it (= 120 pre-split).
    WorldFixtures.put_quotes!(splitter, [
      {~D[2025-12-01], "100"},
      {~D[2026-02-02], "110"},
      {~D[2026-05-04], "60"}
    ])

    split!(splitter, ~D[2026-03-02], {2, 1})

    {:ok, result} = Contribution.for_portfolio(world.portfolio.id, period: "ytd", today: @today)

    plain_row = row(result, plain)
    split_row = row(result, splitter)

    assert equal?(plain_row.contribution, "200")
    assert split_row.contribution == plain_row.contribution
    assert zero?(split_row.net_flows)
    assert equal?(split_row.start_value, "1000")
    # 20 units at 60.
    assert equal?(split_row.end_value, "1200")
    assert equal?(result.totals.result, "400")
  end

  # User story (FR-41, ADR-0051 §6, ADR-0019):
  # As a local portfolio maintainer with two depots,
  # I want moving shares between my depots to change no contribution, and a
  # view that sees one depot to treat the move as money crossing its edge,
  # so that a position is never charged with its own transfer.
  #
  # Acceptance criteria (ADR-0051 I6):
  # - A transfer between two depots of one portfolio changes no contribution.
  # - In a view that sees only one of the two depots, the moved value is a
  #   boundary flow of that position, at the day's price: out of the
  #   sending depot's view, into the receiving one's.
  # - The two views' contributions add up to the portfolio's.
  test "a transfer between depots changes no contribution; a view sees a boundary flow (I6)" do
    world = base_world(name: "Depots", cash_name: "Cash A", depot_name: "Depot A")
    other = add_depot(world.portfolio, cash_name: "Cash B", depot_name: "Depot B")
    mover = create_security!(name: "Mover", ticker: "MOV")

    deposit!(world, "2000", ~D[2025-12-01])
    WorldFixtures.buy!(world, mover, quantity: "10", price: "100", date: ~D[2025-12-01])

    WorldFixtures.put_quotes!(mover, [
      {~D[2025-12-01], "100"},
      {~D[2026-02-02], "110"},
      {~D[2026-05-04], "120"}
    ])

    pid = world.portfolio.id
    {:ok, before} = Contribution.for_portfolio(pid, period: "ytd", today: @today)

    book!(%{
      portfolio_id: pid,
      securities_account_id: world.depot.id,
      counter_securities_account_id: other.depot.id,
      security_id: mover.id,
      type: "security_transfer",
      date: ~D[2026-03-02],
      quantity: "4",
      currency_code: "EUR"
    })

    {:ok, later} = Contribution.for_portfolio(pid, period: "ytd", today: @today)

    assert later.positions == before.positions
    assert later.remainder == before.remainder
    assert equal?(row(later, mover).contribution, "200")

    view_a = core_view!([world.depot], [world.cash])
    view_b = core_view!([other.depot], [])

    {:ok, in_a} = Contribution.for_portfolio(pid, view: view_a.id, period: "ytd", today: @today)
    {:ok, in_b} = Contribution.for_portfolio(pid, view: view_b.id, period: "ytd", today: @today)

    # Depot A: 10 held at 100, 4 leave at 110 (a boundary outflow of 440),
    # 6 end at 120.
    sender = row(in_a, mover)
    assert equal?(sender.start_value, "1000")
    assert equal?(sender.net_flows, "-440")
    assert equal?(sender.end_value, "720")
    assert equal?(sender.contribution, "160")
    assert equal?(in_a.totals.result, "160")
    assert in_a.view_id == view_a.id

    # Depot B: 4 arrive at 110 (a boundary inflow) and end at 120.
    receiver = row(in_b, mover)
    refute receiver.held_at_start
    assert equal?(receiver.net_flows, "440")
    assert equal?(receiver.end_value, "480")
    assert equal?(receiver.contribution, "40")
    assert equal?(in_b.totals.result, "40")

    assert Decimal.equal?(
             Decimal.add(sender.contribution, receiver.contribution),
             row(later, mover).contribution
           )
  end

  # User story (FR-41, ADR-0051 §10):
  # As a local portfolio maintainer,
  # I want a position the walk could not value to stay in the table, named,
  # with the number of days it counted zero and why,
  # so that the sum still agrees with my money result and I know which price
  # or rate to add.
  #
  # Acceptance criteria (ADR-0051 I7):
  # - A position that counted zero keeps its place in the sum: the positions
  #   plus the remainder still equal the money result.
  # - It carries `unvalued_days`, the window days on which it was held and
  #   counted zero, and `unvalued_reason`: `:no_price` without any price,
  #   `:no_rate` without a rate path to the base currency.
  # - A position unvalued for part of the window counts only those days; a
  #   valued position carries 0 days and no reason.
  test "a position that counted zero keeps its place and carries its days (I7)" do
    world = base_world(name: "Gaps", cash_name: "Cash", depot_name: "Depot")
    valued = create_security!(name: "Valued Fund", ticker: "VAL")
    ghost = create_security!(name: "Ghost Fund", ticker: "GHO")
    late = create_security!(name: "Late Quote", ticker: "LTQ")
    yen = create_security!(name: "Yen Co", ticker: "YEN", currency: "JPY")

    deposit!(world, "1000", ~D[2025-12-01])
    WorldFixtures.buy!(world, valued, quantity: "5", price: "100", date: ~D[2025-12-01])
    WorldFixtures.put_quotes!(valued, [{~D[2025-12-01], "100"}, {~D[2026-04-01], "110"}])

    # Never priced: no booked price, no quote.
    delivery!(world, ghost, "5", ~D[2026-02-02])
    # Unpriced until its first quote lands on 2026-04-01.
    delivery!(world, late, "10", ~D[2026-02-02])
    WorldFixtures.put_quote!(late, ~D[2026-04-01], "20")
    # Priced in JPY, but no JPY rate is stored.
    delivery!(world, yen, "100", ~D[2026-03-02], price: "1000", currency: "JPY")

    {:ok, result} = Contribution.for_portfolio(world.portfolio.id, period: "ytd", today: @today)

    assert length(result.positions) == 4

    ghost_row = row(result, ghost)
    assert ghost_row.held_at_end
    assert zero?(ghost_row.end_value)
    assert zero?(ghost_row.contribution)
    # 2026-02-02 to 2026-06-30.
    assert ghost_row.unvalued_days == 149
    assert ghost_row.unvalued_reason == :no_price

    yen_row = row(result, yen)
    assert zero?(yen_row.contribution)
    # 2026-03-02 to 2026-06-30.
    assert yen_row.unvalued_days == 121
    assert yen_row.unvalued_reason == :no_rate

    late_row = row(result, late)
    # 2026-02-02 to 2026-03-31; delivered at no value, it ends at 10 x 20.
    assert late_row.unvalued_days == 58
    assert late_row.unvalued_reason == :no_price
    assert equal?(late_row.contribution, "200")

    valued_row = row(result, valued)
    assert valued_row.unvalued_days == 0
    assert valued_row.unvalued_reason == nil
    assert equal?(valued_row.contribution, "50")

    assert equal?(result.totals.result, "250")
    assert equal?(result.totals.positions, "250")
    assert_remainder_zero(result)

    # Every balance was valued: no cash account is named (#1055).
    assert result.unvalued_cash_accounts == []
  end

  # User story (FR-41 review round, ADR-0051 §5 and §10):
  # As a local portfolio maintainer who buys a security priced in a currency
  # the instance holds no rate for yet,
  # I want the trade to bring its units in at the cash it cost,
  # so that the position is not credited with its whole value the day a rate
  # arrives, and the currency line does not book the purchase as a loss.
  #
  # Acceptance criteria:
  # - A trade whose price currency has no rate path to the base on the
  #   booking day is a flow into its position at its cash leg in the base
  #   currency: the position's net flows are what it cost, and the currency
  #   effect on cash holds no settlement difference for it.
  # - Once the first rate arrives, the position contributes its value against
  #   that cost; if none ever arrives, it contributes minus that cost, and it
  #   is named as unvalued with its days (I7).
  # - The positions plus the remainder lines still sum to the money result (I1).
  test "a trade whose price currency has no rate yet flows in at its cash leg" do
    world = base_world(name: "Rateless", cash_name: "Cash", depot_name: "Depot")
    yen = create_security!(name: "Yen Late Co", ticker: "YLC", currency: "JPY")
    franc = create_security!(name: "Franc Never AG", ticker: "FNA", currency: "CHF")

    deposit!(world, "1000", ~D[2025-12-01])

    settled_buy = fn security, quantity, price, currency, amount, settled ->
      book!(%{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-02-03],
        quantity: quantity,
        price: price,
        currency_code: currency,
        security_amount: amount,
        settlement_amount: settled,
        settlement_fx_rate: Decimal.div(Decimal.new(settled), Decimal.new(amount)),
        gross_amount: settled
      })
    end

    # 10 @ 1000 JPY settled 62 EUR; the first JPY rate (160) arrives on
    # 2026-04-01 and values the position at 10 x 1000 / 160 = 62.5.
    settled_buy.(yen, "10", "1000", "JPY", "10000", "62")
    WorldFixtures.put_quotes!(yen, [{~D[2026-02-03], "1000"}])
    rate!("JPY", ~D[2026-04-01], "160")

    # 1 @ 50 CHF settled 65 EUR; no CHF rate ever arrives.
    settled_buy.(franc, "1", "50", "CHF", "50", "65")
    WorldFixtures.put_quotes!(franc, [{~D[2026-02-03], "50"}])

    {:ok, result} = Contribution.for_portfolio(world.portfolio.id, period: "ytd", today: @today)

    yen_row = row(result, yen)
    assert equal?(yen_row.net_flows, "62")
    assert zero?(yen_row.costs)
    assert equal?(yen_row.end_value, "62.5")
    assert equal?(yen_row.contribution, "0.5")
    # 2026-02-03 to 2026-03-31.
    assert yen_row.unvalued_days == 57
    assert yen_row.unvalued_reason == :no_rate

    franc_row = row(result, franc)
    assert equal?(franc_row.net_flows, "65")
    assert zero?(franc_row.end_value)
    assert equal?(franc_row.contribution, "-65")
    # 2026-02-03 to 2026-06-30.
    assert franc_row.unvalued_days == 148
    assert franc_row.unvalued_reason == :no_rate

    assert_remainder_zero(result)
    # 873 cash + 62.5 - the 1000 held at the start.
    assert equal?(result.totals.result, "-64.5")
    assert equal?(result.totals.positions, "-64.5")
  end

  # User story (#1051, ADR-0051 amendment 2026-10-03, §5's no-rate row):
  # As a local portfolio maintainer who buys a security priced in a currency
  # the instance holds no rate for, through my EUR account, and pays fees,
  # I want those fees counted once,
  # so that the position is charged what the trade cost and not the fees a
  # second time.
  #
  # Acceptance criteria:
  # - A trade whose price currency has no rate path on its day flows into its
  #   position at its whole cash leg, fees and taxes included, and carries no
  #   costs of its own, although the walk now reads those fees in the
  #   account's currency (#1051): they ride inside the cash, as before.
  # - No settlement difference is left on the currency effect on cash.
  # - The positions plus the remainder lines still sum to the money result
  #   (I1).
  test "a trade with no rate keeps its fees inside its cash leg, counted once" do
    world = base_world(name: "Rateless Fees", cash_name: "Cash", depot_name: "Depot")
    franc = create_security!(name: "Franc Fee AG", ticker: "FFA", currency: "CHF")

    deposit!(world, "1000", ~D[2025-12-01])

    # 1 @ 50 CHF settled 65 EUR, fees 2 and taxes 1 EUR: 68 EUR paid. No CHF
    # rate ever arrives.
    WorldFixtures.cross_trade!(world, franc,
      quantity: "1",
      price: "50",
      settled: "65",
      fees: "2",
      taxes: "1",
      gross: "68",
      date: ~D[2026-02-03]
    )

    WorldFixtures.put_quotes!(franc, [{~D[2026-02-03], "50"}])

    {:ok, result} = Contribution.for_portfolio(world.portfolio.id, period: "ytd", today: @today)

    position = row(result, franc)
    assert equal?(position.net_flows, "68")
    assert zero?(position.costs)
    assert zero?(position.end_value)
    assert equal?(position.contribution, "-68")
    assert position.unvalued_reason == :no_rate

    assert_remainder_zero(result)
    # 932 cash - the 1000 held at the start.
    assert equal?(result.totals.result, "-68")
    assert equal?(result.totals.positions, "-68")
  end

  # -- I1 -------------------------------------------------------------------------

  # The contribution and the performance read of one scope, side by side.
  defp scoped_reads(pid, view) do
    [
      {"portfolio", &Contribution.for_portfolio(pid, period: &1, today: @today),
       &Performance.for_portfolio(pid, period: &1, today: @today)},
      {"portfolio narrowed by a view",
       &Contribution.for_portfolio(pid, view: view, period: &1, today: @today),
       &Performance.for_portfolio(pid, view: view, period: &1, today: @today)},
      {"view across portfolios", &Contribution.for_view(view, period: &1, today: @today),
       &Performance.for_view(view, period: &1, today: @today)},
      {"Everything view", &Contribution.for_view(nil, period: &1, today: @today),
       &Performance.for_view(nil, period: &1, today: @today)}
    ]
  end

  defp sum(decimals), do: Enum.reduce(decimals, Decimal.new("0"), &Decimal.add/2)

  # I1 for one scope and period: the positions plus the remainder lines sum
  # to the money result the performance read shows, and no line is a plug.
  defp assert_money_identity(result, read, label) do
    money_result =
      read.end_value |> Decimal.sub(read.start_value) |> Decimal.sub(read.net_external_flows)

    assert Decimal.equal?(result.totals.result, money_result), label

    assert Decimal.equal?(
             Decimal.add(result.totals.positions, result.totals.remainder),
             result.totals.result
           ),
           label

    assert Decimal.equal?(
             result.totals.positions,
             sum(Enum.map(result.positions, & &1.contribution))
           )

    assert Decimal.equal?(result.totals.remainder, sum(Map.values(result.remainder)))
    assert result.start_date == read.start_date, label

    # #1055: both reads of one scope and window name the same accounts.
    assert result.unvalued_cash_accounts == read.unvalued_cash_accounts, label

    for position <- result.positions do
      assert Decimal.equal?(
               position.contribution,
               position.end_value
               |> Decimal.sub(position.start_value)
               |> Decimal.sub(position.net_flows)
               |> Decimal.add(position.income)
               |> Decimal.sub(position.costs)
             ),
             label
    end

    contributions = Enum.map(result.positions, & &1.contribution)
    assert contributions == Enum.sort(contributions, &(Decimal.compare(&1, &2) != :lt)), label

    if is_nil(read.start_date), do: assert(result.positions == [], label)
  end

  defp assert_lines(result, interest, standalone, currency) do
    assert equal?(result.remainder.interest, interest)
    assert equal?(result.remainder.standalone_fees_and_taxes, standalone)
    assert equal?(result.remainder.cash_currency_effect, currency)
  end

  # User story (FR-41, ADR-0051 §1, §3, §4, §6):
  # As a local portfolio maintainer (and the agent I run),
  # I want the positions and three itemised remainder lines to add up to the
  # period's money result to the cent and beyond, for any period and scope,
  # so that the table agrees with the "+x EUR in the period" figure beside my
  # TTWROR instead of being a third number nobody can reconcile.
  #
  # Acceptance criteria (ADR-0051 I1):
  # - The positions plus the remainder lines sum to end − start − net external
  #   flows, exact in Decimal, for every period (ytd, 1y, 3y, 5y, max, a
  #   calendar year, a custom range) and every scope (a portfolio, a portfolio
  #   narrowed by a view, a view across portfolios, the Everything view), on a
  #   world with a cross-currency position, a dividend, interest, a standalone
  #   fee, deliveries, a split, a transfer, a snapshot and unvalued positions.
  # - The money result is the one the performance read shows for the same
  #   period and scope.
  # - No line is a plug: each remainder line equals the sum of its own
  #   bookings, pinned for three periods; each position's contribution is
  #   end − start − net flows + income − costs; positions are sorted largest
  #   first.
  # - A window holding no walked day is empty: no positions, never zeros.
  test "positions plus remainder sum exactly to the money result, every period and scope (I1)" do
    world = rich_world()

    for {scope, contribution, performance} <-
          scoped_reads(world.rich.portfolio.id, world.view.id),
        period <- @periods do
      {:ok, result} = contribution.(period)
      {:ok, read} = performance.(period)
      assert_money_identity(result, read, "#{scope} #{inspect(period)}")
    end

    pid = world.rich.portfolio.id
    s = world.securities

    # The whole history, by hand (see the world's comment for the bookings).
    {:ok, max} = Contribution.for_portfolio(pid, period: "max", today: @today)

    # 90 units at 70 (100 after the split, 40 of them moved to Depot B, 10
    # sold from there at 66): bought for 5000, sold for 660, a 40 dividend,
    # fees of 5 and 2.
    assert equal?(row(max, s.euro).contribution, "1993")
    assert equal?(row(max, s.euro).net_flows, "4340")
    assert equal?(row(max, s.euro).income, "40")
    assert equal?(row(max, s.euro).costs, "7")
    # 6 left at 125 USD x 0.78125, bought 800, sold 325 (4 x 130 x 0.625),
    # an 8 USD dividend at 0.78125, fees of 2 USD at 0.625.
    assert equal?(row(max, s.us_corp).contribution, "115.9375")
    assert equal?(row(max, s.us_corp).net_flows, "475")
    assert equal?(row(max, s.us_corp).income, "6.25")
    assert equal?(row(max, s.us_corp).costs, "1.25")
    # 20 x 50 USD at the hub rate (800, settled at 820 EUR) and 4 x 55 USD at
    # 0.625 (137.5, a fee of 1 USD); 24 end at 60 USD x 0.78125.
    assert equal?(row(max, s.us_tech).net_flows, "937.5")
    assert equal?(row(max, s.us_tech).costs, "0.625")
    assert equal?(row(max, s.us_tech).contribution, "186.875")
    # Delivered at its booked 30, ends at 33.
    assert equal?(row(max, s.gift).net_flows, "300")
    assert equal?(row(max, s.gift).contribution, "30")
    assert equal?(row(max, s.flip).contribution, "48")
    assert zero?(row(max, s.ghost).contribution)
    assert row(max, s.ghost).unvalued_reason == :no_price
    assert zero?(row(max, s.yen).contribution)
    assert row(max, s.yen).unvalued_reason == :no_rate
    assert equal?(max.totals.positions, "2373.8125")

    # Interest 12 EUR + 3 USD x 0.625; fee -7 and refund +6; the settlement
    # difference -20 (800 at the hub rate, 820 paid) and the USD balance's
    # revaluation: 1000 x (0.625 - 0.8) + 1300 x (0.78125 - 0.625).
    assert_lines(max, "13.875", "-1", "8.125")
    assert equal?(max.totals.result, "2394.8125")

    {:ok, year} = Contribution.for_portfolio(pid, period: {:year, 2025}, today: @today)
    assert_lines(year, "12", "-7", "-195")

    {:ok, ytd} = Contribution.for_portfolio(pid, period: "ytd", today: @today)
    assert_lines(ytd, "1.875", "6", "203.125")

    # The view sees Depot A and Cash EUR. 40 Euro Fund leave at 60 on the
    # transfer; the sale from Depot B only brings cash in; the US Tech bought
    # with USD arrives at the cash it cost (221 USD x 0.625, the fee
    # included); the USD account and its interest stay outside.
    {:ok, core} =
      Contribution.for_portfolio(pid, view: world.view.id, period: "max", today: @today)

    assert equal?(row(core, s.euro).net_flows, "2600")
    assert equal?(row(core, s.euro).contribution, "1635")
    assert equal?(row(core, s.us_tech).net_flows, "938.125")
    assert equal?(row(core, s.us_tech).contribution, "186.875")
    assert row(core, s.us_corp) == nil
    assert_lines(core, "12", "-1", "-20")
    assert equal?(core.totals.result, "1890.875")

    # #1055: the CHF reserve counted zero on every day since its deposit and
    # its currency never got a rate, so it is named with no first-rate date;
    # Core leaves the account out, and names nothing.
    assert [reserve] = max.unvalued_cash_accounts
    assert reserve.cash_account_id == world.reserve.id
    assert reserve.name == "Reserve CHF"
    assert reserve.currency_code == "CHF"
    assert equal?(reserve.balance, "500")
    assert reserve.unvalued_days == Date.diff(@today, ~D[2025-04-01]) + 1
    assert reserve.unvalued_reason == :no_rate
    assert reserve.unvalued_through_end
    assert reserve.first_rate_date == nil
    assert core.unvalued_cash_accounts == []

    # Nothing walked yet in 2027: empty, never a table of zeros.
    {:ok, empty} = Contribution.for_view(nil, period: {:year, 2027}, today: @today)
    assert empty.positions == []
    assert empty.start_date == nil
    assert empty.view_id == nil
  end

  # -- #1051: a cross-currency trade's fees and taxes ----------------------------
  #
  # Invented figures only. One EUR-base portfolio: Cash EUR settles Depot A,
  # Cash USD settles Depot B, and one USD security is bought and sold through
  # Cash EUR (ADR-0015). A cross-currency trade records its fees and taxes in
  # its cash account's currency, the cash leg they are part of
  # (`Ledger.SettlementGuard`). EUR/USD moves 1.25 -> 1.6 (0.8 -> 0.625 EUR
  # per USD), so every figure is exact in Decimal and computable by hand.
  #
  #   2025-12-01  deposit 2000 EUR, deposit 500 USD
  #               buy US Fund 10 @ 100 USD into Depot A, settled 790 EUR,
  #               fees 5 and taxes 1 EUR (796 EUR paid)
  #   2026-02-02  buy US Fund 5 @ 110 USD into Depot A, settled 440 EUR,
  #               fees 3.50 and taxes 0.50 EUR (444 EUR paid)
  #   2026-03-02  buy US Fund 2 @ 105 USD into Depot B from Cash USD, fees
  #               1 USD (211 USD paid: a same-currency trade)
  #   2026-05-04  sell US Fund 6 @ 120 USD from Depot A, settled 446.40 EUR,
  #               fees 4 and taxes 2 EUR (440.40 EUR received)
  #
  # The view "Core" sees Depot A and Cash EUR; Depot B and Cash USD are out
  # of view.
  defp cross_world do
    world = base_world(name: "Cross", cash_name: "Cash EUR", depot_name: "Depot A")

    usd =
      world.portfolio
      |> add_depot(cash_currency: "USD", cash_name: "Cash USD", depot_name: "Depot B")
      |> Map.put(:portfolio, world.portfolio)

    fund = create_security!(name: "US Fund", ticker: "USF", currency: "USD")

    rate!("USD", ~D[2025-12-01], "1.25")
    rate!("USD", ~D[2026-04-01], "1.6")

    deposit!(world, "2000", ~D[2025-12-01])
    deposit!(usd, "500", ~D[2025-12-01], currency: "USD")

    WorldFixtures.cross_trade!(world, fund,
      quantity: "10",
      price: "100",
      settled: "790",
      fees: "5",
      taxes: "1",
      gross: "796",
      date: ~D[2025-12-01]
    )

    WorldFixtures.cross_trade!(world, fund,
      quantity: "5",
      price: "110",
      settled: "440",
      fees: "3.50",
      taxes: "0.50",
      gross: "444",
      date: ~D[2026-02-02]
    )

    WorldFixtures.buy!(usd, fund,
      quantity: "2",
      price: "105",
      fees: "1",
      date: ~D[2026-03-02],
      currency: "USD"
    )

    WorldFixtures.cross_trade!(world, fund,
      type: "sell",
      quantity: "6",
      price: "120",
      settled: "446.40",
      fees: "4",
      taxes: "2",
      gross: "440.40",
      date: ~D[2026-05-04]
    )

    WorldFixtures.put_quotes!(fund, [
      {~D[2025-12-01], "100"},
      {~D[2025-12-31], "105"},
      {~D[2026-02-02], "110"},
      {~D[2026-06-30], "125"}
    ])

    view = core_view!([world.depot], [world.cash])

    %{world: world, usd: usd, fund: fund, view: view}
  end

  # User story (#1051, ADR-0051 §5, ADR-0036 risk tier):
  # As a local portfolio maintainer who buys USD securities through my EUR
  # account,
  # I want the walk behind the contribution table to stay byte-identical with
  # its accumulators on when my cross-currency trades carry fees and taxes,
  # so that reading the table never moves my TTWROR.
  #
  # Acceptance criteria (ADR-0051 I9):
  # - On a world whose cross-currency trades carry fees and taxes, the walk
  #   with the accumulators on answers exactly what the plain walk answers,
  #   for every period and every scope.
  test "the walk stays byte-identical on cross-currency trades with costs (I9)" do
    %{world: world, view: view} = cross_world()

    for {scope, plain_walk, kept_walk} <- walk_pairs(world.portfolio.id, view.id),
        period <- @periods do
      assert_walks_identical(
        plain_walk.(),
        kept_walk.(period),
        period,
        "#{scope} #{inspect(period)}"
      )
    end
  end

  # User story (#1051, ADR-0051 §1, §3, ADR-0015):
  # As a local portfolio maintainer who buys USD securities through my EUR
  # account,
  # I want a position's costs to be the fees and taxes my broker charged in
  # euros, counted as euros,
  # so that the costs column shows what I paid, and the currency effect on
  # cash holds only what the broker's rate made of the trade.
  #
  # Acceptance criteria:
  # - A cross-currency trade's fees and taxes are its position's costs,
  #   converted from its cash account's currency, exact in Decimal.
  # - The walk's trade costs on the trade's day are the same figure, in a
  #   portfolio and in a view whose scope holds the trade's cash account; a
  #   trade whose cash account is out of view is still not counted.
  # - The settlement difference left on cash_currency_effect is the hub value
  #   against the settled amount alone.
  # - The positions plus the remainder lines sum to the money result for
  #   every period and scope (I1).
  test "a cross-currency trade's fees and taxes are its position's costs, read in its account's currency (I1)" do
    %{world: world, fund: fund, view: view} = cross_world()
    pid = world.portfolio.id

    for {scope, contribution, performance} <- scoped_reads(pid, view.id), period <- @periods do
      {:ok, result} = contribution.(period)
      {:ok, read} = performance.(period)
      assert_money_identity(result, read, "#{scope} #{inspect(period)}")
    end

    {:ok, max} = Contribution.for_portfolio(pid, period: "max", today: @today)
    position = row(max, fund)

    # 6 + 4 + 6 EUR on the three cross-currency trades, and 1 USD at 0.8 on
    # the Depot B buy: not 6, 4 and 6 read as USD (4.8, 3.2 and 3.75).
    assert equal?(position.costs, "16.8")
    # 10 × 100 and 5 × 110 USD at 0.8, 2 × 105 USD at 0.8, 6 × 120 USD out at
    # 0.625: 800 + 440 + 168 - 450.
    assert equal?(position.net_flows, "958")
    # 11 left at 125 USD × 0.625.
    assert equal?(position.end_value, "859.375")
    assert equal?(position.contribution, "-115.425")

    # The settlement differences: 800 at the hub for 790 (+10), 440 for 440
    # (0), 450 for 446.40 (-3.60); and Cash USD's 289 USD revalued from 0.8
    # to 0.625 (-50.575).
    assert_lines(max, "0", "0", "-44.175")
    # 1200.40 EUR + 289 USD × 0.625 + 859.375, less 2000 EUR and 500 USD
    # × 0.8 paid in.
    assert equal?(max.totals.result, "-159.6")

    # The view sees Depot A and Cash EUR: the three cross-currency trades
    # whole, Depot B's buy and Cash USD not at all.
    {:ok, core} = Contribution.for_portfolio(pid, view: view.id, period: "max", today: @today)
    core_position = row(core, fund)
    assert equal?(core_position.costs, "16")
    assert equal?(core_position.net_flows, "790")
    assert equal?(core_position.contribution, "-102.875")
    assert_lines(core, "0", "0", "6.4")
    assert equal?(core.totals.result, "-96.475")

    # The walk's trade costs are the same figures, day by day.
    %{daily: daily} = Performance.analysis(pid, today: @today)
    %{daily: core_daily} = Performance.analysis(pid, view: view.id, today: @today)

    for {date, portfolio_costs, core_costs} <- [
          {~D[2025-12-01], "6", "6"},
          {~D[2026-02-02], "4", "4"},
          {~D[2026-03-02], "0.8", "0"},
          {~D[2026-05-04], "6", "6"}
        ] do
      assert equal?(costs_on(daily, date), portfolio_costs), Date.to_iso8601(date)
      assert equal?(costs_on(core_daily, date), core_costs), Date.to_iso8601(date)
    end
  end

  defp costs_on(daily, date),
    do:
      daily
      |> Enum.find(&(Date.compare(&1.date, date) == :eq))
      |> Performance.trade_costs_of()

  # -- the edges of the read ------------------------------------------------------

  defp transfer!(portfolio, from, to, amount, date) do
    book!(%{
      portfolio_id: portfolio.id,
      cash_account_id: from.id,
      counter_cash_account_id: to.id,
      type: "cash_transfer",
      date: date,
      gross_amount: amount,
      currency_code: from.currency_code
    })
  end

  # User story (FR-41, ADR-0051 §3):
  # As a local portfolio maintainer,
  # I want money I move between my own cash accounts to contribute nothing,
  # so that shifting cash from one account to another never reads as a
  # position earning or losing money.
  #
  # Acceptance criteria (ADR-0051 §3):
  # - A transfer between two accounts inside the scope, in EUR or in a
  #   foreign currency, is no external flow and changes no position's
  #   contribution.
  # - Its two legs cancel in the base currency, so every remainder line and
  #   the money result stay at 0, and the identity still holds.
  test "a cash transfer between own accounts contributes nothing" do
    %{world: world, usd: usd} = steady_world()

    %{cash: second_eur} =
      add_depot(world.portfolio, cash_name: "Cash EUR 2", depot_name: "Depot EUR 2")

    %{cash: second_usd} =
      add_depot(world.portfolio,
        cash_currency: "USD",
        cash_name: "Cash USD 2",
        depot_name: "Depot USD 2"
      )

    {:ok, before} = Contribution.for_portfolio(world.portfolio.id, period: "ytd", today: @today)

    transfer!(world.portfolio, world.cash, second_eur, "300", ~D[2026-02-02])
    transfer!(world.portfolio, usd.cash, second_usd, "250", ~D[2026-03-02])

    {:ok, moved} = Contribution.for_portfolio(world.portfolio.id, period: "ytd", today: @today)

    assert moved.positions == before.positions
    for position <- moved.positions, do: assert(zero?(position.contribution))
    assert_remainder_zero(moved)
    assert zero?(moved.totals.positions)
    assert zero?(moved.totals.result)
  end

  # User story (FR-41, ADR-0051 §6):
  # As the operator's agent asking about a view that was deleted meanwhile,
  # I want the contribution read to answer that the view is not found,
  # so that a stale view id costs me one round trip and never a crash.
  #
  # Acceptance criteria:
  # - An unknown view narrowing a portfolio, and an unknown view across
  #   every portfolio, are {:error, :view_not_found}.
  test "an unknown view is a not-found in both forms" do
    %{world: world} = steady_world()

    assert {:error, :view_not_found} =
             Contribution.for_portfolio(world.portfolio.id, view: 9_999_999, today: @today)

    assert {:error, :view_not_found} = Contribution.for_view(9_999_999, today: @today)
  end

  # User story (FR-41, ADR-0051 §5):
  # As a local portfolio maintainer,
  # I want the walk behind the contribution table to end today unless told
  # otherwise, valued in EUR across portfolios,
  # so that the table and the performance badge beside it speak about the
  # same days.
  #
  # Acceptance criteria:
  # - Without :today, the portfolio's and the view's windowed walks end on
  #   the host's today, and the window of a period ending today ends there.
  # - Without :base_currency, the walk across portfolios is valued in EUR.
  test "without a today the windowed walks end on the host's today" do
    %{world: world} = steady_world()

    first_day = Clock.today()
    portfolio = Performance.contribution_analysis(world.portfolio.id, :unscoped, "ytd")
    everything = Performance.view_contribution_analysis(nil, :unscoped, "ytd")
    last_day = Clock.today()

    for analysis <- [portfolio, everything] do
      assert analysis.today in [first_day, last_day]
      assert analysis.contribution.window.end == analysis.today
      assert List.last(analysis.daily).date == analysis.today
      assert analysis.base_currency == "EUR"
    end
  end
end
