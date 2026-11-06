defmodule Portfolixir.Portfolios.Performance.SaleReinvestment do
  @moduledoc """
  What a switch cost (I18 mode 3; ADR-0057): a sale compared with the
  purchases its money went into, found by rule. Ladder (c): it compares what
  was done with what was held before and replays no rule against past
  prices. Nothing is stored; every read derives the matches from the ledger
  and the figures from the closes and rates the catalogue holds at that
  moment, so the same ledger always gives the same answer.

  ## The matching rule (ADR-0057 §1)

    1. **Proceeds** are the sale's booked cash amount on its cash account
       (`Portfolixir.Ledger.Projection.cash_amount/1`: its settlement, after
       its fees and taxes), in that account's currency. A tax refund split
       off the sale (a `tax_refund` booking of the sold security on the
       sale's date and cash account, the shape the import gives it) is a
       negative tax of the sale: its cash joins the proceeds and its amount
       lowers the sale's taxes.
    2. **Candidates** are `buy` bookings debiting the same cash account,
       dated on or after the sale's date and at most #{30} calendar days after
       it, of any security other than the one sold.
    3. **Order:** proceeds wait in a queue by sale date, then booking id;
       buys take from the oldest proceeds first, in date order, then booking
       id, each at most its own cash debit (`cash_amount/1` negated: price,
       quantity, fees and taxes). On one date the day's sales enter the queue
       before its buys take from it.
    4. What is left over is `unallocated` and stays out of the comparison.

  A sale with no cash account, or whose booked cash amount is not positive
  (no settlement), is `no_match` with `:no_cash_account`; one no buy took
  from is `no_match` with `:proceeds_taken_by_earlier_sale` when a candidate
  existed (earlier proceeds funded it) and `:no_buy_within_30_days` when
  none did.

  ## The two sides, per span (ADR-0057 §2)

  The spans are FR-50's, over the same ends as the sale's own row
  (`SaleHindsight.span_ends/2`): `1m`, `3m`, `12m` and `latest`, each
  `:pending` while its end is after today. With `a` the share of the
  proceeds the matched buys took:

    * **kept** = `a` × the sold quantity × the sold security's close at the
      end, in EUR: what the part of the position whose money went on would
      be worth had it been kept;
    * **switched** = the sum over the matched buys of, for a buy dated after
      the end, the amount it took as cash in the account's currency at the
      end's rate (`WindowReturn.eur_rate/2` on the end date), and for one on
      or before it, the share of the buy this sale paid for × the buy's
      quantity × the bought security's close at the end, in EUR;
    * **difference** = switched − kept.

  Every close and its EUR value is `WindowReturn.price_return/3`'s: the
  split-adjusted close standing for the date (at most 7 days older), at the
  stored EUR-hub rate of its own date. A booked quantity is read in that
  basis: multiplied by the ratio of the security's splits after its booking
  date (`QuoteAdjustment.cumulative_ratio_after/2`), so a split is not a
  move. Each side is computed as one division of exact products. A span
  that cannot be measured is `:incomplete` with the `side` (`:kept` or
  `:switched`) and `WindowReturn`'s reason (`:no_start_close`,
  `:no_end_close`, `:no_fx_rate`).

  ## Costs and income (ADR-0057 §3)

    * **fees_inside** = `a` × the sale's fees + each matched buy's share ×
      its fees, for the buys dated on or before the end, as cash at the
      end's rate: the switched side already carries them; the line names
      how much of the difference they are.
    * **taxes_apart** = `a` × the sale's taxes, signed (a refund split off
      the sale is negative), as cash at the end's rate, **added back to the
      switched side**: `difference = switched + taxes_apart − kept`, both
      sides before tax, because the kept position's latent tax is not
      booked (deriving it is F7, behind its own gate).
    * **income_apart**: the bought positions' booked distributions (a
      `dividend`, or `interest` naming a bond) dated after each buy and on
      or before the end, before withholding tax (`gross_amount` + `taxes`),
      each buy's part being the share this sale paid for × its quantity over
      the quantity the portfolio held the day before, at the end's rate.
      Named and **never added**: the kept side's distributions are not
      booked, so both sides are price only.

  `match/1` is the rule as a pure function over ledger rows; `blocks/2`
  loads the rows once and answers each sale's block.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.QuoteAdjustment
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Performance.SaleHindsight
  alias Portfolixir.Portfolios.Performance.WindowReturn
  alias Portfolixir.Repo

  @window_days 30
  @zero Decimal.new(0)

  @type reason :: :no_buy_within_30_days | :proceeds_taken_by_earlier_sale | :no_cash_account

  @typedoc """
  One buy a sale's proceeds went into: the booking (`buy_id`), its date, its
  security and quantity, its whole cash debit, the amount this sale's
  proceeds paid of it and that amount's share of the debit.
  """
  @type matched_buy :: %{
          buy_id: integer(),
          date: Date.t(),
          security: Security.t() | nil,
          quantity: Decimal.t(),
          cash_debit: Decimal.t(),
          amount_taken: Decimal.t(),
          share_of_buy: Decimal.t()
        }

  @typedoc """
  A sale's block. `share_of_proceeds_matched` is ADR-0057's `a`: the sum
  of the amounts the matched buys took over the proceeds. Amounts are in
  `currency_code`, the sale's cash account's currency.
  """
  @type block :: %{
          status: :matched | :no_match,
          reason: reason() | nil,
          cash_account_id: integer() | nil,
          currency_code: String.t() | nil,
          proceeds: Decimal.t() | nil,
          buys: [matched_buy()],
          days_to_first_buy: non_neg_integer() | nil,
          share_of_proceeds_matched: Decimal.t() | nil,
          unallocated: Decimal.t() | nil,
          spans: [map()]
        }

  @doc "The window in calendar days after a sale within which a buy can take its proceeds."
  @spec window_days() :: pos_integer()
  def window_days, do: @window_days

  @doc """
  Each sale's block, keyed by the sale's id. The ledger rows the rule reads
  (every `buy`, `sell` and `tax_refund` of the sales' cash accounts) are
  loaded once; nothing is written.
  """
  @spec blocks([Transaction.t()], Date.t()) :: %{optional(integer()) => block()}
  def blocks(sales, %Date{} = today) when is_list(sales) do
    ledger = sales |> cash_account_ids() |> load_ledger()
    matching = match(ledger)
    loaded = Map.new(ledger, &{&1.id, &1})
    context = %{today: today, splits: split_events(matching), income: income_rows(matching)}

    Map.new(sales, fn sale ->
      # The row as loaded with its security and cash account, where the
      # ledger read holds it.
      sale = Map.get(loaded, sale.id, sale)
      {sale.id, block(sale, Map.get(matching, sale.id), context)}
    end)
  end

  # The split events (ADR-0028) of every sold and bought security, in one
  # read: each quantity is read in the closes' current display basis.
  defp split_events(matching) do
    matching
    |> Enum.flat_map(fn {_sale_id, match} ->
      [match.security_id | Enum.map(match.takes, & &1.buy.security_id)]
    end)
    |> Enum.uniq()
    |> Quotes.split_events_by_security()
  end

  # Every booking of the bought securities, for their distributions and the
  # quantities held when each was paid (ADR-0057 §3, income apart).
  defp income_rows(matching) do
    ids =
      matching
      |> Enum.flat_map(fn {_sale_id, match} -> Enum.map(match.takes, & &1.buy.security_id) end)
      |> Enum.uniq()

    case ids do
      [] ->
        %{}

      ids ->
        from(t in Transaction, where: t.security_id in ^ids, preload: [:cash_account])
        |> Repo.all()
        |> Enum.group_by(&{&1.portfolio_id, &1.security_id})
    end
  end

  defp cash_account_ids(sales) do
    sales |> Enum.map(& &1.cash_account_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  defp load_ledger([]), do: []

  defp load_ledger(cash_account_ids) do
    from(t in Transaction,
      where:
        t.cash_account_id in ^cash_account_ids and
          (t.type in ["buy", "sell"] or (t.type == "tax_refund" and not is_nil(t.security_id))),
      preload: [:security, :cash_account]
    )
    |> Repo.all()
  end

  @doc """
  The matching rule (ADR-0057 §1) over ledger rows: `buy`, `sell` and
  `tax_refund` bookings, each with its `cash_account_id`. Pure: the same
  rows give the same answer.

  Answers `%{sale_id => match}` for every sell with a cash account, where a
  match is `%{security_id, proceeds, taxes, fees, refunds, takes,
  candidate?}`: the sold security, the proceeds (or nil when not positive), the sale's taxes net of its refunds
  (signed), its fees, the refund bookings, the takes (`%{buy, amount}`, in
  queue order) and whether any candidate buy existed.
  """
  @spec match([Transaction.t() | map()]) :: %{optional(integer()) => map()}
  def match(rows) when is_list(rows) do
    rows
    |> Enum.reject(&is_nil(&1.cash_account_id))
    |> Enum.group_by(& &1.cash_account_id)
    |> Enum.flat_map(fn {_account, account_rows} -> match_account(account_rows) end)
    |> Map.new()
  end

  defp match_account(rows) do
    sales = rows |> Enum.filter(&(&1.type == "sell")) |> Enum.sort_by(&order_key/1)
    buys = rows |> Enum.filter(&(&1.type == "buy")) |> Enum.sort_by(&order_key/1)
    refunds = refunds_by_sale(Enum.filter(rows, &(&1.type == "tax_refund")), sales)

    entries = Enum.map(sales, &entry(&1, Map.get(refunds, &1.id, [])))

    takes =
      (Enum.map(entries, &{:sale, &1}) ++ Enum.map(buys, &{:buy, &1}))
      |> Enum.sort_by(&event_key/1)
      |> Enum.reduce({[], %{}}, &step/2)
      |> elem(1)

    Enum.map(entries, fn entry ->
      {entry.sale.id,
       %{
         security_id: entry.sale.security_id,
         proceeds: entry.proceeds,
         taxes: entry.taxes,
         fees: entry.sale.fees || @zero,
         refunds: entry.refunds,
         takes: takes |> Map.get(entry.sale.id, []) |> Enum.reverse(),
         candidate?: Enum.any?(buys, &candidate?(entry.sale, &1))
       }}
    end)
  end

  defp order_key(row), do: {Date.to_gregorian_days(row.date), row.id}

  # On one date, the day's sales enter the queue before its buys take.
  defp event_key({:sale, entry}), do: {Date.to_gregorian_days(entry.sale.date), 0, entry.sale.id}
  defp event_key({:buy, buy}), do: {Date.to_gregorian_days(buy.date), 1, buy.id}

  # A refund split off a sale is booked right after it: it belongs to the
  # sale of the same security, date and cash account with the greatest id
  # below its own.
  defp refunds_by_sale(refunds, sales) do
    refunds
    |> Enum.flat_map(fn refund ->
      sales
      |> Enum.filter(
        &(&1.security_id == refund.security_id and &1.date == refund.date and &1.id < refund.id)
      )
      |> Enum.max_by(& &1.id, fn -> nil end)
      |> case do
        nil -> []
        sale -> [{sale.id, refund}]
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp entry(sale, refunds) do
    refunded = Enum.reduce(refunds, @zero, &Decimal.add(cash(&1), &2))
    proceeds = Decimal.add(cash(sale), refunded)

    %{
      sale: sale,
      refunds: refunds,
      taxes: Decimal.sub(sale.taxes || @zero, refunded),
      proceeds: if(positive?(proceeds), do: proceeds, else: nil),
      remaining: if(positive?(proceeds), do: proceeds, else: @zero)
    }
  end

  defp cash(row), do: Projection.cash_amount(row) || @zero

  # A buy's cash debit: its booked cash amount on its account, negated.
  defp debit(buy), do: Decimal.negate(cash(buy))

  defp positive?(amount), do: Decimal.compare(amount, @zero) == :gt

  defp step({:sale, entry}, {queue, takes}), do: {queue ++ [entry], takes}

  defp step({:buy, buy}, {queue, takes}) do
    debit = debit(buy)

    if positive?(debit) do
      take(queue, buy, debit, [], takes)
    else
      {queue, takes}
    end
  end

  # The buy walks the queue oldest first and takes from each eligible
  # entry until its debit is paid or the queue ends; `need` is what is still
  # unpaid, `:paid` once nothing is.
  defp take([], _buy, _need, passed, takes), do: {Enum.reverse(passed), takes}
  defp take(queue, _buy, :paid, passed, takes), do: {Enum.reverse(passed, queue), takes}

  defp take([entry | rest], buy, need, passed, takes) do
    if eligible?(entry, buy) do
      amount = Decimal.min(entry.remaining, need)
      entry = %{entry | remaining: Decimal.sub(entry.remaining, amount)}
      taken = %{buy: buy, amount: amount}
      takes = Map.update(takes, entry.sale.id, [taken], &[taken | &1])
      left = Decimal.sub(need, amount)
      take(rest, buy, if(positive?(left), do: left, else: :paid), [entry | passed], takes)
    else
      take(rest, buy, need, [entry | passed], takes)
    end
  end

  defp eligible?(entry, buy),
    do: positive?(entry.remaining) and candidate?(entry.sale, buy)

  defp candidate?(sale, buy) do
    days = Date.diff(buy.date, sale.date)
    buy.security_id != sale.security_id and days >= 0 and days <= @window_days
  end

  # A sale's block: no_match with its reason, or the matched buys, a, the
  # unallocated rest and the days to the first buy.
  defp block(sale, nil, _context), do: no_match(sale, nil, :no_cash_account)

  defp block(sale, %{proceeds: nil} = match, _context),
    do: no_match(sale, match, :no_cash_account)

  defp block(sale, %{takes: []} = match, _context) do
    reason =
      if match.candidate?, do: :proceeds_taken_by_earlier_sale, else: :no_buy_within_30_days

    no_match(sale, match, reason)
  end

  defp block(sale, %{takes: takes, proceeds: proceeds} = match, context) do
    taken = Enum.reduce(takes, @zero, &Decimal.add(&1.amount, &2))
    [%{buy: first} | _rest] = takes
    base = base(sale, :matched, nil)
    switch = Map.merge(match, %{taken: taken, currency: base.currency_code})

    %{
      base
      | proceeds: proceeds,
        buys: Enum.map(takes, &matched_buy/1),
        days_to_first_buy: Date.diff(first.date, sale.date),
        share_of_proceeds_matched: Decimal.div(taken, proceeds),
        unallocated: Decimal.sub(proceeds, taken),
        spans: spans(sale, switch, context)
    }
  end

  defp no_match(sale, match, reason) do
    proceeds = match && match.proceeds
    %{base(sale, :no_match, reason) | proceeds: proceeds, unallocated: proceeds}
  end

  defp base(sale, status, reason) do
    %{
      status: status,
      reason: reason,
      cash_account_id: sale.cash_account_id,
      currency_code: account_currency(sale),
      proceeds: nil,
      buys: [],
      days_to_first_buy: nil,
      share_of_proceeds_matched: nil,
      unallocated: nil,
      spans: []
    }
  end

  defp account_currency(%{cash_account: %CashAccount{currency_code: currency}}), do: currency
  defp account_currency(_sale), do: nil

  defp matched_buy(%{buy: buy, amount: amount}) do
    debit = debit(buy)

    %{
      buy_id: buy.id,
      date: buy.date,
      security: buy.security,
      quantity: buy.quantity,
      cash_debit: debit,
      amount_taken: amount,
      share_of_buy: Decimal.div(amount, debit)
    }
  end

  # --- The two sides, per span (ADR-0057 §2) ---

  defp spans(sale, switch, context) do
    sale
    |> SaleHindsight.span_ends(context.today)
    |> Enum.map(fn {label, end_on} -> span(label, end_on, sale, switch, context) end)
  end

  # FR-50's latest span without a close after the sale has no end.
  defp span(label, nil, _sale, _switch, _context),
    do: incomplete(label, nil, :kept, :no_end_close)

  defp span(label, end_on, sale, switch, context) do
    if Date.compare(end_on, context.today) == :gt do
      span_base(label, end_on, :pending)
    else
      measure(label, end_on, sale, switch, context)
    end
  end

  defp measure(label, end_on, sale, switch, context) do
    with {:ok, kept} <- kept(sale, switch, end_on, context),
         {:ok, rate} <- cash_rate(switch.currency, end_on),
         {:ok, switched} <- switched(switch, end_on, rate, context),
         {:ok, income} <- income_apart(switch, end_on, context) do
      taxes = taxes_apart(switch, rate)

      %{
        span_base(label, end_on, :complete)
        | kept: kept,
          switched: switched,
          # Before tax (§3): the sale's taxes are added back to the
          # switched side, because the kept side's latent tax is not known.
          difference: switched |> Decimal.add(taxes) |> Decimal.sub(kept),
          fees_inside: fees_inside(switch, end_on, rate),
          taxes_apart: taxes,
          income_apart: income
      }
    else
      {:error, side, reason} -> incomplete(label, end_on, side, reason)
    end
  end

  # kept = a x the sold quantity x the sold security's close at the end, in
  # EUR, as one division: taken x quantity x close in EUR / proceeds. The
  # quantity is read in the closes' basis (the splits after the sale).
  defp kept(sale, switch, end_on, context) do
    case WindowReturn.price_return(sale.security, sale.date, end_on) do
      {:ok, result} ->
        {numerator, denominator} = ratio_after(context, sale.security_id, sale.date)

        {:ok,
         switch.taken
         |> Decimal.mult(sale.quantity)
         |> Decimal.mult(numerator)
         |> Decimal.mult(result.end.eur_value)
         |> Decimal.div(Decimal.mult(switch.proceeds, denominator))}

      {:error, reason} ->
        {:error, :kept, reason}
    end
  end

  # Cash in the account's currency converts at the end's rate.
  defp cash_rate(currency, end_on) do
    case WindowReturn.eur_rate(currency, end_on) do
      {:ok, rate} -> {:ok, rate}
      {:error, reason} -> {:error, :switched, reason}
    end
  end

  defp switched(switch, end_on, rate, context) do
    Enum.reduce_while(switch.takes, {:ok, @zero}, fn take, {:ok, sum} ->
      case bought_value(take, end_on, rate, context) do
        {:ok, value} -> {:cont, {:ok, Decimal.add(sum, value)}}
        {:error, reason} -> {:halt, {:error, :switched, reason}}
      end
    end)
  end

  # A buy dated after the end is still cash: the amount it took, at the
  # end's rate. A buy on or before it is the share this sale paid for x the
  # buy's quantity (in the closes' basis) x the bought security's close at
  # the end, in EUR, as one division.
  defp bought_value(%{buy: buy, amount: amount}, end_on, rate, context) do
    if Date.compare(buy.date, end_on) == :gt do
      {:ok, Decimal.mult(amount, rate)}
    else
      case WindowReturn.price_return(buy.security, end_on, end_on) do
        {:ok, result} ->
          {numerator, denominator} = ratio_after(context, buy.security_id, buy.date)

          {:ok,
           amount
           |> Decimal.mult(buy.quantity)
           |> Decimal.mult(numerator)
           |> Decimal.mult(result.end.eur_value)
           |> Decimal.div(Decimal.mult(debit(buy), denominator))}

        # A one-day window: its start is its end.
        {:error, reason} when reason in [:no_start_close, :no_end_close] ->
          {:error, :no_end_close}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # --- Costs and income (ADR-0057 §3) ---

  # a x the sale's taxes (net of its refunds, signed), as cash at the end's
  # rate: taken x taxes x rate / proceeds.
  defp taxes_apart(switch, rate) do
    switch.taken
    |> Decimal.mult(switch.taxes)
    |> Decimal.mult(rate)
    |> Decimal.div(switch.proceeds)
  end

  # a x the sale's fees + each buy's share x its fees, for the buys dated on
  # or before the end (a later buy's money is still cash), at the end's rate.
  # The fees are already inside the switched side; this names them.
  defp fees_inside(switch, end_on, rate) do
    sale_fees = switch.taken |> Decimal.mult(switch.fees) |> Decimal.div(switch.proceeds)

    switch.takes
    |> Enum.filter(&(Date.compare(&1.buy.date, end_on) != :gt))
    |> Enum.reduce(sale_fees, fn %{buy: buy, amount: amount}, sum ->
      amount
      |> Decimal.mult(buy.fees || @zero)
      |> Decimal.div(debit(buy))
      |> Decimal.add(sum)
    end)
    |> Decimal.mult(rate)
  end

  # The bought positions' booked distributions (dividends, and interest on a
  # bond) dated after each buy and on or before the end, before withholding
  # tax (the cash credited plus the tax withheld): each buy's part is the
  # share this sale paid for x the buy's quantity (in that day's basis) over
  # the quantity the portfolio held the day before. Named, never added.
  defp income_apart(switch, end_on, context) do
    switch.takes
    |> Enum.filter(&(Date.compare(&1.buy.date, end_on) != :gt))
    |> Enum.flat_map(fn take -> distributions(take, end_on, context) end)
    |> Enum.reduce_while({:ok, @zero}, fn {take, distribution, rows}, {:ok, sum} ->
      case distribution_part(take, distribution, rows, end_on) do
        {:ok, part} -> {:cont, {:ok, Decimal.add(sum, part)}}
        {:error, reason} -> {:halt, {:error, :switched, reason}}
      end
    end)
  end

  defp distributions(%{buy: buy} = take, end_on, context) do
    rows = Map.get(context.income, {buy.portfolio_id, buy.security_id}, [])

    rows
    |> Enum.filter(fn row ->
      row.type in ["dividend", "interest"] and Date.compare(row.date, buy.date) == :gt and
        Date.compare(row.date, end_on) != :gt
    end)
    |> Enum.map(&{take, &1, rows})
  end

  defp distribution_part(%{buy: buy, amount: amount}, distribution, rows, end_on) do
    held = held_before(rows, buy.security_id, distribution.date)

    with true <- Decimal.compare(held, @zero) == :gt,
         {:ok, rate} <- WindowReturn.eur_rate(account_currency(distribution), end_on) do
      {numerator, denominator} = splits_between(rows, buy.date, distribution.date)
      gross = Decimal.add(distribution.gross_amount || @zero, distribution.taxes || @zero)

      {:ok,
       amount
       |> Decimal.mult(buy.quantity)
       |> Decimal.mult(numerator)
       |> Decimal.mult(gross)
       |> Decimal.mult(rate)
       |> Decimal.div(debit(buy) |> Decimal.mult(denominator) |> Decimal.mult(held))}
    else
      false -> {:ok, @zero}
      {:error, reason} -> {:error, reason}
    end
  end

  # The quantity of the security the portfolio held across its depots after
  # every booking dated before `date` (Positions' fold).
  defp held_before(rows, security_id, date) do
    rows
    |> Enum.filter(&(Date.compare(&1.date, date) == :lt))
    |> Positions.calculate()
    |> Enum.reduce(@zero, fn
      {{_account, ^security_id}, quantity}, sum -> Decimal.add(sum, quantity)
      _other, sum -> sum
    end)
  end

  # The ratio of the portfolio's split rows after `from` and before `to`:
  # the splits the held quantity of `held_before/3` has applied since the
  # buy.
  defp splits_between(rows, from, to) do
    rows
    |> Enum.filter(fn row ->
      row.type == "split" and Date.compare(row.date, from) == :gt and
        Date.compare(row.date, to) == :lt
    end)
    |> Enum.reduce({1, 1}, fn row, {p, q} ->
      {p * row.split_ratio_numerator, q * row.split_ratio_denominator}
    end)
  end

  # The cumulative ratio of the security's splits after `date` (a split on
  # the date itself applies before that day's trades, ADR-0028 §3).
  defp ratio_after(context, security_id, date) do
    context.splits
    |> Map.get(security_id, [])
    |> QuoteAdjustment.cumulative_ratio_after(date)
  end

  defp incomplete(label, end_on, side, reason),
    do: %{span_base(label, end_on, :incomplete) | side: side, reason: reason}

  defp span_base(label, end_on, status) do
    %{
      span: label,
      end_on: end_on,
      status: status,
      side: nil,
      reason: nil,
      kept: nil,
      switched: nil,
      difference: nil,
      fees_inside: nil,
      taxes_apart: nil,
      income_apart: nil
    }
  end
end
