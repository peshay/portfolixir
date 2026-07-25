defmodule Portfolixir.Portfolios.Performance.TradePriceBasisTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios.Performance

  defp gain(result) do
    result.end_value
    |> Decimal.sub(result.start_value)
    |> Decimal.sub(result.net_external_flows)
  end

  # User story (issue #545):
  # As a local portfolio maintainer holding a security without quote history,
  # I want the day a new trade re-prices my existing position to be treated as
  # a valuation-basis step rather than a one-day market return,
  # so that my headline TTWROR degrades gracefully into "no measurable market
  # return" instead of exploding into a four-digit percentage.
  #
  # Acceptance criteria:
  # - Buys at 100 -> 1,000 -> 8,000 across four years no longer compound into a
  #   spurious return; the trade-price steps are neutralised exactly.
  # - end_value / net_external_flows (and therefore the #336 EUR-gain badge)
  #   keep reporting the unchanged money facts.
  #
  # Pre-fix characterisation (the magnitude of the bug, on record): the same
  # fixture chained 5.5 (the 2022 step) x 4.85 (the 2024 step) = 26.675 growth,
  # i.e. a TTWROR of 25.675 -> +2,567.5 %, with no market data behind it.
  test "an unquoted position re-priced by later buys yields no spurious return" do
    world = unquoted_world()

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2024-06-28])

    assert Decimal.equal?(result.ttwror, Decimal.new("0"))

    # The money facts are untouched by the fix.
    assert Decimal.equal?(result.start_value, Decimal.new("0"))
    assert Decimal.equal?(result.end_value, Decimal.new("97000"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("11000"))
    assert Decimal.equal?(gain(result), Decimal.new("86000"))

    # Every day of the four-year walk chains a factor of exactly 1.
    assert Enum.all?(result.series, &Decimal.equal?(&1.cumulative_ttwror, Decimal.new("0")))
  end

  # User story (issue #545, over-neutralisation guard):
  # As a local portfolio maintainer who finally sells an unquoted holding,
  # I want the sale to convert the position into real cash at the sale price
  # and count as return,
  # so that neutralising the mark-to-model step never swallows a realised gain.
  #
  # Acceptance criteria:
  # - A full sale at 10x the buy price yields a TTWROR of exactly 9.
  # - A partial sale counts the sold slice and neutralises only the slice still
  #   held at the end of the day.
  test "selling an unquoted position realises the gain as return" do
    world = base_world(name: "SL", cash_name: "SL Cash", depot_name: "SL Depot")
    security = create_security!(name: "Sold Co", ticker: "SLD")

    deposit!(world, "1000", ~D[2020-01-02])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2020-01-02])
    sell!(world, security, quantity: "10", price: "1000", date: ~D[2022-01-03])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2022-06-30])

    assert Decimal.equal?(result.ttwror, Decimal.new("9"))
    assert Decimal.equal?(result.end_value, Decimal.new("10000"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("1000"))
  end

  test "a partial sale counts the sold slice and neutralises the retained slice" do
    world = base_world(name: "PS", cash_name: "PS Cash", depot_name: "PS Depot")
    security = create_security!(name: "Part Co", ticker: "PRT")

    deposit!(world, "1000", ~D[2020-01-02])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2020-01-02])
    sell!(world, security, quantity: "4", price: "1000", date: ~D[2022-01-03])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2022-06-30])

    # Value 6 x 1000 + 4000 cash = 10000 over a base of 1000 + 6 x (1000 - 100)
    # = 6400 -> 1.5625.
    assert Decimal.equal?(result.ttwror, Decimal.new("0.5625"))
    assert Decimal.equal?(result.end_value, Decimal.new("10000"))
  end

  # User story (issue #545 AC 3):
  # As a local portfolio maintainer whose portfolio mixes quoted and unquoted
  # holdings,
  # I want only the unquoted re-pricing steps neutralised,
  # so that the real market move of my quoted position still shows up in the
  # headline figure.
  #
  # Acceptance criteria:
  # - The quoted leg's +20 % move is the only return in the period.
  # - The unquoted leg's 100 -> 1,000 trade step contributes nothing.
  test "mixed portfolio: quoted moves count, unquoted trade-price steps do not" do
    world = base_world(name: "MI", cash_name: "MI Cash", depot_name: "MI Depot")
    quoted = create_security!(name: "Quoted Co", ticker: "MIQ")
    unquoted = create_security!(name: "Unquoted Co", ticker: "MIU")

    deposit!(world, "2000", ~D[2026-01-01])
    put_quote!(quoted, ~D[2026-01-01], "100")
    buy!(world, quoted, quantity: "10", price: "100", date: ~D[2026-01-01])
    buy!(world, unquoted, quantity: "10", price: "100", date: ~D[2026-01-01])

    put_quote!(quoted, ~D[2026-01-10], "120")

    deposit!(world, "1000", ~D[2026-01-20])
    buy!(world, unquoted, quantity: "1", price: "1000", date: ~D[2026-01-20])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-31])

    # Only the quoted leg moved: 2000 -> 2200 on 01-10. The 01-20 buy re-prices
    # the 10 already-held unquoted units (9000 basis step), which is neutralised.
    assert Decimal.equal?(result.ttwror, Decimal.new("0.1"))
    assert Decimal.equal?(result.end_value, Decimal.new("12200"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("3000"))
  end

  # User story (issue #545 AC 2):
  # As a local portfolio maintainer holding a security with quote history,
  # I want the trade-price basis fix to leave my TTWROR untouched,
  # so that hardening the unquoted case never silently rewrites a figure that
  # was already derived from real market data.
  #
  # Acceptance criteria:
  # - Buys and sells on days WITHOUT a quote still re-price the position from
  #   the last known market price and still count as return.
  # - The chained TTWROR is the exact same Decimal as before the fix.
  test "quoted portfolio: off-quote trade days still count as return (byte-identical TTWROR)" do
    world = base_world(name: "QO", cash_name: "QO Cash", depot_name: "QO Depot")
    security = create_security!(name: "Quoted Co", ticker: "QOC")

    put_quote!(security, ~D[2026-01-01], "100")
    deposit!(world, "1000", ~D[2026-01-01])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-01])

    # No quote on 01-05: the buy price is the day's price observation and the
    # step from the last quote (100 -> 200) is a genuine market move.
    deposit!(world, "1000", ~D[2026-01-05])
    buy!(world, security, quantity: "5", price: "200", date: ~D[2026-01-05])

    put_quote!(security, ~D[2026-01-10], "240")

    # No quote on 01-20 either: a sell re-prices 240 -> 300.
    sell!(world, security, quantity: "5", price: "300", date: ~D[2026-01-20])

    put_quote!(security, ~D[2026-01-31], "390")

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-31])

    # 1.5 x 1.2 x 1.25 x 1.2 = 2.7 growth.
    assert Decimal.equal?(result.ttwror, Decimal.new("1.7"))
    assert Decimal.equal?(result.end_value, Decimal.new("5400"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("2000"))
  end

  # User story (issue #545 composed with ADR-0028 §2/§3):
  # As a local portfolio maintainer whose unquoted holding was split,
  # I want the trade-price basis step measured in the day's own post-split
  # basis,
  # so that the split rescale and the re-pricing neutralisation cannot
  # double-count or fight each other.
  #
  # Acceptance criteria:
  # - The split day itself carries no basis step (the rescale and the quantity
  #   scale already cancel) and no return.
  # - A later buy at the post-split price compares against the rescaled carried
  #   price, so the re-pricing of the 100 post-split units is neutralised.
  test "an unquoted position keeps a flat TTWROR across a split and a later buy" do
    world = base_world(name: "SP", cash_name: "SP Cash", depot_name: "SP Depot")
    security = create_security!(name: "Split Co", ticker: "SPC")

    deposit!(world, "1000", ~D[2026-01-05])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])

    {:ok, _rows} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2026-01-07],
        ratio_numerator: 10,
        ratio_denominator: 1
      })

    # Post-split units: 100 carried at 10, a new buy observes 20.
    deposit!(world, "20", ~D[2026-01-09])
    buy!(world, security, quantity: "1", price: "20", date: ~D[2026-01-09])

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-09])

    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
    assert Decimal.equal?(result.end_value, Decimal.new("2020"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("1020"))
  end

  defp unquoted_world do
    world = base_world(name: "TP", cash_name: "TP Cash", depot_name: "TP Depot")
    security = create_security!(name: "Unquoted Co", ticker: "UNQ")

    deposit!(world, "1000", ~D[2020-01-02])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2020-01-02])

    deposit!(world, "1000", ~D[2022-01-03])
    buy!(world, security, quantity: "1", price: "1000", date: ~D[2022-01-03])

    deposit!(world, "9000", ~D[2024-01-02])
    buy!(world, security, quantity: "1", price: "8000", date: ~D[2024-01-02])

    Map.put(world, :security, security)
  end
end
