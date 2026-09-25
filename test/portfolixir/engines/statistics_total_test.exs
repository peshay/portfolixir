defmodule Portfolixir.Engines.StatisticsTotalTest do
  # E25 S3, F73 (#888): the square root is the one float operation of AR-3's
  # island (ADR-0047 §4), and a Decimal outside the double range used to raise
  # on its way into it — so implausible stored prices or rates could break the
  # whole risk read. The root is now total: a value the float step cannot
  # carry is nil, and so is every figure built on it (board 11: the pair reads
  # "not computable" with its observations), never a raise.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, put_quotes!: 2]

  alias Portfolixir.Engines.PortfolioMetrics
  alias Portfolixir.Engines.PriceMetrics
  alias Portfolixir.Engines.Statistics
  alias Portfolixir.Portfolios.RiskMetrics

  @as_of ~D[2026-09-19]

  defp d(value), do: Decimal.new(value)
  defp day(offset), do: Date.add(@as_of, offset)

  defp in_unit_interval?(%Decimal{} = value),
    do: Decimal.compare(value, -1) != :lt and Decimal.compare(value, 1) != :gt

  # User story:
  # As the operator reading my portfolio's risk,
  # I want the square root behind every deviation and correlation to answer
  # for any stored magnitude,
  # so that one implausible stored price or rate cannot take the risk read,
  # and every rule on the page, down with it.
  #
  # Acceptance criteria:
  # - Inside the double range the root is the same single float step as before.
  # - A value far above or below the double range answers nil, never a raise.
  # - Zero is zero; a negative value, NaN or an infinity has no root: nil.
  test "square_root is total over Decimals" do
    for value <- ["4E+700", "9E-800", "1E+308", "1E-308", "2E+400", "-1E+500"] do
      assert Statistics.square_root(d(value)) == nil, value
    end

    assert Decimal.equal?(Statistics.square_root(d("0")), d("0"))
    assert Decimal.equal?(Statistics.square_root(d("-0")), d("0"))

    for value <- ["2", "0.0004", "123456.789", "1E+300", "1E-300", "9E+307", "1E-307"] do
      expected = value |> d() |> Decimal.to_float() |> :math.sqrt() |> Decimal.from_float()
      assert Statistics.square_root(d(value)) == expected, value
    end

    for value <- ["-1", "-1E+500", "NaN", "Inf", "-Inf"] do
      assert Statistics.square_root(d(value)) == nil, value
    end
  end

  # Acceptance criteria:
  # - A correlation over returns far above or below the double range is null,
  #   never a raise; one inside it is still a figure in [-1, 1].
  # - The deviation and the risk-adjusted return over such returns are null,
  #   never a raise, in both engines.
  test "correlation and deviation over extreme returns yield a figure or null" do
    huge = Enum.map(1..70, fn i -> if rem(i, 2) == 0, do: d("1E+250"), else: d("-3E+250") end)
    tiny = Enum.map(1..70, fn i -> if rem(i, 2) == 0, do: d("2E-250"), else: d("-1E-250") end)
    plain = Enum.map(1..70, fn i -> if rem(i, 2) == 0, do: d("0.01"), else: d("-0.01") end)

    for {xs, ys} <- [{huge, plain}, {tiny, tiny}, {huge, huge}] do
      assert Statistics.pearson(xs, ys) == nil
    end

    assert in_unit_interval?(Statistics.pearson(plain, Enum.reverse(plain)))
    assert Statistics.annualized_deviation(huge, 365) == nil
    assert Statistics.annualized_deviation(tiny, 252) == nil

    factors =
      Enum.map(0..399, fn i ->
        %{date: day(-i), factor: if(rem(i, 2) == 0, do: d("1E+200"), else: d("1E-200"))}
      end)

    metrics = PortfolioMetrics.compute(factors, @as_of)

    for window <- ~w(30d 90d 365d) do
      refute metrics.volatility[window].insufficient_data
      assert metrics.volatility[window].value == nil
      assert metrics.risk_adjusted_return[window].value == nil
    end

    closes =
      Enum.map(0..300, fn i ->
        %{date: day(-i), close: if(rem(i, 2) == 0, do: d("1E+200"), else: d("1E-200"))}
      end)

    price_metrics = PriceMetrics.compute(closes, @as_of)

    security = create_security!(name: "Synthetic Gamma", ticker: "SYNG")
    {:ok, payload} = Portfolixir.Catalog.SecurityMetrics.for_security(security.id, as_of: @as_of)
    assert payload.computation_basis.gaps =~ "outside the double range"

    for window <- ~w(30d 90d 365d) do
      assert price_metrics.volatility[window].value == nil
    end
  end

  # User story:
  # As the operator whose instance holds implausible exchange rates — stored
  # before the plausibility bounds existed, or positive but absurd in size —
  # I want the risk read to answer anyway,
  # so that the page and its rules stay readable.
  #
  # Acceptance criteria:
  # - With stored rates and closes at the edges of what their columns hold,
  #   converted into a non-hub base currency, the risk read returns: every
  #   correlation pair is a figure in [-1, 1] or null, and the volatility is
  #   a figure or null.
  test "the risk read survives implausible stored rates" do
    world = base_world(currency: "USD")
    a = create_security!(name: "Synthetic Alpha", ticker: "SYNA", currency: "JPY")
    b = create_security!(name: "Synthetic Beta", ticker: "SYNB", currency: "GBP")

    high_close = "99999999999999"
    low_close = "0.000001"
    high_rate = "999999999999999"
    low_rate = "0.000000000000001"
    even? = &(rem(&1, 2) == 0)

    for security <- [a, b] do
      put_quotes!(
        security,
        for(
          offset <- -365..0,
          do: {day(offset), if(even?.(offset), do: high_close, else: low_close)}
        )
      )
    end

    rates =
      for offset <- -366..0,
          {currency, high_on_even?} <- [{"JPY", false}, {"GBP", false}, {"USD", true}] do
        high? = if high_on_even?, do: even?.(offset), else: not even?.(offset)

        %{
          base_currency: "EUR",
          quote_currency: currency,
          date: day(offset),
          rate: if(high?, do: high_rate, else: low_rate),
          source: "manual"
        }
      end

    assert {:ok, _} = Portfolixir.Fx.upsert_many(rates)

    metrics = RiskMetrics.for_portfolio(world.portfolio.id, [a.id, b.id], as_of: @as_of)

    assert [pair] = metrics.correlations.pairs
    assert %{value: nil, insufficient_data: false, observations: 365} = pair

    # The payload says what such a null means (AGENTS.md metric rule).
    assert metrics.computation_basis.gaps =~ "outside the double range"
    assert metrics.computation_basis.gaps =~ "correlation pair"

    for window <- ~w(30d 90d 365d) do
      value = metrics.volatility[window].value
      assert value == nil or match?(%Decimal{}, value)
    end
  end
end
