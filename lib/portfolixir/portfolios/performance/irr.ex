defmodule Portfolixir.Portfolios.Performance.IRR do
  @moduledoc """
  Money-weighted return (IRR / XIRR) over the same daily series and external
  flows that `Portfolixir.Portfolios.Performance.summarise/2` already produces.

  Where TTWROR neutralises the timing of deposits and withdrawals, the IRR is
  the single annualised rate `r` that discounts every dated cashflow back to
  zero:

      NPV(r) = Σ cf_i / (1 + r) ^ (days_i / 365) = 0

  The cashflow vector is derived from a period summary: the value at the start
  of the period is the first outflow, each external `flow` on its date is an
  outflow (money put in) or inflow (money taken out), and the period's
  `end_value` is the final inflow. The sign convention mirrors the series'
  `flow` (positive = money entering the portfolio), so a contribution is a
  negative cashflow from the investor's point of view and the terminal value is
  a positive one.

  ## Decimal vs. float

  Money inputs stay `Decimal` end to end. Fractional exponentiation
  (`(1 + r) ^ (days / 365)`) is impractical in pure `Decimal`, so the numeric
  root-find converts the cashflow amounts to floats **only at the solver
  boundary** and returns the solved rate as a `Decimal` rounded to six decimal
  places. This is consistent with the project rule that floats are forbidden
  for *persisted financial values*: the IRR is a derived, displayed ratio, not
  a stored money value, and nothing about the cashflows themselves is kept as a
  float.

  ## Method

  Bisection (derivative-free and robust) on a bracket `[lower, upper]`. The
  bracket must show a sign change of `NPV` across its ends; without one there
  is no rate to find. Deterministic given the same inputs and options.

  Returns `Decimal.t()` on success and `nil` for every degenerate case —
  fewer than two cashflows, all flows the same sign, no sign change of `NPV`
  across the bracket, or non-convergence within `max_iterations`. It never
  raises.
  """

  @type cashflow :: {Date.t(), Decimal.t()}

  @zero Decimal.new("0")
  @days_per_year 365.0
  @scale 6

  @default_lower -0.999999
  @default_upper 1.0e7
  @default_tolerance 1.0e-7
  @default_max_iterations 100

  @doc """
  Computes the IRR for a period summary (a `summarise/2` result).

  Builds the cashflow vector from the summary's `start_value`, daily `series`
  flows and `end_value`, then solves `NPV(r) = 0`. Returns `Decimal.t()` or
  `nil`.

  Options (all injectable for deterministic tests):

    * `:max_iterations` — bisection steps (default #{@default_max_iterations}).
    * `:tolerance` — `|NPV|` accepted as a root (default #{@default_tolerance}).
    * `:bracket` — `{lower, upper}` rate bounds
      (default `{#{@default_lower}, #{@default_upper}}`).
  """
  @spec for_summary(map(), keyword()) :: Decimal.t() | nil
  def for_summary(summary, opts \\ []) when is_map(summary) do
    summary
    |> cashflows()
    |> compute(opts)
  end

  @doc """
  Solves `NPV(r) = 0` for an explicit list of dated cashflows.

  Each cashflow is `{Date.t(), Decimal.t()}`; a positive amount is an inflow to
  the investor. Returns `Decimal.t()` or `nil`.
  """
  @spec compute([cashflow()], keyword()) :: Decimal.t() | nil
  def compute(cashflows, opts \\ [])

  def compute(cashflows, _opts) when length(cashflows) < 2, do: nil

  def compute(cashflows, opts) do
    if sign_change?(cashflows) do
      solve(cashflows, opts)
    else
      nil
    end
  end

  @doc """
  Derives the cashflow vector from a period summary.

  Exposed for testing the sign convention directly.
  """
  @spec cashflows(map()) :: [cashflow()]
  def cashflows(%{series: series, start_value: start_value, end_value: end_value} = summary) do
    start_date = Map.get(summary, :start_date)
    end_date = Map.get(summary, :end_date)

    initial = initial_flow(start_date, start_value)
    contributions = Enum.flat_map(series, &flow_cashflow/1)
    terminal = terminal_flow(end_date, series, end_value)

    initial ++ contributions ++ terminal
  end

  def cashflows(_summary), do: []

  defp initial_flow(%Date{} = date, %Decimal{} = start_value) do
    if Decimal.compare(start_value, @zero) == :gt do
      [{date, Decimal.negate(start_value)}]
    else
      []
    end
  end

  defp initial_flow(_date, _start_value), do: []

  # A day's external flow is money entering (+) or leaving (−) the portfolio;
  # from the investor's side that is a contribution (−) or a withdrawal (+).
  defp flow_cashflow(%{date: %Date{} = date, flow: %Decimal{} = flow}) do
    if Decimal.equal?(flow, @zero) do
      []
    else
      [{date, Decimal.negate(flow)}]
    end
  end

  defp flow_cashflow(_point), do: []

  defp terminal_flow(%Date{} = end_date, _series, %Decimal{} = end_value) do
    [{end_date, end_value}]
  end

  defp terminal_flow(nil, [_ | _] = series, %Decimal{} = end_value) do
    [{List.last(series).date, end_value}]
  end

  defp terminal_flow(_end_date, _series, _end_value), do: []

  defp sign_change?(cashflows) do
    signs =
      cashflows
      |> Enum.map(fn {_date, amount} -> Decimal.compare(amount, @zero) end)
      |> Enum.reject(&(&1 == :eq))
      |> Enum.uniq()

    length(signs) > 1
  end

  defp solve(cashflows, opts) do
    {lower, upper} = Keyword.get(opts, :bracket, {@default_lower, @default_upper})
    tolerance = Keyword.get(opts, :tolerance, @default_tolerance)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)

    points = numeric_points(cashflows)
    npv_lower = npv(points, lower)
    npv_upper = npv(points, upper)

    if bracketed?(npv_lower, npv_upper) do
      bisect(points, lower, upper, npv_lower, tolerance, max_iterations)
    else
      nil
    end
  end

  # Converts the dated Decimal cashflows to `{years_from_first, amount_float}`
  # once, at the solver boundary; the bisection then works purely on floats.
  defp numeric_points(cashflows) do
    {first_date, _amount} = hd(cashflows)

    Enum.map(cashflows, fn {date, amount} ->
      {Date.diff(date, first_date) / @days_per_year, Decimal.to_float(amount)}
    end)
  end

  defp npv(points, rate) do
    base = 1.0 + rate

    Enum.reduce(points, 0.0, fn {years, amount}, acc ->
      acc + amount / :math.pow(base, years)
    end)
  end

  # A valid bracket must straddle the root: one end's NPV positive, the other
  # negative (a zero at an end is already the root).
  defp bracketed?(npv_lower, npv_upper) do
    npv_lower == 0.0 or npv_upper == 0.0 or npv_lower * npv_upper < 0.0
  end

  # Exhausting the iteration budget without reaching the tolerance is treated
  # as non-convergence: no IRR rather than a half-solved guess.
  defp bisect(_points, _lower, _upper, _npv_lower, _tolerance, 0), do: nil

  defp bisect(points, lower, upper, npv_lower, tolerance, iterations) do
    mid = (lower + upper) / 2.0
    npv_mid = npv(points, mid)

    cond do
      abs(npv_mid) <= tolerance ->
        finalize(mid)

      npv_lower * npv_mid < 0.0 ->
        bisect(points, lower, mid, npv_lower, tolerance, iterations - 1)

      true ->
        bisect(points, mid, upper, npv_mid, tolerance, iterations - 1)
    end
  end

  defp finalize(rate) do
    rate
    |> Decimal.from_float()
    |> Decimal.round(@scale)
  end
end
