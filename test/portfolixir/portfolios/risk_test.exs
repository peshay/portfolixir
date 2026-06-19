defmodule Portfolixir.Portfolios.RiskTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Portfolios.Risk

  # User story:
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want one call that surfaces my single-name and asset-class concentration
  # over the steerable basis,
  # so that a position growing past a safe threshold (or an asset class over its
  # cap) is flagged before it hurts, instead of staying hidden behind the
  # per-position weights.
  #
  # Acceptance criteria:
  # - Single-name Top-N comes back largest first, default N = 10, overridable.
  # - Each entry carries its percentage weight (share of the steerable basis) and
  #   a severity (ok/warn/hard) from the instrument-type-aware thresholds.
  # - HHI is Sigma weight^2 on the 0-10000 scale with a low/moderate/concentrated
  #   band.
  # - Asset-class caps are opt-in; only classes over cap come back, with the
  #   overage in percentage points.
  # - Positions flagged excluded_from_allocation_targets are kept out of the
  #   basis (the steerable basis, issue #329).

  defp equity!(name, ticker),
    do: create_security!(name: name, ticker: ticker, asset_class: "equity")

  defp etf!(name, ticker),
    do: create_security!(name: name, ticker: ticker, asset_class: "etf")

  defp holding(risk, security_id),
    do: Enum.find(risk.top_holdings, &(&1.security_id == security_id))

  # Builds a world whose steerable basis is exactly 1000 EUR:
  #   stock_big 600 (60%), stock_mid 90 (9%), stock_small 50 (5%), big_etf 260 (26%)
  # plus an excluded crypto of 500 that must stay out of the basis.
  defp risk_world do
    world = base_world()

    stock_big = equity!("Stock Big", "BIG")
    stock_mid = equity!("Stock Mid", "MID")
    stock_small = equity!("Stock Small", "SML")
    big_etf = etf!("Big World ETF", "WRLD")

    {:ok, crypto} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Store Of Value",
        currency_code: "EUR",
        asset_class: "crypto",
        excluded_from_allocation_targets: true
      })

    deposit!(world, "2000", ~D[2026-01-01])

    buy!(world, stock_big, quantity: "6", price: "100")
    buy!(world, stock_mid, quantity: "9", price: "10")
    buy!(world, stock_small, quantity: "5", price: "10")
    buy!(world, big_etf, quantity: "26", price: "10")
    buy!(world, crypto, quantity: "5", price: "100")

    prices = %{
      stock_big.id => Decimal.new("100"),
      stock_mid.id => Decimal.new("10"),
      stock_small.id => Decimal.new("10"),
      big_etf.id => Decimal.new("10"),
      crypto.id => Decimal.new("100")
    }

    {Map.merge(world, %{
       stock_big: stock_big,
       stock_mid: stock_mid,
       stock_small: stock_small,
       big_etf: big_etf,
       crypto: crypto
     }), prices}
  end

  # User story:
  # As a local portfolio maintainer,
  # I want risk to optionally scope to a view, while no view stays my whole
  # steerable basis, so that I can read concentration for a slice of my wealth
  # (#444).
  test "a view scopes risk through the underlying valuation; default identical" do
    {world, prices} = risk_world()

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Drop"})
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "NoMid", include_all: true})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [], [bucket.id])

    :ok =
      Buckets.set_position_override(Actor.owner_ui(), world.depot, world.stock_mid, [bucket.id])

    default = Risk.for_portfolio(world.portfolio.id, prices: prices)
    scoped = Risk.for_portfolio(world.portfolio.id, prices: prices, view: view.id)

    assert world.stock_mid.id in Enum.map(default.top_holdings, & &1.security_id)
    refute world.stock_mid.id in Enum.map(scoped.top_holdings, & &1.security_id)

    # The basis drops by stock_mid's 90 EUR (1000 -> 910); single-count preserved.
    assert Decimal.equal?(default.steerable_basis, Decimal.new("1000"))
    assert Decimal.equal?(scoped.steerable_basis, Decimal.new("910"))
  end

  test "reports single-name Top-N, HHI and the steerable basis with exact weights" do
    {world, prices} = risk_world()

    risk = Risk.for_portfolio(world.portfolio.id, prices: prices)

    # The excluded crypto (500) stays out of the basis: 600 + 90 + 50 + 260 = 1000.
    assert Decimal.equal?(risk.steerable_basis, Decimal.new("1000"))

    # Largest first, on the percentage scale.
    assert Enum.map(risk.top_holdings, & &1.security_id) == [
             world.stock_big.id,
             world.big_etf.id,
             world.stock_mid.id,
             world.stock_small.id
           ]

    big = holding(risk, world.stock_big.id)
    assert Decimal.equal?(big.weight, Decimal.new("60"))

    etf = holding(risk, world.big_etf.id)
    assert Decimal.equal?(etf.weight, Decimal.new("26"))

    # The excluded crypto never appears as a single-name exposure.
    refute Enum.any?(risk.top_holdings, &(&1.security_id == world.crypto.id))

    # HHI = 60^2 + 9^2 + 5^2 + 26^2 = 3600 + 81 + 25 + 676 = 4382 -> concentrated.
    assert Decimal.equal?(risk.hhi.value, Decimal.new("4382"))
    assert risk.hhi.band == "concentrated"
  end

  test "severity is instrument-type aware: stock warn>7/hard>10, ETF warn>25" do
    {world, prices} = risk_world()

    risk = Risk.for_portfolio(world.portfolio.id, prices: prices)

    # 60% equity -> hard, 9% equity -> warn, 5% equity -> ok.
    assert holding(risk, world.stock_big.id).severity == "hard"
    assert holding(risk, world.stock_mid.id).severity == "warn"
    assert holding(risk, world.stock_small.id).severity == "ok"

    # 26% ETF -> warn (ETFs never go hard).
    assert holding(risk, world.big_etf.id).severity == "warn"
  end

  test "Top-N defaults to 10 and is overridable per call" do
    {world, prices} = risk_world()

    default = Risk.for_portfolio(world.portfolio.id, prices: prices)
    # Four steerable single names, well under the default of 10.
    assert length(default.top_holdings) == 4

    limited = Risk.for_portfolio(world.portfolio.id, prices: prices, top_n: 2)

    assert Enum.map(limited.top_holdings, & &1.security_id) == [
             world.stock_big.id,
             world.big_etf.id
           ]
  end

  test "HHI bands are overridable per call" do
    {world, prices} = risk_world()

    # Raise the 'concentrated' cutoff above the actual 4382 so the same HHI now
    # reads as moderate rather than concentrated.
    risk =
      Risk.for_portfolio(world.portfolio.id,
        prices: prices,
        hhi_bands: %{low: Decimal.new("1500"), high: Decimal.new("5000")}
      )

    assert Decimal.equal?(risk.hhi.value, Decimal.new("4382"))
    assert risk.hhi.band == "moderate"
  end

  test "asset-class caps are opt-in and return only classes over cap with the overage" do
    {world, prices} = risk_world()

    # No caps configured -> no violations (opt-in, no shipped defaults).
    assert Risk.for_portfolio(world.portfolio.id, prices: prices).asset_class_violations == []

    risk =
      Risk.for_portfolio(world.portfolio.id,
        prices: prices,
        asset_class_caps: %{"equity" => Decimal.new("50"), "etf" => Decimal.new("30")}
      )

    # Equity = 74% > 50% cap -> violation with 24pp overage; ETF = 26% <= 30% -> none.
    assert [violation] = risk.asset_class_violations
    assert violation.asset_class == "equity"
    assert Decimal.equal?(violation.current_weight, Decimal.new("74"))
    assert Decimal.equal?(violation.cap, Decimal.new("50"))
    assert Decimal.equal?(violation.overage, Decimal.new("24"))
  end

  test "an empty portfolio yields a zero basis and no holdings or violations" do
    world = base_world()

    risk =
      Risk.for_portfolio(world.portfolio.id, asset_class_caps: %{"equity" => Decimal.new("10")})

    assert Decimal.equal?(risk.steerable_basis, Decimal.new("0"))
    assert risk.top_holdings == []
    assert risk.asset_class_violations == []
    assert Decimal.equal?(risk.hhi.value, Decimal.new("0"))
    assert risk.hhi.band == "low"
  end
end
