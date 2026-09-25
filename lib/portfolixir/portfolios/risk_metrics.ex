defmodule Portfolixir.Portfolios.RiskMetrics do
  @moduledoc """
  The per-portfolio and per-view derived metrics read (FR-40,
  [ADR-0047](../../docs/decisions/0047-derived-metrics-per-security-and-per-view.md)),
  served **on the existing risk read** rather than beside it (§9): the risk
  family has exactly one endpoint, and the view arrives as the `?view=`
  parameter the concentration lens already honours.

  The **shell** half of the engine/shell split (AR-2): it loads the TTWROR walk
  and the Top-N names' close series, hands them to
  `Portfolixir.Engines.PortfolioMetrics`, and wraps the answer in the
  computation basis the `AGENTS.md` metric rule requires **in the payload**.

  ## Two series, never mixed (§1)

    * **Volatility, drawdown, risk-adjusted return** read the daily valuation
      walk of ADR-0010 in the base currency, scoped by the view — through its
      **flow-adjusted return factors**, never through the change in value
      (§2). A day with no return base is not an observation
      (`Performance.return_factor/2`).
    * **Correlations** read the Top-N single names' own stored closes,
      **converted to the base currency first** — the deliberate opposite of the
      per-security rule, because "do the things I own move together in my
      money" includes a shared FX leg. A security whose currency has no stored
      rate path is **absent from the matrix** and named in `excluded`, never
      silently unconverted (identity I7).

  ## Registry

  `portfolio_metrics` registers with ADR-0039 §2 at computation version 1 and
  lifetime `:request`, keyed under `Derived.portfolio_basis/1` exactly as
  `performance_analysis` is (§8): every write that can move the walk, a held
  security's quote or an exchange rate already bumps that basis. The entry
  key carries the basis version read before the walk (E25 S6, F46), so
  metrics are never filed under a version their walk did not see.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Derived
  alias Portfolixir.Engines.PortfolioMetrics
  alias Portfolixir.Fx
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Benchmark
  alias Portfolixir.Repo

  @zero Decimal.new(0)
  @hub "EUR"
  @gbx_per_gbp Decimal.new(100)
  @factor_scale 15
  @max_correlated_names 20

  @doc """
  How many leading Top-N names the correlation matrix covers at most. The
  pair count grows with the square of the names, so the matrix is bounded
  while the Top-N list is not (E25 S4, F72).
  """
  @spec max_correlated_names() :: pos_integer()
  def max_correlated_names, do: @max_correlated_names

  @doc """
  The metrics for `portfolio_id` over the lens's Top-N `top_security_ids`;
  the correlation matrix covers the leading `max_correlated_names/0` of them.

  Options:

    * `:view` — the view id the walk is scoped by (`nil` = unscoped).
    * `:as_of` — the day the metrics are computed as of (default today, UTC,
      the risk read's own `as_of`).
    * `:risk_free_rate` — the annual risk-free rate as a Decimal fraction,
      default `0`.
    * `:base_currency` — the currency correlations are converted into; the
      walk's own base wins when the walk has one.
    * `:analysis` — the function the walk is read through, `(portfolio_id,
      opts) -> analysis`; `Performance.analysis/2` unless a test injects one.

  Returns the metrics map or `{:error, :view_not_found}`.
  """
  @spec for_portfolio(integer(), [integer()], keyword()) :: map() | {:error, :view_not_found}
  def for_portfolio(portfolio_id, top_security_ids, opts \\ [])
      when is_integer(portfolio_id) and is_list(top_security_ids) do
    as_of = Keyword.get(opts, :as_of) || Clock.today()
    rate = Keyword.get(opts, :risk_free_rate) || @zero
    view = Keyword.get(opts, :view)
    leading_ids = Enum.take(top_security_ids, @max_correlated_names)

    read_walk = Keyword.get(opts, :analysis, &Performance.analysis/2)
    basis = Derived.portfolio_basis(portfolio_id)

    # The basis's version is read BEFORE the walk and carried in the entry
    # key (E25 S6, F46): a write landing between the walk and the metrics
    # stores them under the walk's version, which the next read — reading a
    # newer one — never asks for. The version `Derived.fetch/5` composes is
    # read later, at the fetch, and alone would file the old walk's metrics
    # as current.
    walk_version = Derived.current_version(basis)

    case read_walk.(portfolio_id, view: view, today: as_of) do
      {:error, :view_not_found} = error ->
        error

      %{} = analysis ->
        base = analysis.base_currency || Keyword.get(opts, :base_currency, @hub)
        compute = fn -> compute(analysis, leading_ids, as_of, rate, base) end

        # Only a whole-basis-point risk-free rate is remembered: a finer one
        # is computed on every read, so a sweep of distinct rates adds no
        # memo entry (E25 S4, G03). A walk served stale is never the basis
        # of a remembered result (F46).
        if Benchmark.memoisable_rate?(rate) and not Map.get(analysis, :stale, false) do
          {:fresh, metrics} =
            Derived.fetch(
              :portfolio_metrics,
              basis,
              entry_key(walk_version, view, as_of, rate, leading_ids, base),
              compute
            )

          metrics
        else
          compute.()
        end
    end
  end

  defp entry_key(walk_version, view, as_of, rate, ids, base) do
    "walk=#{walk_version}|view=#{view || "unscoped"}|as_of=#{as_of}|" <>
      "rf=#{Decimal.to_string(rate, :normal)}|base=#{base}|top=#{Enum.join(ids, ",")}"
  end

  defp compute(analysis, leading_ids, as_of, rate, base) do
    walk =
      PortfolioMetrics.compute(observations(analysis.daily), as_of,
        risk_free_rate: rate,
        daily_rate_factor: &Benchmark.daily_rate_factor/1
      )

    {series, excluded} = converted_series(leading_ids, as_of, base)
    correlations = PortfolioMetrics.correlations(series, as_of)

    %{
      as_of: as_of,
      base_currency: base,
      computation_basis: computation_basis(base, rate),
      volatility: walk.volatility,
      max_drawdown: walk.max_drawdown,
      risk_adjusted_return: walk.risk_adjusted_return,
      correlations:
        Map.merge(correlations, %{
          leading_names: length(leading_ids),
          security_ids: Enum.map(series, &elem(&1, 0)),
          excluded: excluded
        })
    }
  end

  # The chain's return factors, one per walked day that HAS a return base.
  # `prev` is the previous walked day's value, as the TTWROR chain reads it.
  defp observations(daily) do
    {observations, _prev} =
      Enum.flat_map_reduce(daily, @zero, fn point, prev ->
        case Performance.return_factor(point, prev) do
          {:ok, factor} -> {[%{date: point.date, factor: round_factor(factor)}], point.value}
          :no_return -> {[], point.value}
        end
      end)

    observations
  end

  # A walk converted through exchange rates leaves Decimal division residue in
  # a factor (0.999…9 at 34 places) on days nothing moved. That residue is not
  # a return, and left in it reads as a drawdown of "-0" and a risk-adjusted
  # return made of rounding noise (closing-act finding). 15 places keeps every
  # real daily return exactly and drops only the residue.
  defp round_factor(factor), do: Decimal.round(factor, @factor_scale)

  # ------------------------------------------------------------ correlations

  # Each Top-N security's split-adjusted closes over the correlation window,
  # converted into `base` at the rate stored on or before each close's day. A
  # close before the currency's first stored rate has no converted value and
  # is not a point; a currency with no stored rate at all is excluded.
  #
  # Rates are loaded from the window's start only, seeded with the one rate
  # stored on or before it, and walked together with the ascending closes in
  # one pass — the cost is closes + rates, not closes × every rate ever stored
  # (closing-act finding: 9,000 daily rates made the read take seconds).
  defp converted_series(ids, as_of, base) do
    from = Date.add(as_of, -PortfolioMetrics.correlation_window_days())
    securities = Repo.all(from(s in Security, where: s.id in ^ids)) |> Map.new(&{&1.id, &1})
    base_rates = hub_rate_series(base, from)

    {series, excluded} =
      ids
      |> Enum.filter(&Map.has_key?(securities, &1))
      |> Enum.reduce({[], []}, fn id, {series, excluded} ->
        security = Map.fetch!(securities, id)

        case convert(security, from, as_of, base, base_rates) do
          {:ok, points} -> {[{id, points} | series], excluded}
          :no_rate_path -> {series, [%{security_id: id, reason: "no_rate_path"} | excluded]}
        end
      end)

    {Enum.reverse(series), Enum.reverse(excluded)}
  end

  defp convert(%Security{} = security, from, as_of, base, base_rates) do
    closes =
      security.id
      |> Quotes.adjusted_range(from, as_of)
      |> Enum.map(&%{date: &1.date, close: &1.close})
      |> Enum.sort_by(& &1.date, Date)

    currency = security.currency_code || base

    cond do
      currency == base ->
        {:ok, closes}

      base_rates == :none ->
        :no_rate_path

      true ->
        case hub_rate_series(currency, from) do
          :none -> :no_rate_path
          rates -> {:ok, convert_points(closes, rates, base_rates)}
        end
    end
  end

  # One merge walk over the ascending closes and both ascending rate lists:
  # each rate cursor advances past every rate dated on or before the close.
  defp convert_points(closes, from_rates, base_rates) do
    {points, _cursors} =
      Enum.flat_map_reduce(closes, {from_rates, nil, base_rates, nil}, fn point,
                                                                          {fr, fcur, br, bcur} ->
        {fr, fcur} = advance(fr, fcur, point.date)
        {br, bcur} = advance(br, bcur, point.date)

        case {fcur, bcur} do
          {%Decimal{} = from_rate, %Decimal{} = base_rate} ->
            # EUR-hub rates are units of the currency per 1 EUR, so
            # close_in_base = close / from_rate × base_rate.
            converted = point.close |> Decimal.div(from_rate) |> Decimal.mult(base_rate)
            {[%{date: point.date, close: converted}], {fr, fcur, br, bcur}}

          _no_rate_yet ->
            {[], {fr, fcur, br, bcur}}
        end
      end)

    points
  end

  defp advance(:hub, _current, _date), do: {:hub, Decimal.new(1)}

  defp advance([{rate_date, rate} | rest] = rates, current, date) do
    if Date.compare(rate_date, date) != :gt,
      do: advance(rest, rate, date),
      else: {rates, current}
  end

  defp advance([], current, _date), do: {[], current}

  # `:hub` for EUR (always 1), `:none` for a currency with no stored rate, or
  # the ascending `{date, rate}` list from the window on, seeded with the rate
  # stored on or before its start — GBX as GBP × 100, as `Fx` resolves it.
  defp hub_rate_series(@hub, _from), do: :hub

  defp hub_rate_series("GBX", from) do
    case hub_rate_series("GBP", from) do
      rates when is_list(rates) ->
        Enum.map(rates, fn {d, r} -> {d, Decimal.mult(r, @gbx_per_gbp)} end)

      other ->
        other
    end
  end

  defp hub_rate_series(currency, from) do
    seed =
      case Fx.hub_rate_before(currency, from) do
        nil -> []
        row -> [{row.date, row.rate}]
      end

    in_window = currency |> Fx.series(from) |> Enum.map(&{&1.date, &1.rate})

    case Enum.uniq_by(seed ++ in_window, &elem(&1, 0)) do
      [] -> :none
      rates -> rates
    end
  end

  # ------------------------------------------------------------------- basis

  # AGENTS.md metric rule / ADR-0047 §6: the SHARED parts of the basis sit once;
  # the window — the part that varies — sits on each metric with its
  # observation count and `required`.
  defp computation_basis(base, rate) do
    %{
      input_series:
        "volatility, max_drawdown and risk_adjusted_return: the flow-adjusted daily " <>
          "return factors of the TTWROR chain over the daily valuation walk (ADR-0010), " <>
          "in the base currency #{base}, scoped by the active view — never the " <>
          "day-over-day change of the portfolio's value, so a deposit or a withdrawal " <>
          "is not a return (ADR-0047 §2). correlations: at most the " <>
          "#{@max_correlated_names} leading names of the Top-N list, largest first " <>
          "(correlations.leading_names states how many; the pair count grows with the " <>
          "square of the names, so the matrix is bounded while the list is not), by their " <>
          "own stored closes in the ADR-0028 §2 display basis, CONVERTED to #{base} at the " <>
          "exchange rate stored on or before each close's day (ADR-0047 §3)",
      window:
        "per metric: every metric carries the span it was measured over, or the span it " <>
          "was asked for when it refused, with its observation count and the minimum it " <>
          "required (ADR-0047 §6); the correlation matrix carries one window for all pairs",
      reference: reference(rate),
      gaps:
        "a walked day whose return base (previous value + flow + basis step) is zero or " <>
          "negative produces no return observation rather than a zero return; the walk's " <>
          "own carry-forward of prices and rates is unchanged, so a day on which nothing " <>
          "was re-priced is an observation of no movement (ADR-0047 §5). A correlation " <>
          "pair reads only the days on which BOTH securities have a stored close, with " <>
          "returns between consecutive shared days, and a close before its currency's " <>
          "first stored rate is not a point. A security whose currency has no stored " <>
          "rate path is absent from the matrix and listed in excluded. Below its minimum " <>
          "a metric is null with insufficient_data, its observations and required: " <>
          "#{PortfolioMetrics.min_return_observations()} return observations for " <>
          "volatility and risk_adjusted_return, #{PortfolioMetrics.min_drawdown_points()} " <>
          "index points for max_drawdown, #{PortfolioMetrics.min_pair_observations()} " <>
          "overlapping returns per correlation pair. A risk_adjusted_return over a " <>
          "volatility of exactly 0, and a correlation where either side never moved, is " <>
          "null without insufficient_data: the figure is undefined, not short of data. " <>
          "So is a figure whose square root the one float step cannot carry, a magnitude " <>
          "outside the double range that only implausible stored prices or rates reach: " <>
          "that volatility and the risk_adjusted_return beside it, or that correlation pair, " <>
          "is null without insufficient_data, never a number over such data (E25, F73)",
      assumptions:
        "volatility is the POPULATION standard deviation of the window's daily returns " <>
          "(divided by the observation count), annualized by " <>
          "√#{PortfolioMetrics.days_per_year()} — the walk is a calendar walk, one point " <>
          "per day (ADR-0047 §4). risk_adjusted_return is the mean daily excess return " <>
          "over the daily risk-free leg ((1 + risk_free_rate)^(1/365) − 1, ADR-0046's " <>
          "daily compounding), times #{PortfolioMetrics.days_per_year()}, divided by the " <>
          "annualized volatility. max_drawdown runs over the chained return index, which " <>
          "starts at 1 on the day before the window's first observation. Correlation is " <>
          "Pearson's over simple returns in a #{PortfolioMetrics.correlation_window_days()}-day " <>
          "window. Figures are ratios, not percentages (0.05 is +5 %), rounded at scale 6; " <>
          "the square root is the one float operation of AR-3's island and nothing float " <>
          "is persisted"
    }
  end

  defp reference(rate) do
    if Decimal.equal?(rate, @zero) do
      "risk_adjusted_return at risk_free_rate 0: the figure is return per unit of risk, " <>
        "not an excess return over a risk-free rate — none was supplied, and none is " <>
        "inferred, fetched or stored"
    else
      "risk_adjusted_return over the caller-supplied risk_free_rate " <>
        "#{Decimal.to_string(rate, :normal)} p.a. (a decimal fraction), compounded daily; " <>
        "the rate is the request's, never inferred, fetched or stored"
    end
  end
end
