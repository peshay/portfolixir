defmodule Portfolixir.Portfolios.RiskMetricsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Risk
  alias Portfolixir.Portfolios.RiskMetrics

  @as_of ~D[2026-09-19]

  defp day(offset), do: Date.add(@as_of, offset)

  defp daily_closes(security, from_offset, close_fun) do
    points = for offset <- from_offset..0, do: {day(offset), close_fun.(offset)}
    put_quotes!(security, points)
  end

  defp removal!(world, amount, date) do
    {:ok, _tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "removal",
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })
  end

  defp rate!(currency, date, rate) do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: currency,
          date: date,
          rate: rate,
          source: "manual"
        }
      ])
  end

  defp assert_scale_6(actual, expected) do
    assert Decimal.to_string(actual, :normal) == expected,
           "expected #{expected} at scale 6, got #{inspect(actual)}"
  end

  # User story (FR-40, ADR-0047 §2 and §11, identity I1 — risk-tier):
  # As the operator who saves into the portfolio and sometimes takes money out,
  # I want the portfolio's volatility and drawdown measured over the TTWROR
  # chain's flow-adjusted return factors,
  # so that my deposits and withdrawals are never reported as risk.
  #
  # Acceptance criteria:
  # - A portfolio whose prices never move, with several deposits, buys and a
  #   withdrawal, has volatility exactly 0 and maximum drawdown exactly 0 at
  #   scale 6, in every window — read through the real daily walk, not a
  #   hand-built factor list.
  test "I1: unchanging prices with deposits and withdrawals give volatility 0 and drawdown 0" do
    world = base_world()
    security = create_security!(name: "Flat Co", ticker: "FLT")

    deposit!(world, "1000", day(-100))
    buy!(world, security, quantity: "5", price: "100", date: day(-100))
    deposit!(world, "500", day(-70))
    buy!(world, security, quantity: "2", price: "100", date: day(-70))
    removal!(world, "200", day(-40))
    deposit!(world, "300", day(-20))
    daily_closes(security, -100, fn _ -> "100" end)

    metrics = RiskMetrics.for_portfolio(world.portfolio.id, [security.id], as_of: @as_of)

    for window <- ~w(30d 90d 365d) do
      volatility = metrics.volatility[window]
      refute volatility.insufficient_data, "#{window} refused: #{inspect(volatility)}"
      assert_scale_6(volatility.value, "0.000000")

      drawdown = metrics.max_drawdown[window]
      refute drawdown.insufficient_data
      assert_scale_6(drawdown.value, "0.000000")
    end

    # The 365d window reads every walked day that had a return base: 101
    # walked days, and the first one's base is its opening deposit.
    assert metrics.volatility["365d"].observations == 101
  end

  # Acceptance criteria (ADR-0047 §2, the contrast that makes I1 mean
  # something):
  # - Two fully invested portfolios on the same price path report the SAME
  #   volatility to the last digit, although one of them saved five times its
  #   starting value along the way: a saver and a holder read the same risk.
  # - The figure is non-zero: the price path does move.
  test "deposits invested along the way do not change the volatility of a price path" do
    closes = fn offset -> if offset >= -10, do: "110", else: "100" end

    saver = base_world()
    saver_security = create_security!(name: "Saver Co", ticker: "SAV")
    deposit!(saver, "1000", day(-60))
    buy!(saver, saver_security, quantity: "10", price: "100", date: day(-60))
    deposit!(saver, "5000", day(-30))
    buy!(saver, saver_security, quantity: "50", price: "100", date: day(-30))
    deposit!(saver, "2200", day(-5))
    buy!(saver, saver_security, quantity: "20", price: "110", date: day(-5))
    daily_closes(saver_security, -60, closes)

    holder = base_world()
    holder_security = create_security!(name: "Holder Co", ticker: "HLD")
    deposit!(holder, "1000", day(-60))
    buy!(holder, holder_security, quantity: "10", price: "100", date: day(-60))
    daily_closes(holder_security, -60, closes)

    saver_metrics =
      RiskMetrics.for_portfolio(saver.portfolio.id, [saver_security.id], as_of: @as_of)

    holder_metrics =
      RiskMetrics.for_portfolio(holder.portfolio.id, [holder_security.id], as_of: @as_of)

    assert Decimal.compare(holder_metrics.volatility["90d"].value, Decimal.new(0)) == :gt

    assert Decimal.to_string(saver_metrics.volatility["90d"].value) ==
             Decimal.to_string(holder_metrics.volatility["90d"].value)

    assert Decimal.to_string(saver_metrics.risk_adjusted_return["90d"].value) ==
             Decimal.to_string(holder_metrics.risk_adjusted_return["90d"].value)
  end

  # Acceptance criteria (closing-act finding F2/F3, I1 under currency
  # conversion): a flat multi-currency portfolio whose walk leaves Decimal
  # division residue in a factor (0.999…9 at 34 places) still reads as flat —
  # volatility and drawdown "0.000000", no risk-adjusted-return number made
  # of rounding noise, and no "-0" drawdown left unrecovered.
  test "I1 survives currency conversion: division residue is not a return" do
    for {ccy, rate} <- [{"USD", "3"}, {"CHF", "7"}], do: rate!(ccy, day(-200), rate)

    world = base_world()
    usd = create_security!(name: "Flat USD", ticker: "FUS", currency: "USD")
    chf = create_security!(name: "Flat CHF", ticker: "FCH", currency: "CHF")

    deposit!(world, "1000", day(-100))
    buy!(world, usd, quantity: "1", price: "33", date: day(-100))
    buy!(world, chf, quantity: "1", price: "14", date: day(-100))

    for {amount, offset} <- [
          {"7", -90},
          {"61", -80},
          {"999", -70},
          {"9001", -50},
          {"13", -40},
          {"88888", -30},
          {"3", -20},
          {"900001", -10},
          {"1", -3}
        ],
        do: deposit!(world, amount, day(offset))

    daily_closes(usd, -100, fn _ -> "100" end)
    daily_closes(chf, -100, fn _ -> "100" end)

    metrics = RiskMetrics.for_portfolio(world.portfolio.id, [usd.id, chf.id], as_of: @as_of)

    for window <- ~w(30d 90d 365d) do
      assert_scale_6(metrics.volatility[window].value, "0.000000")
      assert_scale_6(metrics.max_drawdown[window].value, "0.000000")
      assert metrics.max_drawdown[window].recovery_date
      assert metrics.risk_adjusted_return[window].value == nil
    end
  end

  # User story (FR-40, ADR-0047 §3 and §11, identity I7):
  # As the operator holding positions in several currencies,
  # I want the correlation matrix computed in my base currency,
  # so that two holdings sharing an FX leg show that shared movement.
  #
  # Acceptance criteria:
  # - A USD security whose USD price never moves, held by a EUR portfolio,
  #   correlates exactly 1 with a EUR security that tracks the converted
  #   price: the matrix converted first.
  # - A security whose currency has no stored rate path is absent from the
  #   matrix and listed in `excluded`, never silently unconverted.
  test "I7: correlations convert to the base currency first, and exclude what cannot be converted" do
    world = base_world()
    usd = create_security!(name: "Dollar Co", ticker: "USDC", currency: "USD")
    tracker = create_security!(name: "Tracker Co", ticker: "TRK")
    no_rate = create_security!(name: "Franc Co", ticker: "CHFC", currency: "CHF")

    # EUR/USD moves every day; 1 USD = 1/rate EUR.
    rate_of = fn offset -> Decimal.add(Decimal.new("1.1"), Decimal.div(offset + 100, 1000)) end
    for offset <- -100..0, do: rate!("USD", day(offset), rate_of.(offset))

    daily_closes(usd, -100, fn _ -> "100" end)
    daily_closes(tracker, -100, fn offset -> Decimal.div(Decimal.new(100), rate_of.(offset)) end)
    daily_closes(no_rate, -100, fn offset -> "#{100 + rem(offset, 5)}" end)

    metrics =
      RiskMetrics.for_portfolio(world.portfolio.id, [usd.id, tracker.id, no_rate.id],
        as_of: @as_of
      )

    correlations = metrics.correlations
    assert correlations.security_ids == [usd.id, tracker.id]
    assert correlations.excluded == [%{security_id: no_rate.id, reason: "no_rate_path"}]

    [pair] = correlations.pairs
    assert {pair.security_id_a, pair.security_id_b} == {usd.id, tracker.id}
    assert pair.observations == 100
    assert_scale_6(pair.value, "1.000000")
  end

  # Acceptance criteria (ADR-0047 §3, I7 — the conversion's edges):
  # - A GBX (pence) security converts through GBP × 100, as `Fx` resolves it.
  # - A close dated before its currency's first stored rate is not a point:
  #   the pair's overlap shrinks rather than reading an unconverted close.
  # - A portfolio whose BASE currency has no stored rate path cannot convert
  #   anything foreign: every foreign name is excluded, never unconverted.
  test "I7 at the edges: GBX through GBP, closes before the first rate, a base with no rate" do
    world = base_world()
    pence = create_security!(name: "Pence Co", ticker: "PNC", currency: "GBX")
    tracker = create_security!(name: "Sterling Tracker", ticker: "STR")

    # GBP rates only from day -80: the 20 earlier closes have no converted value.
    rate_of = fn offset -> Decimal.add(Decimal.new("0.8"), Decimal.div(offset + 100, 2000)) end
    for offset <- -80..0, do: rate!("GBP", day(offset), rate_of.(offset))

    daily_closes(pence, -100, fn _ -> "10000" end)

    daily_closes(tracker, -100, fn offset ->
      Decimal.div(Decimal.new(100), rate_of.(max(offset, -80)))
    end)

    %{correlations: correlations} =
      RiskMetrics.for_portfolio(world.portfolio.id, [pence.id, tracker.id], as_of: @as_of)

    [pair] = correlations.pairs
    assert pair.observations == 80
    assert_scale_6(pair.value, "1.000000")

    # A CHF-based portfolio with no CHF rate stored: nothing converts.
    empty = Portfolixir.WorldFixtures.base_world(currency: "CHF")

    %{correlations: chf} =
      RiskMetrics.for_portfolio(empty.portfolio.id, [pence.id, tracker.id], as_of: @as_of)

    assert chf.security_ids == []
    assert Enum.map(chf.excluded, & &1.security_id) == [pence.id, tracker.id]
  end

  # Acceptance criteria (ADR-0047 §9):
  # - The figures ride the existing risk read, scoped by the view the lens
  #   honours, over the lens's own Top-N.
  test "the risk lens carries the metrics over its own Top-N" do
    world = base_world()
    a = create_security!(name: "Alpha", ticker: "ALP")
    b = create_security!(name: "Beta", ticker: "BET")
    deposit!(world, "2000", day(-90))
    buy!(world, a, quantity: "10", price: "100", date: day(-90))
    buy!(world, b, quantity: "5", price: "100", date: day(-90))
    daily_closes(a, -90, fn offset -> "#{100 + rem(offset, 3)}" end)
    daily_closes(b, -90, fn offset -> "#{100 - rem(offset, 4)}" end)

    risk = Risk.for_portfolio(world.portfolio.id, as_of: @as_of)

    assert risk.metrics.correlations.security_ids == Enum.map(risk.top_holdings, & &1.security_id)
    assert risk.metrics.as_of == @as_of
    refute risk.metrics.volatility["90d"].insufficient_data
    assert risk.metrics.volatility["90d"].required == 20
  end
end
