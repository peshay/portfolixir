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

    # Size: cash 6270, then 900 down to Able's 100, and other's 130 between.
    assert Enum.map(r.bands, & &1.name) ==
             ["Cash", "Big 1", "Big 2", "Big 3", "Big 4", "Big 5", "Other", "Able"]

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
  # - An unknown level or sort, an unknown classification or category, a
  #   category of another tree and a category without the security level are
  #   each an error naming it; an invalid period is the family's error.
  test "a wrong level, sort, tree or category is refused" do
    w = bands_world()
    s = strategy!(w)
    {:ok, other} = Classifications.create_classification(Actor.owner_ui(), %{name: "Other"})
    pid = w.world.portfolio.id

    assert {:error, :invalid_level} = Bands.for_portfolio(pid, level: :sector)
    assert {:error, :invalid_sort} = Bands.for_portfolio(pid, sort: :name)
    assert {:error, :invalid_period} = Bands.for_portfolio(pid, period: "2y")
    assert {:error, :classification_not_found} = Bands.for_portfolio(pid, classification_id: -1)

    assert {:error, :category_not_found} =
             Bands.for_portfolio(pid, level: :security, category_id: -1)

    assert {:error, :category_outside_classification} =
             Bands.for_portfolio(pid,
               level: :security,
               category_id: s.growth.id,
               classification_id: other.id
             )

    assert {:error, :category_needs_security_level} =
             Bands.for_portfolio(pid, level: :category, category_id: s.growth.id)

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
  #   significant digit of the day's value, per day.
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
          assert Decimal.compare(gap, last_unit(point.value)) != :gt, label
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
                 "one unit in the 34th significant digit per day"
    end

    {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Bands)
    assert moduledoc =~ "one unit in the 34th significant digit"
  end
end
