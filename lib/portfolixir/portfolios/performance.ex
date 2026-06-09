defmodule Portfolixir.Portfolios.Performance do
  @moduledoc """
  Read-time portfolio performance: a daily valuation series and the true
  time-weighted rate of return (TTWROR), the Portfolio Performance way.

  The portfolio is valued **every day** from the first transaction onward
  (positions priced from the most recent quote close on or before the day,
  converted to the base currency via `Portfolixir.Fx`, plus cash). Each day's
  return neutralises **external cash flows** — deposits, removals, security
  deliveries in/out, and the residual jump of a balance snapshot — so the
  result measures the investments themselves, independent of when money was
  added or taken out. Daily returns chain geometrically:

      TTWROR = ∏(1 + r_d) − 1   with   r_d = V_d / (V_{d−1} + F_d) − 1

  where `F_d` is the day's net external flow, assumed at the start of the day.
  Dividends, interest, fees and taxes are internal (they are return); buys,
  sells and transfers between own accounts only move money around inside the
  portfolio. Nothing is stored — like holdings and the valuation, the series
  is derived on read (ADR-0004, ADR-0010).

  Limitations (recorded in ADR-0010): a security without any usable quote or
  rate path contributes zero value until one exists, and the later jump counts
  as return; deliveries without a quote enter as a zero-valued flow.
  """

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @zero Decimal.new("0")
  @one Decimal.new("1")
  @periods ~w(ytd 1y 3y 5y max)

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
    today = Keyword.get(opts, :today, Date.utc_today())

    with :ok <- validate_period(period) do
      base = base_currency(portfolio_id)
      transactions = sorted_transactions(portfolio_id)
      {:ok, build(portfolio_id, period, today, base, transactions)}
    end
  end

  defp validate_period(period) when period in @periods, do: :ok
  defp validate_period(_period), do: {:error, :invalid_period}

  defp build(portfolio_id, period, today, base, []) do
    empty_result(portfolio_id, period, today, base)
  end

  defp build(portfolio_id, period, today, base, transactions) do
    first_date = hd(transactions).date

    if Date.compare(first_date, today) == :gt do
      empty_result(portfolio_id, period, today, base)
    else
      daily = daily_series(portfolio_id, transactions, first_date, today, base)
      start_date = clamp_start(period_start(period, today), first_date)
      summarise(portfolio_id, period, base, daily, start_date, today)
    end
  end

  defp empty_result(portfolio_id, period, today, base) do
    %{
      portfolio_id: portfolio_id,
      period: period,
      base_currency: base,
      start_date: nil,
      end_date: today,
      start_value: @zero,
      end_value: @zero,
      net_external_flows: @zero,
      ttwror: @zero,
      series: []
    }
  end

  # -- daily walk -------------------------------------------------------------

  # Walks every day from the first transaction to `today`, maintaining held
  # quantities and per-account cash, and records each day's portfolio value
  # (base currency) and net external flow.
  defp daily_series(portfolio_id, transactions, first_date, today, base) do
    by_day = Enum.group_by(transactions, & &1.date)

    context = %{
      base: base,
      currencies: account_currencies(portfolio_id),
      pricing: init_pricing(transactions, first_date)
    }

    state = %{qty: %{}, cash: %{}}

    {series, _state, _context} =
      Enum.reduce(Date.range(first_date, today), {[], state, context}, &walk_day(by_day, &1, &2))

    Enum.reverse(series)
  end

  defp walk_day(by_day, day, {acc, state, context}) do
    context = %{context | pricing: advance_pricing(context.pricing, day)}
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

  defp add_qty(state, security_id, delta) do
    %{state | qty: Map.update(state.qty, security_id, delta, &Decimal.add(&1, delta))}
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

  # Per security: currency, the close carried in from before the walk, and the
  # remaining quote series to consume as days advance (one DB read per security).
  defp init_pricing(transactions, first_date) do
    transactions
    |> Enum.filter(& &1.security_id)
    |> Enum.uniq_by(& &1.security_id)
    |> Map.new(fn tx ->
      carried =
        case Quotes.at_or_before(tx.security_id, Date.add(first_date, -1)) do
          %{close: %Decimal{} = close} -> close
          _ -> nil
        end

      upcoming = Quotes.range(tx.security_id, first_date, ~D[9999-12-31])
      {tx.security_id, %{currency: security_currency(tx), close: carried, upcoming: upcoming}}
    end)
  end

  defp security_currency(%{security: %{currency_code: ccy}}) when is_binary(ccy), do: ccy
  defp security_currency(tx), do: tx.currency_code

  defp advance_pricing(pricing, day) do
    Map.new(pricing, fn {security_id, entry} -> {security_id, advance_entry(entry, day)} end)
  end

  defp advance_entry(%{upcoming: [%{date: date, close: close} | rest]} = entry, day) do
    if Date.compare(date, day) in [:lt, :eq] do
      advance_entry(%{entry | close: close, upcoming: rest}, day)
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
      %{close: %Decimal{} = close, currency: currency} ->
        to_base(Decimal.mult(qty, close), currency, context)

      _ ->
        @zero
    end
  end

  # A missing rate path contributes zero rather than failing the whole series;
  # ADR-0010 records this trade-off.
  defp to_base(amount, currency, context) do
    case Fx.convert(amount, currency, context.base, context.day) do
      {:ok, converted} -> converted
      {:error, _reason} -> @zero
    end
  end

  # -- chaining ---------------------------------------------------------------

  defp summarise(portfolio_id, period, base, daily, start_date, today) do
    {before, in_period} = Enum.split_with(daily, &(Date.compare(&1.date, start_date) == :lt))
    start_value = baseline(before)

    {points, growth, flows, _prev} =
      Enum.reduce(in_period, {[], @one, @zero, start_value}, &chain_day/2)

    series = Enum.reverse(points)

    %{
      portfolio_id: portfolio_id,
      period: period,
      base_currency: base,
      start_date: start_date,
      end_date: today,
      start_value: start_value,
      end_value: end_value(series, start_value),
      net_external_flows: flows,
      ttwror: Decimal.sub(growth, @one),
      series: series
    }
  end

  defp chain_day(point, {acc, growth, flows, prev}) do
    growth = Decimal.mult(growth, day_factor(point, prev))
    entry = Map.put(point, :cumulative_ttwror, Decimal.sub(growth, @one))
    {[entry | acc], growth, Decimal.add(flows, point.flow), point.value}
  end

  defp baseline([]), do: @zero
  defp baseline(before), do: List.last(before).value

  defp end_value([], start_value), do: start_value
  defp end_value(series, _start_value), do: List.last(series).value

  # r_d = V_d / (V_{d-1} + F_d) − 1, flows at the start of the day. A day with
  # nothing invested (zero denominator) contributes no return.
  defp day_factor(point, prev) do
    denominator = Decimal.add(prev, point.flow)

    if Decimal.equal?(denominator, @zero) do
      @one
    else
      Decimal.div(point.value, denominator)
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
