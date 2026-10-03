defmodule Portfolixir.Portfolios.Performance.ContributionTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, create_security!: 1, deposit!: 3, deposit!: 4]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Derived.Registry
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
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
  #   2025-10-01  transfer 40 Euro Fund from Depot A to Depot B
  #   2025-11-03  sell US Corp 4 @ 130 USD, fees 2 USD
  #   2025-12-01  removal 1000 EUR
  #   2026-01-15  interest 3 USD
  #   2026-02-02  tax refund 6 EUR; delivery Yen Co 100 @ 1000 JPY (no JPY rate)
  #   2026-04-01  dividend US Corp 8 USD
  #   2026-05-04  buy Flip Share 10 @ 20, fees 1 (never quoted)
  #   2026-05-15  balance snapshot Cash USD 1530 (a residual jump of 1 USD)
  #   2026-05-20  sell Flip Share 10 @ 25, fees 1
  #   2026-06-01  deposit 500 EUR
  #
  # The side portfolio deposits 1000 EUR and buys Euro Fund 5 @ 100 on
  # 2025-01-02. The view "Core" sees Depot A, Cash EUR and the side
  # portfolio's two accounts: Depot B and Cash USD are out of view.
  defp rich_world do
    rich = base_world(name: "Rich", cash_name: "Cash EUR", depot_name: "Depot A")

    usd =
      rich.portfolio
      |> add_depot(cash_currency: "USD", cash_name: "Cash USD", depot_name: "Depot B")
      |> Map.put(:portfolio, rich.portfolio)

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
      counter_securities_account_id: usd.depot.id,
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
    cash!(rich, "tax_refund", "6", ~D[2026-02-02])
    delivery!(rich, yen, "100", ~D[2026-02-02], price: "1000", currency: "JPY")
    cash!(usd, "dividend", "8", ~D[2026-04-01], security_id: us_corp.id, currency: "USD")
    WorldFixtures.buy!(rich, flip, quantity: "10", price: "20", fees: "1", date: ~D[2026-05-04])
    snapshot!(usd.cash, "1530", ~D[2026-05-15])
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

    view = core_view!([rich.depot, side.depot], [rich.cash, side.cash])

    %{
      rich: rich,
      usd: usd,
      side: side,
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

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Core", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [core.id], [])
    view
  end

  # -- I9 -------------------------------------------------------------------------

  # The four ways a walk is scoped: the portfolio, the portfolio narrowed by a
  # view, a view across all portfolios, and the Everything view. Each pairs the
  # plain walk with the walk that keeps the per-position figures apart.
  defp walk_pairs(world) do
    pid = world.rich.portfolio.id
    view = world.view.id

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

    for {scope, plain_walk, kept_walk} <- walk_pairs(world), period <- @periods do
      plain = plain_walk.()
      kept = kept_walk.(period)

      assert Map.has_key?(kept, :contribution), "#{scope} #{inspect(period)}"
      assert kept.daily == plain.daily, "#{scope} #{inspect(period)}"

      assert Map.drop(kept, [:contribution, :basis, :stale]) == Map.drop(plain, [:basis, :stale]),
             "#{scope} #{inspect(period)}"

      assert Map.delete(kept.basis, :computed_at) == Map.delete(plain.basis, :computed_at)

      {:ok, plain_summary} = Performance.summarise(plain, period)
      {:ok, kept_summary} = Performance.summarise(kept, period)

      assert Map.drop(kept_summary, [:as_of, :stale]) ==
               Map.drop(plain_summary, [:as_of, :stale]),
             "#{scope} #{inspect(period)}"

      # The figures really were kept wherever the window holds a walked day.
      assert is_map(kept.contribution) == not is_nil(plain_summary.start_date),
             "#{scope} #{inspect(period)}"

      if is_map(kept.contribution), do: assert(kept.contribution.positions != %{})
    end

    assert Registry.computation_version!(:performance_analysis) == 3
    assert Registry.computation_version!(:performance_view_analysis) == 3
  end
end
