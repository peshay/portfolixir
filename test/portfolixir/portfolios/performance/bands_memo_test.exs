defmodule Portfolixir.Portfolios.Performance.BandsMemoTest do
  # The stacked chart's bands under ADR-0039's memo (I34 step 1, Sprint 29
  # P1), with the derived layer ON (the test config keeps it off, so the
  # async engine suite never sees a hit). The memo table is global, hence
  # async: false.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, create_security!: 1, deposit!: 3, deposit!: 4]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Derived.Memo
  alias Portfolixir.Derived.Registry
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Fx
  alias Portfolixir.Portfolios.Performance.Bands
  alias Portfolixir.WorldFixtures

  @today ~D[2026-06-30]

  setup do
    Memo.reset()
    on_exit(&Memo.reset/0)
    DerivedConfig.enable!(lifetimes: [])
    :ok
  end

  # -- the synthetic world ------------------------------------------------------
  #
  # Invented figures only. One EUR-base portfolio with a EUR and a USD cash
  # account, each with its own depot; EUR/USD 1.25 (a reciprocal that
  # terminates, so every figure is exact). The tree "Strategy": Alpha in
  # Growth, Beta and Ucorp in Income.
  defp world! do
    world = base_world(name: "Bands memo", cash_name: "Cash EUR", depot_name: "Depot EUR")

    usd =
      world.portfolio
      |> add_depot(cash_currency: "USD", cash_name: "Cash USD", depot_name: "Depot USD")
      |> Map.put(:portfolio, world.portfolio)

    alpha = create_security!(name: "Alpha", ticker: "BMA")
    beta = create_security!(name: "Beta", ticker: "BMB")
    ucorp = create_security!(name: "Ucorp", ticker: "BMU", currency: "USD")

    rate!("USD", ~D[2025-12-01], "1.25")

    deposit!(world, "10000", ~D[2025-12-01])
    deposit!(usd, "1000", ~D[2025-12-01], currency: "USD")
    WorldFixtures.buy!(world, alpha, quantity: "10", price: "100", date: ~D[2025-12-01])
    WorldFixtures.buy!(world, beta, quantity: "20", price: "50", date: ~D[2026-02-02])

    WorldFixtures.buy!(usd, ucorp,
      quantity: "5",
      price: "80",
      date: ~D[2025-12-01],
      currency: "USD"
    )

    WorldFixtures.put_quotes!(alpha, [{~D[2025-12-01], "100"}, {~D[2026-03-02], "110"}])
    WorldFixtures.put_quotes!(beta, [{~D[2026-02-02], "50"}, {~D[2026-04-01], "55"}])
    WorldFixtures.put_quotes!(ucorp, [{~D[2025-12-01], "80"}, {~D[2026-06-01], "90"}])

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})
    growth = category!(tree, "Growth")
    income = category!(tree, "Income")
    assign!(alpha, tree, growth)
    assign!(beta, tree, income)
    assign!(ucorp, tree, income)

    %{
      world: world,
      alpha: alpha,
      beta: beta,
      tree: tree,
      growth: growth,
      income: income
    }
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

  defp category!(tree, name) do
    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: name
      })

    category
  end

  defp assign!(security, tree, category) do
    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), security.id, tree.id, category.id)
  end

  # -- reading the memo ----------------------------------------------------------

  defp entry_keys(analytic) do
    :ets.select(Memo, [{{{analytic, :_, :"$1", :_, :_}, :_, :_, :_}, [], [:"$1"]}])
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Marks every stored entry of `analytic` whose entry key matches: a read
  # that answers with the mark was served from the memo, one without it was
  # computed. The mark is how a hit is told from a recomputation.
  defp probe!(analytic, matches? \\ fn _entry_key -> true end) do
    for {{^analytic, _basis, entry_key, _version, _comp} = key, value, as_of, _stored} <-
          :ets.tab2list(Memo),
        matches?.(entry_key) do
      Memo.put(key, Map.put(value, :memo_probe, true), as_of)
    end

    :ok
  end

  defp probed?(result), do: Map.get(result, :memo_probe) == true

  # The two scopes a stack is read in: one portfolio, and the Everything
  # view across portfolios; each with the request the screen sends.
  defp read(w, :portfolio, opts) do
    {:ok, result} =
      Bands.for_portfolio(
        w.world.portfolio.id,
        Keyword.merge([today: @today, classification_id: w.tree.id], opts)
      )

    result
  end

  defp read(w, :everything, opts) do
    {:ok, result} =
      Bands.for_view(nil, Keyword.merge([today: @today, classification_id: w.tree.id], opts))

    result
  end

  defp fresh(w, scope, opts), do: DerivedConfig.with_layer_off(fn -> read(w, scope, opts) end)

  # Byte for byte, without `as_of`: the instant the walk was computed is the
  # one field a recomputation must move (a hit keeps its own, as the
  # contribution table's does).
  defp bytes(result),
    do: result |> Map.delete(:as_of) |> :erlang.term_to_binary([:deterministic])

  # -- the analytic --------------------------------------------------------------

  # User story (I34 step 1, Sprint 29 P1; ADR-0039 §2, FR-53):
  # As the operator switching periods on the stacked value chart,
  # I want the bands read served as its own derived value per scope, period
  # and request,
  # so that a period I already looked at is not walked a second time.
  #
  # Acceptance criteria:
  # - `performance_bands` (portfolio basis) and `performance_view_bands`
  #   (global basis) are registered with the default lifetime `:request`, at
  #   computation version 1 (no C3 activation).
  # - A fixed-period read is memoised under its analytic, keyed as the
  #   contribution table is (scope, walk end date, period, and the base
  #   currency across portfolios) plus the request's level, sort, scale,
  #   category and classification.
  # - A custom range, and a calendar year past today, are computed on every
  #   read and never remembered.
  test "the bands are their own request-lifetime analytic per scope, period and request" do
    assert Registry.computation_version!(:performance_bands) == 1
    assert Registry.computation_version!(:performance_view_bands) == 1
    assert Registry.lifetime(:performance_bands) == :request
    assert Registry.lifetime(:performance_view_bands) == :request

    w = world!()
    tree = w.tree.id

    read(w, :portfolio, period: "ytd")
    read(w, :portfolio, period: {:year, 2026}, level: :security, sort: :change)
    read(w, :portfolio, period: "1y", scale: :ttwror, category_id: w.income.id)
    read(w, :portfolio, period: "max", level: :total, category_id: :unclassified)
    read(w, :everything, period: "ytd")

    {:ok, _default} = Bands.for_portfolio(w.world.portfolio.id, period: "3y", today: @today)

    assert entry_keys(:performance_bands) == [
             "view=unscoped|today=2026-06-30|period=1y|level=category|sort=size|scale=ttwror" <>
               "|category=#{w.income.id}|classification=#{tree}",
             "view=unscoped|today=2026-06-30|period=3y|level=category|sort=size|scale=value" <>
               "|category=none|classification=default",
             "view=unscoped|today=2026-06-30|period=max|level=total|sort=size|scale=value" <>
               "|category=unclassified|classification=#{tree}",
             "view=unscoped|today=2026-06-30|period=year:2026|level=security|sort=change" <>
               "|scale=value|category=none|classification=#{tree}",
             "view=unscoped|today=2026-06-30|period=ytd|level=category|sort=size|scale=value" <>
               "|category=none|classification=#{tree}"
           ]

    assert entry_keys(:performance_view_bands) == [
             "view=unscoped|base=EUR|today=2026-06-30|period=ytd|level=category|sort=size" <>
               "|scale=value|category=none|classification=#{tree}"
           ]

    # The walk analytics and the contribution table are not filled by it.
    assert entry_keys(:performance_analysis) == []
    assert entry_keys(:performance_contribution) == []

    # A custom range and a year past today are computed, never remembered.
    before = entry_keys(:performance_bands)
    ranged = read(w, :portfolio, period: {:range, ~D[2026-02-01], ~D[2026-05-31]})
    future = read(w, :portfolio, period: {:year, 2027})
    assert ranged.start_date == ~D[2026-02-01]
    assert future.bands == []
    assert entry_keys(:performance_bands) == before

    probe!(:performance_bands)
    refute probed?(read(w, :portfolio, period: {:range, ~D[2026-02-01], ~D[2026-05-31]}))
  end

  # User story (I34 step 1, the owner's case of 2026-11-10):
  # As the operator looking at 3 years, then 1 year, then 3 years again,
  # I want the second look at 3 years served from what the first computed,
  # so that switching back to a period does not walk it again.
  #
  # Acceptance criteria:
  # - A switch back to a period already seen is a memo hit, in a portfolio
  #   and across portfolios.
  # - The hit equals a fresh read byte for byte.
  # - The same period under another request (another level) is its own
  #   entry, never served the first request's bands.
  test "a switch back to a period already seen is a hit" do
    w = world!()

    for scope <- [:portfolio, :everything] do
      three = read(w, scope, period: "3y")
      _one = read(w, scope, period: "1y")

      analytic = if scope == :portfolio, do: :performance_bands, else: :performance_view_bands
      probe!(analytic, &String.contains?(&1, "period=3y|"))

      again = read(w, scope, period: "3y")
      assert probed?(again), "#{scope}: the switch back to 3y walked again"
      assert bytes(Map.delete(again, :memo_probe)) == bytes(three)
      assert bytes(Map.delete(again, :memo_probe)) == bytes(fresh(w, scope, period: "3y"))

      refute probed?(read(w, scope, period: "1y"))
      refute probed?(read(w, scope, period: "3y", level: :security))
    end
  end

  # -- every write that moves the bands invalidates them --------------------------

  # The five kinds of write the plan names, each with the requests it moves
  # in the world above: a category change and a classification edit move the
  # category stack, never the security stack, which no tree groups.
  defp writes(w) do
    [
      {"a booking", :every,
       fn ->
         WorldFixtures.buy!(w.world, w.alpha, quantity: "4", price: "105", date: ~D[2026-05-04])
       end},
      {"a quote", :every,
       fn -> WorldFixtures.put_quotes!(w.alpha, [{~D[2026-06-15], "130"}]) end},
      {"a category change", :category, fn -> assign!(w.beta, w.tree, w.growth) end},
      {"an FX rate", :every, fn -> rate!("USD", ~D[2026-06-01], "1.6") end},
      {"a classification edit", :category,
       fn ->
         {:ok, _} =
           Classifications.update_category(Actor.owner_ui(), w.income, %{name: "Yield"})

         {:ok, _} =
           Classifications.update_classification(
             Actor.owner_ui(),
             Classifications.get_classification(w.tree.id),
             %{name: "Sleeves"}
           )
       end}
    ]
  end

  @requests [
    {:portfolio, [period: "ytd"]},
    {:portfolio, [period: "max", level: :security]},
    {:everything, [period: "ytd"]},
    {:everything, [period: "max", level: :security]}
  ]

  defp analytic(:portfolio), do: :performance_bands
  defp analytic(:everything), do: :performance_view_bands

  defp moves?(:every, _opts), do: true
  defp moves?(:category, opts), do: Keyword.get(opts, :level, :category) == :category

  # User story (I34 step 1, Sprint 29 P1; ADR-0039 §4 "versioned", §5 I4):
  # As the operator who just booked, priced, filed or renamed something,
  # I want the next stacked chart to show it,
  # so that a remembered chart is never older than my records.
  #
  # Acceptance criteria:
  # - Before each write, the repeated read is a hit (the memo is there to be
  #   invalidated).
  # - After a booking, a quote, a category change, an FX rate and a
  #   classification edit, the next read in a portfolio and across
  #   portfolios is not the remembered answer: it equals a fresh read, byte
  #   for byte, and differs from the answer before the write where the write
  #   moves that request.
  test "a memo hit equals a fresh read after every kind of write that moves the bands" do
    w = world!()

    for {label, moved, write} <- writes(w) do
      before =
        for {scope, opts} <- @requests, into: %{} do
          answer = read(w, scope, opts)
          probe!(analytic(scope))
          assert probed?(read(w, scope, opts)), "#{label}: the repeated read was not a hit"
          {{scope, opts}, answer}
        end

      write.()

      for {scope, opts} <- @requests do
        context = "#{label}, #{scope}, #{inspect(opts)}"
        after_write = read(w, scope, opts)

        refute probed?(after_write), "#{context}: a remembered answer outlived the write"
        assert bytes(after_write) == bytes(fresh(w, scope, opts)), context

        if moves?(moved, opts),
          do:
            refute(
              bytes(after_write) == bytes(before[{scope, opts}]),
              "#{context}: the write moved nothing"
            )
      end
    end
  end
end
