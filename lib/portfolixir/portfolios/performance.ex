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

  The expensive daily walk is computed once per portfolio via `analysis/2`;
  every period (`ytd`/`1y`/…) is then a cheap pure `summarise/2` over that
  series, so callers can switch periods without re-walking.

  All quote, FX-rate and transaction data is preloaded up front; the walk
  itself issues no queries.
  """

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.QuoteAdjustment
  alias Portfolixir.Catalog.Quotes
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
  `ttwror`, the money-weighted `irr` (`Decimal.t() | nil`),
  `start_value`/`end_value`, `net_external_flows`, and the daily `series` of
  `%{date, value, flow, cumulative_ttwror}` for the period.
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

  Returns a map with the raw `daily` series (`%{date, value, flow}`),
  `first_date`/`today`, the base currency, and `suspect_dates` (dates of
  bookings older than #{inspect(@earliest_plausible)}, applied on the first
  plausible day). Feed it to `summarise/2` once per period.
  """
  def analysis(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    # `:view` (a view id) scopes the series to the holdings matching that view;
    # `nil` -> `:unscoped` -> the walk takes the unchanged code path (#444).
    # A vanished view returns `{:error, :view_not_found}` (fix round).
    case Buckets.load_scope(portfolio_id, Keyword.get(opts, :view)) do
      {:error, :view_not_found} = error -> error
      scope -> scoped_analysis(portfolio_id, scope, opts)
    end
  end

  defp scoped_analysis(portfolio_id, scope, opts) do
    today = Keyword.get(opts, :today, Date.utc_today())
    base = base_currency(portfolio_id)
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
          daily: daily_series(portfolio_id, transactions, start, today, base, scope)
        }
    end
  end

  @doc """
  Chains one period out of an `analysis/2` result.

  Pure and cheap — switching periods needs no new queries or daily walk.
  Returns `{:ok, result}` or `{:error, :invalid_period}`.
  """
  def summarise(analysis, period) do
    with :ok <- validate_period(period) do
      {:ok, do_summarise(analysis, period)}
    end
  end

  defp validate_period(period) when period in @periods, do: :ok
  defp validate_period(_period), do: {:error, :invalid_period}

  defp do_summarise(%{daily: []} = analysis, period) do
    empty_result(analysis, period)
  end

  defp do_summarise(%{daily: daily} = analysis, period) do
    start_date = clamp_start(period_start(period, analysis.today), analysis.first_date)
    {before, in_period} = Enum.split_with(daily, &(Date.compare(&1.date, start_date) == :lt))
    start_value = baseline(before)

    {points, growth, flows, _prev} =
      Enum.reduce(in_period, {[], @one, @zero, start_value}, &chain_day/2)

    series = Enum.reverse(points)

    summary = %{
      portfolio_id: analysis.portfolio_id,
      period: period,
      base_currency: analysis.base_currency,
      start_date: start_date,
      end_date: analysis.today,
      start_value: start_value,
      end_value: end_value(series, start_value),
      net_external_flows: flows,
      ttwror: Decimal.sub(growth, @one),
      suspect_dates: analysis.suspect_dates,
      series: series
    }

    Map.put(summary, :irr, IRR.for_summary(summary))
  end

  defp empty_analysis(portfolio_id, today, base, suspects) do
    %{
      portfolio_id: portfolio_id,
      base_currency: base,
      today: today,
      first_date: nil,
      suspect_dates: suspects,
      daily: []
    }
  end

  defp empty_result(analysis, period) do
    %{
      portfolio_id: analysis.portfolio_id,
      period: period,
      base_currency: analysis.base_currency,
      start_date: nil,
      end_date: analysis.today,
      start_value: @zero,
      end_value: @zero,
      net_external_flows: @zero,
      ttwror: @zero,
      irr: nil,
      suspect_dates: analysis.suspect_dates,
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
    context = %{
      context
      | pricing: advance_map(context.pricing, day, &advance_entry/2),
        fx: advance_map(context.fx, day, &advance_rate/2)
    }

    context = Map.put(context, :day, day)
    day_txs = by_day |> Map.get(day, []) |> sort_within_day()
    {state, flow} = apply_transactions(day_txs, state, context)
    value = portfolio_value(state, context)
    {[%{date: day, value: value, flow: flow} | acc], state, context}
  end

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

  defp apply_transactions(transactions, state, context) do
    Enum.reduce(transactions, {state, @zero}, fn tx, {state, flow} ->
      {state, tx_flow} = apply_transaction(tx, state, context)
      {state, Decimal.add(flow, tx_flow)}
    end)
  end

  # -- canonical effects (ADR-0011): {new_state, external_flow_in_base} -------

  # Applies the transaction's effect from the single per-kind reducer. When
  # the projection marks the booking external, the applied cash deltas (for a
  # balance snapshot: the residual jump — money that appeared or left outside
  # the recorded bookings) and the market value of the moved quantities count
  # as the day's external flow, converted to the base currency.
  defp apply_transaction(tx, state, %{scope: :unscoped} = context) do
    effect = Projection.effects(tx)
    {state, cash_flow} = apply_cash_legs(effect.cash, tx, state, context, effect.external)
    {state, qty_flow} = apply_quantity_legs(effect.quantities, state, context, effect.external)
    {state, Decimal.add(cash_flow, qty_flow)}
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

    state =
      Enum.reduce(kept_qty, state, fn
        {:scale, %{security_id: sec, ratio: ratio}}, st -> scale_qty(st, sec, ratio)
        {_acct, sec, delta}, st -> add_qty(st, sec, delta)
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

    {state, flow}
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
  defp apply_quantity_legs(legs, state, context, external?) do
    Enum.reduce(legs, {state, @zero}, fn
      # A split's scale leg (ADR-0028) multiplies the held quantity; it is
      # never an external flow, so it contributes nothing to the day's flow.
      # The walk is per portfolio, so the row's per-portfolio scope holds by
      # construction. The walk aggregates quantities per security across the
      # portfolio's accounts; scaling the aggregate equals the sum of the
      # per-account scaled quantities up to the volume-scale-6 quantization.
      {:scale, %{security_id: security_id, ratio: ratio}}, {state, flow} ->
        {scale_qty(state, security_id, ratio), flow}

      {_account_id, security_id, delta}, {state, flow} ->
        flow =
          if external? do
            Decimal.add(flow, security_value(security_id, delta, context))
          else
            flow
          end

        {add_qty(state, security_id, delta), flow}
    end)
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
    %{price: carried, upcoming: points}
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

        %{close: close, currency: currency}

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

  # A rescale point (ADR-0028 §2) moves the *carried* price across a split's
  # effective date (divide by the ratio) instead of setting an absolute close.
  # It sorts at rank -1, so a same-day trade or quote point — already in the
  # post-split basis — consumes afterwards and wins as usual.
  defp advance_entry(%{upcoming: [%{rescale: ratio, date: date} | rest]} = entry, day) do
    if Date.compare(date, day) in [:lt, :eq] do
      advance_entry(%{entry | price: rescale_carried(entry.price, ratio), upcoming: rest}, day)
    else
      entry
    end
  end

  defp advance_entry(%{upcoming: [%{date: date} = point | rest]} = entry, day) do
    if Date.compare(date, day) in [:lt, :eq] do
      advance_entry(
        %{entry | price: %{close: point.close, currency: point.currency}, upcoming: rest},
        day
      )
    else
      entry
    end
  end

  defp advance_entry(entry, _day), do: entry

  defp rescale_carried(nil, _ratio), do: nil

  defp rescale_carried(%{close: close, currency: currency}, {p, q}),
    do: %{close: close |> Decimal.mult(q) |> Decimal.div(p), currency: currency}

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

  # r_d = V_d / (V_{d-1} + F_d) − 1, flows at the start of the day. A day whose
  # base is zero or negative (nothing meaningfully invested) contributes no
  # return — a near-zero base would otherwise explode the chain.
  defp day_factor(point, prev) do
    denominator = Decimal.add(prev, point.flow)

    if Decimal.compare(denominator, @zero) == :gt do
      Decimal.div(point.value, denominator)
    else
      @one
    end
  end

  # -- periods ----------------------------------------------------------------

  defp period_start("max", _today), do: ~D[0001-01-01]
  defp period_start("ytd", today), do: Date.new!(today.year, 1, 1)
  defp period_start("1y", today), do: years_ago(today, 1)
  defp period_start("3y", today), do: years_ago(today, 3)
  defp period_start("5y", today), do: years_ago(today, 5)

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
