defmodule Portfolixir.Engines.PortfolioMetrics do
  @moduledoc """
  The per-portfolio and per-view derived metrics of [ADR-0047](../../docs/decisions/0047-derived-metrics-per-security-and-per-view.md)
  §3 (FR-40, scope-ladder level (a)).

  This is an **engine** (architecture D2/P3): pure functions over injected
  series — no `Repo`, no clock, no config. `Portfolixir.Portfolios.RiskMetrics`
  loads the inputs and wraps the answer in its computation basis.

  ## What each metric is measured over

  **Volatility, drawdown and the risk-adjusted return read the TTWROR chain's
  flow-adjusted daily return factors** (§2) — `1 + r_d` with
  `r_d = V_d / (V_{d−1} + F_d + B_d) − 1` — and never the day-over-day change of
  the portfolio's value. A deposit moves the value and the return by nothing;
  a volatility over the value series would score it as movement, and the error
  would grow with how actively the operator saves. That is the invariant this
  whole record exists for (identity I1).

    * `volatility` — the **population** standard deviation of the window's
      daily returns `r_d`, annualized by `√365` (§4, identity I4): the walk is
      a **calendar** walk, one point per day, so its observations per year are
      365, not the 252 of a stored-close series. Refused below 20
      observations.
    * `max_drawdown` — over the **chained return index**, which starts at `1`
      on the day before the window's first observation and multiplies in each
      factor. Refused below 2 index points.
    * `risk_adjusted_return` — `(annualized mean daily return − risk-free) /
      annualized volatility`. Both halves are annualized from the same daily
      observations: the mean daily excess return `r_d − rf_d` times 365 over
      the daily deviation times `√365`, where `rf_d` is the risk-free rate
      compounded daily exactly as ADR-0046's fixed-rate benchmark is. The rate
      is the caller's, defaulting to `0`; nothing here infers or fetches one.
      Refused with the volatility, and `nil` — not a division by zero — when
      the volatility is exactly `0`.
    * `correlations` — the pairwise Pearson correlation of the Top-N single
      names' daily returns, over **converted** close series the caller
      supplies (base currency, §3). A pair reads only the days **both**
      securities closed on and carries its overlap count. Refused below 60
      overlapping observations; `nil` when either side never moved.

  ## A gap produces no observation

  The caller hands the engine only days that **have** a return: a walked day
  whose return base is zero or negative is not a return of zero, it is no
  return, and it is absent rather than entered as `1` (§5). The walk's own
  carry-forward is unchanged — it is what the valuation reads — so a quiet day
  on which nothing was re-priced is a real observation of no movement, which
  is exactly what I1 needs it to be.

  Every metric carries `observations`, what it read, and `required`, what it
  needs (§6 as amended 2026-09-19): on a computed metric and on a refused one
  alike, so a reader comparing two payloads never has to know which state
  they are in to find the threshold.
  """

  alias Portfolixir.Engines.Statistics

  @days_per_year 365

  # §3: the day windows the walk-derived metrics are computed over.
  @day_windows [{"30d", 30}, {"90d", 90}, {"365d", 365}]
  @correlation_window_days 365

  # §5, the stated minima.
  @min_return_observations 20
  @min_drawdown_points 2
  @min_pair_observations 60

  @zero Decimal.new(0)
  @one Decimal.new(1)

  @type observation :: %{date: Date.t(), factor: Decimal.t()}
  @type close_point :: %{date: Date.t(), close: Decimal.t()}

  @doc """
  Volatility, maximum drawdown and risk-adjusted return per §3 window.

  `observations` are the chain's return factors `%{date, factor}`; order is not
  assumed and observations dated after `as_of` are not read.

  Options:

    * `:risk_free_rate` — the annual risk-free rate as a Decimal fraction
      (`0.02` is 2 % p.a.), default `0`.
    * `:daily_rate_factor` — `(1 + rate)^(1/365)` for that rate. The shell
      passes ADR-0046's own function so the convention is shared rather than
      restated; without it only the rate `0` is accepted.
  """
  @spec compute([observation()], Date.t(), keyword()) :: map()
  def compute(observations, %Date{} = as_of, opts \\ []) when is_list(observations) do
    rate = Keyword.get(opts, :risk_free_rate, @zero)
    rate_factor = daily_rate_factor(rate, opts)

    series =
      observations
      |> Enum.filter(&(Date.compare(&1.date, as_of) != :gt))
      |> Enum.sort_by(& &1.date, Date)

    Map.new([:volatility, :max_drawdown, :risk_adjusted_return], fn metric ->
      {metric,
       Map.new(@day_windows, fn {label, days} ->
         slice = slice(series, as_of, days)
         {label, metric(metric, slice, as_of, days, rate, rate_factor)}
       end)}
    end)
  end

  @doc """
  The pairwise correlation matrix of the Top-N single names (§3).

  `series` is an ordered list of `{security_id, [%{date, close}]}` — closes
  already converted to the base currency by the caller. Pairs come back in the
  input order (`a` before `b`), which is the lens's Top-N order.
  """
  @spec correlations([{integer(), [close_point()]}], Date.t()) :: map()
  def correlations(series, %Date{} = as_of) when is_list(series) do
    from = Date.add(as_of, -@correlation_window_days)

    prepared =
      Enum.map(series, fn {security_id, points} ->
        {security_id,
         points
         |> Enum.filter(&in_range?(&1.date, from, as_of))
         |> Enum.filter(&positive?(&1.close))
         |> Map.new(&{&1.date, &1.close})}
      end)

    %{
      window: %{start_date: from, end_date: as_of},
      pairs: pairs(prepared)
    }
  end

  @doc "The calendar walk's observations per year, for the basis (§4, I4)."
  @spec days_per_year() :: pos_integer()
  def days_per_year, do: @days_per_year

  @doc "The labelled day windows (§3)."
  @spec day_windows() :: [{String.t(), pos_integer()}]
  def day_windows, do: @day_windows

  @doc "The correlation matrix's window in days."
  @spec correlation_window_days() :: pos_integer()
  def correlation_window_days, do: @correlation_window_days

  @doc "The minimum return observations of volatility and the risk-adjusted return (§5)."
  @spec min_return_observations() :: pos_integer()
  def min_return_observations, do: @min_return_observations

  @doc "The minimum index points of the drawdown (§5)."
  @spec min_drawdown_points() :: pos_integer()
  def min_drawdown_points, do: @min_drawdown_points

  @doc "The minimum overlapping observations of one correlation pair (§5)."
  @spec min_pair_observations() :: pos_integer()
  def min_pair_observations, do: @min_pair_observations

  # --------------------------------------------------------------- volatility

  defp metric(:volatility, slice, as_of, days, _rate, _rate_factor) do
    observations = length(slice)

    if observations < @min_return_observations do
      refused(as_of, days, observations, @min_return_observations)
    else
      %{
        value: Statistics.annualized_deviation(returns(slice), @days_per_year),
        window: measured_window(slice),
        observations: observations,
        required: @min_return_observations,
        insufficient_data: false
      }
    end
  end

  # ----------------------------------------------------------------- drawdown

  defp metric(:max_drawdown, slice, as_of, days, _rate, _rate_factor) do
    points = index_points(slice)
    count = length(points)

    if count < @min_drawdown_points do
      as_of
      |> refused(days, count, @min_drawdown_points)
      |> Map.merge(%{peak_date: nil, trough_date: nil, recovery_date: nil})
    else
      points
      |> Statistics.drawdown()
      |> Map.merge(%{
        window: %{start_date: List.first(points).date, end_date: List.last(points).date},
        observations: count,
        required: @min_drawdown_points,
        insufficient_data: false
      })
    end
  end

  # ---------------------------------------------------- risk-adjusted return

  defp metric(:risk_adjusted_return, slice, as_of, days, rate, rate_factor) do
    observations = length(slice)

    base =
      if observations < @min_return_observations do
        refused(as_of, days, observations, @min_return_observations)
      else
        %{
          value: sharpe(returns(slice), rate_factor),
          window: measured_window(slice),
          observations: observations,
          required: @min_return_observations,
          insufficient_data: false
        }
      end

    Map.put(base, :risk_free_rate, rate)
  end

  # (mean(r_d − rf_d) × 365) / (σ_daily × √365). The deviation is taken over
  # the raw returns: a constant daily risk-free leg shifts the mean and leaves
  # the deviation unchanged.
  defp sharpe(returns, rate_factor) do
    variance = Statistics.population_variance(returns)

    # The ratio follows the volatility the reader sees beside it: when that
    # rounds to 0 at scale 6 the ratio is undefined, never a quotient of
    # rounding residue (closing-act finding).
    if Decimal.equal?(Statistics.annualized_deviation(returns, @days_per_year), @zero) do
      nil
    else
      daily_rf = Decimal.sub(rate_factor, @one)

      excess =
        returns
        |> Enum.map(&Decimal.sub(&1, daily_rf))
        |> Statistics.mean()
        |> Decimal.mult(@days_per_year)

      volatility = variance |> Decimal.mult(@days_per_year) |> Statistics.square_root()

      excess |> Decimal.div(volatility) |> Statistics.round_scale()
    end
  end

  # ----------------------------------------------------------------- matrices

  defp pairs(prepared) do
    for {{id_a, closes_a}, index} <- Enum.with_index(prepared),
        {id_b, closes_b} <- Enum.drop(prepared, index + 1) do
      pair(id_a, closes_a, id_b, closes_b)
    end
  end

  # A pair reads only the days on which BOTH securities have a close; returns
  # are taken between consecutive shared days, so neither side is carried
  # forward across a day the other one priced.
  defp pair(id_a, closes_a, id_b, closes_b) do
    shared =
      closes_a
      |> Map.keys()
      |> Enum.filter(&Map.has_key?(closes_b, &1))
      |> Enum.sort(Date)

    returns_a = shared |> Enum.map(&Map.fetch!(closes_a, &1)) |> simple_returns()
    returns_b = shared |> Enum.map(&Map.fetch!(closes_b, &1)) |> simple_returns()
    observations = length(returns_a)
    insufficient? = observations < @min_pair_observations

    %{
      security_id_a: id_a,
      security_id_b: id_b,
      value: if(insufficient?, do: nil, else: Statistics.pearson(returns_a, returns_b)),
      observations: observations,
      required: @min_pair_observations,
      insufficient_data: insufficient?
    }
  end

  defp simple_returns(closes) do
    closes
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [previous, current] ->
      current |> Decimal.sub(previous) |> Decimal.div(previous)
    end)
  end

  # ------------------------------------------------------------------ helpers

  # The window's observations: dated after `as_of − days`, so the day
  # `as_of − days` is the window's baseline and a 30-day window reads at most
  # 30 returns.
  defp slice(series, as_of, days) do
    from = Date.add(as_of, -days)
    Enum.filter(series, &(Date.compare(&1.date, from) == :gt))
  end

  defp returns(slice), do: Enum.map(slice, &Decimal.sub(&1.factor, @one))

  # The chained return index: `1` on the day before the first observation,
  # then the running product. The baseline is what makes a first-day fall a
  # drawdown rather than the peak.
  defp index_points([]), do: []

  defp index_points([first | _] = slice) do
    baseline = %{date: Date.add(first.date, -1), value: @one}

    {points, _level} =
      Enum.map_reduce(slice, @one, fn observation, level ->
        level = Decimal.mult(level, observation.factor)
        {%{date: observation.date, value: level}, level}
      end)

    [baseline | points]
  end

  # A measured window starts on the day the first return is measured FROM —
  # the day before the first observation — like a close series' window starts
  # on its first close.
  defp measured_window([first | _] = slice),
    do: %{start_date: Date.add(first.date, -1), end_date: List.last(slice).date}

  defp refused(as_of, days, observations, required) do
    %{
      value: nil,
      window: %{start_date: Date.add(as_of, -days), end_date: as_of},
      observations: observations,
      required: required,
      insufficient_data: true
    }
  end

  defp daily_rate_factor(rate, opts) do
    case Keyword.fetch(opts, :daily_rate_factor) do
      {:ok, fun} when is_function(fun, 1) ->
        fun.(rate)

      :error ->
        if Decimal.equal?(rate, @zero),
          do: @one,
          else: raise(ArgumentError, "a non-zero risk-free rate needs :daily_rate_factor")
    end
  end

  defp in_range?(date, from, to),
    do: Date.compare(date, from) != :lt and Date.compare(date, to) != :gt

  defp positive?(%Decimal{} = value), do: Decimal.compare(value, @zero) == :gt
  defp positive?(_value), do: false
end
