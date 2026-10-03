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
  positions are named (§10). A trade priced in a currency with no rate path
  on its booking day flows into its position at its cash leg, so the
  position is not credited with its whole value when a rate arrives (§5, as
  amended 2026-10-03).

  Nothing is persisted (§12). Each read runs its own walk with a window, and
  the table is a derived value of its own (ADR-0039): the
  `:performance_contribution` analytic under the portfolio's basis, and
  `:performance_view_contribution` under the global basis for a view across
  portfolios, computation version 1, lifetime `:request` by default, keyed
  by scope, walk end date and period. The stored walk analytics never carry
  the per-position figures.
  """

  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Derived
  alias Portfolixir.Portfolios.Performance

  @zero Decimal.new("0")
  @hub "EUR"

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
          stale: boolean(),
          computation_basis: %{
            input_series: String.t(),
            window: %{start_date: Date.t() | nil, end_date: Date.t()},
            reference: nil,
            gaps: String.t(),
            assumptions: String.t()
          }
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
  `positions`, `remainder` and `totals`, the instant its walk was computed
  as `as_of`, and `stale: false`: a memoised table is only served while the
  portfolio's data version is unchanged (ADR-0039 C4). `computation_basis`
  states the metric's input series, window, reference (none), gap treatment
  and assumptions in the payload (AGENTS.md metric rule, ADR-0051 §11).

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
      compute = fn ->
        portfolio_id
        |> Performance.contribution_analysis(scope, period, today: today)
        |> build(period)
        |> Map.merge(%{portfolio_id: portfolio_id, view_id: view})
      end

      key = "view=#{view || "unscoped"}|today=#{today}|period=#{period_key(period)}"

      {:ok,
       served(
         :performance_contribution,
         Derived.portfolio_basis(portfolio_id),
         key,
         {period, today},
         compute
       )}
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
    base = Keyword.get(opts, :base_currency, @hub)
    today = Keyword.get(opts, :today, Clock.today())

    with :ok <- Performance.validate_period(period),
         {:ok, scope} <- loaded(Buckets.load_global_scope(view_id)) do
      compute = fn ->
        view_id
        |> Performance.view_contribution_analysis(scope, period,
          base_currency: base,
          today: today
        )
        |> build(period)
        |> Map.merge(%{portfolio_id: nil, view_id: view_id})
      end

      key =
        "view=#{view_id || "unscoped"}|base=#{base}|today=#{today}|period=#{period_key(period)}"

      {:ok,
       served(
         :performance_view_contribution,
         Derived.global_basis(),
         key,
         {period, today},
         compute
       )}
    end
  end

  defp loaded({:error, :view_not_found} = error), do: error
  defp loaded(scope), do: {:ok, scope}

  # -- the analytic (ADR-0051 §12, ADR-0039) ------------------------------------

  # Its own analytic per scope and period, keyed like the walk analytics --
  # the walk's end date within the basis -- plus the period. Only the fixed
  # periods are memoised: a custom range, or a calendar year past today, is
  # computed on every read, so a sweep of distinct ranges adds nothing to the
  # memo (E25 S4, G03). Freshness is annotated outside the memoised value
  # (ADR-0039 C4): a memo hit counts only while its basis's data version is
  # current, so whatever is served here is fresh.
  defp served(analytic, basis, key, {period, today}, compute) do
    value =
      if fixed_period?(period, today) do
        {:fresh, value} = Derived.fetch(analytic, basis, key, compute)
        value
      else
        compute.()
      end

    Map.put(value, :stale, false)
  end

  defp fixed_period?({:year, year}, today), do: year <= today.year
  defp fixed_period?(period, _today) when is_binary(period), do: true
  defp fixed_period?(_range, _today), do: false

  defp period_key({:year, year}), do: "year:#{year}"
  defp period_key({:range, from, to}), do: "range:#{from}..#{to}"
  defp period_key(period) when is_binary(period), do: period

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
      computation_basis: computation_basis(summary.start_date, summary.end_date)
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
      computation_basis: computation_basis(nil, summary.end_date)
    }
  end

  # The metric's basis IN the payload (AGENTS.md metric rule, ADR-0051 §11):
  # input series, window, reference and the treatment of gaps, plus the
  # assumptions (ADR-0046's key) a reader needs to check a row by hand. Two
  # precisions ride along that the record left implicit: the identity is exact
  # only while the conversion quotients terminate, and the currency line holds
  # a trade's settlement difference.
  defp computation_basis(start_date, end_date) do
    %{
      input_series:
        "the daily valuation walk of ADR-0010 per position: recorded transactions, " <>
          "stored quotes and stored EUR-hub exchange rates, each position's figures kept " <>
          "apart inside the window (ADR-0051 §5), the walk the TTWROR and the money " <>
          "result of this scope read",
      window: %{start_date: start_date, end_date: end_date},
      reference: nil,
      gaps:
        "a day on which a held position has no price, or no rate path to the base " <>
          "currency, counts zero, as in the walk; the position stays in the sum, and the " <>
          "affected positions are listed with their days (unvalued_days, and " <>
          "unvalued_reason no_price or no_rate; ADR-0051 §10). Prices and rates carry the " <>
          "most recent stored point on or before each day forward, and a security with no " <>
          "quote yet is priced by its own latest trade (ADR-0010). A window holding no " <>
          "walked day is empty: start_date null and no positions, never a table of zeros " <>
          "(ADR-0051 §4). A foreign-currency cash balance likewise counts zero on a day " <>
          "its currency has no rate path; when the first rate arrives, the balance's whole " <>
          "value enters cash_currency_effect, and no account is named for it",
      assumptions:
        "per position, in the base currency, contribution = end_value − start_value − " <>
          "net_flows + income − costs over the window (ADR-0051 §1): start_value is the " <>
          "close of the last day the walk covers before the window (0 when not held then, " <>
          "or when the walk starts inside it) and end_value the window's last day (0 when " <>
          "sold out); net_flows counts a buy + price × quantity and a sell − price × " <>
          "quantity at the booking day's rate (a trade priced in a currency with no rate " <>
          "path that day: its cash leg), a delivery ± the value the walk's external " <>
          "flow gives it, a split and a transfer inside the scope 0, and a leg crossing a " <>
          "view's edge as its boundary flow (ADR-0019); income is the dividends as " <>
          "credited; costs are the fees and taxes on the position's own trades (#708). " <>
          "The positions plus the remainder lines sum to totals.result, end value − start " <>
          "value − net external flows of the scope over the window, the money result " <>
          "beside the TTWROR (ADR-0051 §3). Each line is summed from its own bookings and " <>
          "is never a plug: interest is every interest booking; standalone_fees_and_taxes " <>
          "the fee, tax and tax refund bookings no trade carries; cash_currency_effect the " <>
          "revaluation of foreign-currency cash, plus the settlement difference of a trade " <>
          "between its cash leg and price × quantity plus costs on the booking day, plus " <>
          "what a cash transfer between currencies leaves. Every figure is in the base " <>
          "currency, currency move included: a foreign-currency position's contribution " <>
          "is its money result in the base currency, not split into price and currency " <>
          "(ADR-0051 §7). Exact in " <>
          "Decimal whenever every conversion quotient terminates; otherwise the walk's sums " <>
          "round at Decimal's 34 significant digits, the identity holds to that precision, " <>
          "and nothing balances the difference. Positions are sorted by contribution, " <>
          "largest first; there is no share, rank or label (ADR-0051 §2)"
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
