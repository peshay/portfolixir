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

  `match/1` is the rule as a pure function over ledger rows; `blocks/2`
  loads the rows once and answers each sale's block.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.CashAccount
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
  def blocks(sales, %Date{} = _today) when is_list(sales) do
    ledger = sales |> cash_account_ids() |> load_ledger()
    matching = match(ledger)
    loaded = Map.new(ledger, &{&1.id, &1})

    Map.new(sales, fn sale ->
      # The row as loaded with its security and cash account, where the
      # ledger read holds it.
      sale = Map.get(loaded, sale.id, sale)
      {sale.id, block(sale, Map.get(matching, sale.id))}
    end)
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
  match is `%{proceeds, taxes, fees, refunds, takes, candidate?}`: the
  proceeds (or nil when not positive), the sale's taxes net of its refunds
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

  defp positive?(amount), do: Decimal.compare(amount, @zero) == :gt

  defp step({:sale, entry}, {queue, takes}), do: {queue ++ [entry], takes}

  defp step({:buy, buy}, {queue, takes}) do
    debit = Decimal.negate(cash(buy))

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
  defp block(sale, nil), do: no_match(sale, nil, :no_cash_account)
  defp block(sale, %{proceeds: nil} = match), do: no_match(sale, match, :no_cash_account)

  defp block(sale, %{takes: []} = match) do
    reason =
      if match.candidate?, do: :proceeds_taken_by_earlier_sale, else: :no_buy_within_30_days

    no_match(sale, match, reason)
  end

  defp block(sale, %{takes: takes, proceeds: proceeds}) do
    taken = Enum.reduce(takes, @zero, &Decimal.add(&1.amount, &2))
    [%{buy: first} | _rest] = takes

    %{
      base(sale, :matched, nil)
      | proceeds: proceeds,
        buys: Enum.map(takes, &matched_buy/1),
        days_to_first_buy: Date.diff(first.date, sale.date),
        share_of_proceeds_matched: Decimal.div(taken, proceeds),
        unallocated: Decimal.sub(proceeds, taken)
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
    debit = Decimal.negate(cash(buy))

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
end
