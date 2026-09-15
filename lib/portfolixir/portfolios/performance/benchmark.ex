defmodule Portfolixir.Portfolios.Performance.Benchmark do
  @moduledoc """
  The benchmark comparison (ADR-0046, issue #572, FR-9): a benchmark is a
  price series the portfolio's own flows are replayed into.

  Two benchmark kinds behind one interface — anything that yields a daily
  price in the base currency for every day of the walk:

    * `{:rate, annual_rate}` — a constant effective annual rate compounding
      daily from a base of 1 (Act/365; the savings-account alternative, and
      in v1 also how inflation is expressed);
    * `{:security, security}` — a catalog security flagged `is_benchmark`,
      priced from its stored quotes in the current display basis
      (ADR-0028), each day converted to the base currency at the most recent
      stored EUR-hub rate on or before the day, exactly as the walk prices
      positions.

  Two comparisons, both Portfolio Performance's, over the same period the
  figures they sit next to use:

    * **bought once** — the benchmark rebased to the close before the window
      (or to the window's first day when the window opens with no value),
      drawn next to the portfolio's cumulative TTWROR; flow-neutral, so it
      answers "did my selection beat the index";
    * **savings plan** — the window's opening value and every external flow
      of the walk (ADR-0034 §1 at the same scope) invested into the
      benchmark at that day's price (a fixed rate: at par). The synthetic
      end value against the real one is the figure that answers "was the
      effort worth it", beside the two IRRs `Portfolixir.Portfolios.Performance.IRR`
      solves on identical flows.

  Rules the replay inherits rather than invents: a day without a close
  carries the most recent close forward; a flow dated before the benchmark's
  first close is **excluded and named**, and the comparison states the window
  it covers (the portfolio figures are re-chained over that window, so both
  sides always speak about the same days). The synthetic portfolio is
  frictionless — no fees, no taxes — and the computation basis says so; the
  bias runs against the real portfolio, the conservative direction.

  Nothing is persisted (ADR-0046 §5): the comparison is memoised under
  ADR-0039's one mechanism as the `:benchmark_comparison` analytic — under
  the **global** basis, because a benchmark the portfolio never held lies
  outside the portfolio's own blast radius and every quote, rate or ledger
  write bumps the global basis.

  The one float in this module is the daily compounding factor of a fixed
  rate, `(1 + rate)^(1/365)`, derived once at the arithmetic boundary the
  way the IRR solver does and then compounded in `Decimal`; a rate of
  exactly 0 uses the exact factor 1, so the ADR's first identity — a 0 %
  savings plan ends at exactly the net invested capital — holds by
  construction.
  """

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Derived
  alias Portfolixir.Fx
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.IRR

  @zero Decimal.new("0")
  @one Decimal.new("1")
  @minus_one Decimal.new("-1")
  @hub "EUR"
  @gbx_per_gbp Decimal.new(100)
  @days_per_year 365

  @type benchmark :: {:rate, Decimal.t()} | {:security, Security.t()}

  @doc """
  The comparison for one portfolio's walk.

  Options: `:period` (as `Performance.summarise/2`; default `"max"`),
  `:view` (a view id scoping the walk) and `:today`. Returns
  `{:ok, comparison}` or `{:error, :invalid_benchmark | :invalid_period |
  :view_not_found}`.
  """
  @spec for_portfolio(integer(), benchmark(), keyword()) :: {:ok, map()} | {:error, atom()}
  def for_portfolio(portfolio_id, benchmark, opts \\ []) when is_integer(portfolio_id) do
    period = Keyword.get(opts, :period, "max")

    with {:ok, benchmark} <- validate_benchmark(benchmark),
         :ok <- Performance.validate_period(period),
         %{} = analysis <- Performance.analysis(portfolio_id, Keyword.take(opts, [:view, :today])) do
      compare(analysis, period, benchmark, Keyword.take(opts, [:view]))
    end
  end

  @doc """
  The comparison for a bucket view's cross-portfolio walk
  (`Performance.view_analysis/2`); `view_id == nil` is the "Everything"
  scope. Options: `:period`, `:base_currency`, `:today`.
  """
  @spec for_view(integer() | nil, benchmark(), keyword()) :: {:ok, map()} | {:error, atom()}
  def for_view(view_id, benchmark, opts \\ []) when is_integer(view_id) or is_nil(view_id) do
    period = Keyword.get(opts, :period, "max")

    with {:ok, benchmark} <- validate_benchmark(benchmark),
         :ok <- Performance.validate_period(period),
         %{} = analysis <-
           Performance.view_analysis(view_id, Keyword.take(opts, [:base_currency, :today])) do
      compare(analysis, period, benchmark, [])
    end
  end

  @doc """
  Compares one `analysis` (a `Performance.analysis/2` or
  `Performance.view_analysis/2` result) over `period` with `benchmark`.

  `opts` may carry the `:view` a scoped portfolio walk was computed under —
  it is part of the memo identity, because the walk itself does not record
  it. Freshness (`as_of`, `stale`) is the analysis's own, annotated outside
  the memoised value (ADR-0039 C4).
  """
  @spec compare(map(), term(), benchmark(), keyword()) :: {:ok, map()} | {:error, atom()}
  def compare(analysis, period, benchmark, opts \\ []) do
    with {:ok, benchmark} <- validate_benchmark(benchmark),
         :ok <- Performance.validate_period(period) do
      {:fresh, comparison} =
        Derived.fetch(
          :benchmark_comparison,
          Derived.global_basis(),
          entry_key(analysis, period, benchmark, opts),
          fn -> build(analysis, period, benchmark) end
        )

      {:ok,
       Map.merge(comparison, %{
         as_of: analysis.basis.computed_at,
         stale: Map.get(analysis, :stale, false)
       })}
    end
  end

  # -- validation --------------------------------------------------------------

  defp validate_benchmark({:rate, %Decimal{} = rate}) do
    if Decimal.nan?(rate) or Decimal.inf?(rate) or Decimal.compare(rate, @minus_one) != :gt do
      {:error, :invalid_benchmark}
    else
      {:ok, {:rate, rate}}
    end
  end

  defp validate_benchmark({:security, %Security{} = security}), do: {:ok, {:security, security}}
  defp validate_benchmark(_other), do: {:error, :invalid_benchmark}

  # -- memo identity ------------------------------------------------------------

  defp entry_key(analysis, period, benchmark, opts) do
    scope =
      if Map.has_key?(analysis, :view_id),
        do: "view:#{analysis.view_id || "unscoped"}",
        else: "portfolio:#{analysis.portfolio_id}|view=#{Keyword.get(opts, :view) || "unscoped"}"

    "scope=#{scope}|base=#{analysis.base_currency}|today=#{analysis.today}" <>
      "|period=#{period_key(period)}|benchmark=#{benchmark_key(benchmark)}"
  end

  defp period_key({:year, year}), do: "year:#{year}"
  defp period_key({:range, from, to}), do: "range:#{from}..#{to}"
  defp period_key(period) when is_binary(period), do: period

  defp benchmark_key({:rate, rate}),
    do: "rate:#{rate |> Decimal.normalize() |> Decimal.to_string(:normal)}"

  defp benchmark_key({:security, %Security{id: id}}), do: "security:#{id}"

  # -- the comparison -----------------------------------------------------------

  defp build(analysis, period, benchmark) do
    {:ok, requested} = Performance.summarise(analysis, period)

    if is_nil(requested.start_date) do
      # Nothing to walk yet: the same honest emptiness as the performance
      # read, never an inverted window.
      empty(analysis, period, requested, benchmark, [])
    else
      prices =
        price_series(benchmark, requested, analysis.base_currency, rebase_wanted(requested))

      case coverage(requested, prices) do
        :none ->
          empty(analysis, period, requested, benchmark, flows_of(requested.series))

        {:ok, rebase_day, covered_start} ->
          covered(analysis, period, requested, benchmark, prices, rebase_day, covered_start)
      end
    end
  end

  # The day the benchmark is rebased to: the close before the window, which
  # is what the window's opening value was struck at — or the window's first
  # day when it opens with no value, because then there is nothing earlier to
  # compare against. When that day has no price (the benchmark's history
  # starts later), the window shifts to the day after the first close and
  # the flows before it are the excluded ones.
  defp coverage(%{start_date: start_date, end_date: end_date} = requested, prices) do
    wanted = rebase_wanted(requested)

    if priced?(prices, wanted) do
      {:ok, wanted, start_date}
    else
      case Enum.find(Date.range(wanted, end_date), &priced?(prices, &1)) do
        nil ->
          :none

        first ->
          if Date.compare(first, end_date) == :eq,
            do: :none,
            else: {:ok, first, Date.add(first, 1)}
      end
    end
  end

  defp rebase_wanted(%{start_date: start_date, start_value: start_value}) do
    if Decimal.equal?(start_value, @zero), do: start_date, else: Date.add(start_date, -1)
  end

  defp priced?(prices, day), do: match?(%Decimal{}, Map.get(prices, day))

  defp covered(analysis, period, requested, benchmark, prices, rebase_day, covered_start) do
    summary =
      if Date.compare(covered_start, requested.start_date) == :eq do
        requested
      else
        {:ok, shifted} =
          Performance.summarise(analysis, {:range, covered_start, requested.end_date})

        shifted
      end

    excluded =
      requested.series
      |> Enum.filter(&(Date.compare(&1.date, covered_start) == :lt))
      |> flows_of()

    # Every day from the rebase day on is priced: the close carries forward
    # and so does the rate, so a fetch cannot miss inside the window.
    rebase_price = Map.fetch!(prices, rebase_day)

    series =
      Enum.map(summary.series, fn point ->
        %{
          date: point.date,
          cumulative_return:
            Decimal.sub(Decimal.div(Map.fetch!(prices, point.date), rebase_price), @one)
        }
      end)

    opening_units = Decimal.div(summary.start_value, rebase_price)

    units =
      Enum.reduce(summary.series, opening_units, fn point, acc ->
        if Decimal.equal?(point.flow, @zero),
          do: acc,
          else: Decimal.add(acc, Decimal.div(point.flow, Map.fetch!(prices, point.date)))
      end)

    benchmark_end_value = Decimal.mult(units, Map.fetch!(prices, summary.end_date))

    %{
      portfolio_id: analysis.portfolio_id,
      view_id: Map.get(analysis, :view_id),
      period: period,
      base_currency: analysis.base_currency,
      benchmark: describe(benchmark),
      requested_window: window(requested),
      window: window(summary),
      excluded_flows: excluded,
      bought_once: %{
        benchmark_return: List.last(series).cumulative_return,
        portfolio_ttwror: summary.ttwror,
        series: series
      },
      savings_plan: %{
        invested_capital: summary.invested_capital,
        portfolio_end_value: summary.end_value,
        benchmark_end_value: benchmark_end_value,
        end_value_delta: Decimal.sub(summary.end_value, benchmark_end_value),
        portfolio_irr: summary.irr,
        # The same dated flows and opening value, the synthetic end value in
        # place of the real one: identical vectors, so an identical benchmark
        # solves to an identical rate.
        benchmark_irr: IRR.for_summary(%{summary | end_value: benchmark_end_value}),
        benchmark_units: units
      },
      computation_basis: computation_basis(benchmark, window(summary), excluded)
    }
  end

  defp empty(analysis, period, requested, benchmark, excluded) do
    window = %{start_date: nil, end_date: requested.end_date}

    %{
      portfolio_id: analysis.portfolio_id,
      view_id: Map.get(analysis, :view_id),
      period: period,
      base_currency: analysis.base_currency,
      benchmark: describe(benchmark),
      requested_window: window(requested),
      window: window,
      excluded_flows: excluded,
      bought_once: %{benchmark_return: nil, portfolio_ttwror: nil, series: []},
      savings_plan: %{
        invested_capital: nil,
        portfolio_end_value: nil,
        benchmark_end_value: nil,
        end_value_delta: nil,
        portfolio_irr: nil,
        benchmark_irr: nil,
        benchmark_units: nil
      },
      computation_basis: computation_basis(benchmark, window, excluded)
    }
  end

  defp window(%{start_date: start_date, end_date: end_date}),
    do: %{start_date: start_date, end_date: end_date}

  defp flows_of(points) do
    for %{date: date, flow: flow} <- points,
        not Decimal.equal?(flow, @zero),
        do: %{date: date, flow: flow}
  end

  defp describe({:rate, rate}), do: %{kind: :rate, annual_rate: rate}

  defp describe({:security, %Security{} = security}) do
    %{
      kind: :security,
      security_id: security.id,
      name: security.name,
      currency_code: security.currency_code
    }
  end

  # AGENTS.md analytics rule / ADR-0039 C4: the basis IN the payload — input
  # series, window, reference, the treatment of gaps — plus the frictionless
  # assumption ADR-0046 §2 requires the explanation line to state.
  defp computation_basis(benchmark, window, excluded) do
    %{
      input_series:
        "daily portfolio valuation derived from recorded transactions, stored quotes and " <>
          "stored EUR-hub exchange rates (ADR-0010) — the same walk the TTWROR and IRR of " <>
          "this scope read — and " <> series_text(benchmark),
      window: window,
      reference: reference_text(benchmark),
      gaps:
        "the benchmark carries the most recent close on or before each day forward, " <>
          "converted at the most recent stored EUR-hub rate on or before the day; a flow " <>
          "dated before the benchmark's first close is excluded from the replay and listed " <>
          "in excluded_flows (#{length(excluded)} excluded), and window states the days the " <>
          "comparison covers — the portfolio figures are chained over the same window",
      assumptions:
        "the synthetic portfolio is frictionless — no fees, no taxes, every flow invested " <>
          "at that day's close (a fixed rate: at par) — which biases the comparison against " <>
          "the real portfolio",
      frictionless: true
    }
  end

  defp series_text({:rate, rate}),
    do:
      "a fixed annual rate of #{Decimal.to_string(rate, :normal)} compounding daily from a " <>
        "base of 1 (effective annual rate, Act/365)"

  defp series_text({:security, %Security{} = security}),
    do:
      "the stored quotes of #{security.name} (security #{security.id}, " <>
        "#{security.currency_code}) in the current display basis (ADR-0028)"

  defp reference_text({:rate, rate}), do: "fixed rate #{Decimal.to_string(rate, :normal)} p.a."

  defp reference_text({:security, %Security{} = security}),
    do: "security #{security.id} #{security.name} (#{security.currency_code})"

  # -- the benchmark price series ------------------------------------------------

  # One base-currency price (or nil) for every day from the day before the
  # requested window to its end. The fixed rate is a base of exactly 1 on the
  # day the comparison rebases to (`anchor`), so its units are money in that
  # day's terms; the security series is what the quotes say.
  defp price_series({:rate, rate}, %{start_date: start_date, end_date: end_date}, _base, anchor) do
    factor = daily_factor(rate)
    from = Date.add(start_date, -1)
    # `from` is the anchor itself or the day before it: the base of 1, or one
    # day of compounding below it.
    opening = if Date.compare(from, anchor) == :eq, do: @one, else: Decimal.div(@one, factor)

    {prices, _next} =
      Enum.reduce(Date.range(from, end_date), {%{}, opening}, fn day, {acc, price} ->
        {Map.put(acc, day, price), Decimal.mult(price, factor)}
      end)

    prices
  end

  defp price_series(
         {:security, security},
         %{start_date: start_date, end_date: end_date},
         base,
         _anchor
       ) do
    from = Date.add(start_date, -1)

    seed =
      case Quotes.at_or_before(security.id, from) do
        nil -> []
        row -> [row]
      end

    rows =
      Quotes.adjust_rows(seed ++ Quotes.range(security.id, Date.add(from, 1), end_date), security)

    fx = init_fx(security.currency_code, base, from)

    {prices, _close, _rows, _fx} =
      Enum.reduce(Date.range(from, end_date), {%{}, nil, rows, fx}, fn day,
                                                                       {acc, close, rows, fx} ->
        {close, rows} = advance_close(close, rows, day)
        fx = Map.new(fx, fn {ccy, entry} -> {ccy, advance_rate(entry, day)} end)
        {Map.put(acc, day, priced(close, security.currency_code, base, fx)), close, rows, fx}
      end)

    prices
  end

  # `(1 + rate)^(1/365)`: the one float, taken once at the arithmetic
  # boundary (as the IRR solver does) and compounded in Decimal from there.
  # A rate of exactly 0 keeps the exact factor 1.
  defp daily_factor(rate) do
    if Decimal.equal?(rate, @zero) do
      @one
    else
      (1.0 + Decimal.to_float(rate))
      |> :math.pow(1 / @days_per_year)
      |> Decimal.from_float()
    end
  end

  defp advance_close(close, [%{date: date, close: next} | rest] = rows, day) do
    if Date.compare(date, day) in [:lt, :eq],
      do: advance_close(next, rest, day),
      else: {close, rows}
  end

  defp advance_close(close, [], _day), do: {close, []}

  defp priced(nil, _currency, _base, _fx), do: nil

  defp priced(%Decimal{} = close, currency, base, fx) do
    case conversion_rate(currency, base, fx) do
      {:ok, rate} -> Decimal.mult(close, rate)
      :error -> nil
    end
  end

  # -- in-memory FX, the walk's own shape ----------------------------------------

  defp init_fx(currency, base, from) do
    [currency, base]
    |> Enum.flat_map(fn
      "GBX" -> ["GBP"]
      ccy -> [ccy]
    end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in [nil, @hub]))
    |> Map.new(fn ccy ->
      carried =
        case Fx.hub_rate_before(ccy, Date.add(from, -1)) do
          %{rate: %Decimal{} = rate} -> rate
          _ -> nil
        end

      points = ccy |> Fx.series(from) |> Enum.map(&%{date: &1.date, rate: &1.rate})
      {ccy, %{rate: carried, upcoming: points}}
    end)
  end

  defp advance_rate(%{upcoming: [%{date: date, rate: rate} | rest]} = entry, day) do
    if Date.compare(date, day) in [:lt, :eq] do
      advance_rate(%{entry | rate: rate, upcoming: rest}, day)
    else
      entry
    end
  end

  defp advance_rate(entry, _day), do: entry

  defp conversion_rate(same, same, _fx), do: {:ok, @one}

  defp conversion_rate(from, to, fx) do
    with {:ok, from_rate} <- eur_rate(from, fx),
         {:ok, to_rate} <- eur_rate(to, fx) do
      {:ok, Decimal.div(to_rate, from_rate)}
    end
  end

  defp eur_rate(@hub, _fx), do: {:ok, @one}

  defp eur_rate("GBX", fx) do
    with {:ok, gbp} <- eur_rate("GBP", fx) do
      {:ok, Decimal.mult(gbp, @gbx_per_gbp)}
    end
  end

  defp eur_rate(ccy, fx) when is_binary(ccy) do
    case fx do
      %{^ccy => %{rate: %Decimal{} = rate}} -> {:ok, rate}
      _ -> :error
    end
  end

  defp eur_rate(_ccy, _fx), do: :error
end
