defmodule Portfolixir.Portfolios.Performance.Contribution do
  @moduledoc """
  Contribution analysis (FR-41, ADR-0051, scope-ladder level (b)): which
  position made how much of a period's money result.

  Per position, in the base currency, over the window of a period:

      contribution = end value − start value − net flows + income − costs

  The positions plus three remainder lines sum **exactly in `Decimal`** to
  the period's money result, `end value − start value − net external flows`,
  the "+x EUR in the period" figure beside the TTWROR (ADR-0051 §1, §3, I1).

  This is the performance walk (`Portfolixir.Portfolios.Performance`, ADR-0010)
  keeping each position's figures apart inside the window instead of summing
  them away (§5). It reads only legs the walk applies anyway; the walk's
  TTWROR, IRR, series and every other output stay byte-identical, and its
  computation version does not move (I9).

  The terms (§1, §5):

    * **start value** — the position's value at the close of the last day the
      walk covers before the window; `0` when it was not held then, or when
      the walk starts inside the window (the walk's baseline rule, §4);
    * **end value** — its value at the window's last day; `0` when sold out;
    * **net flows** — a buy `+ price × quantity`, a sell `− price × quantity`,
      each at the booking day's rate; a delivery `±` the value the walk's
      external flow gives it (its booked price, else the day's price, #779);
      a split and a transfer inside the scope `0`; a leg crossing a view's
      boundary the boundary flow the walk books for it (ADR-0019, §6);
    * **income** — dividends as credited, at the booking day's rate;
    * **costs** — the fees and taxes carried by the position's own trades
      (#708's trade costs, kept per security), counted when the whole trade
      is inside the scope.

  The remainder lines (§3), each summed from its own bookings and **never a
  plug** (the result minus the positions):

    * `interest` — every `interest` booking;
    * `standalone_fees_and_taxes` — `fee`, `tax` and `tax_refund` bookings,
      even when one names a security;
    * `cash_currency_effect` — the revaluation of cash balances in foreign
      currencies, plus the settlement difference of a trade between its cash
      leg and its security leg plus costs on the booking day (ADR-0015,
      ADR-0033), plus whatever an internal cash transfer between accounts of
      different currencies leaves in the base currency.

  Deposits, removals, the value of deliveries and the residual jump of a
  balance snapshot are external flows: they never reach the result, so they
  never reach the remainder either. Money paid into a foreign-currency
  account is no contribution; what the larger balance does with the rate
  afterwards is the currency effect on cash.

  Scoped to a view, a booking is read through the legs the walk keeps
  (ADR-0019): a dividend credited to an in-view account is its security's
  income even when the position sits outside the view (the view received
  it); a trade whose cash leg is outside the view brings its units in at the
  cash they cost, fees included, as a boundary flow, so it carries no cost
  line of its own; a trade whose units leave the view only moves cash across
  the edge and is kept nowhere.

  **Exactness.** Every term is computed by the walk's own arithmetic, in
  `Decimal`. With conversion rates whose quotients terminate the identity is
  exact to the last digit; with a rate quotient that does not terminate, the
  walk's own sums round at the `Decimal` context's precision, and the
  identity holds to that precision. Nothing balances the difference.

  Missing data contributes zero, as it does in the walk, and the affected
  positions are named (§10). Nothing is stored: everything is derived on
  read.
  """

  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Portfolios.Performance

  @zero Decimal.new("0")

  @typedoc "One position's row (ADR-0051 §11)."
  @type position :: %{
          security_id: integer(),
          name: String.t() | nil,
          isin: String.t() | nil,
          start_value: Decimal.t(),
          end_value: Decimal.t(),
          net_flows: Decimal.t(),
          income: Decimal.t(),
          costs: Decimal.t(),
          contribution: Decimal.t(),
          held_at_start: boolean(),
          held_at_end: boolean(),
          unvalued_days: non_neg_integer(),
          unvalued_reason: :no_price | :no_rate | nil
        }

  @type result :: %{
          portfolio_id: integer() | nil,
          view_id: integer() | nil,
          period: term(),
          base_currency: String.t() | nil,
          start_date: Date.t() | nil,
          end_date: Date.t(),
          positions: [position()],
          remainder: %{
            interest: Decimal.t(),
            standalone_fees_and_taxes: Decimal.t(),
            cash_currency_effect: Decimal.t()
          },
          totals: %{result: Decimal.t(), positions: Decimal.t(), remainder: Decimal.t()},
          as_of: DateTime.t(),
          stale: boolean()
        }

  @doc """
  The contribution of every position of one portfolio over a period.

  Options:

    * `:period` — exactly `Performance.summarise/2`'s periods: one of
      `#{inspect(Performance.periods())}`, `{:year, year}` or
      `{:range, from, to}` (default `"max"`), with the walk's clamping;
    * `:view` — a view id narrowing the portfolio (ADR-0019 boundary flows);
    * `:today` — the walk's end date (default `Clock.today()`).

  Returns `{:ok, result}` or `{:error, :invalid_period | :view_not_found}`.

  The result carries `portfolio_id`, `view_id` (the `:view` given, or `nil`),
  `period`, `base_currency`, the window's `start_date` and `end_date`,
  `positions`, `remainder` and `totals`, and the walk's `as_of` with
  `stale: false` (ADR-0039 C4: the walk is computed for this read).

  Each position carries `security_id`, `name`, `isin`, `start_value`,
  `end_value`, `net_flows`, `income`, `costs`, `contribution`,
  `held_at_start`, `held_at_end`, `unvalued_days` and `unvalued_reason`.
  Positions are sorted by contribution, largest first; equal contributions
  by name, then id. A position sold inside the window is listed with an end
  value of 0.

  `unvalued_days` counts the window days on which the position was held and
  the walk valued it at zero; `unvalued_reason` is `:no_price` (no price at
  all) or `:no_rate` (no rate path to the base currency), `:no_price` when
  both occurred, and `nil` when every day was valued. Such a position stays
  in the table and in the sum (ADR-0051 §10, I7).

  `remainder` carries `interest`, `standalone_fees_and_taxes` and
  `cash_currency_effect`. `totals.result` is `end value − start value − net
  external flows` exactly as the performance read chains it,
  `totals.positions` the sum of the contributions, and `totals.remainder` the
  sum of the three lines; `totals.positions + totals.remainder ==
  totals.result` (ADR-0051 I1).

  A window holding no walked day — a future year, a range before the
  history, a portfolio with nothing booked yet — is the walk's honest
  emptiness: `start_date: nil`, no positions, and zero lines and totals,
  never a table of zeros.
  """
  @spec for_portfolio(integer(), keyword()) :: {:ok, result()} | {:error, atom()}
  def for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    period = Keyword.get(opts, :period, "max")
    view = Keyword.get(opts, :view)
    today = Keyword.get(opts, :today, Clock.today())

    with :ok <- Performance.validate_period(period),
         {:ok, scope} <- loaded(Buckets.load_scope(portfolio_id, view)) do
      result =
        portfolio_id
        |> Performance.contribution_analysis(scope, period, today: today)
        |> build(period)
        |> Map.merge(%{portfolio_id: portfolio_id, view_id: view})

      {:ok, result}
    end
  end

  @doc """
  The contribution of every position of a bucket view **across all
  portfolios** (ADR-0024), over the scope `Performance.for_view/2` walks:
  each account counted once, money crossing the view's edge a boundary flow
  (ADR-0019). `view_id == nil` is the Everything scope.

  Options: `:period` and `:today` as in `for_portfolio/2`, and
  `:base_currency` (default the EUR hub), the one currency every portfolio's
  slice is valued in. A position held in several portfolios is one row, its
  figures summed.

  Returns `{:ok, result}` — `for_portfolio/2`'s shape with `portfolio_id:
  nil` and `view_id` set — or `{:error, :invalid_period | :view_not_found}`.
  """
  @spec for_view(integer() | nil, keyword()) :: {:ok, result()} | {:error, atom()}
  def for_view(view_id, opts \\ []) when is_integer(view_id) or is_nil(view_id) do
    period = Keyword.get(opts, :period, "max")

    walk_opts =
      [today: Keyword.get(opts, :today, Clock.today())] ++ Keyword.take(opts, [:base_currency])

    with :ok <- Performance.validate_period(period),
         {:ok, scope} <- loaded(Buckets.load_global_scope(view_id)) do
      result =
        view_id
        |> Performance.view_contribution_analysis(scope, period, walk_opts)
        |> build(period)
        |> Map.merge(%{portfolio_id: nil, view_id: view_id})

      {:ok, result}
    end
  end

  defp loaded({:error, :view_not_found} = error), do: error
  defp loaded(scope), do: {:ok, scope}

  # -- the table -----------------------------------------------------------------

  defp build(analysis, period) do
    {:ok, summary} = Performance.summarise(analysis, period)

    case analysis.contribution do
      nil -> empty(summary)
      kept -> table(summary, kept)
    end
  end

  defp table(summary, kept) do
    positions =
      kept.positions
      |> Enum.map(fn {security_id, figures} -> row(security_id, figures, kept.securities) end)
      |> Enum.sort(&before?/2)

    remainder = kept.lines
    position_total = sum(Enum.map(positions, & &1.contribution))
    remainder_total = sum(Map.values(remainder))

    %{
      period: summary.period,
      base_currency: summary.base_currency,
      start_date: summary.start_date,
      end_date: summary.end_date,
      positions: positions,
      remainder: remainder,
      totals: %{
        result: money_result(summary),
        positions: position_total,
        remainder: remainder_total
      },
      as_of: summary.as_of,
      stale: false
    }
  end

  defp empty(summary) do
    %{
      period: summary.period,
      base_currency: summary.base_currency,
      start_date: nil,
      end_date: summary.end_date,
      positions: [],
      remainder: %{
        interest: @zero,
        standalone_fees_and_taxes: @zero,
        cash_currency_effect: @zero
      },
      totals: %{result: money_result(summary), positions: @zero, remainder: @zero},
      as_of: summary.as_of,
      stale: false
    }
  end

  # The "+x EUR in the period" figure, from the very summary the performance
  # read shows (ADR-0051 §3).
  defp money_result(summary) do
    summary.end_value
    |> Decimal.sub(summary.start_value)
    |> Decimal.sub(summary.net_external_flows)
  end

  defp row(security_id, figures, securities) do
    label = Map.get(securities, security_id, %{name: nil, isin: nil})

    contribution =
      figures.end_value
      |> Decimal.sub(figures.start_value)
      |> Decimal.sub(figures.net_flows)
      |> Decimal.add(figures.income)
      |> Decimal.sub(figures.costs)

    %{
      security_id: security_id,
      name: label.name,
      isin: label.isin,
      start_value: figures.start_value,
      end_value: figures.end_value,
      net_flows: figures.net_flows,
      income: figures.income,
      costs: figures.costs,
      contribution: contribution,
      held_at_start: figures.held_at_start,
      held_at_end: figures.held_at_end,
      unvalued_days: map_size(figures.unvalued),
      unvalued_reason: unvalued_reason(Map.values(figures.unvalued))
    }
  end

  # Without a price no rate helps, so a missing price names the position
  # before a missing rate does.
  defp unvalued_reason([]), do: nil

  defp unvalued_reason(reasons),
    do: if(:no_price in reasons, do: :no_price, else: :no_rate)

  # Largest contribution first; ties by name, then id, so the order is stable.
  defp before?(a, b) do
    case Decimal.compare(a.contribution, b.contribution) do
      :gt -> true
      :lt -> false
      :eq -> {a.name || "", a.security_id} <= {b.name || "", b.security_id}
    end
  end

  defp sum(decimals), do: Enum.reduce(decimals, @zero, &Decimal.add(&2, &1))
end
