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
  portfolio. Nothing is stored — like holdings and the valuation, the series
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

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

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
  `ttwror`, `start_value`/`end_value`, `net_external_flows`, and the daily
  `series` of `%{date, value, flow, cumulative_ttwror}` for the period.
  """
  def for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    period = Keyword.get(opts, :period, "max")

    with :ok <- validate_period(period) do
      portfolio_id |> analysis(opts) |> summarise(period)
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
          daily: daily_series(portfolio_id, transactions, start, today, base)
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

    %{
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
  defp daily_series(portfolio_id, transactions, walk_start, today, base) do
    by_day = Enum.group_by(transactions, &effective_date(&1, walk_start))
    currencies = account_currencies(portfolio_id)

    context = %{
      base: base,
      currencies: currencies,
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

  # A balance snapshot states the balance *including* the rest of its day, so
  # it is applied after the day's other bookings (mirrors Ledger.cash_balances).
  defp sort_within_day(transactions) do
    Enum.sort_by(transactions, &{&1.type == "balance_adjustment", &1.id})
  end

  defp apply_transactions(transactions, state, context) do
    Enum.reduce(transactions, {state, @zero}, fn tx, {state, flow} ->
      {state, tx_flow} = apply_transaction(tx, state, context)
      {state, Decimal.add(flow, tx_flow)}
    end)
  end

  # -- per-kind effects: {new_state, external_flow_in_base} -------------------

  defp apply_transaction(%{type: "deposit"} = tx, state, context) do
    amount = gross(tx)
    {add_cash(state, tx.cash_account_id, amount), cash_to_base(amount, tx, context)}
  end

  defp apply_transaction(%{type: "removal"} = tx, state, context) do
    amount = Decimal.negate(gross(tx))
    {add_cash(state, tx.cash_account_id, amount), cash_to_base(amount, tx, context)}
  end

  defp apply_transaction(%{type: type} = tx, state, _context)
       when type in ["dividend", "interest", "tax_refund"] do
    {add_cash(state, tx.cash_account_id, gross(tx)), @zero}
  end

  defp apply_transaction(%{type: type} = tx, state, _context) when type in ["fee", "tax"] do
    {add_cash(state, tx.cash_account_id, Decimal.negate(gross(tx))), @zero}
  end

  defp apply_transaction(%{type: "buy"} = tx, state, _context) do
    state =
      state
      |> add_qty(tx.security_id, tx.quantity)
      |> add_cash(tx.cash_account_id, Decimal.negate(buy_cost(tx)))

    {state, @zero}
  end

  defp apply_transaction(%{type: "sell"} = tx, state, _context) do
    state =
      state
      |> add_qty(tx.security_id, Decimal.negate(tx.quantity))
      |> add_cash(tx.cash_account_id, sell_proceeds(tx))

    {state, @zero}
  end

  defp apply_transaction(%{type: "cash_transfer"} = tx, state, _context) do
    amount = gross(tx)

    state =
      state
      |> add_cash(tx.cash_account_id, Decimal.negate(amount))
      |> add_cash(tx.counter_cash_account_id, amount)

    {state, @zero}
  end

  defp apply_transaction(%{type: "inbound_delivery"} = tx, state, context) do
    state = add_qty(state, tx.security_id, tx.quantity)
    {state, security_value(tx.security_id, tx.quantity, context)}
  end

  defp apply_transaction(%{type: "outbound_delivery"} = tx, state, context) do
    state = add_qty(state, tx.security_id, Decimal.negate(tx.quantity))
    {state, Decimal.negate(security_value(tx.security_id, tx.quantity, context))}
  end

  # Same security, same portfolio — quantities net out at portfolio level.
  defp apply_transaction(%{type: "security_transfer"}, state, _context), do: {state, @zero}

  # The stated balance replaces the derived one; the residual jump is money
  # that appeared or left outside the recorded bookings, i.e. an external flow.
  defp apply_transaction(%{type: "balance_adjustment"} = tx, state, context) do
    previous = Map.get(state.cash, tx.cash_account_id, @zero)
    jump = Decimal.sub(gross(tx), previous)
    {add_cash(state, tx.cash_account_id, jump), cash_to_base(jump, tx, context)}
  end

  defp apply_transaction(_tx, state, _context), do: {state, @zero}

  # Sold-out positions are dropped so the daily valuation only touches what
  # is actually held — with long histories most securities are closed.
  defp add_qty(state, security_id, delta) do
    qty = state.qty |> Map.get(security_id, @zero) |> Decimal.add(delta)

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

  defp cash_to_base(amount, tx, context) do
    currency = Map.get(context.currencies, tx.cash_account_id, tx.currency_code)
    to_base(amount, currency, context)
  end

  defp gross(%{gross_amount: %Decimal{} = amount}), do: amount
  defp gross(_tx), do: @zero

  defp buy_cost(%{gross_amount: %Decimal{} = amount}), do: amount
  defp buy_cost(tx), do: tx.quantity |> Decimal.mult(tx.price) |> Decimal.add(fees_and_taxes(tx))

  defp sell_proceeds(%{gross_amount: %Decimal{} = amount}), do: amount

  defp sell_proceeds(tx),
    do: tx.quantity |> Decimal.mult(tx.price) |> Decimal.sub(fees_and_taxes(tx))

  defp fees_and_taxes(tx), do: Decimal.add(tx.fees || @zero, tx.taxes || @zero)

  # -- pricing ----------------------------------------------------------------

  # Per security: the price carried in from before the walk and the remaining
  # price points to consume as days advance (one DB read per security). Price
  # points merge the quote series with the portfolio's own trade prices; a
  # quote wins over a trade on the same day (rank 1 is consumed after rank 0,
  # and the last consumed point sticks).
  defp init_pricing(transactions, walk_start) do
    transactions
    |> Enum.filter(& &1.security_id)
    |> Enum.group_by(& &1.security_id)
    |> Map.new(fn {security_id, txs} ->
      currency = security_currency(hd(txs))

      carried =
        case Quotes.at_or_before(security_id, Date.add(walk_start, -1)) do
          %{close: %Decimal{} = close} -> %{close: close, currency: currency}
          _ -> nil
        end

      quote_points =
        security_id
        |> Quotes.range(walk_start, ~D[9999-12-31])
        |> Enum.map(&%{date: &1.date, close: &1.close, currency: currency, rank: 1})

      points =
        (trade_points(txs, walk_start) ++ quote_points)
        |> Enum.sort_by(&{Date.to_erl(&1.date), &1.rank})

      {security_id, %{price: carried, upcoming: points}}
    end)
  end

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
    |> Enum.sort_by(&{Date.to_erl(&1.date), &1.id})
  end

  defp base_currency(portfolio_id) do
    case Portfolios.get_portfolio(portfolio_id) do
      %{base_currency_code: code} -> code
      _ -> nil
    end
  end
end
