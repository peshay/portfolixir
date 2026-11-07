defmodule Portfolixir.Portfolios.Performance.BandsTest do
  # I23, FR-53 (Sprint 27 S1): the performance walk keeps, per day, each held
  # security's value and the cash apart, so the value chart can be stacked.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, create_security!: 1, deposit!: 3, deposit!: 4]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.WorldFixtures

  @today ~D[2026-06-30]

  @periods [
    "max",
    "ytd",
    "1y",
    {:year, 2025},
    {:year, 2027},
    {:range, ~D[2026-02-01], ~D[2026-04-30]},
    {:range, ~D[2024-01-01], ~D[2024-06-30]}
  ]

  # -- the synthetic world ------------------------------------------------------
  #
  # Invented figures only. One EUR-base portfolio with a EUR and a USD cash
  # account, each with its own depot. EUR/USD 1.25, then 1.6 from
  # 2026-04-30: rates whose reciprocals terminate (0.8, 0.625), so every
  # figure is exact in Decimal and computable by hand.
  #
  #   2025-12-01  deposit 10000 EUR, deposit 1000 USD
  #               buy Alpha 10 @ 100 EUR; buy Ucorp 5 @ 80 USD (Cash USD)
  #   2026-02-02  buy Beta 20 @ 50 EUR
  #   2026-03-02  buy Alpha 5 @ 110 EUR
  #   2026-03-16  dividend Alpha 15 EUR
  #   2026-04-01  inbound delivery Ghost 5, no price, never quoted
  #   2026-05-04  sell Beta 20 @ 55, fees 2
  #   2026-05-15  removal 500 EUR
  #
  # Quotes: Alpha 100 (2025-12-01), 110 (2026-03-02), 120 (2026-06-01);
  # Beta 50 (2026-02-02), 55 (2026-04-01); Ucorp 80 (2025-12-01), 90
  # (2026-06-01).
  defp bands_world do
    world = base_world(name: "Bands", cash_name: "Cash EUR", depot_name: "Depot EUR")

    usd =
      world.portfolio
      |> add_depot(cash_currency: "USD", cash_name: "Cash USD", depot_name: "Depot USD")
      |> Map.put(:portfolio, world.portfolio)

    alpha = create_security!(name: "Alpha", ticker: "ALP")
    beta = create_security!(name: "Beta", ticker: "BET")
    ucorp = create_security!(name: "Ucorp", ticker: "UCO", currency: "USD")
    ghost = create_security!(name: "Ghost", ticker: "GHO")

    rate!("USD", ~D[2025-12-01], "1.25")
    rate!("USD", ~D[2026-04-30], "1.6")

    deposit!(world, "10000", ~D[2025-12-01])
    deposit!(usd, "1000", ~D[2025-12-01], currency: "USD")
    WorldFixtures.buy!(world, alpha, quantity: "10", price: "100", date: ~D[2025-12-01])

    WorldFixtures.buy!(usd, ucorp,
      quantity: "5",
      price: "80",
      date: ~D[2025-12-01],
      currency: "USD"
    )

    WorldFixtures.buy!(world, beta, quantity: "20", price: "50", date: ~D[2026-02-02])
    WorldFixtures.buy!(world, alpha, quantity: "5", price: "110", date: ~D[2026-03-02])
    cash!(world, "dividend", "15", ~D[2026-03-16], security_id: alpha.id)

    book!(%{
      portfolio_id: world.portfolio.id,
      securities_account_id: world.depot.id,
      security_id: ghost.id,
      type: "inbound_delivery",
      date: ~D[2026-04-01],
      quantity: "5",
      currency_code: "EUR"
    })

    WorldFixtures.sell!(world, beta, quantity: "20", price: "55", fees: "2", date: ~D[2026-05-04])
    cash!(world, "removal", "500", ~D[2026-05-15])

    WorldFixtures.put_quotes!(alpha, [
      {~D[2025-12-01], "100"},
      {~D[2026-03-02], "110"},
      {~D[2026-06-01], "120"}
    ])

    WorldFixtures.put_quotes!(beta, [{~D[2026-02-02], "50"}, {~D[2026-04-01], "55"}])
    WorldFixtures.put_quotes!(ucorp, [{~D[2025-12-01], "80"}, {~D[2026-06-01], "90"}])

    view = view!([world.depot], [world.cash])

    %{
      world: world,
      usd: usd,
      view: view,
      alpha: alpha,
      beta: beta,
      ucorp: ucorp,
      ghost: ghost
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

  # A view that sees the EUR depot and the EUR cash account only.
  defp view!(depots, cash_accounts) do
    {:ok, bucket} =
      Buckets.create_bucket(Actor.owner_ui(), %{
        name: "Bands #{System.unique_integer([:positive])}"
      })

    for depot <- depots,
        do: :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [bucket.id])

    for cash <- cash_accounts,
        do: :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [bucket.id])

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{
        name: "Bands #{System.unique_integer([:positive])}",
        include_all: false
      })

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])
    view
  end

  # The four ways a walk is scoped, each as the contribution walk with and
  # without the per-day values kept.
  defp kept_walks(pid, view) do
    [
      {"portfolio", &Performance.contribution_analysis(pid, :unscoped, &1, &2)},
      {"portfolio narrowed by a view",
       &Performance.contribution_analysis(pid, Buckets.load_scope(pid, view), &1, &2)},
      {"view across portfolios",
       &Performance.view_contribution_analysis(view, Buckets.load_global_scope(view), &1, &2)},
      {"Everything view", &Performance.view_contribution_analysis(nil, :unscoped, &1, &2)}
    ]
  end

  defp sum(decimals), do: Enum.reduce(decimals, Decimal.new("0"), &Decimal.add/2)

  # -- the walk keeps each day's values apart -----------------------------------

  # User story (I23, FR-53; ADR-0051 §5 as precedent):
  # As a local portfolio maintainer,
  # I want the performance walk to keep each held security's value and the
  # cash apart on every day of a period without changing anything it already
  # computes,
  # so that the value chart can be split into bands while the line, the
  # TTWROR, the IRR and the contribution table stay exactly what they were.
  #
  # Acceptance criteria:
  # - With the per-day values kept, the walk's daily series, every summary
  #   chained from it (TTWROR, IRR, MWR, values, flows) and the contribution's
  #   kept positions and lines are byte-identical to the walk without them,
  #   for every period and every scope, from the first booking and from the
  #   window's baseline day.
  # - The walk without a window is the stored walk, unchanged.
  test "keeping each day's values moves no other output of the walk" do
    w = bands_world()

    for {scope, walk} <- kept_walks(w.world.portfolio.id, w.view.id),
        period <- @periods,
        from_baseline <- [false, true] do
      label = "#{scope} #{inspect(period)} from_baseline=#{from_baseline}"
      opts = [today: @today, from_baseline: from_baseline]
      plain = walk.(period, opts)
      kept = walk.(period, Keyword.put(opts, :bands, true))

      assert kept.daily == plain.daily, label

      assert Map.drop(kept, [:contribution, :basis, :stale]) ==
               Map.drop(plain, [:contribution, :basis, :stale]),
             label

      {:ok, plain_summary} = Performance.summarise(plain, period)
      {:ok, kept_summary} = Performance.summarise(kept, period)

      assert Map.drop(kept_summary, [:as_of, :stale]) ==
               Map.drop(plain_summary, [:as_of, :stale]),
             label

      case plain.contribution do
        nil ->
          assert kept.contribution == nil, label

        contribution ->
          assert Map.take(kept.contribution, [:positions, :lines, :securities, :baseline]) ==
                   Map.take(contribution, [:positions, :lines, :securities, :baseline]),
                 label

          assert Map.delete(kept.contribution.window, :bands) == contribution.window, label

          refute Map.has_key?(contribution, :days), label
          assert is_map(kept.contribution.days), label
      end
    end

    # The stored walk keeps no window, so it never carries the days.
    refute Map.has_key?(Performance.analysis(w.world.portfolio.id, today: @today), :contribution)
  end

  # User story (I23, FR-53):
  # As a local portfolio maintainer,
  # I want the bands of the stacked chart to add up to the line I see today,
  # so that splitting the chart never changes what it says my wealth is.
  #
  # Acceptance criteria:
  # - On every day of the window, each held security's kept value plus the
  #   kept cash is exactly the series' value of that day, in every scope.
  # - The kept days are exactly the series' days.
  # - The cash kept on the baseline day plus the positions' start values is
  #   the period's start value.
  test "on every day the kept securities and the cash sum exactly to the series" do
    w = bands_world()

    for {scope, walk} <- kept_walks(w.world.portfolio.id, w.view.id),
        period <- @periods do
      label = "#{scope} #{inspect(period)}"
      kept = walk.(period, today: @today, from_baseline: true, bands: true)
      {:ok, summary} = Performance.summarise(kept, period)

      case kept.contribution do
        nil ->
          assert summary.series == [], label

        %{days: days} = contribution ->
          assert Enum.sort(Map.keys(days), Date) == Enum.map(summary.series, & &1.date), label

          for point <- summary.series do
            day = Map.fetch!(days, point.date)

            assert Decimal.equal?(sum([day.cash | Map.values(day.securities)]), point.value),
                   label
          end

          start =
            contribution.positions
            |> Map.values()
            |> Enum.map(& &1.start_value)
            |> then(&sum([contribution.cash_start | &1]))

          assert Decimal.equal?(start, summary.start_value), label
      end
    end
  end
end
