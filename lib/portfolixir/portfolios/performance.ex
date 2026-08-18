defmodule Portfolixir.Portfolios.Performance do
  @moduledoc """
  Read-time portfolio performance: a daily valuation series and the true
  time-weighted rate of return (TTWROR), the Portfolio Performance way.

  The portfolio is valued **every day** from the first plausible transaction
  onward (positions priced from the most recent quote close on or before the
  day, converted to the base currency, plus cash). Each day's return
  neutralises **external cash flows** — deposits, removals, security
  deliveries in/out, and the residual jump of a balance snapshot — so the
  result measures the investments themselves, independent of when money was
  added or taken out. Daily returns chain geometrically:

      TTWROR = ∏(1 + r_d) − 1   with   r_d = V_d / (V_{d−1} + F_d) − 1

  where `F_d` is the day's net external flow, assumed at the start of the day.
  Dividends, interest, fees and taxes are internal (they are return); buys,
  sells and transfers between own accounts only move money around inside the
  portfolio. What each booking kind does — and whether it is external — comes
  from the single per-kind reducer `Portfolixir.Ledger.Projection`
  (ADR-0011). Nothing is stored — like holdings and the valuation, the series
  is derived on read (ADR-0004, ADR-0010).

  Pricing falls back to the **latest own trade price** when a security has no
  quote yet (a buy or sell is a price observation, exactly how Portfolio
  Performance seeds prices from bookings), so freshly imported portfolios are
  not valued at zero. Quotes win over trades on the same day.

  Real-world guards (ADR-0010 amendments):

    * Bookings dated before #{inspect(~D[1970-01-01])} are treated as data
      errors (e.g. a `0217-12-05` typo in an import); their effects are
      applied on the first plausible day instead of walking centuries of
      empty days, and the dates are reported as `suspect_dates`.
    * A day whose return base (`V_{d−1} + F_d`) is zero or negative
      contributes no return.
    * A **trade-price basis step** is neutralised like a flow (issue #545).
      A position held at its own last trade price sits flat between trades;
      the day a new price lands, the whole previously-held quantity re-prices
      at once. That step is a change of valuation *basis*, not a market move
      — nothing was observed except the price of the portfolio's own trade —
      so the day carries a `basis` component that enters the return base next
      to the flow:

          r_d = V_d / (V_{d−1} + F_d + B_d) − 1

      `B_d` applies to a security that is **unmeasured** coming into the day
      (no quote has ever landed on an earlier day) and covers every unit that
      ends the day marked at the day's price without having become cash: the
      sleeve carried in from yesterday, whatever was acquired today at its own
      price, and whatever left as an external delivery (valued at the day's
      price in `F_d`). A sale is the exception — it turns the position into
      real cash, so its gain against the basis it consumed stays return.
      `B_d` is converted at **yesterday's** exchange rates, because it
      restates yesterday's closing value; the retained sleeve's own currency
      move therefore stays in the return. `B_d` never touches `value`,
      `start_value`, `end_value` or `net_external_flows`: the money facts (and
      the €-gain badge derived from them) stay exactly as booked.

  The expensive daily walk is computed once per portfolio via `analysis/2`;
  every period (`ytd`/`1y`/…) is then a cheap pure `summarise/2` over that
  series, so callers can switch periods without re-walking.

  All quote, FX-rate and transaction data is preloaded up front; the walk
  itself issues no queries.
  """

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.QuoteAdjustment
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Derived
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance.IRR

  @zero Decimal.new("0")
  @one Decimal.new("1")
  @periods ~w(ytd 1y 3y 5y max)
  @earliest_plausible ~D[1970-01-01]
  @hub "EUR"
  @gbx_per_gbp Decimal.new(100)

  def periods, do: @periods

  @doc """
  Computes the performance of one portfolio.

  Options:
    * `:period` — one of #{inspect(@periods)} (default `"max"`).
    * `:today` — end date override (for tests); defaults to `Date.utc_today()`.

  Returns `{:ok, result}` or `{:error, :invalid_period}`. The result carries
  `ttwror`, the money-weighted `irr` (`Decimal.t() | nil`) and its
  non-annualized period companion `mwr`, `start_value`/`end_value`,
  `net_external_flows`, `invested_capital` (opening value + net period
  flows) with the `wealth_multiple` (`Decimal.t() | nil`, #568/ADR-0034),
  and the daily `series` of `%{date, value, flow, cumulative_ttwror}` for
  the period.
  """
  def for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    period = Keyword.get(opts, :period, "max")

    with :ok <- validate_period(period),
         %{} = analysis <- analysis(portfolio_id, opts) do
      summarise(analysis, period)
    end
  end

  @doc """
  The expensive, period-independent part: one full daily walk.

  Returns a map with the raw `daily` series (`%{date, value, flow, basis}`),
  `first_date`/`today`, the base currency, and `suspect_dates` (dates of
  bookings older than #{inspect(@earliest_plausible)}, applied on the first
  plausible day). Feed it to `summarise/2` once per period.
  """
  def analysis(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    # `:view` (a view id) scopes the series to the holdings matching that view;
    # `nil` -> `:unscoped` -> the walk takes the unchanged code path (#444).
    # A vanished view returns `{:error, :view_not_found}` (fix round).
    case Buckets.load_scope(portfolio_id, Keyword.get(opts, :view)) do
      {:error, :view_not_found} = error ->
        error

      scope ->
        # Served through the derived-value axis (ADR-0039) as the
        # `:performance_analysis` analytic: keyed per portfolio basis, scope,
        # walk end date, that basis's data version and the computation
        # version. With the layer off (or the lifetime `:none`) this is a
        # plain call to `scoped_analysis/3` and the numbers are identical,
        # which is what the layer-off suite run proves.
        {:fresh, analysis} =
          Derived.fetch(
            :performance_analysis,
            Derived.portfolio_basis(portfolio_id),
            entry_key(opts),
            fn -> scoped_analysis(portfolio_id, scope, opts) end
          )

        # Freshness is annotated OUTSIDE the computed (and stored) value, so a
        # stored payload never carries a frozen claim about its own currency
        # (ADR-0039 C4): served fresh here, served stale by the peek path.
        Map.put(analysis, :stale, false)
    end
  end

  @doc """
  The most recent superseded analysis for a scope, or `nil` (ADR-0032 §6,
  carried forward as ADR-0039's stale read).

  A surface renders this immediately -- labelled with its as-of and marked as
  recomputing -- rather than a skeleton, while the fresh series computes. For
  the durable lifetime it survives restarts.
  """
  def previous_analysis(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    case Derived.peek(
           :performance_analysis,
           Derived.portfolio_basis(portfolio_id),
           entry_key(opts)
         ) do
      {:stale, analysis, _as_of} -> Map.put(analysis, :stale, true)
      _fresh_or_none -> nil
    end
  end

  # One walk's identity within its basis: the view scope and the walk end
  # date. The data and computation versions are composed in by the derived
  # layer itself (ADR-0039's full key).
  defp entry_key(opts) do
    view = Keyword.get(opts, :view) || "unscoped"
    "view=#{view}|today=#{Keyword.get(opts, :today, Date.utc_today())}"
  end

  defp view_entry_key(view_id, base, opts) do
    "view=#{view_id || "unscoped"}|base=#{base}|today=#{Keyword.get(opts, :today, Date.utc_today())}"
  end

  defp scoped_analysis(portfolio_id, scope, opts) do
    today = Keyword.get(opts, :today, Date.utc_today())
    walk_portfolio(portfolio_id, scope, base_currency(portfolio_id), today)
  end

  # One portfolio's daily walk under `scope`, valued in an explicit `base`
  # currency. The per-portfolio entry point (`analysis/2`) passes the
  # portfolio's own base; the cross-portfolio view walk (#577) passes one
  # common base so the slices are summable.
  defp walk_portfolio(portfolio_id, scope, base, today) do
    transactions = sorted_transactions(portfolio_id)
    suspects = suspect_dates(transactions)

    case walk_start(transactions, today) do
      nil ->
        empty_analysis(portfolio_id, today, base, suspects)

      start ->
        %{
          portfolio_id: portfolio_id,
          base_currency: base,
          today: today,
          first_date: start,
          suspect_dates: suspects,
          basis: basis(transactions),
          daily: daily_series(portfolio_id, transactions, start, today, base, scope)
        }
    end
  end

  # -- cross-portfolio view walk (#577) ---------------------------------------

  @doc """
  Computes the performance of a bucket view **across all portfolios**
  (ADR-0024): the same deduplicated account scope
  (`Portfolixir.Buckets.load_global_scope/1`) the view valuation covers, so
  the header total and the TTWROR/IRR always speak about the same accounts.

  `view_id == nil` is the "Everything" scope. Options are `analysis/2`'s plus
  `:base_currency` (default the EUR hub) — all portfolios' slices are valued
  in that one currency.

  Returns `{:ok, result}` (the `summarise/2` shape with `view_id` set and
  `portfolio_id: nil`) or `{:error, :invalid_period | :view_not_found}`.
  """
  def for_view(view_id, opts \\ []) when is_integer(view_id) or is_nil(view_id) do
    period = Keyword.get(opts, :period, "max")

    with :ok <- validate_period(period),
         %{} = analysis <- view_analysis(view_id, opts) do
      summarise(analysis, period)
    end
  end

  @doc """
  The expensive, period-independent part of `for_view/2`: one daily walk per
  portfolio under the view's instance-wide scope, merged into one combined
  daily series (values, flows and return-base steps sum per day — no
  transaction can span two portfolios, so the sum of the per-portfolio scoped
  walks is exactly the walk over the deduplicated account union). Money
  crossing the view boundary stays an external flow per ADR-0019; money moving
  between two in-scope accounts — of the same or of different portfolios —
  nets out.

  Memoised under the `:global` scope dimension (ADR-0032, #577): any
  portfolio's write invalidates it, because the combined series depends on
  every portfolio.
  """
  def view_analysis(view_id, opts \\ []) when is_integer(view_id) or is_nil(view_id) do
    case Buckets.load_global_scope(view_id) do
      {:error, :view_not_found} = error ->
        error

      scope ->
        base = Keyword.get(opts, :base_currency, @hub)
        today = Keyword.get(opts, :today, Date.utc_today())

        {:fresh, analysis} =
          Derived.fetch(
            :performance_view_analysis,
            Derived.global_basis(),
            view_entry_key(view_id, base, opts),
            fn -> view_scoped_analysis(view_id, scope, base, today) end
          )

        Map.put(analysis, :stale, false)
    end
  end

  @doc "The most recent superseded view analysis for a scope, or `nil` (ADR-0032 §6)."
  def previous_view_analysis(view_id, opts \\ []) when is_integer(view_id) or is_nil(view_id) do
    case Derived.peek(
           :performance_view_analysis,
           Derived.global_basis(),
           view_entry_key(view_id, Keyword.get(opts, :base_currency, @hub), opts)
         ) do
      {:stale, analysis, _as_of} -> Map.put(analysis, :stale, true)
      _fresh_or_none -> nil
    end
  end

  defp view_scoped_analysis(view_id, scope, base, today) do
    # Only portfolios with at least one transaction touching an in-scope
    # account are walked (#577 fix round): a fully out-of-scope portfolio
    # contributes an all-zero walk whose sums would not change the merged
    # series — but its span would, inheriting an older history as leading
    # zero-value days, a wrong start_date and dataless year-picker entries.
    # Membership is decided on legs, not values: an in-scope portfolio whose
    # net value happens to be zero every day still walks.
    Portfolios.list_portfolios()
    |> Enum.filter(&portfolio_scope_activity?(&1.id, scope))
    |> Enum.map(&walk_portfolio(&1.id, scope, base, today))
    |> merge_analyses(view_id, base, today)
  end

  defp portfolio_scope_activity?(portfolio_id, scope) do
    portfolio_id
    |> sorted_transactions()
    |> Enum.any?(&transaction_in_scope?(scope, &1))
  end

  defp transaction_in_scope?(scope, tx) do
    tx_cash_in_scope?(scope, tx.cash_account_id) or
      tx_cash_in_scope?(scope, tx.counter_cash_account_id) or
      tx_position_in_scope?(scope, tx.securities_account_id, tx.security_id) or
      tx_position_in_scope?(scope, tx.counter_securities_account_id, tx.security_id)
  end

  defp tx_cash_in_scope?(_scope, nil), do: false

  defp tx_cash_in_scope?(scope, cash_account_id),
    do: Buckets.cash_in_scope?(scope, cash_account_id)

  defp tx_position_in_scope?(_scope, nil, _security_id), do: false
  defp tx_position_in_scope?(_scope, _account_id, nil), do: false

  defp tx_position_in_scope?(scope, account_id, security_id),
    do: Buckets.position_in_scope?(scope, account_id, security_id)

  defp merge_analyses(analyses, view_id, base, today) do
    suspects = analyses |> Enum.flat_map(& &1.suspect_dates) |> Enum.uniq()
    walked = Enum.reject(analyses, &(&1.daily == []))

    merged = %{
      portfolio_id: nil,
      view_id: view_id,
      base_currency: base,
      today: today,
      first_date: nil,
      suspect_dates: suspects,
      basis: merged_basis(analyses),
      daily: []
    }

    case walked do
      [] ->
        merged

      _some ->
        first = walked |> Enum.map(& &1.first_date) |> Enum.min(Date)
        %{merged | first_date: first, daily: merged_daily(walked, first, today)}
    end
  end

  # Sums the per-portfolio points per day. A portfolio whose walk starts later
  # has no point yet on earlier days — its value there is genuinely zero, so
  # the day is the sum of the portfolios already walking.
  defp merged_daily(walked, first, today) do
    sums =
      Enum.reduce(walked, %{}, fn analysis, acc ->
        Enum.reduce(analysis.daily, acc, fn point, acc ->
          Map.update(acc, point.date, point_slice(point), &add_slices(&1, point))
        end)
      end)

    zero = %{value: @zero, flow: @zero, basis: @zero, trade_costs: @zero}

    Enum.map(Date.range(first, today), fn date ->
      slice = Map.get(sums, date, zero)

      %{
        date: date,
        value: slice.value,
        flow: slice.flow,
        basis: slice.basis,
        trade_costs: slice.trade_costs
      }
    end)
  end

  defp point_slice(point) do
    %{
      value: point.value,
      flow: point.flow,
      basis: basis_of(point),
      trade_costs: trade_costs_of(point)
    }
  end

  defp add_slices(slice, point) do
    %{
      value: Decimal.add(slice.value, point.value),
      flow: Decimal.add(slice.flow, point.flow),
      basis: Decimal.add(slice.basis, basis_of(point)),
      trade_costs: Decimal.add(slice.trade_costs, trade_costs_of(point))
    }
  end

  # What the combined series contains (ADR-0032 §6 banner): bookings across
  # all walked portfolios.
  defp merged_basis(analyses) do
    %{
      booking_count: analyses |> Enum.map(& &1.basis.booking_count) |> Enum.sum(),
      last_booking_date:
        analyses
        |> Enum.map(& &1.basis.last_booking_date)
        |> Enum.reject(&is_nil/1)
        |> Enum.max(Date, fn -> nil end),
      computed_at: DateTime.truncate(DateTime.utc_now(), :second)
    }
  end

  # What a served series CONTAINS, so a superseded one is never a bare number
  # (ADR-0032 §6, owner requirement): the booking count and the newest booking
  # date at compute time, plus the compute instant. A stale banner renders
  # these, which makes "what is missing" readable instead of implied.
  defp basis(transactions) do
    %{
      booking_count: length(transactions),
      last_booking_date: transactions |> Enum.map(& &1.date) |> Enum.max(Date, fn -> nil end),
      computed_at: DateTime.truncate(DateTime.utc_now(), :second)
    }
  end

  @doc """
  Chains one period out of an `analysis/2` result.

  `period` is one of #{inspect(@periods)}, `{:year, year}` for one calendar
  year (#563 — clamped to today for the current year), or
  `{:range, from, to}` for a custom date range (`from <= to`, clamped to the
  available history). Pure and cheap — switching periods needs no new queries
  or daily walk. Returns `{:ok, result}` or `{:error, :invalid_period}`.
  """
  def summarise(analysis, period) do
    with :ok <- validate_period(period) do
      {:ok, do_summarise(analysis, period)}
    end
  end

  defp validate_period(period) when period in @periods, do: :ok

  defp validate_period({:year, year}) when is_integer(year) and year >= 1970, do: :ok

  defp validate_period({:range, %Date{} = from, %Date{} = to}) do
    if Date.compare(from, to) == :gt, do: {:error, :invalid_period}, else: :ok
  end

  defp validate_period(_period), do: {:error, :invalid_period}

  defp do_summarise(%{daily: []} = analysis, period) do
    empty_result(analysis, period)
  end

  defp do_summarise(%{daily: daily} = analysis, period) do
    start_date = clamp_start(period_start(period, analysis.today), analysis.first_date)
    # Bounded periods (#563: a previous year, a custom range) end before
    # today; the walk's tail after `end_date` simply stays unchained.
    end_date = period_end(period, analysis.today)
    {before, rest} = Enum.split_with(daily, &(Date.compare(&1.date, start_date) == :lt))
    in_period = Enum.take_while(rest, &(Date.compare(&1.date, end_date) != :gt))

    # A bounded window containing no walked day (a future year, a range fully
    # before the history) is the same honest emptiness as "nothing to walk
    # yet" — never an inverted window carrying the current value as both ends.
    if in_period == [] do
      empty_result(analysis, period)
    else
      chain_period(analysis, period, in_period, before, start_date, end_date)
    end
  end

  defp chain_period(analysis, period, in_period, before, start_date, end_date) do
    start_value = baseline(before)

    {points, growth, flows, _prev} =
      Enum.reduce(in_period, {[], @one, @zero, start_value}, &chain_day/2)

    series = Enum.reverse(points)

    summary = %{
      portfolio_id: analysis.portfolio_id,
      view_id: Map.get(analysis, :view_id),
      period: period,
      base_currency: analysis.base_currency,
      start_date: start_date,
      end_date: end_date,
      start_value: start_value,
      end_value: end_value(series, start_value),
      net_external_flows: flows,
      ttwror: Decimal.sub(growth, @one),
      suspect_dates: analysis.suspect_dates,
      as_of: analysis.basis.computed_at,
      stale: Map.get(analysis, :stale, false),
      computation_basis: computation_basis(start_date, end_date),
      series: series
    }

    summary = Map.put(summary, :irr, IRR.for_summary(summary))
    Map.merge(summary, wealth_metrics(summary))
  end

  # ADR-0039 C4 / AGENTS.md analytics rule: every metric states its
  # computation basis IN the payload — input series, window, reference where
  # one exists, and the treatment of gaps. The payload is where the reviewer
  # and the agent both read it; a doc page does not satisfy the rule.
  defp computation_basis(start_date, end_date) do
    %{
      input_series:
        "daily portfolio valuation derived from recorded transactions, " <>
          "stored quotes and stored EUR-hub exchange rates (ADR-0010)",
      window: %{start_date: start_date, end_date: end_date},
      reference: nil,
      gaps:
        "prices and exchange rates carry the most recent stored point on or " <>
          "before each day forward; a security with no quote yet is priced by " <>
          "its own latest trade; a missing conversion path contributes zero " <>
          "(ADR-0010)"
    }
  end

  # Money-weighted companions to TTWROR/IRR (#568, ADR-0034): the invested
  # capital the period actually saw, the honest wealth multiple, and the
  # non-annualized period MWR. Opening value and net period flows stay two
  # separate numbers in the summary — this only adds their sum.
  defp wealth_metrics(summary) do
    invested = Decimal.add(summary.start_value, summary.net_external_flows)

    %{
      invested_capital: invested,
      wealth_multiple: wealth_multiple(summary.end_value, invested),
      mwr: period_mwr(summary.irr, summary.start_date, summary.end_date)
    }
  end

  # Net invested capital at or below zero — or an overdrawn (negative) end
  # value — renders "n/a": never a negative or infinite multiple
  # (ADR-0034 §3). A zero end value stays ×0: a total loss is a result.
  defp wealth_multiple(end_value, invested) do
    if Decimal.compare(invested, @zero) == :gt and
         Decimal.compare(end_value, @zero) != :lt do
      end_value |> Decimal.div(invested) |> Decimal.round(4)
    end
  end

  # The non-annualized period MWR; the float de-annualization lives in the
  # IRR module so float64 stays confined to the solver island (ADR-0034 §2).
  # Windows shorter than a year display this figure instead of the
  # annualized IRR.
  defp period_mwr(%Decimal{} = irr, %Date{} = start_date, %Date{} = end_date) do
    IRR.period_rate(irr, Date.diff(end_date, start_date))
  end

  defp period_mwr(_irr, _start_date, _end_date), do: nil

  defp empty_analysis(portfolio_id, today, base, suspects) do
    %{
      portfolio_id: portfolio_id,
      base_currency: base,
      today: today,
      first_date: nil,
      suspect_dates: suspects,
      basis: basis([]),
      daily: []
    }
  end

  defp empty_result(analysis, period) do
    %{
      portfolio_id: analysis.portfolio_id,
      view_id: Map.get(analysis, :view_id),
      period: period,
      base_currency: analysis.base_currency,
      start_date: nil,
      end_date: analysis.today,
      start_value: @zero,
      end_value: @zero,
      net_external_flows: @zero,
      invested_capital: @zero,
      wealth_multiple: nil,
      ttwror: @zero,
      irr: nil,
      mwr: nil,
      suspect_dates: analysis.suspect_dates,
      as_of: analysis.basis.computed_at,
      stale: Map.get(analysis, :stale, false),
      computation_basis: computation_basis(nil, analysis.today),
      series: []
    }
  end

  # The walk starts at the first plausibly-dated transaction; anything older
  # is a data error whose effects land on that first day. No transactions (or
  # only future-dated ones) mean there is nothing to walk yet.
  defp walk_start([], _today), do: nil

  defp walk_start(transactions, today) do
    start =
      case Enum.find(transactions, &(Date.compare(&1.date, @earliest_plausible) != :lt)) do
        nil -> today
        tx -> tx.date
      end

    if Date.compare(start, today) == :gt, do: nil, else: start
  end

  defp suspect_dates(transactions) do
    transactions
    |> Enum.filter(&(Date.compare(&1.date, @earliest_plausible) == :lt))
    |> Enum.map(& &1.date)
    |> Enum.uniq()
  end

  # -- daily walk -------------------------------------------------------------

  # Walks every day from the first plausible transaction to `today`,
  # maintaining held quantities and per-account cash, and records each day's
  # portfolio value (base currency) and net external flow. All pricing data
  # (quotes, own trade prices, FX rates) is preloaded; the walk is pure.
  defp daily_series(portfolio_id, transactions, walk_start, today, base, scope) do
    by_day = Enum.group_by(transactions, &effective_date(&1, walk_start))
    currencies = account_currencies(portfolio_id)

    context = %{
      base: base,
      currencies: currencies,
      scope: scope,
      pricing: init_pricing(transactions, walk_start),
      fx: init_fx(transactions, currencies, base, walk_start)
    }

    state = %{qty: %{}, cash: %{}}

    {series, _state, _context} =
      Enum.reduce(Date.range(walk_start, today), {[], state, context}, &walk_day(by_day, &1, &2))

    Enum.reverse(series)
  end

  defp effective_date(tx, walk_start) do
    if Date.compare(tx.date, walk_start) == :lt, do: walk_start, else: tx.date
  end

  defp walk_day(by_day, day, {acc, state, context}) do
    {pricing, steps} = advance_pricing(context.pricing, day)
    carried_fx = context.fx

    context = %{context | pricing: pricing, fx: advance_map(context.fx, day, &advance_rate/2)}

    context = Map.put(context, :day, day)
    day_txs = by_day |> Map.get(day, []) |> sort_within_day()
    # The quantities held *before* the day's bookings: the sleeve a basis step
    # restates. Captured here because `apply_transactions/3` mutates them.
    opening = state.qty
    {state, flow, legs} = apply_transactions(day_txs, state, context)
    value = portfolio_value(state, context)
    basis = basis_adjustment(steps, opening, legs, context, carried_fx)

    {[
       %{
         date: day,
         value: value,
         flow: flow,
         basis: basis,
         trade_costs: trade_costs(day_txs, context)
       }
       | acc
     ], state, context}
  end

  # The fees and taxes carried BY A TRADE, per day, in the base currency
  # (ADR-0027's 2026-08-15 amendment §1, issue #708). Nothing here changes the
  # walk: `value` and `flow` are untouched, so the TTWROR this series produces
  # is exactly what it was. The figure rides along so a consumer that wants the
  # return BEFORE transaction costs can reclassify them without a second
  # engine.
  #
  # Two exclusions are the definition, not an oversight:
  #
  #   - standalone `fee` and `tax` bookings are out. A custody fee or an
  #     account charge is not caused by a trade, and the counterfactual's
  #     frozen holder would have paid it too — removing it would flatter the
  #     real side against a holder who pays it as well;
  #   - dividend and interest withholding is out. It belongs to the dividend
  #     asymmetry ADR-0027 §2 already records as its own follow-up, and taking
  #     it out here would half-fix the wrong gap.
  #
  # Scope-aware for the same reason the flow is: in a scoped walk only a trade
  # whose CASH leg is in view moved money the view can see.
  defp trade_costs(day_txs, context) do
    Enum.reduce(day_txs, @zero, fn tx, acc ->
      if trade_cost_in_scope?(tx, context) do
        cost = Decimal.add(tx.fees || @zero, tx.taxes || @zero)
        Decimal.add(acc, to_base(cost, tx.currency_code, context))
      else
        acc
      end
    end)
  end

  defp trade_cost_in_scope?(%{type: type} = tx, context) when type in ["buy", "sell"] do
    case context.scope do
      :unscoped ->
        true

      scope ->
        not is_nil(tx.cash_account_id) and Buckets.cash_in_scope?(scope, tx.cash_account_id)
    end
  end

  defp trade_cost_in_scope?(_tx, _context), do: false

  defp account_currencies(portfolio_id) do
    portfolio_id
    |> Portfolios.list_cash_accounts_for_portfolio()
    |> Map.new(&{&1.id, &1.currency_code})
  end

  # The shared intra-day replay order (ADR-0028 §3): a split applies first
  # (start-of-day, so same-day trades book in post-split units), and a
  # balance snapshot states the balance *including* the rest of its day, so
  # it is applied after the day's other bookings (mirrors
  # Ledger.cash_balances).
  defp sort_within_day(transactions) do
    Enum.sort_by(transactions, &{Projection.intra_day_order(&1), &1.id})
  end

  # Returns the day's state, its net external flow and the day's quantity legs
  # per security, **in replay order**. The trade-price basis step (issue #545)
  # needs the individual legs, not their net: a day can carry several trades at
  # different prices, and what a leg did with the quantity it moved — paid cash
  # for it, delivered it out, netted it against the same day's own purchase —
  # decides whether its re-pricing is return or basis.
  defp apply_transactions(transactions, state, context) do
    {state, flow, legs} =
      Enum.reduce(transactions, {state, @zero, %{}}, fn tx, {state, flow, legs} ->
        {state, tx_flow, tx_legs} = apply_transaction(tx, state, context)
        {state, Decimal.add(flow, tx_flow), merge_legs(legs, tx_legs)}
      end)

    {state, flow,
     Map.new(legs, fn {security_id, booked} -> {security_id, Enum.reverse(booked)} end)}
  end

  defp merge_legs(legs, booked) do
    Enum.reduce(booked, legs, fn {security_id, leg}, acc ->
      Map.update(acc, security_id, [leg], &[leg | &1])
    end)
  end

  # One quantity leg as the basis walk sees it. A buy or a sell moved cash at
  # its own booked price; every other kind (deliveries, depot transfers) moved
  # quantity only and is valued at the day's price wherever it shows up — in
  # the day's external flow, or in the counter depot.
  defp quantity_leg(%{type: type, price: %Decimal{} = price} = tx, delta)
       when type in ["buy", "sell"],
       do: {:trade, delta, %{close: price, currency: tx.currency_code}}

  defp quantity_leg(_tx, delta), do: {:mark, delta}

  # -- canonical effects (ADR-0011): {new_state, external_flow_in_base} -------

  # Applies the transaction's effect from the single per-kind reducer. When
  # the projection marks the booking external, the applied cash deltas (for a
  # balance snapshot: the residual jump — money that appeared or left outside
  # the recorded bookings) and the market value of the moved quantities count
  # as the day's external flow, converted to the base currency.
  defp apply_transaction(tx, state, %{scope: :unscoped} = context) do
    effect = Projection.effects(tx)
    {state, cash_flow} = apply_cash_legs(effect.cash, tx, state, context, effect.external)

    {state, qty_flow, legs} =
      apply_quantity_legs(effect.quantities, tx, state, context, effect.external)

    {state, Decimal.add(cash_flow, qty_flow), legs}
  end

  # Scoped walk (#444, ADR-0019): only in-view legs touch the state, so the daily
  # value covers exactly the view's single-count holdings. The flow is the value
  # crossing the view boundary: kept external legs (deposits/dividends/deliveries
  # restricted to in-view accounts/positions) plus, for value-conserving internal
  # transactions that straddle the boundary (a trade or transfer with some legs in
  # and some out), the net booked value of the kept legs. A fully-in or fully-out
  # transaction never straddles, so an include-everything view reproduces the
  # unscoped result exactly.
  defp apply_transaction(tx, state, context) do
    effect = Projection.effects(tx)
    scope = context.scope

    kept_cash = Enum.filter(effect.cash, &cash_leg_in_scope?(&1, scope))
    kept_qty = Enum.filter(effect.quantities, &qty_leg_in_scope?(&1, scope))

    # Apply the kept legs to the (in-view) state and capture the kept cash's booked
    # base value — ungated, because a straddle's cash side is a boundary flow even
    # for an internal trade.
    {state, kept_cash_base} = apply_kept_cash(kept_cash, tx, state, context)

    {state, legs} =
      Enum.reduce(kept_qty, {state, []}, fn
        {:scale, %{security_id: sec, ratio: ratio}}, {st, legs} ->
          {scale_qty(st, sec, ratio), [{sec, {:scale, ratio}} | legs]}

        {_acct, sec, delta}, {st, legs} ->
          {add_qty(st, sec, delta), [{sec, quantity_leg(tx, delta)} | legs]}
      end)

    flow =
      cond do
        effect.external ->
          Decimal.add(kept_cash_base, kept_qty_market_value(kept_qty, context))

        straddles?(effect, kept_cash, kept_qty) ->
          Decimal.add(kept_cash_base, kept_qty_booked_value(effect, kept_qty, tx, context))

        true ->
          @zero
      end

    {state, flow, Enum.reverse(legs)}
  end

  defp apply_kept_cash(legs, tx, state, context) do
    Enum.reduce(legs, {state, @zero}, fn {account_id, _op} = leg, {st, acc} ->
      {st, applied} = apply_cash_leg(leg, st)
      currency = Map.get(context.currencies, account_id, tx.currency_code)
      {st, Decimal.add(acc, to_base(applied, currency, context))}
    end)
  end

  defp cash_leg_in_scope?({account_id, _op}, scope),
    do: not is_nil(account_id) and Buckets.cash_in_scope?(scope, account_id)

  # A scale leg (ADR-0028) is handled explicitly — the tagged shape must
  # never be silently dropped by the same-arity tuple filter below. It is
  # always kept: the scoped state only ever holds in-view quantities, and
  # multiplication distributes over whatever subset is held, so scaling the
  # in-view quantity is exactly the in-view effect of the split.
  defp qty_leg_in_scope?({:scale, _scale}, _scope), do: true

  defp qty_leg_in_scope?({account_id, security_id, _delta}, scope),
    do: Buckets.position_in_scope?(scope, account_id, security_id)

  # A value-conserving internal transaction straddles the view when it has at
  # least one in-view leg and at least one out-of-view leg.
  defp straddles?(effect, kept_cash, kept_qty) do
    total = length(effect.cash) + length(effect.quantities)
    kept = length(kept_cash) + length(kept_qty)
    kept > 0 and kept < total
  end

  # External quantity legs (deliveries) are valued at market, like the unscoped path.
  defp kept_qty_market_value(kept_qty, context) do
    Enum.reduce(kept_qty, @zero, fn {_acct, security_id, delta}, acc ->
      Decimal.add(acc, security_value(security_id, delta, context))
    end)
  end

  # Booked value of the kept quantity legs for an internal straddle. For a trade
  # (the transaction also moves cash) the quantity side is worth the negated total
  # cash delta, apportioned by quantity, so a fully-in-view trade nets to zero. For
  # a cashless transfer the moved quantity is valued at market.
  defp kept_qty_booked_value(%{cash: []} = _effect, kept_qty, _tx, context),
    do: kept_qty_market_value(kept_qty, context)

  defp kept_qty_booked_value(effect, kept_qty, tx, context) do
    total_cash_base = total_add_cash_base(effect.cash, tx, context)
    # A trade's security legs always carry positive quantity (changeset-validated),
    # so the apportionment denominator is never zero.
    total_abs_qty = effect.quantities |> Enum.map(&Decimal.abs(elem(&1, 2))) |> sum()

    Enum.reduce(kept_qty, @zero, fn {_acct, _sec, delta}, acc ->
      share = Decimal.div(Decimal.abs(delta), total_abs_qty)
      Decimal.add(acc, Decimal.mult(Decimal.negate(total_cash_base), share))
    end)
  end

  # The transaction's total `{:add, delta}` cash movement in base. Trades use
  # additive legs; balance snapshots ({:set}) are external and never reach here,
  # and a nil-account leg carries no value — the comprehension skips both.
  defp total_add_cash_base(cash_legs, tx, context) do
    for {account_id, {:add, delta}} <- cash_legs, not is_nil(account_id), reduce: @zero do
      acc ->
        currency = Map.get(context.currencies, account_id, tx.currency_code)
        Decimal.add(acc, to_base(delta, currency, context))
    end
  end

  defp sum(decimals), do: Enum.reduce(decimals, @zero, &Decimal.add/2)

  defp apply_cash_legs(legs, tx, state, context, external?) do
    Enum.reduce(legs, {state, @zero}, fn {account_id, _op} = leg, {state, flow} ->
      {state, applied} = apply_cash_leg(leg, state)

      flow =
        if external? do
          currency = Map.get(context.currencies, account_id, tx.currency_code)
          Decimal.add(flow, to_base(applied, currency, context))
        else
          flow
        end

      {state, flow}
    end)
  end

  defp apply_cash_leg({nil, _amount}, state), do: {state, @zero}

  defp apply_cash_leg({account_id, {:add, delta}}, state),
    do: {add_cash(state, account_id, delta), delta}

  # The stated balance replaces the derived one.
  defp apply_cash_leg({account_id, {:set, absolute}}, state) do
    jump = Decimal.sub(absolute, Map.get(state.cash, account_id, @zero))
    {add_cash(state, account_id, jump), jump}
  end

  # Quantities are tracked per security, so the two legs of a security
  # transfer net out at portfolio level.
  defp apply_quantity_legs(legs, tx, state, context, external?) do
    {state, flow, booked} =
      Enum.reduce(legs, {state, @zero, []}, fn
        # A split's scale leg (ADR-0028) multiplies the held quantity; it is
        # never an external flow, so it contributes nothing to the day's flow.
        # The walk is per portfolio, so the row's per-portfolio scope holds by
        # construction. The walk aggregates quantities per security across the
        # portfolio's accounts; scaling the aggregate equals the sum of the
        # per-account scaled quantities up to the volume-scale-6 quantization.
        {:scale, %{security_id: security_id, ratio: ratio}}, {state, flow, booked} ->
          {scale_qty(state, security_id, ratio), flow, [{security_id, {:scale, ratio}} | booked]}

        {_account_id, security_id, delta}, {state, flow, booked} ->
          flow =
            if external? do
              Decimal.add(flow, security_value(security_id, delta, context))
            else
              flow
            end

          {add_qty(state, security_id, delta), flow,
           [{security_id, quantity_leg(tx, delta)} | booked]}
      end)

    {state, flow, Enum.reverse(booked)}
  end

  # Sold-out positions are dropped so the daily valuation only touches what
  # is actually held — with long histories most securities are closed.
  defp add_qty(state, security_id, delta) do
    qty = state.qty |> Map.get(security_id, @zero) |> Decimal.add(delta)
    put_qty(state, security_id, qty)
  end

  defp scale_qty(state, security_id, ratio) do
    case Map.get(state.qty, security_id) do
      nil -> state
      qty -> put_qty(state, security_id, Projection.scale_quantity(qty, ratio))
    end
  end

  defp put_qty(state, security_id, qty) do
    qty_map =
      if Decimal.equal?(qty, @zero) do
        Map.delete(state.qty, security_id)
      else
        Map.put(state.qty, security_id, qty)
      end

    %{state | qty: qty_map}
  end

  defp add_cash(state, nil, _delta), do: state

  defp add_cash(state, account_id, delta) do
    %{state | cash: Map.update(state.cash, account_id, delta, &Decimal.add(&1, delta))}
  end

  # -- pricing ----------------------------------------------------------------

  # Per security: the price carried in from before the walk and the remaining
  # price points to consume as days advance (one DB read per security). Price
  # points merge the quote series with the portfolio's own trade prices; a
  # quote wins over a trade on the same day (rank 1 is consumed after rank 0,
  # and the last consumed point sticks).
  #
  # Split basis (ADR-0028 §2): every point is converted to its own date's
  # **as-traded (raw) basis** — provider-mirror closes multiply back up by
  # the cumulative ratio of strictly-later splits, manual closes and trade
  # prices are already as-traded — so each day's price matches the basis the
  # day's booked quantities are in. §2 states this as "(quantity x cumulative
  # later split ratio) x adjusted quote"; applying the same factor on the
  # price side is the identical product and fits the walk's price pointers.
  # When the walk crosses an effective date, a rank -1 rescale point moves
  # the carried price into the post-split era, exactly when the quantity
  # fold scales — the events are security-level (deduplicated across the
  # per-portfolio fan-out), so a portfolio without its own split row still
  # prices every era correctly.
  defp init_pricing(transactions, walk_start) do
    events_by_security =
      transactions
      |> Enum.map(& &1.security_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Quotes.split_events_by_security()

    transactions
    |> Enum.filter(& &1.security_id)
    |> Enum.group_by(& &1.security_id)
    |> Map.new(fn {security_id, txs} ->
      events = Map.get(events_by_security, security_id, [])
      {security_id, init_security_pricing(security_id, txs, walk_start, events)}
    end)
  end

  defp init_security_pricing(security_id, txs, walk_start, events) do
    currency = security_currency(hd(txs))
    security = security_struct(hd(txs))

    quote_points =
      security_id
      |> Quotes.range(walk_start, ~D[9999-12-31])
      |> Enum.map(
        &%{
          date: &1.date,
          close: raw_basis_close(&1, security, events),
          currency: currency,
          price_source: :quote,
          rank: 1
        }
      )

    rescale_points =
      for %{date: eff, ratio: ratio} <- events,
          Date.compare(eff, walk_start) != :lt,
          do: %{date: eff, rescale: ratio, rank: -1}

    points =
      (trade_points(txs, walk_start) ++ quote_points ++ rescale_points)
      |> Enum.sort_by(&{Date.to_erl(&1.date), &1.rank})

    carried = carried_seed(security_id, walk_start, currency, security, events)
    # `measured?` records whether a **quote** has ever landed on an earlier
    # day: `carried_seed/5` only ever returns a quote, so seeding it from the
    # carried price is exact. It gates the basis step (issue #545).
    %{price: carried, upcoming: points, measured?: not is_nil(carried)}
  end

  # The seed close (last close before the walk) converted into the basis era
  # of the day before the walk starts: as-traded at its own date, then
  # rebased across any effective date between the quote and the walk.
  defp carried_seed(security_id, walk_start, currency, security, events) do
    seed_day = Date.add(walk_start, -1)

    case Quotes.at_or_before(security_id, seed_day) do
      %{close: %Decimal{}} = quote_row ->
        close =
          quote_row
          |> raw_basis_close(security, events)
          |> QuoteAdjustment.rebase_close(quote_row.date, seed_day, events)

        %{close: close, currency: currency, price_source: :quote}

      _ ->
        nil
    end
  end

  defp raw_basis_close(quote_row, security, events) do
    basis = QuoteAdjustment.basis(quote_row.source, security)
    QuoteAdjustment.raw_close(quote_row.close, quote_row.date, basis, events)
  end

  defp security_struct(%{security: %Portfolixir.Catalog.Security{} = security}), do: security
  defp security_struct(_tx), do: nil

  defp trade_points(transactions, walk_start) do
    transactions
    |> Enum.filter(&(&1.type in ["buy", "sell"] and match?(%Decimal{}, &1.price)))
    |> Enum.map(
      &%{
        date: effective_date(&1, walk_start),
        close: &1.price,
        currency: &1.currency_code,
        price_source: :trade,
        rank: 0
      }
    )
  end

  defp security_currency(%{security: %{currency_code: ccy}}) when is_binary(ccy), do: ccy
  defp security_currency(tx), do: tx.currency_code

  # Advances every pointer map entry to `day`, only re-inserting entries that
  # actually consumed a point — most days change nothing for most keys.
  defp advance_map(map, day, advance_fun) do
    Enum.reduce(map, map, fn {key, entry}, acc ->
      case advance_fun.(entry, day) do
        ^entry -> acc
        advanced -> Map.put(acc, key, advanced)
      end
    end)
  end

  # Advances every security's price pointer to `day` and collects the day's
  # trade-price basis steps (issue #545) as `security_id => {from, to}`. Like
  # `advance_map/3` it only re-inserts entries that actually consumed a point.
  defp advance_pricing(pricing, day) do
    Enum.reduce(pricing, {pricing, %{}}, fn {security_id, entry}, {prices, steps} = unchanged ->
      case advance_entry(entry, day) do
        {^entry, _step} ->
          unchanged

        {advanced, nil} ->
          {Map.put(prices, security_id, advanced), steps}

        {advanced, step} ->
          {Map.put(prices, security_id, advanced), Map.put(steps, security_id, step)}
      end
    end)
  end

  # Returns `{advanced_entry, basis_step | nil}` — the pair of prices
  # bracketing the day's re-pricing, reported only for a security that is
  # **unmeasured** coming into the day. Measurement is evaluated before the
  # day's own points are consumed, so the transition from a fabricated trade
  # price to the security's first quote ever is itself a basis step.
  defp advance_entry(entry, day) do
    measured? = entry.measured?
    {entry, opening} = consume_points(entry, day, :none)
    {entry, basis_step(measured?, opening, entry.price)}
  end

  # A rescale point (ADR-0028 §2) moves the *carried* price across a split's
  # effective date (divide by the ratio) instead of setting an absolute close.
  # It sorts at rank -1, so a same-day trade or quote point — already in the
  # post-split basis — consumes afterwards and wins as usual. That ordering is
  # what makes `opening` (captured at the day's first price point) share the
  # day's post-split basis with the price replacing it.
  defp consume_points(%{upcoming: [%{rescale: ratio, date: date} | rest]} = entry, day, open) do
    if Date.compare(date, day) in [:lt, :eq] do
      entry = %{entry | price: rescale_carried(entry.price, ratio), upcoming: rest}
      consume_points(entry, day, open)
    else
      {entry, open}
    end
  end

  defp consume_points(%{upcoming: [%{date: date} = point | rest]} = entry, day, open) do
    if Date.compare(date, day) in [:lt, :eq] do
      # Captured before the point overwrites it: `open` is the price the day's
      # *first* price point replaced, in the day's post-split basis.
      open = opening(open, entry.price)
      price = %{close: point.close, currency: point.currency, price_source: point.price_source}
      entry = %{entry | price: price, upcoming: rest, measured?: measured?(entry, point)}
      consume_points(entry, day, open)
    else
      {entry, open}
    end
  end

  defp consume_points(entry, _day, open), do: {entry, open}

  defp measured?(_entry, %{price_source: :quote}), do: true
  defp measured?(entry, _point), do: entry.measured?

  # The price the day's first price point replaced — `:none` until one is
  # consumed.
  defp opening(:none, replaced), do: {:price, replaced}
  defp opening(open, _replaced), do: open

  # A security that has never carried a quote from an earlier day is priced by
  # its own bookings alone; every re-pricing of it restates a fabricated basis
  # rather than observing a market — including its very first quote, which
  # would otherwise discharge the whole accumulated drift as one day of return.
  # Once a quote has landed the security is measured: later gaps in the feed
  # are just gaps, and the trade prices filling them stay return (issue #545
  # AC 2, quoted portfolios byte-identical).
  defp basis_step(false, {:price, from}, to), do: {from, to}
  defp basis_step(_measured, _opening, _to), do: nil

  defp rescale_carried(nil, _ratio), do: nil

  # The currency and the `price_source` ride along: a rescaled trade price is
  # still a trade price, just restated in the post-split basis.
  defp rescale_carried(%{close: close} = price, {p, q}),
    do: %{price | close: close |> Decimal.mult(q) |> Decimal.div(p)}

  # -- trade-price basis steps (issue #545) -----------------------------------

  # The day's valuation-basis step in base currency: the part of the value
  # change that only re-states a fabricated price. `day_factor/2` neutralises
  # it exactly the way it neutralises an external flow — no market was
  # observed, so it is not return.
  #
  # Per security with a step, the day is replayed as a queue of lots: the
  # sleeve carried in from yesterday at `from`, plus whatever today's legs
  # added at their own price. Every unit that ends the day marked at `to`
  # without having become cash contributes `quantity x (to - basis)`; a sale
  # contributes nothing, because it turned its slice into real cash and its
  # gain against the basis it consumed is genuine return.
  defp basis_adjustment(steps, opening, legs, context, carried_fx) when map_size(steps) > 0 do
    context = carried_rates_context(context, carried_fx)

    Enum.reduce(steps, @zero, fn {security_id, {from, to}}, acc ->
      held = Map.get(opening, security_id, @zero)
      booked = Map.get(legs, security_id, [])
      Decimal.add(acc, security_basis(held, from, to, booked, context))
    end)
  end

  defp basis_adjustment(_steps, _opening, _legs, _context, _carried_fx), do: @zero

  # A basis step restates *yesterday's* closing value into the new price basis,
  # so it converts at yesterday's rates — converting it at today's would cancel
  # the retained sleeve's own currency move out of the return. A currency whose
  # series starts today has no carried rate and falls back to today's, so the
  # step is still converted instead of collapsing to zero on the walk's first
  # day.
  defp carried_rates_context(context, carried_fx) do
    fx =
      Map.new(context.fx, fn {currency, entry} ->
        case Map.get(carried_fx, currency) do
          %{rate: %Decimal{}} = carried -> {currency, carried}
          _absent -> {currency, entry}
        end
      end)

    %{context | fx: fx}
  end

  defp security_basis(held, from, to, legs, context) do
    mark = %{price: to, context: context}

    {lots, delivered} =
      Enum.reduce(legs, {open_lots(held, from), @zero}, &place_leg(&1, &2, mark))

    Enum.reduce(lots, delivered, fn {quantity, basis}, acc ->
      Decimal.add(acc, step_value(quantity, basis, mark))
    end)
  end

  defp open_lots(quantity, price) do
    if Decimal.equal?(quantity, @zero), do: [], else: [{quantity, price}]
  end

  defp step_value(quantity, basis, %{price: to, context: context}),
    do: Decimal.sub(priced(quantity, to, context), priced(quantity, basis, context))

  # A split's scale leg (ADR-0028) multiplies the held quantity. Prices are
  # left alone: the carried price was already rescaled at rank -1 before the
  # day's points, and a split replays first within the day (`intra_day_order`),
  # so the only lot in the queue is the opening sleeve at that already-rescaled
  # `from`.
  defp place_leg({:scale, ratio}, {lots, delivered}, _mark) do
    {Enum.map(lots, fn {qty, basis} -> {Projection.scale_quantity(qty, ratio), basis} end),
     delivered}
  end

  defp place_leg({:trade, delta, price}, acc, mark),
    do: settle_leg(acc, delta, price, false, mark)

  defp place_leg({:mark, delta}, acc, mark), do: settle_leg(acc, delta, mark.price, true, mark)

  # Places one quantity leg on the security's lot queue. A disposal consumes
  # the **most recently acquired** lot first: what a day buys is netted against
  # what the same day sells, and only the residual reaches the sleeve carried
  # in from yesterday. `carried?` marks a disposal that produced no cash (an
  # outbound delivery, a depot transfer) — those units are still marked at the
  # day's price, in the day's external flow or in the counter depot, so their
  # re-pricing stays a basis step.
  defp settle_leg({[], delivered}, delta, price, _carried?, _mark),
    do: {new_lot(delta, price), delivered}

  defp settle_leg({[{quantity, basis} | rest] = lots, delivered}, delta, price, carried?, mark) do
    if closing?(quantity, delta) do
      taken = closed_quantity(quantity, delta)

      delivered =
        if carried?,
          do: Decimal.add(delivered, step_value(Decimal.negate(taken), basis, mark)),
          else: delivered

      remaining = keep_lot(Decimal.add(quantity, taken), basis, rest)
      settle_leg({remaining, delivered}, Decimal.sub(delta, taken), price, carried?, mark)
    else
      {new_lot(delta, price) ++ lots, delivered}
    end
  end

  # The queue only ever holds lots of one sign — an opposite leg consumes
  # rather than joins — so testing the head decides the whole queue.
  defp closing?(quantity, delta) do
    (Decimal.positive?(quantity) and Decimal.negative?(delta)) or
      (Decimal.negative?(quantity) and Decimal.positive?(delta))
  end

  # The signed slice of `delta` this lot absorbs: `delta`'s sign, magnitude
  # capped by the lot.
  defp closed_quantity(quantity, delta) do
    magnitude = Decimal.min(Decimal.abs(quantity), Decimal.abs(delta))
    if Decimal.negative?(delta), do: Decimal.negate(magnitude), else: magnitude
  end

  defp keep_lot(quantity, basis, rest) do
    if Decimal.equal?(quantity, @zero), do: rest, else: [{quantity, basis} | rest]
  end

  defp new_lot(delta, price) do
    if Decimal.equal?(delta, @zero), do: [], else: [{delta, price}]
  end

  defp priced(_quantity, nil, _context), do: @zero

  defp priced(quantity, %{close: close, currency: currency}, context),
    do: to_base(Decimal.mult(quantity, close), currency, context)

  defp portfolio_value(state, context) do
    securities =
      Enum.reduce(state.qty, @zero, fn {security_id, qty}, acc ->
        Decimal.add(acc, security_value(security_id, qty, context))
      end)

    Enum.reduce(state.cash, securities, fn {account_id, balance}, acc ->
      currency = Map.get(context.currencies, account_id)
      Decimal.add(acc, to_base(balance, currency, context))
    end)
  end

  defp security_value(security_id, qty, context) do
    case Map.get(context.pricing, security_id) do
      %{price: %{close: %Decimal{} = close, currency: currency}} ->
        to_base(Decimal.mult(qty, close), currency, context)

      _ ->
        @zero
    end
  end

  # -- in-memory FX ------------------------------------------------------------

  # Preloads the EUR-hub rate series for every currency the walk can touch
  # (account, security/trade and transaction currencies plus the base), so the
  # daily conversion never queries. GBX is priced through GBP × 100, mirroring
  # `Portfolixir.Fx`.
  defp init_fx(transactions, account_currencies, base, walk_start) do
    transactions
    |> Enum.flat_map(&[&1.currency_code, security_currency(&1)])
    |> Enum.concat(Map.values(account_currencies))
    |> Enum.concat([base])
    |> Enum.flat_map(fn
      "GBX" -> ["GBP"]
      ccy -> [ccy]
    end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in [nil, @hub]))
    |> Map.new(fn ccy ->
      carried =
        case Fx.hub_rate_before(ccy, Date.add(walk_start, -1)) do
          %{rate: %Decimal{} = rate} -> rate
          _ -> nil
        end

      points =
        ccy
        |> Fx.series(walk_start)
        |> Enum.map(&%{date: &1.date, rate: &1.rate})

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

  # A missing rate path contributes zero rather than failing the whole series;
  # ADR-0010 records this trade-off.
  defp to_base(amount, currency, context) do
    case conversion_rate(currency, context.base, context.fx) do
      {:ok, rate} -> Decimal.mult(amount, rate)
      {:error, _reason} -> @zero
    end
  end

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
      _ -> {:error, :no_rate}
    end
  end

  defp eur_rate(_ccy, _fx), do: {:error, :no_rate}

  # -- chaining ---------------------------------------------------------------

  defp chain_day(point, {acc, growth, flows, prev}) do
    growth = Decimal.mult(growth, day_factor(point, prev))
    entry = Map.put(point, :cumulative_ttwror, Decimal.sub(growth, @one))
    {[entry | acc], growth, Decimal.add(flows, point.flow), point.value}
  end

  defp baseline([]), do: @zero
  defp baseline(before), do: List.last(before).value

  defp end_value([], start_value), do: start_value
  defp end_value(series, _start_value), do: List.last(series).value

  @doc """
  One day's return factor `1 + r_d` against the previous day's value.

  `r_d = V_d / (V_{d−1} + F_d + B_d) − 1`, with the day's external flow `F_d`
  and its trade-price basis step `B_d` (issue #545) both assumed at the start
  of the day. A day whose base is zero or negative (nothing meaningfully
  invested) contributes no return — a near-zero base would otherwise explode
  the chain.

  Public so every chaining caller shares one definition; `SnapshotComparison`
  chains the same daily points from the as-of date.
  """
  def day_factor(point, prev) do
    denominator = prev |> Decimal.add(point.flow) |> Decimal.add(basis_of(point))

    if Decimal.compare(denominator, @zero) == :gt do
      Decimal.div(point.value, denominator)
    else
      @one
    end
  end

  defp basis_of(point), do: Map.get(point, :basis, @zero)

  @doc """
  The trade costs a walk point carries (#708), defaulting to zero so a point
  from an older stored payload never reads as `nil` in arithmetic.
  """
  def trade_costs_of(point), do: Map.get(point, :trade_costs) || @zero

  # -- periods ----------------------------------------------------------------

  defp period_start("max", _today), do: ~D[0001-01-01]
  defp period_start("ytd", today), do: Date.new!(today.year, 1, 1)
  defp period_start("1y", today), do: years_ago(today, 1)
  defp period_start("3y", today), do: years_ago(today, 3)
  defp period_start("5y", today), do: years_ago(today, 5)
  defp period_start({:year, year}, _today), do: Date.new!(year, 1, 1)
  defp period_start({:range, from, _to}, _today), do: from

  # Where the chained period ends: today, except for the bounded periods
  # (#563), which clamp to today so a current year or an open-ended range
  # never claims days that have not happened yet.
  defp period_end({:year, year}, today), do: clamp_end(Date.new!(year, 12, 31), today)
  defp period_end({:range, _from, to}, today), do: clamp_end(to, today)
  defp period_end(_period, today), do: today

  defp clamp_end(date, today) do
    if Date.compare(date, today) == :gt, do: today, else: date
  end

  defp years_ago(%Date{} = date, years) do
    case Date.new(date.year - years, date.month, date.day) do
      {:ok, shifted} -> shifted
      # Feb 29 in a non-leap target year.
      {:error, _} -> Date.new!(date.year - years, date.month, date.day - 1)
    end
  end

  defp clamp_start(start, first_date) do
    if Date.compare(start, first_date) == :lt, do: first_date, else: start
  end

  defp sorted_transactions(portfolio_id) do
    portfolio_id
    |> Ledger.list_transactions_for_portfolio()
    |> Projection.replay_sort()
  end

  defp base_currency(portfolio_id) do
    case Portfolios.get_portfolio(portfolio_id) do
      %{base_currency_code: code} -> code
      _ -> nil
    end
  end
end
