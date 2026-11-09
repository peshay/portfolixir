defmodule Portfolixir.Portfolios.Performance.BandsTest do
  # I23, FR-53 (Sprint 27 S1): the performance walk keeps, per day, each held
  # security's value and the cash apart, so the value chart can be stacked.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, create_security!: 1, deposit!: 3, deposit!: 4]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Bands
  alias Portfolixir.Portfolios.Targets
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
    assert_walk_unmoved(w, @periods)

    # The stored walk keeps no window, so it never carries the days.
    refute Map.has_key?(Performance.analysis(w.world.portfolio.id, today: @today), :contribution)
  end

  # The pin of the walk's outputs (Sprint 27 S1, extended by Sprint 28 S3):
  # with the per-day terms kept, every other output is byte-identical to the
  # walk without them, and the per-day flows and basis steps the per-band
  # return reads add up to what the walk itself holds: each security's flows
  # over the window to its ADR-0051 net flows, each day's basis steps to the
  # day's basis step in the series.
  defp assert_walk_unmoved(w, periods) do
    for {scope, walk} <- kept_walks(w.world.portfolio.id, w.view.id),
        period <- periods,
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
          assert_days_add_up(kept, label)
      end
    end
  end

  defp assert_days_add_up(kept, label) do
    days = kept.contribution.days
    by_date = Map.new(kept.daily, &{&1.date, &1})

    for {date, day} <- days do
      assert Decimal.equal?(
               sum(Map.values(day.basis)),
               Map.get(Map.fetch!(by_date, date), :basis, Decimal.new("0"))
             ),
             "#{label} basis #{date}"
    end

    for {id, position} <- kept.contribution.positions do
      flows = days |> Map.values() |> Enum.map(&Map.get(&1.flows, id, Decimal.new("0")))
      assert Decimal.equal?(sum(flows), position.net_flows), "#{label} flows #{id}"
    end
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

  # -- the bands ------------------------------------------------------------------

  defp d(value), do: Decimal.new(value)

  # The tree "Strategy": Growth (the operator's colour), Income (no colour)
  # with its child Dividends. Alpha in Growth, Ucorp in Dividends, Beta in
  # Income; Ghost is filed nowhere.
  defp strategy!(w) do
    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})
    growth = category!(tree, "Growth", color: "#112233")
    income = category!(tree, "Income")
    dividends = category!(tree, "Dividends", parent_id: income.id)
    assign!(w.alpha, tree, growth)
    assign!(w.ucorp, tree, dividends)
    assign!(w.beta, tree, income)
    %{tree: tree, growth: growth, income: income, dividends: dividends}
  end

  defp category!(tree, name, opts \\ []) do
    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: name,
        color: Keyword.get(opts, :color),
        parent_id: Keyword.get(opts, :parent_id)
      })

    category
  end

  defp assign!(security, tree, category) do
    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), security.id, tree.id, category.id)
  end

  defp bands!(w, opts) do
    {:ok, result} =
      Bands.for_portfolio(w.world.portfolio.id, Keyword.merge([today: @today], opts))

    result
  end

  defp band(result, key), do: Enum.find(result.bands, &(&1.key == key))

  defp value_on(result, key, date) do
    index = Enum.find_index(result.dates, &(&1 == date))
    result |> band(key) |> Map.fetch!(:values) |> Enum.at(index)
  end

  # User story (I23, FR-53):
  # As a local portfolio maintainer,
  # I want the value chart split into bands by total, by category or by
  # security, each band's daily values adding up to the line,
  # so that I see what my wealth is made of without the line changing.
  #
  # Acceptance criteria:
  # - At every level, in the portfolio, the narrowed and the view forms, the
  #   bands' values sum exactly, day by day, to the performance read's series
  #   of the same period, and the bands' dates are the series' dates.
  # - The total level is one band: the series itself.
  # - A category stacked by its securities sums, day by day, to its band.
  test "on every day the bands sum exactly to the series' value, at every level" do
    w = bands_world()
    s = strategy!(w)
    pid = w.world.portfolio.id

    reads = [
      {"portfolio", &Bands.for_portfolio(pid, &1), &Performance.for_portfolio(pid, &1)},
      {"narrowed", &Bands.for_portfolio(pid, [view: w.view.id] ++ &1),
       &Performance.for_portfolio(pid, [view: w.view.id] ++ &1)},
      {"view", &Bands.for_view(w.view.id, &1), &Performance.for_view(w.view.id, &1)},
      {"Everything", &Bands.for_view(nil, &1), &Performance.for_view(nil, &1)}
    ]

    for {scope, bands_read, performance_read} <- reads,
        period <- @periods,
        level <- [:total, :category, :security] do
      label = "#{scope} #{inspect(period)} #{level}"
      opts = [period: period, today: @today]
      {:ok, performance} = performance_read.(opts)

      {:ok, result} =
        bands_read.(opts ++ [level: level, classification_id: s.tree.id])

      assert result.dates == Enum.map(performance.series, & &1.date), label

      for {point, index} <- Enum.with_index(performance.series) do
        day_sum = sum(Enum.map(result.bands, &Enum.at(&1.values, index)))
        assert Decimal.equal?(day_sum, point.value), label
      end

      if level == :total and performance.series != [] do
        assert [%{key: "total", values: values}] = result.bands
        assert values == Enum.map(performance.series, & &1.value), label
      end
    end

    category = bands!(w, period: "ytd", level: :category, classification_id: s.tree.id)

    assert Enum.map(category.bands, & &1.key) |> Enum.sort() ==
             Enum.sort([
               "cash",
               "category:#{s.growth.id}",
               "category:#{s.income.id}",
               "unclassified"
             ])

    # Income holds Ucorp through its child Dividends, and Beta directly.
    drilled = bands!(w, period: "ytd", level: :security, category_id: s.income.id)

    assert Enum.map(drilled.bands, & &1.key) |> Enum.sort() ==
             Enum.sort(["security:#{w.beta.id}", "security:#{w.ucorp.id}"])

    assert drilled.classification.chosen_by == :category

    for {date, index} <- Enum.with_index(drilled.dates) do
      day_sum = sum(Enum.map(drilled.bands, &Enum.at(&1.values, index)))
      assert Decimal.equal?(day_sum, value_on(category, "category:#{s.income.id}", date))
    end

    # The operator's colour rides along; a category without one has none.
    assert band(category, "category:#{s.growth.id}").color == "#112233"
    assert band(category, "category:#{s.income.id}").color == nil
  end

  # User story (I23, FR-53):
  # As a local portfolio maintainer,
  # I want a buy to show as a step in its own band and a security with no
  # price to count zero as the line counts it,
  # so that the stack tells composition honestly.
  #
  # Acceptance criteria:
  # - Alpha's band steps from 1000 (10 at 100) on 2026-03-01 to 1650 (15 at
  #   110) on 2026-03-02, the day 5 were bought; Beta's from 0 to 1000 on the
  #   day it was bought, 2026-02-02.
  # - Ghost, delivered on 2026-04-01 without a price and never quoted, is a
  #   band of zeros, every day, and the bands still sum to the line.
  test "a buy is a step in its band, and an unpriced day counts zero as the line does" do
    w = bands_world()
    r = bands!(w, period: "ytd", level: :security)
    alpha = "security:#{w.alpha.id}"
    beta = "security:#{w.beta.id}"
    ghost = "security:#{w.ghost.id}"

    assert Decimal.equal?(value_on(r, alpha, ~D[2026-03-01]), d("1000"))
    assert Decimal.equal?(value_on(r, alpha, ~D[2026-03-02]), d("1650"))
    assert Decimal.equal?(value_on(r, beta, ~D[2026-02-01]), d("0"))
    assert Decimal.equal?(value_on(r, beta, ~D[2026-02-02]), d("1000"))

    ghost_band = band(r, ghost)
    assert Enum.all?(ghost_band.values, &Decimal.equal?(&1, d("0")))
    assert ghost_band.change == nil

    {:ok, performance} =
      Performance.for_portfolio(w.world.portfolio.id, period: "ytd", today: @today)

    for {point, index} <- Enum.with_index(performance.series),
        Date.compare(point.date, ~D[2026-04-01]) != :lt do
      assert Decimal.equal?(sum(Enum.map(r.bands, &Enum.at(&1.values, index))), point.value)
    end
  end

  # User story (I23, FR-53; Sprint 27 plan D-5):
  # As a local portfolio maintainer,
  # I want a security I moved to another category to be drawn in the category
  # it has now, over the whole period,
  # so that the stack follows my classification as it is stored, without a
  # history it does not have.
  #
  # Acceptance criteria:
  # - Beta, filed under Income and then moved to Growth, is in Growth on every
  #   day of the window, also before the move, and Income no longer holds it.
  # - The basis says that a security is drawn in its category of today.
  test "a security that changed category is in its category of today for the whole window" do
    w = bands_world()
    s = strategy!(w)
    before = bands!(w, period: "ytd", level: :category, classification_id: s.tree.id)

    assign!(w.beta, s.tree, s.growth)
    now = bands!(w, period: "ytd", level: :category, classification_id: s.tree.id)

    growth = "category:#{s.growth.id}"
    income = "category:#{s.income.id}"

    for date <- now.dates do
      assert Decimal.equal?(
               value_on(now, growth, date),
               Decimal.add(value_on(before, growth, date), value_on(before, income, date))
               |> Decimal.sub(value_on(now, income, date))
             )
    end

    assert Decimal.equal?(value_on(now, growth, ~D[2026-02-02]), d("2000"))
    assert Decimal.equal?(value_on(before, growth, ~D[2026-02-02]), d("1000"))
    # Income keeps Ucorp alone: 5 at 80 USD at 0.8.
    assert Decimal.equal?(value_on(now, income, ~D[2026-02-02]), d("320"))
    assert now.computation_basis.category_change =~ "category of today"
  end

  # User story (I23, FR-53; Sprint 27 plan D-5):
  # As a local portfolio maintainer,
  # I want the band's change over the period without money moved in or out,
  # so that "Veränderung" says how the band did, not how much I added.
  #
  # Acceptance criteria:
  # - A security band's change is (end − start − net flows) / start, its net
  #   flows ADR-0051's: Alpha (1800 − 1000 − 550) / 1000 = 0.25; Ucorp
  #   (281.25 − 320) / 320 = −0.12109375.
  # - Without a start value the change is none: Beta and Ghost, not held at
  #   the baseline.
  # - The cash band's net flows are the scope's net external flows less the
  #   positions' net flows (−500 − 450 = −950), so its change is
  #   (8438 − 9480 + 950) / 9480; the total band's are the net external
  #   flows, (10519.25 − 10800 + 500) / 10800.
  # - The bands' money changes (end − start − net flows) sum exactly to the
  #   period's money result, 219.25.
  # - The share is the band's value over the bands' sum on the last day.
  test "each band's change without flows, and none without a start value" do
    w = bands_world()
    r = bands!(w, period: "ytd", level: :security)
    total = bands!(w, period: "ytd", level: :total)

    alpha = band(r, "security:#{w.alpha.id}")
    assert Decimal.equal?(alpha.start_value, d("1000"))
    assert Decimal.equal?(alpha.end_value, d("1800"))
    assert Decimal.equal?(alpha.net_flows, d("550"))
    assert Decimal.equal?(alpha.change, d("0.25"))

    assert Decimal.equal?(band(r, "security:#{w.ucorp.id}").change, d("-0.12109375"))
    assert band(r, "security:#{w.beta.id}").change == nil
    assert Decimal.equal?(band(r, "security:#{w.beta.id}").net_flows, d("-100"))

    cash = band(r, "cash")
    assert Decimal.equal?(cash.start_value, d("9480"))
    assert Decimal.equal?(cash.end_value, d("8438"))
    assert Decimal.equal?(cash.net_flows, d("-950"))
    assert Decimal.equal?(cash.change, Decimal.div(d("-92"), d("9480")))

    [whole] = total.bands
    assert Decimal.equal?(whole.start_value, d("10800"))
    assert Decimal.equal?(whole.end_value, d("10519.25"))
    assert Decimal.equal?(whole.change, Decimal.div(d("219.25"), d("10800")))
    assert Decimal.equal?(whole.share, d("1"))

    money =
      r.bands
      |> Enum.map(&(&1.end_value |> Decimal.sub(&1.start_value) |> Decimal.sub(&1.net_flows)))
      |> sum()

    assert Decimal.equal?(money, d("219.25"))
    assert Decimal.equal?(alpha.share, Decimal.div(d("1800"), d("10519.25")))

    # A window that starts with the history has no start value anywhere.
    first = bands!(w, period: {:range, ~D[2025-12-01], ~D[2025-12-31]}, level: :security)
    assert Enum.all?(first.bands, &(&1.change == nil))
  end

  # User story (I23, FR-53; Sprint 27 plan D-5):
  # As a local portfolio maintainer,
  # I want at most eight bands, the smallest merged into "other",
  # so that the chart stays readable, and the same data always draws the same
  # bands.
  #
  # Acceptance criteria:
  # - Nine securities and the cash are ten bands: the cash keeps its own, the
  #   six largest securities by value on the window's last day keep theirs,
  #   and the other three merge into other, eight bands in all.
  # - A tie on the last day's value is broken by name, never by id: Zulu
  #   (booked first, the smaller id) merges and Able keeps its band.
  # - other carries its members and sums them day by day.
  # - Sorted by size, the largest band comes first; by change, the largest
  #   change first and a band without one last.
  test "more than eight bands merge the smallest into other, ties by name, never by id" do
    world = base_world(name: "Many", cash_name: "Cash", depot_name: "Depot")
    deposit!(world, "10000", ~D[2025-12-01])

    holdings = [
      {"Zulu", "100"},
      {"Able", "100"},
      {"Big 1", "900"},
      {"Big 2", "800"},
      {"Big 3", "700"},
      {"Big 4", "600"},
      {"Big 5", "500"},
      {"Tiny 2", "20"},
      {"Tiny 1", "10"}
    ]

    securities =
      for {name, price} <- holdings, into: %{} do
        security = create_security!(name: name, ticker: nil)
        WorldFixtures.buy!(world, security, quantity: "1", price: price, date: ~D[2025-12-01])
        WorldFixtures.put_quote!(security, ~D[2025-12-01], price)
        {name, security}
      end

    assert securities["Zulu"].id < securities["Able"].id

    {:ok, r} =
      Bands.for_portfolio(world.portfolio.id, period: "ytd", today: @today, level: :security)

    keys = Enum.map(r.bands, & &1.key)
    assert length(keys) == 8
    assert "cash" in keys
    assert "security:#{securities["Able"].id}" in keys
    refute "security:#{securities["Zulu"].id}" in keys

    other = band(r, "other")
    assert Enum.map(other.members, & &1.name) == ["Zulu", "Tiny 2", "Tiny 1"]
    assert Enum.all?(other.values, &Decimal.equal?(&1, d("130")))

    # Size: cash 6270, then 900 down to Able's 100; other (130) on top of
    # the stack whatever its size (the closing act, D4).
    assert Enum.map(r.bands, & &1.name) ==
             ["Cash", "Big 1", "Big 2", "Big 3", "Big 4", "Big 5", "Able", "Other"]

    # A tie in value and name alike is no reason to look at an id: both merge.
    twin = create_security!(name: "Able", ticker: nil)
    WorldFixtures.buy!(world, twin, quantity: "1", price: "100", date: ~D[2025-12-01])
    WorldFixtures.put_quote!(twin, ~D[2025-12-01], "100")

    {:ok, twins} =
      Bands.for_portfolio(world.portfolio.id, period: "ytd", today: @today, level: :security)

    refute Enum.any?(twins.bands, &(&1.name == "Able"))
    assert Enum.count(band(twins, "other").members, &(&1.name == "Able")) == 2

    # By change, in the walk's world: Alpha 0.25, the cash -92/9480, Ucorp
    # -0.12109375, then Beta and Ghost, which have none, by name.
    w = bands_world()
    by_change = bands!(w, period: "ytd", level: :security, sort: :change)
    assert Enum.map(by_change.bands, & &1.name) == ["Alpha", "Cash", "Ucorp", "Beta", "Ghost"]
    assert by_change.sort == :change
  end

  # User story (I23, FR-53; Sprint 27 plan D-5):
  # As a local portfolio maintainer,
  # I want the category stack to follow the tree my allocation targets use
  # when I name none,
  # so that the chart and the drift table speak about the same categories.
  #
  # Acceptance criteria:
  # - Without a classification_id, the category level stacks by the tree of
  #   the scope's active target plan's categories (chosen_by targets).
  # - With no target in the scope, it stacks by the default steering tree,
  #   the first custom classification (chosen_by default).
  # - A requested tree is used as asked (chosen_by requested).
  # - The basis states the rule.
  test "the default classification is the one the allocation targets use, else the first tree" do
    w = bands_world()
    {:ok, first} = Classifications.create_classification(Actor.owner_ui(), %{name: "First"})
    s = strategy!(w)

    plain = bands!(w, period: "ytd", level: :category)
    assert plain.classification.id == first.id
    assert plain.classification.chosen_by == :default

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), w.world.portfolio.id, s.tree.id, [
        %{category_id: s.growth.id, target_weight: d("0.5")}
      ])

    targeted = bands!(w, period: "ytd", level: :category)
    assert targeted.classification.id == s.tree.id
    assert targeted.classification.chosen_by == :targets
    assert targeted.computation_basis.classification =~ "allocation targets"

    # The view's own plan is a different scope: it has no target there.
    {:ok, viewed} =
      Bands.for_portfolio(w.world.portfolio.id,
        period: "ytd",
        today: @today,
        level: :category,
        view: w.view.id
      )

    assert viewed.classification.id == first.id

    asked = bands!(w, period: "ytd", level: :category, classification_id: first.id)
    assert asked.classification.chosen_by == :requested
  end

  # User story (I23, FR-53):
  # As the operating agent,
  # I want a wrong level, sort or id refused by name,
  # so that I never read a stack I did not ask for.
  #
  # Acceptance criteria:
  # - An unknown level or sort, an unknown classification or category and a
  #   category of another tree are each an error naming it, at every level;
  #   an invalid period is the family's error.
  # - A category is a filter at every level (FR-56), so a category at the
  #   category or total level is no error any more; neither is the
  #   unclassified filter; any other filter value is refused.
  test "a wrong level, sort, tree or category is refused" do
    w = bands_world()
    s = strategy!(w)
    {:ok, other} = Classifications.create_classification(Actor.owner_ui(), %{name: "Other"})
    pid = w.world.portfolio.id

    assert {:error, :invalid_level} = Bands.for_portfolio(pid, level: :sector)
    assert {:error, :invalid_sort} = Bands.for_portfolio(pid, sort: :name)
    assert {:error, :invalid_period} = Bands.for_portfolio(pid, period: "2y")
    assert {:error, :classification_not_found} = Bands.for_portfolio(pid, classification_id: -1)

    for level <- [:total, :category, :security] do
      assert {:error, :category_not_found} =
               Bands.for_portfolio(pid, level: level, category_id: -1)

      assert {:error, :category_outside_classification} =
               Bands.for_portfolio(pid,
                 level: level,
                 category_id: s.growth.id,
                 classification_id: other.id
               )

      assert {:error, :invalid_category} =
               Bands.for_portfolio(pid, level: level, category_id: "none")

      assert {:ok, _} = Bands.for_portfolio(pid, level: level, category_id: s.growth.id)
      assert {:ok, _} = Bands.for_portfolio(pid, level: level, category_id: :unclassified)
    end

    assert {:error, :view_not_found} = Bands.for_view(-1, [])
  end

  # -- the bound when a quotient does not terminate (closing act, M2) ------------

  # Four USD securities and one EUR one in three categories, at EUR/USD
  # 1.0832, then 1.0917 from 2026-03-10: a USD value over these rates does
  # not terminate, so the walk rounds at Decimal's 34 significant digits.
  defp fx_world do
    world = base_world(name: "Dollar Bands", cash_name: "Cash EUR", depot_name: "Depot EUR")

    usd =
      world.portfolio
      |> add_depot(cash_currency: "USD", cash_name: "Cash USD", depot_name: "Depot USD")
      |> Map.put(:portfolio, world.portfolio)

    rate!("USD", ~D[2025-12-01], "1.0832")
    rate!("USD", ~D[2026-03-10], "1.0917")
    deposit!(world, "10000", ~D[2025-12-01])
    deposit!(usd, "5000", ~D[2025-12-01], currency: "USD")

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Regions"})
    [a, b, c] = Enum.map(~w(Alpha Beta Gamma), &category!(tree, &1))

    for {name, price, quantity, category, currency} <- [
          {"U1", "123.45", "7", a, "USD"},
          {"U2", "77.13", "11", b, "USD"},
          {"U3", "41.97", "3", c, "USD"},
          {"E1", "99.99", "13", a, "EUR"},
          {"U4", "250.01", "2", b, "USD"}
        ] do
      security = create_security!(name: name, currency: currency)
      into = if currency == "USD", do: usd, else: world

      WorldFixtures.buy!(into, security,
        quantity: quantity,
        price: price,
        date: ~D[2025-12-02],
        currency: currency
      )

      later = price |> Decimal.new() |> Decimal.add(Decimal.new("1.11")) |> Decimal.to_string()
      WorldFixtures.put_quotes!(security, [{~D[2025-12-02], price}, {~D[2026-02-02], later}])
      assign!(security, tree, category)
    end

    %{world: world, tree: tree}
  end

  # One unit in the 34th significant digit of `value`.
  defp last_unit(value) do
    value = Decimal.normalize(value)
    digits = value.coef |> Integer.digits() |> length()
    Decimal.new(1, 1, value.exp + digits - 1 - 33)
  end

  # User story (I23, FR-53; the closing act's money lens, M2):
  # As the operator's agent adding up the bands of a category stack in a
  # foreign currency,
  # I want the payload to say how far the sum may sit from the series, and
  # the sum to keep to it,
  # so that I do not mistake Decimal's rounding for a missing amount.
  #
  # Acceptance criteria:
  # - At the security and total levels the bands sum exactly to the series
  #   on every day, also when a USD value over 1.0832 or 1.0917 does not
  #   terminate.
  # - At the category level the sum is within one unit in the 34th
  #   significant digit of the day's value per band added.
  # - `computation_basis.input_series` and the module's documentation state
  #   that bound, and that it applies only at the category level and only
  #   when a quotient does not terminate.
  test "a category stack sums to the series within one unit in the 34th digit when FX does not terminate" do
    w = fx_world()
    pid = w.world.portfolio.id

    reads = [
      {"portfolio", &Bands.for_portfolio(pid, &1), &Performance.for_portfolio(pid, &1)},
      {"Everything", &Bands.for_view(nil, &1), &Performance.for_view(nil, &1)}
    ]

    for {scope, bands_read, performance_read} <- reads,
        level <- [:total, :category, :security] do
      opts = [period: "ytd", today: @today]
      {:ok, performance} = performance_read.(opts)
      {:ok, result} = bands_read.(opts ++ [level: level, classification_id: w.tree.id])
      assert performance.series != []

      for {point, index} <- Enum.with_index(performance.series) do
        day_sum = sum(Enum.map(result.bands, &Enum.at(&1.values, index)))
        label = "#{scope} #{level} #{point.date}"

        if level == :category do
          gap = day_sum |> Decimal.sub(point.value) |> Decimal.abs()
          bound = Decimal.mult(length(result.bands), last_unit(point.value))
          assert Decimal.compare(gap, bound) != :gt, label
        else
          assert Decimal.equal?(day_sum, point.value), label
        end
      end

      # The case is real: on some day the category sum is not exact.
      if level == :category do
        assert Enum.any?(Enum.with_index(performance.series), fn {point, index} ->
                 day_sum = sum(Enum.map(result.bands, &Enum.at(&1.values, index)))
                 not Decimal.equal?(day_sum, point.value)
               end)
      end

      assert result.computation_basis.input_series =~
               "at the category level, the bands' sum may differ from the series by at most " <>
                 "one unit in the 34th significant digit per band added"
    end

    {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Bands)
    assert moduledoc =~ "one unit in the 34th significant digit per band added"
    refute moduledoc =~ "significant digit per day"
  end

  # The closing act's money lens (ML3): six USD members over EUR/USD 1.0832
  # filed in three sub-categories of one category. The three filtered bands
  # each round their partial sums, and their sum lands three units in the
  # 34th significant digit from the category's band one level up: the bound
  # "one unit per day" was false; it is one unit per band added.
  #
  # User story: as the operator's agent adding up a filtered category's
  # bands, I want the stated bound to hold, so that a rounding difference
  # within it is never mistaken for a missing amount and one beyond it
  # always is.
  #
  # Acceptance criteria:
  # - The filtered bands' sum differs from the parent band by more than one
  #   unit in the 34th significant digit (the old bound fails).
  # - It stays within one unit per band added, and the basis says so.
  test "a filtered category's bands sum to the parent within one unit per band added" do
    rate!("USD", ~D[2026-01-02], "1.0832")

    world =
      base_world(name: "Bound", cash_name: "Cash", depot_name: "Depot", cash_currency: "USD")

    deposit!(world, "1000000", ~D[2026-01-02], currency: "USD")

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Bound"})
    top = category!(tree, "Top")
    subs = Map.new(1..3, &{&1, category!(tree, "Sub #{&1}", parent_id: top.id)})

    for {price, sub} <-
          Enum.zip([49_846, 78_810, 37_316, 77_793, 81_361, 73_701], [2, 1, 2, 3, 1, 3]) do
      security = create_security!(name: "S#{price}", currency: "USD")

      WorldFixtures.buy!(world, security,
        quantity: "1",
        price: "#{price}",
        date: ~D[2026-01-02],
        currency: "USD"
      )

      WorldFixtures.put_quotes!(security, [{~D[2026-01-02], "#{price}"}])
      assign!(security, tree, subs[sub])
    end

    opts = [
      period: {:range, ~D[2026-01-05], ~D[2026-01-09]},
      today: @today,
      classification_id: tree.id,
      level: :category
    ]

    {:ok, roots} = Bands.for_portfolio(world.portfolio.id, opts)
    parent = band(roots, "category:#{top.id}")
    {:ok, filtered} = Bands.for_portfolio(world.portfolio.id, opts ++ [category_id: top.id])
    assert length(filtered.bands) == 3

    for index <- 0..(length(parent.values) - 1) do
      expected = Enum.at(parent.values, index)
      day_sum = sum(Enum.map(filtered.bands, &Enum.at(&1.values, index)))
      gap = day_sum |> Decimal.sub(expected) |> Decimal.abs()
      unit = last_unit(expected)

      assert Decimal.gt?(gap, unit), "the old bound fails on day #{index}: #{gap}"
      assert Decimal.compare(gap, Decimal.mult(3, unit)) != :gt, "day #{index}: #{gap}"
    end

    assert filtered.computation_basis.input_series =~
             "within one unit in the 34th significant digit per band added"
  end

  # User story (I23, FR-53; the closing act's money lens, M4):
  # As the operator's agent drilling into a category that holds nothing in
  # this scope,
  # I want the answer to keep the window and its days, with no band,
  # so that I can tell "nothing filed here" from "no day in this window".
  #
  # Acceptance criteria:
  # - A drilled category with no security in scope answers the window's
  #   start_date, the series' dates and an empty bands list; the basis's
  #   window keeps its start date.
  # - A window holding no walked day still answers start_date nil and no
  #   dates.
  test "a drilled category with nothing in scope keeps the window's days" do
    w = bands_world()
    s = strategy!(w)
    dormant = category!(s.tree, "Dormant")

    {:ok, performance} =
      Performance.for_portfolio(w.world.portfolio.id, period: "ytd", today: @today)

    drilled = bands!(w, period: "ytd", level: :security, category_id: dormant.id)

    assert drilled.bands == []
    assert drilled.start_date == performance.start_date
    assert drilled.start_date != nil
    assert drilled.dates == Enum.map(performance.series, & &1.date)
    assert drilled.computation_basis.window.start_date == performance.start_date

    empty =
      bands!(w,
        period: {:range, ~D[2024-01-01], ~D[2024-06-30]},
        level: :security,
        category_id: dormant.id
      )

    assert {empty.start_date, empty.dates, empty.bands} == {nil, [], []}
  end

  # User story (I23, board 01 A; the closing act's design critic, D4):
  # As the operator reading a stack whose small positions add up to more
  # than any one band,
  # I want "Other" always on top of the stack, the last band of the answer,
  # so that the rest never sits at the base where the largest band belongs.
  #
  # Acceptance criteria:
  # - Fourteen positions of 100 and six of 150, with 1000 of cash: "Other"
  #   holds the fourteen, 1400, the largest band; by size it is still the
  #   last band, the others largest first; by change too.
  # - The basis's merge rule says so.
  test "other is always the last band, on top of the stack, whatever the sort" do
    world = base_world(name: "Crowd", cash_name: "Cash", depot_name: "Depot")
    deposit!(world, "3300", ~D[2025-12-01])

    holdings =
      for(k <- 1..6, do: {"Large #{k}", "150"}) ++
        for(k <- 1..14, do: {"Small #{String.pad_leading("#{k}", 2, "0")}", "100"})

    for {name, price} <- holdings do
      security = create_security!(name: name, ticker: nil)
      WorldFixtures.buy!(world, security, quantity: "1", price: price, date: ~D[2025-12-01])
      WorldFixtures.put_quote!(security, ~D[2025-12-01], price)
    end

    for sort <- [:size, :change] do
      {:ok, r} =
        Bands.for_portfolio(world.portfolio.id,
          period: "ytd",
          today: @today,
          level: :security,
          sort: sort
        )

      assert length(r.bands) == 8
      assert List.last(r.bands).key == "other", inspect(sort)
      assert Decimal.equal?(List.last(r.bands).end_value, d("1400"))

      assert r.computation_basis.merge_rule =~
               "other is always the last band, on top of the stack"

      if sort == :size do
        assert Enum.map(r.bands, & &1.name) ==
                 ["Cash"] ++ Enum.map(1..6, &"Large #{&1}") ++ ["Other"]
      end
    end
  end

  # -- the filter (FR-56, Sprint 28 S1) ------------------------------------------
  #
  # Invented figures only. One EUR-base portfolio with a EUR and a USD cash
  # account. EUR/USD 1.25, then 1.6 from 2026-04-30 (reciprocals 0.8 and
  # 0.625: every figure exact and computable by hand). The window is ytd,
  # 2026-01-01 to 2026-06-30, its baseline day 2025-12-31.
  #
  # The tree "Filter": Equity with the sub-categories Tech (with its own
  # sub-category Chips) and Value; Bonds without one. Direct Co is filed in
  # Equity itself, Soft AG in Tech itself, Chip Inc (USD) in Chips, Bank SE,
  # Ghost and Short Ltd in Value, Bund in Bonds; Loose plc nowhere. Soft AG
  # was first filed in Value and then re-filed in Tech (a category change).
  #
  #   2025-12-01  deposit 10000 EUR, 1000 USD; buy Direct Co 10 @ 100,
  #               Chip Inc 5 @ 80 USD, Bank SE 20 @ 50, Soft AG 4 @ 25,
  #               Loose plc 3 @ 10
  #   2026-02-02  buy Bund 10 @ 100                       (a buy)
  #   2026-02-10  buy Soft AG 4 @ 30                      (a buy)
  #   2026-03-02  sell Bank SE 20 @ 55                    (a sale)
  #   2026-04-01  inbound delivery Ghost 5, never quoted  (an unpriced day)
  #   2026-04-15  removal 12000 EUR; 2026-04-22 deposit 12000 EUR
  #               (the EUR cash negative for seven days)
  #   2026-05-11  sell Short Ltd 2 @ 40, held none: −2 until
  #   2026-05-20  buy Short Ltd 2 @ 45                    (a negative band)
  #
  # Quotes: Direct Co 100, 120 from 2026-03-02; Chip Inc 80, 96 USD from
  # 2026-05-04; Soft AG 25, 30 from 2026-02-10; Bank SE 50, 55 from
  # 2026-03-02; Short Ltd 40 from 2026-05-11, 45 from 2026-05-20; Bund 100;
  # Loose plc 10, 12 from 2026-06-01.
  defp filter_world do
    world = base_world(name: "Filter", cash_name: "Cash EUR", depot_name: "Depot EUR")

    usd =
      world.portfolio
      |> add_depot(cash_currency: "USD", cash_name: "Cash USD", depot_name: "Depot USD")
      |> Map.put(:portfolio, world.portfolio)

    rate!("USD", ~D[2025-12-01], "1.25")
    rate!("USD", ~D[2026-04-30], "1.6")
    deposit!(world, "10000", ~D[2025-12-01])
    deposit!(usd, "1000", ~D[2025-12-01], currency: "USD")

    [direct, soft, bank, ghost, short, bund, loose] =
      Enum.map(
        ["Direct Co", "Soft AG", "Bank SE", "Ghost", "Short Ltd", "Bund", "Loose plc"],
        &create_security!(name: &1, ticker: nil)
      )

    chip = create_security!(name: "Chip Inc", ticker: nil, currency: "USD")

    WorldFixtures.buy!(world, direct, quantity: "10", price: "100", date: ~D[2025-12-01])

    WorldFixtures.buy!(usd, chip,
      quantity: "5",
      price: "80",
      date: ~D[2025-12-01],
      currency: "USD"
    )

    WorldFixtures.buy!(world, bank, quantity: "20", price: "50", date: ~D[2025-12-01])
    WorldFixtures.buy!(world, soft, quantity: "4", price: "25", date: ~D[2025-12-01])
    WorldFixtures.buy!(world, loose, quantity: "3", price: "10", date: ~D[2025-12-01])
    WorldFixtures.buy!(world, bund, quantity: "10", price: "100", date: ~D[2026-02-02])
    WorldFixtures.buy!(world, soft, quantity: "4", price: "30", date: ~D[2026-02-10])
    WorldFixtures.sell!(world, bank, quantity: "20", price: "55", date: ~D[2026-03-02])

    book!(%{
      portfolio_id: world.portfolio.id,
      securities_account_id: world.depot.id,
      security_id: ghost.id,
      type: "inbound_delivery",
      date: ~D[2026-04-01],
      quantity: "5",
      currency_code: "EUR"
    })

    cash!(world, "removal", "12000", ~D[2026-04-15])
    deposit!(world, "12000", ~D[2026-04-22])
    WorldFixtures.sell!(world, short, quantity: "2", price: "40", date: ~D[2026-05-11])
    WorldFixtures.buy!(world, short, quantity: "2", price: "45", date: ~D[2026-05-20])

    WorldFixtures.put_quotes!(direct, [{~D[2025-12-01], "100"}, {~D[2026-03-02], "120"}])
    WorldFixtures.put_quotes!(chip, [{~D[2025-12-01], "80"}, {~D[2026-05-04], "96"}])
    WorldFixtures.put_quotes!(soft, [{~D[2025-12-01], "25"}, {~D[2026-02-10], "30"}])
    WorldFixtures.put_quotes!(bank, [{~D[2025-12-01], "50"}, {~D[2026-03-02], "55"}])
    WorldFixtures.put_quotes!(short, [{~D[2026-05-11], "40"}, {~D[2026-05-20], "45"}])
    WorldFixtures.put_quotes!(bund, [{~D[2026-02-02], "100"}])
    WorldFixtures.put_quotes!(loose, [{~D[2025-12-01], "10"}, {~D[2026-06-01], "12"}])

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Filter"})
    equity = category!(tree, "Equity", color: "#445566")
    tech = category!(tree, "Tech", parent_id: equity.id)
    chips = category!(tree, "Chips", parent_id: tech.id)
    value = category!(tree, "Value", parent_id: equity.id)
    bonds = category!(tree, "Bonds")

    assign!(direct, tree, equity)
    assign!(soft, tree, value)
    assign!(chip, tree, chips)
    assign!(bank, tree, value)
    assign!(ghost, tree, value)
    assign!(short, tree, value)
    assign!(bund, tree, bonds)
    # The category change: Soft AG moves from Value to Tech.
    assign!(soft, tree, tech)

    %{
      world: world,
      tree: tree,
      equity: equity,
      tech: tech,
      chips: chips,
      value: value,
      bonds: bonds,
      direct: direct,
      soft: soft,
      chip: chip,
      bank: bank,
      ghost: ghost,
      short: short,
      bund: bund,
      loose: loose
    }
  end

  defp filtered!(f, opts) do
    {:ok, result} =
      Bands.for_portfolio(
        f.world.portfolio.id,
        Keyword.merge([period: "ytd", today: @today, classification_id: f.tree.id], opts)
      )

    result
  end

  defp keys(result), do: result.bands |> Enum.map(& &1.key) |> Enum.sort()

  # The bands' sum on each date equals `parent`'s values, exactly; and their
  # start values and net flows add up to the parent's.
  defp assert_sums_to(result, parent, label) do
    assert result.dates != [], label

    for {_date, index} <- Enum.with_index(result.dates) do
      day = sum(Enum.map(result.bands, &Enum.at(&1.values, index)))
      assert Decimal.equal?(day, Enum.at(parent.values, index)), "#{label} day #{index}"
    end

    assert Decimal.equal?(sum(Enum.map(result.bands, & &1.start_value)), parent.start_value),
           label

    assert Decimal.equal?(sum(Enum.map(result.bands, & &1.net_flows)), parent.net_flows), label
  end

  # User story (FR-56, I29; Sprint 28 plan S1, D-1 criterion 7):
  # As a local portfolio maintainer whose classification has sub-categories,
  # I want a category filter to split the category into its direct
  # sub-categories, each over its subtree, and a band „‹name› (direkt)“ for
  # what is filed in the category itself,
  # so that I read a tree with several levels one level at a time, and the
  # parts always add up to the whole I clicked.
  #
  # Acceptance criteria:
  # - `category_id` at the category level answers one band per direct
  #   sub-category holding something (key `category:<id>`) plus one band of
  #   kind `direct` (key `direct:<id>`, the category's id and name, no
  #   colour) for the securities filed in the category itself; no cash, no
  #   unclassified.
  # - On every day the filtered bands sum exactly to the category's band of
  #   the read one level up: Equity's of the unfiltered read, Tech's of the
  #   read filtered by Equity; so do their start values and net flows.
  # - A category without sub-categories is one band, its own; so is the
  #   filter at the total level, „the filtered category's line“.
  # - Pinned by hand, with a buy, a sale, a re-filed security, an unpriced
  #   day, a negative cash day, a USD security and a band negative for nine
  #   days: on 2026-01-15 Direct Co 1000, Tech 320 + 100 = 420, Value 1000;
  #   on 2026-05-15 Direct Co 1200, Tech 300 + 240 = 540 (Chip Inc 5 × 96
  #   USD at 0.625), Value −80 (Short Ltd −2 × 40); on 2026-06-30 Value 0.
  test "a category filter's bands are its sub-categories and (direkt), summing to its band" do
    f = filter_world()
    top = filtered!(f, level: :category)
    equity_band = band(top, "category:#{f.equity.id}")

    # The parent read itself: Equity, Bonds, the cash and Loose plc.
    assert keys(top) ==
             Enum.sort([
               "cash",
               "unclassified",
               "category:#{f.equity.id}",
               "category:#{f.bonds.id}"
             ])

    # The negative cash days lie inside the window.
    assert Decimal.lt?(value_on(top, "cash", ~D[2026-04-15]), d("0"))

    equity = filtered!(f, level: :category, category_id: f.equity.id)

    assert keys(equity) ==
             Enum.sort([
               "category:#{f.tech.id}",
               "category:#{f.value.id}",
               "direct:#{f.equity.id}"
             ])

    assert equity.dates == top.dates
    assert_sums_to(equity, equity_band, "Equity")

    direct = band(equity, "direct:#{f.equity.id}")

    assert {direct.kind, direct.id, direct.name, direct.color} ==
             {:direct, f.equity.id, "Equity", nil}

    assert direct.members == []

    tech = "category:#{f.tech.id}"
    value = "category:#{f.value.id}"
    direct = "direct:#{f.equity.id}"

    for {date, expected} <- [
          {~D[2026-01-15], [{direct, "1000"}, {tech, "420"}, {value, "1000"}]},
          {~D[2026-03-02], [{direct, "1200"}, {tech, "560"}, {value, "0"}]},
          {~D[2026-05-15], [{direct, "1200"}, {tech, "540"}, {value, "-80"}]},
          {~D[2026-05-20], [{direct, "1200"}, {tech, "540"}, {value, "0"}]},
          {~D[2026-06-30], [{direct, "1200"}, {tech, "540"}, {value, "0"}]}
        ],
        {key, figure} <- expected do
      assert Decimal.equal?(value_on(equity, key, date), d(figure)), "#{key} #{date}"
    end

    # Value is negative on exactly the nine days Short Ltd is held short.
    negative =
      for date <- equity.dates, Decimal.lt?(value_on(equity, value, date), d("0")), do: date

    assert negative == Enum.map(0..8, &Date.add(~D[2026-05-11], &1))

    # Start values and flows of the window, by hand: Tech holds Chip Inc 320
    # and Soft AG 100 on the baseline day and buys 120; Value holds Bank SE
    # 1000, sells it for 1100, and goes short and back for −80 + 90.
    assert Decimal.equal?(band(equity, tech).start_value, d("420"))
    assert Decimal.equal?(band(equity, tech).net_flows, d("120"))
    assert Decimal.equal?(band(equity, value).start_value, d("1000"))
    assert Decimal.equal?(band(equity, value).net_flows, d("-1090"))
    assert Decimal.equal?(band(equity, direct).change, d("0.2"))

    # One level further down: Tech is Chips and Tech (direkt), summing to
    # Tech's band of the Equity read; Soft AG, re-filed, is in Tech's own
    # band on every day, also before the move.
    in_tech = filtered!(f, level: :category, category_id: f.tech.id)

    assert keys(in_tech) == Enum.sort(["category:#{f.chips.id}", "direct:#{f.tech.id}"])
    assert_sums_to(in_tech, band(equity, tech), "Tech")
    assert Decimal.equal?(value_on(in_tech, "direct:#{f.tech.id}", ~D[2026-01-15]), d("100"))
    assert Decimal.equal?(value_on(in_tech, "category:#{f.chips.id}", ~D[2026-05-15]), d("300"))
    assert Decimal.equal?(value_on(in_tech, "category:#{f.chips.id}", ~D[2026-01-15]), d("320"))

    # A category without sub-categories is one band, its own, at the
    # category level; Value's equals Value's band one level up, Bonds' its
    # band in the unfiltered read.
    for {category, parent} <- [
          {f.value, band(equity, value)},
          {f.chips, band(in_tech, "category:#{f.chips.id}")},
          {f.bonds, band(top, "category:#{f.bonds.id}")}
        ] do
      leaf = filtered!(f, level: :category, category_id: category.id)
      assert keys(leaf) == ["category:#{category.id}"], category.name
      assert_sums_to(leaf, parent, category.name)
      assert hd(leaf.bands).name == category.name
    end

    # With a filter, the total level is the filtered category's line: one
    # band, the category's, equal to its band one level up.
    for {category, parent} <- [{f.equity, equity_band}, {f.tech, band(equity, tech)}] do
      line = filtered!(f, level: :total, category_id: category.id)
      assert keys(line) == ["category:#{category.id}"], category.name
      assert hd(line.bands).values == parent.values, category.name
      assert Decimal.equal?(hd(line.bands).share, d("1"))
      assert_sums_to(line, parent, category.name)
    end

    # The securities level keeps its filter: Equity's securities, summing to
    # its band.
    securities = filtered!(f, level: :security, category_id: f.equity.id)

    assert keys(securities) ==
             Enum.sort(
               Enum.map(
                 [f.direct, f.soft, f.chip, f.bank, f.ghost, f.short],
                 &"security:#{&1.id}"
               )
             )

    assert_sums_to(securities, equity_band, "Equity's securities")
    # Ghost, never quoted, counts zero on every day.
    assert Enum.all?(band(securities, "security:#{f.ghost.id}").values, &Decimal.equal?(&1, 0))
  end

  # User story (FR-56, I29: „so sieht man, was fehlt“):
  # As a local portfolio maintainer,
  # I want „Nicht zugeordnet“ to be a filter as well,
  # so that I see which securities my tree files nowhere.
  #
  # Acceptance criteria:
  # - `category_id: :unclassified` at the securities level answers the
  #   securities the tree files nowhere, no cash; at the category and total
  #   levels one band, `unclassified`, equal day by day to the unclassified
  #   band of the unfiltered read.
  # - The read names the filter (`category_id`) and has no `category`.
  test "the unclassified remainder is a filter at every level" do
    f = filter_world()
    top = filtered!(f, level: :category)
    parent = band(top, "unclassified")

    securities = filtered!(f, level: :security, category_id: :unclassified)
    assert keys(securities) == ["security:#{f.loose.id}"]
    assert_sums_to(securities, parent, "securities")
    assert securities.category_id == :unclassified
    assert securities.category == nil

    for level <- [:category, :total] do
      result = filtered!(f, level: level, category_id: :unclassified)
      assert keys(result) == ["unclassified"], inspect(level)
      assert hd(result.bands).values == parent.values, inspect(level)
      assert_sums_to(result, parent, inspect(level))
    end

    # Loose plc: 3 at 10, then at 12.
    assert Decimal.equal?(value_on(top, "unclassified", ~D[2026-06-30]), d("36"))
  end

  # User story (FR-56; AGENTS.md metric rule):
  # As the operator's agent reading a filtered stack,
  # I want the basis to name the filter and the level it applies at,
  # so that I can tell a category's sub-categories from the whole scope.
  #
  # Acceptance criteria:
  # - `computation_basis.filter` names the category by name and id, or the
  #   unclassified remainder, or says there is none.
  # - `computation_basis.level` says what a band is under the filter: the
  #   direct sub-categories and (direkt), one band for a category without
  #   sub-categories, the filtered category's line at the total level.
  # - The exactness sentence names the parent band the filtered bands sum to.
  # - Without a filter, `category_id` is nil.
  test "the basis names the filter and its level" do
    f = filter_world()

    plain = filtered!(f, level: :category)
    assert plain.category_id == nil
    assert plain.computation_basis.filter =~ "none"

    equity = filtered!(f, level: :category, category_id: f.equity.id)
    assert equity.category_id == f.equity.id
    assert equity.computation_basis.filter =~ ~s("Equity" \(id #{f.equity.id}\))
    assert equity.computation_basis.level =~ "direct sub-category"
    assert equity.computation_basis.level =~ "kind direct"
    assert equity.computation_basis.level =~ "no cash"

    assert equity.computation_basis.input_series =~
             "with category_id, the bands sum to the filter's band one level up"

    leaf = filtered!(f, level: :category, category_id: f.bonds.id)
    assert leaf.computation_basis.level =~ "no sub-categories"

    line = filtered!(f, level: :total, category_id: f.equity.id)
    assert line.computation_basis.level =~ "the filtered category's line"

    loose = filtered!(f, level: :security, category_id: :unclassified)
    assert loose.computation_basis.filter =~ "unclassified"
    assert loose.computation_basis.level =~ "files nowhere"
  end

  # User story (FR-56; Sprint 28 plan D-8 carry-forward 5, the order lens):
  # As a local portfolio maintainer filtering a category with many
  # sub-categories,
  # I want at most eight bands, the smallest merged into „Sonstige“, and
  # the same bands merged however the tree was built,
  # so that the chart stays readable and the same data draws the same bands.
  #
  # Acceptance criteria:
  # - A filter with nine sub-categories and its own securities is ten
  #   bands: seven keep theirs, three merge into other; no band is fixed,
  #   since a filter has no cash and no unclassified.
  # - Which bands merge depends on the last day's value and the name, never
  #   on an id or on the order the categories were created in: the same
  #   holdings filed in two trees, one built in the reverse order of the
  #   other, merge the same names; at the cut, Kilo and Lima (equal values)
  #   are decided by name, Kilo kept.
  # - The bands still sum to the category's band every day.
  test "the eight-band merge applies inside a filter, independent of ids and order" do
    world = base_world(name: "Many", cash_name: "Cash", depot_name: "Depot")
    deposit!(world, "10000", ~D[2025-12-01])

    # Name, the security's price; "(own)" is filed in the filter itself.
    holdings = [
      {"Alfa", "900"},
      {"Bravo", "800"},
      {"Charlie", "700"},
      {"Delta", "600"},
      {"Echo", "500"},
      {"Kilo", "100"},
      {"Lima", "100"},
      {"Mike", "20"},
      {"November", "10"},
      {"(own)", "300"}
    ]

    securities =
      for {name, price} <- holdings, into: %{} do
        security = create_security!(name: "#{name} Co", ticker: nil)
        WorldFixtures.buy!(world, security, quantity: "1", price: price, date: ~D[2025-12-01])
        WorldFixtures.put_quote!(security, ~D[2025-12-01], price)
        {name, security}
      end

    names = holdings |> Enum.map(&elem(&1, 0)) |> Enum.reject(&(&1 == "(own)"))

    trees =
      for {label, order} <- [{"Forward", names}, {"Reverse", Enum.reverse(names)}] do
        {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: label})
        root = category!(tree, "Many")

        for name <- order do
          category = category!(tree, name, parent_id: root.id)
          assign!(securities[name], tree, category)
        end

        assign!(securities["(own)"], tree, root)
        {label, tree, root}
      end

    answers =
      for {label, tree, root} <- trees do
        {:ok, top} =
          Bands.for_portfolio(world.portfolio.id,
            period: "ytd",
            today: @today,
            level: :category,
            classification_id: tree.id
          )

        {:ok, r} =
          Bands.for_portfolio(world.portfolio.id,
            period: "ytd",
            today: @today,
            level: :category,
            category_id: root.id
          )

        assert length(r.bands) == 8, label
        refute Enum.any?(r.bands, &(&1.kind in [:cash, :unclassified])), label
        assert_sums_to(r, band(top, "category:#{root.id}"), label)

        other = band(r, "other")
        assert Enum.map(other.members, & &1.name) == ["Lima", "Mike", "November"], label
        assert Enum.all?(other.values, &Decimal.equal?(&1, d("130"))), label

        {label, Enum.map(r.bands, &{&1.kind, &1.name})}
      end

    [{_, forward}, {_, reverse}] = answers
    assert forward == reverse

    assert forward == [
             {:category, "Alfa"},
             {:category, "Bravo"},
             {:category, "Charlie"},
             {:category, "Delta"},
             {:category, "Echo"},
             {:direct, "Many"},
             {:category, "Kilo"},
             {:other, "Other"}
           ]
  end

  # User story (FR-56; the closing act's money lens, M2, kept):
  # As the operator's agent adding up a filtered stack in a foreign currency,
  # I want the filtered bands to keep to the bound the basis states,
  # so that I do not mistake Decimal's rounding for a missing amount.
  #
  # Acceptance criteria:
  # - With EUR/USD 1.0832 and 1.0917, whose quotients do not terminate, the
  #   bands of a filter with a sub-category and its own securities sum to
  #   the filter's band one level up within one unit in the 34th significant
  #   digit of that band's value, per day, at every level; at the category
  #   level some day is not exact, so the bound is exercised; at the total
  #   level the line is the band itself, exactly.
  test "a filtered stack keeps the bound when FX does not terminate" do
    w = fx_world()
    pid = w.world.portfolio.id
    [alpha | _] = w.tree.id |> Classifications.list_categories() |> Enum.sort_by(& &1.name)
    sub = category!(w.tree, "Alpha One", parent_id: alpha.id)
    named = Map.new(Portfolixir.Catalog.list_securities(), &{&1.name, &1})
    # Alpha holds E1, U1 and U3 itself, U2 and U4 through Alpha One.
    assign!(named["U2"], w.tree, sub)
    assign!(named["U4"], w.tree, sub)
    assign!(named["U1"], w.tree, alpha)
    assign!(named["U3"], w.tree, alpha)

    opts = [period: "ytd", today: @today]

    {:ok, top} =
      Bands.for_portfolio(pid, opts ++ [level: :category, classification_id: w.tree.id])

    parent = band(top, "category:#{alpha.id}")

    gaps =
      for level <- [:total, :category, :security],
          {:ok, r} = Bands.for_portfolio(pid, opts ++ [level: level, category_id: alpha.id]),
          {value, index} <- Enum.with_index(parent.values) do
        day = sum(Enum.map(r.bands, &Enum.at(&1.values, index)))
        gap = day |> Decimal.sub(value) |> Decimal.abs()
        assert Decimal.compare(gap, last_unit(value)) != :gt, "#{level} day #{index}"
        {level, gap}
      end

    # The case is real: at the category level, Alpha One and Alpha (direkt)
    # group the terms otherwise than Alpha's band, and some day rounds.
    assert Enum.any?(gaps, fn {level, gap} -> level == :category and Decimal.gt?(gap, 0) end)

    # The total level sums the same members in the same order: exact.
    assert Enum.all?(gaps, fn {level, gap} -> level != :total or Decimal.equal?(gap, 0) end)
  end

  # -- the per-band return (FR-57, Sprint 28 S3) ----------------------------------

  # Six window days, 2026-04-28 (D1) to 2026-05-03 (D6); the baseline is the
  # close of 2026-04-27. EUR/USD 1.25, then 1.6 from 2026-04-30 (D3), as in
  # the world above, so a USD value converts at 0.8, then 0.625: exact.
  @window {:range, ~D[2026-04-28], ~D[2026-05-03]}

  # Invented figures only. One EUR portfolio with a EUR and a USD depot.
  #
  #   2026-04-01  deposit 20000 EUR and 5000 USD; buy Alpha 10 @ 100, Bravo
  #               20 @ 50, Delta 5 @ 200, Ucorp 10 @ 80 USD (quotes the same)
  #   D1 04-28    inbound delivery Echo 10 @ 30 (priced)
  #   D2 04-29    sell Alpha 2 @ 150; buy Bravo 4 @ 50; sell Delta 5 @ 275
  #               (all of it); inbound delivery Ghost 5, no price
  #   D3 04-30    buy Charlie 10 @ 40; outbound delivery Echo 4, no price
  #   D4 05-01    buy Alpha 2 @ 120; buy Ucorp 2 @ 100 USD
  #
  # Closes (a trade day carries its own close):
  #
  #   Alpha   100 | 125 150 120 135  —  108
  #   Bravo    50 | 62.5 50 70 93.75 —  90
  #   Charlie   — |  —   —  44  55   —  49.5
  #   Delta   200 | 250 275  (sold out on D2)
  #   Echo      — |  30  36  45  —  40.5  —
  #   Ucorp USD 80| 100  —   —  100 128   —
  #   Ghost     — |  —   —   —  20   24   —
  #
  # The tree "Sleeves" files Alpha and Bravo under Core, Charlie under Late,
  # Delta under Exit, Echo under Gift, Ucorp under Dollar, Ghost under
  # Dormant.
  defp lines_world do
    world = base_world(name: "Lines", cash_name: "Cash EUR", depot_name: "Depot EUR")

    usd =
      world.portfolio
      |> add_depot(cash_currency: "USD", cash_name: "Cash USD", depot_name: "Depot USD")
      |> Map.put(:portfolio, world.portfolio)

    rate!("USD", ~D[2025-12-01], "1.25")
    rate!("USD", ~D[2026-04-30], "1.6")

    [alpha, bravo, charlie, delta, echo, ghost] =
      Enum.map(~w(Alpha Bravo Charlie Delta Echo Ghost), &create_security!(name: &1))

    ucorp = create_security!(name: "Ucorp", currency: "USD")
    start = ~D[2026-04-01]

    deposit!(world, "20000", start)
    deposit!(usd, "5000", start, currency: "USD")
    WorldFixtures.buy!(world, alpha, quantity: "10", price: "100", date: start)
    WorldFixtures.buy!(world, bravo, quantity: "20", price: "50", date: start)
    WorldFixtures.buy!(world, delta, quantity: "5", price: "200", date: start)
    WorldFixtures.buy!(usd, ucorp, quantity: "10", price: "80", date: start, currency: "USD")

    delivery!(world, echo, "inbound_delivery", "10", ~D[2026-04-28], "30")
    WorldFixtures.sell!(world, alpha, quantity: "2", price: "150", date: ~D[2026-04-29])
    WorldFixtures.buy!(world, bravo, quantity: "4", price: "50", date: ~D[2026-04-29])
    WorldFixtures.sell!(world, delta, quantity: "5", price: "275", date: ~D[2026-04-29])
    delivery!(world, ghost, "inbound_delivery", "5", ~D[2026-04-29], nil)
    WorldFixtures.buy!(world, charlie, quantity: "10", price: "40", date: ~D[2026-04-30])
    delivery!(world, echo, "outbound_delivery", "4", ~D[2026-04-30], nil)
    WorldFixtures.buy!(world, alpha, quantity: "2", price: "120", date: ~D[2026-05-01])

    WorldFixtures.buy!(usd, ucorp,
      quantity: "2",
      price: "100",
      date: ~D[2026-05-01],
      currency: "USD"
    )

    closes = [
      {alpha,
       [
         {start, "100"},
         {~D[2026-04-28], "125"},
         {~D[2026-04-29], "150"},
         {~D[2026-04-30], "120"},
         {~D[2026-05-01], "135"},
         {~D[2026-05-03], "108"}
       ]},
      {bravo,
       [
         {start, "50"},
         {~D[2026-04-28], "62.5"},
         {~D[2026-04-29], "50"},
         {~D[2026-04-30], "70"},
         {~D[2026-05-01], "93.75"},
         {~D[2026-05-03], "90"}
       ]},
      {charlie, [{~D[2026-04-30], "44"}, {~D[2026-05-01], "55"}, {~D[2026-05-03], "49.5"}]},
      {delta, [{start, "200"}, {~D[2026-04-28], "250"}, {~D[2026-04-29], "275"}]},
      {echo, [{~D[2026-04-28], "30"}, {~D[2026-04-29], "36"}, {~D[2026-04-30], "45"}]},
      {ucorp,
       [{start, "80"}, {~D[2026-04-28], "100"}, {~D[2026-05-01], "100"}, {~D[2026-05-02], "128"}]},
      {ghost, [{~D[2026-05-01], "20"}, {~D[2026-05-02], "24"}]}
    ]

    for {security, points} <- closes, do: WorldFixtures.put_quotes!(security, points)
    WorldFixtures.put_quote!(echo, ~D[2026-05-02], "40.5")

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Sleeves"})

    categories =
      for name <- ~w(Core Late Exit Gift Dollar Dormant), into: %{} do
        {name, category!(tree, name)}
      end

    for {security, name} <- [
          {alpha, "Core"},
          {bravo, "Core"},
          {charlie, "Late"},
          {delta, "Exit"},
          {echo, "Gift"},
          {ucorp, "Dollar"},
          {ghost, "Dormant"}
        ],
        do: assign!(security, tree, categories[name])

    %{
      world: world,
      view: view!([world.depot], [world.cash]),
      tree: tree,
      categories: categories,
      alpha: alpha,
      bravo: bravo,
      charlie: charlie,
      delta: delta,
      echo: echo,
      ucorp: ucorp,
      ghost: ghost
    }
  end

  defp delivery!(world, security, type, quantity, date, price) do
    book!(%{
      portfolio_id: world.portfolio.id,
      securities_account_id: world.depot.id,
      security_id: security.id,
      type: type,
      date: date,
      quantity: quantity,
      price: price,
      currency_code: "EUR"
    })
  end

  defp lines!(w, opts) do
    {:ok, result} =
      Bands.for_portfolio(
        w.world.portfolio.id,
        Keyword.merge([period: @window, today: @today, scale: :ttwror], opts)
      )

    result
  end

  defp same_line?(a, b) do
    length(a) == length(b) and
      Enum.all?(Enum.zip(a, b), fn
        {nil, nil} -> true
        {%Decimal{} = x, %Decimal{} = y} -> Decimal.equal?(x, y)
        _other -> false
      end)
  end

  # Each expected point a Decimal string or nil, compared exactly.
  defp assert_returns(line, expected, label) do
    assert length(line.returns) == length(expected), label

    for {{got, want}, index} <- Enum.with_index(Enum.zip(line.returns, expected)) do
      case want do
        nil -> assert got == nil, "#{label} D#{index + 1}: #{inspect(got)}"
        _ -> assert got != nil and Decimal.equal?(got, d(want)), "#{label} D#{index + 1}"
      end
    end
  end

  # User story (FR-57, I28; Sprint 28 plan S3, D-1 criterion 7):
  # As the operator's agent comparing how the parts of a view did,
  # I want each band's own time-weighted return over the window, its buys,
  # sells and deliveries as its flows,
  # so that a band's line says how its holdings did, not how much was added
  # to them or taken out.
  #
  # Acceptance criteria (each day's sub-period return r chained, by hand;
  # V the band's value at the day's close, F its day's net flow, B the
  # day's trade-price basis step; an inflow counts at the day's start,
  # 1 + r = V_d / (V_d−1 + F + B), an outflow at its end,
  # 1 + r = (V_d − F) / (V_d−1 + B)):
  # - Alpha, a buy and a partial sale, held at the baseline (V_0 = 10 × 100
  #   = 1000): D1 1250 / 1000 = 1.25; D2 sells 2 @ 150, F = −300:
  #   (8 × 150 + 300) / 1250 = 1.2; D3 960 / 1200 = 0.8; D4 buys 2 @ 120,
  #   F = +240: 10 × 135 / (960 + 240) = 1.125; D5 1; D6 1080 / 1350 = 0.8.
  #   Chained: 1.25, 1.5, 1.2, 1.35, 1.35, 1.08, so the line is 0.25, 0.5,
  #   0.2, 0.35, 0.35, 0.08 and its ttwror 0.08; its net flows −60.
  # - Charlie, bought into on D3 (10 @ 40, close 44): no point on D1 and D2,
  #   0 % on D3 (V 440), then 550 / 440 = 1.25, 1, 495 / 550 = 0.9: 0.25,
  #   0.25, 0.125.
  # - Delta, sold out on D2 (5 @ 275): 1250 / 1000 = 1.25, then
  #   (0 + 1375) / 1250 = 1.1: 0.25, 0.375, and the line ends at the sale
  #   day (no point on D3 to D6); ttwror 0.375, end value 0.
  # - Echo, delivered in on D1 (10 @ 30, F = +300) and 4 out on D3 without a
  #   price (F = −4 × 45 = −180): 0 % on D1 (V 300), 360 / 300 = 1.2,
  #   (270 + 180) / 360 = 1.25, 1, 243 / 270 = 0.9, 1: 0, 0.2, 0.5, 0.5,
  #   0.35, 0.35; net flows +120.
  # - Ucorp in USD, the walk's way (values at each day's rate, flows at the
  #   booking day's): V_0 = 800 × 0.8 = 640; D1 1000 × 0.8 = 800, 1.25; D2
  #   1; D3 1000 × 0.625 = 625, 0.78125; D4 buys 2 @ 100 USD, F = 200 ×
  #   0.625 = 125: 750 / (625 + 125) = 1; D5 1536 × 0.625 = 960, 1.28; D6 1.
  #   Chained: 0.25, 0.25, −0.0234375, −0.0234375, 0.25, 0.25.
  # - Ghost, delivered on D2 without a price and first quoted on D4: held
  #   but valued zero on D2 and D3 (the walk counts it zero), so no point;
  #   0 % on D4 (V 100), 120 / 100 = 1.2 on D5: nil, nil, nil, 0, 0.2, 0.2.
  # - The Everything form answers the same lines.
  # - Core, Alpha and Bravo, its flows the sum of theirs per day (D2
  #   −300 + 200 = −100, an outflow; D4 +240): V_0 2000; D1 2500 / 2000 =
  #   1.25; D2 (1200 + 1200 + 100) / 2500 = 1; D3 (960 + 1680) / 2400 = 1.1;
  #   D4 (1350 + 2250) / (2640 + 240) = 1.25; D5 1; D6 3240 / 3600 = 0.9.
  #   Chained: 0.25, 0.25, 0.375, 0.71875, 0.71875, 0.546875; net flows
  #   +140.
  test "each band's own TTWROR over the window, its trades and deliveries as its flows" do
    w = lines_world()
    r = lines!(w, level: :security)
    line = &band(r, "security:#{&1.id}")

    assert r.scale == :ttwror
    assert r.dates == Enum.map(0..5, &Date.add(~D[2026-04-28], &1))

    assert_returns(line.(w.alpha), ~w(0.25 0.5 0.2 0.35 0.35 0.08), "Alpha")
    assert Decimal.equal?(line.(w.alpha).ttwror, d("0.08"))
    assert Decimal.equal?(line.(w.alpha).net_flows, d("-60"))

    assert_returns(line.(w.charlie), [nil, nil, "0", "0.25", "0.25", "0.125"], "Charlie")
    assert Decimal.equal?(line.(w.charlie).ttwror, d("0.125"))

    assert_returns(line.(w.delta), ["0.25", "0.375", nil, nil, nil, nil], "Delta")
    assert Decimal.equal?(line.(w.delta).ttwror, d("0.375"))
    assert Decimal.equal?(line.(w.delta).end_value, d("0"))

    assert_returns(line.(w.echo), ~w(0 0.2 0.5 0.5 0.35 0.35), "Echo")
    assert Decimal.equal?(line.(w.echo).net_flows, d("120"))

    assert_returns(
      line.(w.ucorp),
      ~w(0.25 0.25 -0.0234375 -0.0234375 0.25 0.25),
      "Ucorp"
    )

    assert_returns(line.(w.ghost), [nil, nil, nil, "0", "0.2", "0.2"], "Ghost")

    c = lines!(w, level: :category, classification_id: w.tree.id)
    core = band(c, "category:#{w.categories["Core"].id}")
    assert_returns(core, ~w(0.25 0.25 0.375 0.71875 0.71875 0.546875), "Core")
    assert Decimal.equal?(core.ttwror, d("0.546875"))
    assert Decimal.equal?(core.net_flows, d("140"))

    # A band of one security is that security's line.
    assert band(c, "category:#{w.categories["Late"].id}").returns == line.(w.charlie).returns

    # The Everything form merges the portfolio's days, flows and basis steps:
    # the same lines.
    {:ok, everything} =
      Bands.for_view(nil, period: @window, today: @today, scale: :ttwror, level: :security)

    for band <- r.bands do
      assert same_line?(band(everything, band.key).returns, band.returns), band.name
    end
  end

  # User story (FR-57; Sprint 28 plan S3: "the walk's other outputs
  # byte-identical, pinned"):
  # As a local portfolio maintainer,
  # I want the per-band return to leave everything the walk already answers
  # untouched,
  # so that the line, the TTWROR, the IRR and the contribution stay exactly
  # what they were.
  #
  # Acceptance criteria:
  # - In a world with sales, a sell-out, deliveries in and out, a USD buy
  #   and two trade-price basis steps (Charlie's first quote on D3, Ghost's
  #   on D4), every walk output is byte-identical with and without the
  #   per-day terms, in every scope and period; each security's kept flows
  #   add up to its net flows, each day's kept basis steps to the series'.
  # - The value read is unchanged by the new scale: without scale and with
  #   scale value it answers the same.
  test "the per-band flows and basis steps move no other output of the walk" do
    w = lines_world()
    assert_walk_unmoved(w, [@window, "ytd", "max", {:range, ~D[2026-04-30], ~D[2026-05-01]}])

    kept =
      Performance.contribution_analysis(w.world.portfolio.id, :unscoped, @window,
        today: @today,
        from_baseline: true,
        bands: true
      )

    assert Decimal.equal?(kept.contribution.days[~D[2026-04-30]].basis[w.charlie.id], d("40"))
    assert Decimal.equal?(kept.contribution.days[~D[2026-05-01]].basis[w.ghost.id], d("100"))

    for level <- [:total, :category, :security] do
      opts = [period: @window, today: @today, level: level, classification_id: w.tree.id]
      {:ok, plain} = Bands.for_portfolio(w.world.portfolio.id, opts)
      {:ok, value} = Bands.for_portfolio(w.world.portfolio.id, [scale: :value] ++ opts)
      assert Map.delete(plain, :as_of) == Map.delete(value, :as_of), "#{level}"
      assert plain.scale == :value
    end
  end

  # User story (FR-57, I28):
  # As a local portfolio maintainer looking at the TTWROR mode,
  # I want at most eight lines, the largest bands at the window's end, and
  # the line of the level above beside them,
  # so that the chart stays readable and the view's own line is there to
  # compare with.
  #
  # Acceptance criteria:
  # - No band of kind cash, unclassified or other is a line, at any level
  #   without a filter; at the total level the one line is the view's own
  #   TTWROR, exactly the performance read's cumulative series.
  # - `parent` is the view's line without a filter, the filter's band with
  #   one (Core's line for category_id Core, at every level).
  # - The basis names the flows, the start rule, the selection rule and the
  #   gaps, and has no merge rule.
  test "the lines leave out cash and unclassified, and parent is the line one level up" do
    w = lines_world()
    loose = create_security!(name: "Loose")
    WorldFixtures.buy!(w.world, loose, quantity: "1", price: "50", date: ~D[2026-04-01])
    WorldFixtures.put_quote!(loose, ~D[2026-04-01], "50")

    {:ok, performance} =
      Performance.for_portfolio(w.world.portfolio.id, period: @window, today: @today)

    view_line = Enum.map(performance.series, & &1.cumulative_ttwror)

    for level <- [:total, :category, :security] do
      r = lines!(w, level: level, classification_id: w.tree.id)
      refute Enum.any?(r.bands, &(&1.kind in [:cash, :unclassified, :other])), "#{level}"
      assert same_line?(r.parent.returns, view_line), "#{level}"
      assert Decimal.equal?(r.parent.ttwror, performance.ttwror), "#{level}"
      refute Map.has_key?(r.computation_basis, :merge_rule)

      for key <- [:flows, :start_rule, :selection_rule, :gaps] do
        assert is_binary(Map.fetch!(r.computation_basis, key)), "#{level} #{key}"
      end
    end

    [total] = lines!(w, level: :total).bands
    assert same_line?(total.returns, view_line)

    core = w.categories["Core"]
    top = lines!(w, level: :category, classification_id: w.tree.id)

    for level <- [:total, :category, :security] do
      r = lines!(w, level: level, category_id: core.id)
      assert r.parent.returns == band(top, "category:#{core.id}").returns, "#{level}"
      assert r.parent.key == "category:#{core.id}"
    end

    assert lines!(w, level: :security, category_id: core.id).bands |> Enum.map(& &1.key) ==
             ["security:#{w.bravo.id}", "security:#{w.alpha.id}"]

    basis = top.computation_basis
    assert basis.flows =~ "net flows"
    assert basis.start_rule =~ "0 %"
    assert basis.selection_rule =~ "never by id"
    assert basis.gaps =~ "counts zero"
  end

  # User story (FR-57; Sprint 28 plan D-8 item 5, the order lens):
  # As the operator's agent,
  # I want the same lines whatever order the categories were created in,
  # so that which bands are drawn never depends on an id.
  #
  # Acceptance criteria:
  # - Ten categories, one security each, plus an unfiled security larger
  #   than all: the eight largest by value on the window's last day are
  #   drawn, equal values decided by name (Kilo 100 before Lima 100 and Mike
  #   100); two bands equal in value and name at the cut (Lima, Lima) are
  #   both left out, since only an id tells them apart; the unclassified
  #   remainder is no line. Seven lines, the same for a tree created
  #   forward and one created in reverse.
  # - sort change orders the lines by ttwror, largest first, equal ones by
  #   name: Charlie, Echo, Foxtrot and Kilo (25 %), Alfa and Delta (20 %),
  #   Bravo (0 %).
  test "which bands are lines depends on value and name, never on ids or order" do
    world = base_world(name: "Order", cash_name: "Cash", depot_name: "Depot")
    deposit!(world, "50000", ~D[2026-04-01])

    # Name, the close at the baseline (its price), the close on the window's
    # last day; the line's ttwror is their quotient less one.
    holdings = [
      {"Alfa", "750", "900"},
      {"Bravo", "800", "800"},
      {"Charlie", "560", "700"},
      {"Delta", "500", "600"},
      {"Echo", "400", "500"},
      {"Foxtrot", "320", "400"},
      {"Kilo", "80", "100"},
      {"Lima", "50", "100"},
      {"Lima", "40", "100"},
      {"Mike", "25", "100"}
    ]

    securities =
      for {{name, price, last}, index} <- Enum.with_index(holdings) do
        security = create_security!(name: "#{name} #{index}")
        WorldFixtures.buy!(world, security, quantity: "1", price: price, date: ~D[2026-04-01])
        WorldFixtures.put_quotes!(security, [{~D[2026-04-01], price}, {~D[2026-05-03], last}])
        {name, security}
      end

    zulu = create_security!(name: "Zulu")
    WorldFixtures.buy!(world, zulu, quantity: "1", price: "5000", date: ~D[2026-04-01])
    WorldFixtures.put_quote!(zulu, ~D[2026-04-01], "5000")

    answers =
      for {label, order} <- [{"Forward", securities}, {"Reverse", Enum.reverse(securities)}] do
        {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: label})

        for {name, security} <- order do
          assign!(security, tree, category!(tree, name))
        end

        {:ok, r} =
          Bands.for_portfolio(world.portfolio.id,
            period: @window,
            today: @today,
            scale: :ttwror,
            level: :category,
            classification_id: tree.id
          )

        {:ok, by_change} =
          Bands.for_portfolio(world.portfolio.id,
            period: @window,
            today: @today,
            scale: :ttwror,
            sort: :change,
            level: :category,
            classification_id: tree.id
          )

        refute Enum.any?(r.bands, &(&1.kind == :unclassified)), label
        {label, Enum.map(r.bands, & &1.name), Enum.map(by_change.bands, & &1.name)}
      end

    [{_, forward, forward_change}, {_, reverse, reverse_change}] = answers
    assert forward == reverse
    assert forward_change == reverse_change
    assert forward == ~w(Alfa Bravo Charlie Delta Echo Foxtrot Kilo)
    # Charlie, Echo, Foxtrot and Kilo gain 25 %, Alfa and Delta 20 %, Bravo
    # nothing; equal ones by name.
    assert forward_change == ~w(Charlie Echo Foxtrot Kilo Alfa Delta Bravo)
  end

  # User story (FR-57):
  # As the operator's agent,
  # I want a scale outside value and ttwror refused,
  # so that I never read lines I did not ask for.
  #
  # Acceptance criteria:
  # - `scale: :percent` is `{:error, :invalid_scale}`.
  test "a wrong scale is refused" do
    w = lines_world()

    assert Bands.for_portfolio(w.world.portfolio.id, scale: :percent, today: @today) ==
             {:error, :invalid_scale}

    assert Bands.for_view(nil, scale: "ttwror", today: @today) == {:error, :invalid_scale}
  end

  # The closing act's money lens (Sprint 28, D-8, ML1): a band whose value
  # is negative (a short) and is then covered by a buy.
  #
  # In the filter world Value holds Bank SE (1000 at the baseline, sold on
  # 2026-03-02 for 1100: +10 %) and Short Ltd, sold short 2 @ 40 on
  # 2026-05-11 (value −80) and covered 2 @ 45 on 2026-05-20 (value 0, an
  # inflow of 90). On the cover day the base V_prev + F = −80 + 90 = 10 is
  # positive only because the inflow nets against the negative opening
  # value; counted, the day's factor 0 / 10 = 0 collapsed the whole chain to
  # −100 %. A day whose opening value V_prev + B is not positive contributes
  # no return: the chain waits until the band is above zero again.
  #
  # User story: as the operator reading a category's bands as lines, I want
  # a short covered inside the window to leave the return its band earned
  # before, so that one cover does not paint the band as wiped out.
  #
  # Acceptance criteria:
  # - Value's line ends at +10 %, Bank SE's sale, exactly.
  # - Short Ltd's line ends at 0 %: it never opened a day above zero.
  # - The basis states the rule in gaps and start_rule.
  test "a short covered inside the window does not wipe out its band's line" do
    f = filter_world()

    equity =
      filtered!(f, level: :category, category_id: f.equity.id, scale: :ttwror)

    value = band(equity, "category:#{f.value.id}")
    assert Decimal.equal?(value.ttwror, d("0.1")), "Value ttwror #{value.ttwror}"
    assert equity.computation_basis.gaps =~ "opening value (V_prev + B) is not positive"
    assert equity.computation_basis.start_rule =~ "a day opening at or below zero adds no return"

    securities =
      filtered!(f, level: :security, category_id: f.value.id, scale: :ttwror)

    short = band(securities, "security:#{f.short.id}")
    assert Decimal.equal?(short.ttwror, d("0")), "Short Ltd ttwror #{short.ttwror}"
    assert Enum.all?(Enum.reject(short.returns, &is_nil/1), &Decimal.equal?(&1, d("0")))
  end
end
