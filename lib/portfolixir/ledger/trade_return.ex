defmodule Portfolixir.Ledger.TradeReturn do
  @moduledoc """
  The annualized return of one closed round-trip (#984 rescoped, Sprint 17
  T1, plan D-7): how fast the money in the trade grew per year, so a
  two-week trade and a three-year trade with the same percentage no longer
  read alike.

  ## The rule

  The figure is the round-trip's **money-weighted** return, the existing
  XIRR solver (`Portfolixir.Portfolios.Performance.IRR`, ADR-0034 §2) over
  the trade's own flows: each consumed lot's buy on its open date for its
  prorated cost (`TradeMatcher`'s `lots`), and the sell's proceeds on the
  close date. Flows are in the trade's own currency, the currency of the
  `realized_pnl_pct` it annualizes; the base-currency result is not what
  it annualizes.

  **Under 365 days of holding it is `nil`** (ADR-0034 §2 refuses to
  annualize a window under a year for the MWR, and the GIPS convention is
  the same): 5 % in 14 days would read as about 257 % a year. The holding
  period is the trade's own `holding_period_days`, the quantity-weighted
  figure the row shows, not the span from the oldest consumed lot: a sell
  that takes one old share and ninety-nine new ones is a short trade, and
  annualizing it would explode exactly as a short window does. So the
  column and the "Haltedauer" beside it can never disagree about the
  threshold.

  ## Float boundary

  Nothing here is a float. The cashflows go to `IRR.solve/2` as `Decimal`s,
  as they are: the solver scales a large trade's flows itself, for every
  caller (ADR-0034 amendment of 2026-10-02, #1031). The rate comes back as a
  `Decimal` rounded to six places; the one float step stays inside the
  solver, which is all ADR-0034 §2's exception grants. Nothing is persisted.
  """

  alias Portfolixir.Portfolios.Performance.IRR

  @min_holding_days 365

  @type reason ::
          :holding_period_under_365_days | IRR.reason()

  @doc """
  The annualized return of a closed trade from `TradeMatcher.match/1`:
  `%{annualized_return: Decimal.t() | nil, annualized_return_reason: reason | nil}`.

  `opts` are the solver's (`IRR.solve/2`), injectable for tests.
  """
  @spec annualized(map(), keyword()) :: %{
          annualized_return: Decimal.t() | nil,
          annualized_return_reason: reason() | nil
        }
  def annualized(trade, opts \\ [])

  def annualized(%{holding_period_days: days}, _opts) when days < @min_holding_days,
    do: none(:holding_period_under_365_days)

  def annualized(%{lots: lots, close_date: close_date, proceeds: proceeds}, opts) do
    buys = Enum.map(lots, fn lot -> {lot.open_date, Decimal.negate(lot.cost)} end)

    case IRR.solve(buys ++ [{close_date, proceeds}], opts) do
      {:ok, rate} -> %{annualized_return: rate, annualized_return_reason: nil}
      {:error, reason} -> none(reason)
    end
  end

  defp none(reason), do: %{annualized_return: nil, annualized_return_reason: reason}

  @doc """
  The rule as one sentence, carried by every payload that serves the figure
  (the AGENTS.md metric rule: the basis travels in the payload).
  """
  @spec basis() :: String.t()
  def basis do
    "annualized_return is the closed trade's money-weighted return per year, a fraction " <>
      "(0.1 = 10 % a year): the XIRR solver of ADR-0034 §2 (Act/365) over the trade's own " <>
      "flows, each consumed lot's buy on its open date for its prorated cost (quantity x buy " <>
      "price plus its buy fees and taxes prorated by the quantity taken) and the sell's " <>
      "proceeds net of fees and taxes on the close date, in the trade's own currency, the " <>
      "one realized_pnl_pct is in, never the base currency; rounded to 6 decimal places, " <>
      "and a loss stays above -1. No benchmark or other reference series enters it. " <>
      "It is null with annualized_return_reason " <>
      "holding_period_under_365_days when holding_period_days (the quantity-weighted days " <>
      "the trade shows, not the span from its oldest lot) is below #{@min_holding_days}, " <>
      "because annualizing a short window explodes the figure; and null with the solver's " <>
      "reason when no rate solves the flows: no_sign_change (proceeds or cost not positive, " <>
      "a total loss among them), no_root (no convergence inside the solver's budget) or " <>
      "amount_out_of_range. Dividends and interest are not flows: income received while " <>
      "the trade was open is not included."
  end
end
