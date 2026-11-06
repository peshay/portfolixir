defmodule Portfolixir.Portfolios.Performance.SaleReinvestment do
  @moduledoc """
  What a switch cost (I18 mode 3; ADR-0057): a sale compared with the
  purchases its money went into, found by rule. Ladder (c): it compares what
  was done with what was held before and replays no rule against past
  prices. Nothing is stored; every read derives the matches from the ledger
  and the figures from the closes and rates the catalogue holds at that
  moment, so the same ledger always gives the same answer.

  ## The matching rule (ADR-0057 §1, as amended on 2026-11-06)

  No booking id decides anything: a booking deleted and booked again
  unchanged gives the same answer.

    1. **Proceeds** are the sale's booked cash amount on its cash account
       (`Portfolixir.Ledger.Projection.cash_amount/1`: its settlement, after
       its fees and taxes), in that account's currency. A tax refund split
       off the sale (a `tax_refund` booking of the sold security on the
       sale's date and cash account, the shape the import gives it, booked
       before or after the sale) is a negative tax of the sale: its cash
       joins the proceeds and its amount lowers the sale's taxes. Several
       sales of that security on that date and account share it in
       proportion to their booked cash amounts (equally when none is
       positive).
    2. **Candidates** are `buy` bookings debiting the same cash account,
       dated on or after the sale's date and at most #{30} calendar days after
       it, of any security other than the one sold.
    3. **Order:** proceeds wait in date groups, one per sale date; buys take
       as date groups, in date order, from the oldest proceeds group first,
       each buy at most its own cash debit (`cash_amount/1` negated: price,
       quantity, fees and taxes). On one date the day's sales enter the
       queue before its buys take from it. Within one pairing of a proceeds
       group and a buy group the amount `t = min(the group's remaining
       proceeds, the buy group's remaining debit)` is split **pro rata**:
       each sale gives in proportion to its remaining proceeds, each buy
       takes in proportion to its remaining debit. Where a buy may not take
       from a sale of its own security, the pairing runs in rounds (see
       `pair/3`) until no allowed pair has money on both sides.
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
      end's rate (`WindowReturn.hub_rate/2` on the end date), and for one on
      or before it, the share of the buy this sale paid for × the buy's
      quantity × the bought security's close at the end, in EUR;
    * **difference** = switched − kept.

  Every close is `WindowReturn.price_return/3`'s: the split-adjusted close
  standing for the date (at most 7 days older), converted at the stored
  EUR-hub rate of its own date. A booked quantity is read in that basis:
  multiplied by the ratio of the security's splits after its booking date
  (`QuoteAdjustment.cumulative_ratio_after/2`), so a split is not a move.

  **Precision** (the Sprint 26 closing act's M3): every figure is carried as
  an exact fraction (`SaleReinvestment.Fraction`) of the stored closes,
  rates, quantities and amounts, each converted to EUR by dividing by its
  hub rate once (never multiplied by the rounded `1 / hub`, as
  `WindowReturn`'s return does since Sprint 25), and rounded once when it
  is shown, at 34 significant digits half-up. The difference is the exact
  `switched + taxes_apart − kept`, rounded once, so a switch that came out
  even reads exactly 0 at any rate. A span
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
  alias Portfolixir.Portfolios.Performance.SaleReinvestment.Fraction
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
  The computation basis of the blocks (AGENTS.md: every metric of ladder
  levels (a)-(c) states it in its payload; ADR-0057 §4): the rule, the 30
  days, the order, the spans, the prices, before tax, price only, and what
  the rule cannot see.
  """
  @spec computation_basis() :: %{atom() => String.t()}
  def computation_basis do
    staleness = WindowReturn.staleness_days()

    %{
      rule:
        "found by rule, never chosen (ADR-0057 §1): a sale's proceeds, its booked cash " <>
          "amount on its cash account (its settlement after its fees and taxes; a tax_refund " <>
          "of the sold security booked on the sale's date and cash account, before or after " <>
          "it, is a negative tax of the sale and joins them, shared by that day's sales of " <>
          "the security on the account in proportion to their cash amounts), go into the " <>
          "buy bookings that debit the same cash account, of any security other than the " <>
          "one sold. No booking id decides: a booking deleted and booked again unchanged " <>
          "gives the same answer",
      window:
        "a buy is a candidate from the sale's date to #{@window_days} calendar days after " <>
          "it, both included; a sale less than #{@window_days} days old can still be " <>
          "matched by a buy booked later",
      order:
        "proceeds wait in date groups, one per sale date; the buys of each date, as one " <>
          "group in date order, take from the oldest proceeds group first, each buy at most " <>
          "its own cash debit (price x quantity plus its fees and taxes); on one date the " <>
          "day's sales enter the queue before its buys take. Within a pairing of a proceeds " <>
          "group and a buy group, t = min(the group's remaining proceeds, the buy group's " <>
          "remaining debit) is split pro rata: each sale gives in proportion to its " <>
          "remaining proceeds, each buy takes in proportion to its remaining debit; where " <>
          "a buy may not take from a sale of its own security, the pairing repeats on what " <>
          "is left, each buy splitting its take over the sales it may take from by their " <>
          "remaining proceeds, until no allowed pair has money on both sides. Amounts are " <>
          "exact until shown. A buy funded in part counts with its " <>
          "share_of_buy. What no buy took is unallocated and stays out of the comparison: " <>
          "money that waited is not money that switched. share_of_proceeds_matched (a) is " <>
          "the sum taken over the proceeds",
      spans:
        "FR-50's spans and ends (1m, 3m, 12m, latest), pending while the end is after " <>
          "today. kept = a x the sold quantity x the sold security's close at the end; " <>
          "switched = for each matched buy dated after the end, the amount it took as cash " <>
          "(it earns nothing while it waits), otherwise its share_of_buy x its quantity x " <>
          "the bought security's close at the end; difference = switched + taxes_apart - " <>
          "kept. A span that cannot be measured is incomplete with side (kept " <>
          "or switched) and reason (no_start_close, no_end_close, no_fx_rate)",
      prices:
        "both sides in EUR with the sale hindsight's rules: the close standing for a date " <>
          "is the last positive stored close on or before it, at most #{staleness} calendar " <>
          "days older, split-adjusted, converted at the stored EUR-hub rate of its own date; " <>
          "a booked quantity is read in the same basis (times the ratio of the splits after " <>
          "its date); cash, fees, taxes and income convert at the rate of the span's end. " <>
          "Each figure is one quotient of exact products, dividing by each hub rate (units " <>
          "per 1 EUR) once, rounded once to 34 significant digits; the difference is the " <>
          "exact switched + taxes_apart - kept rounded once, so an even switch reads 0",
      before_tax:
        "both sides are compared before tax: the sale's fees and each buy's fees are paid " <>
          "out of the money that switched, so they are inside the difference, and " <>
          "fees_inside names them (a x the sale's fees plus each buy's share of its fees, " <>
          "for the buys dated on or before the end); the sale's booked taxes are named apart " <>
          "as taxes_apart (a x them, signed: a refund is negative) and added back to the " <>
          "switched side, because the kept position's latent tax is not booked and is not " <>
          "derived",
      price_only:
        "price only on both sides: the kept side's distributions after the sale are not " <>
          "booked, so income_apart names the bought positions' booked distributions after " <>
          "each buy and up to the end (before withholding tax, each buy's part by its share " <>
          "of the quantity held the day before) and is never added; this understates " <>
          "whichever side paid more",
      fungible_money:
        "money is fungible: a deposit or a dividend that arrived in between could have paid " <>
          "for the buy instead; the rule assumes the sale's proceeds are spent first",
      dates:
        "bookings carry a date, not a time: a buy on the sale's own date counts, though it " <>
          "may have been paid otherwise",
      transfers:
        "money moved to another account by a cash_transfer is not followed: a switch made " <>
          "through another account reads no_match",
      no_match:
        "no_match names its reason: no_buy_within_30_days (no candidate buy), " <>
          "proceeds_taken_by_earlier_sale (the candidates were paid by earlier proceeds), " <>
          "no_cash_account (no cash account or no positive settlement on it)",
      currency:
        "proceeds, cash_debit, amount_taken and unallocated are in currency_code, the " <>
          "sale's cash account's currency; every span figure is in EUR",
      no_total:
        "no field gives a verdict and no total over all switches is reported; nothing is " <>
          "stored, every read derives the matches from the ledger"
    }
  end

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
  The matching rule (ADR-0057 §1, as amended on 2026-11-06) over ledger
  rows: `buy`, `sell` and `tax_refund` bookings, each with its
  `cash_account_id`. Pure, and free of booking ids: the same rows give the
  same answer, and so do the same rows deleted and booked again.

  Answers `%{sale_id => match}` for every sell with a cash account, where a
  match is `%{security_id, proceeds, taxes, fees, takes, candidate?}`: the
  sold security, the proceeds (an exact `Fraction`, or nil when not
  positive), the sale's taxes net of its share of the refunds (signed), its
  fees, the takes (`%{buy, amount}`, the amount an exact `Fraction`, by buy
  date) and whether any candidate buy existed.
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
    sales = Enum.filter(rows, &(&1.type == "sell"))
    buys = Enum.filter(rows, &(&1.type == "buy"))
    refunds = refund_shares(Enum.filter(rows, &(&1.type == "tax_refund")), sales)
    entries = Enum.map(sales, &entry(&1, Map.get(refunds, &1.id, Fraction.zero())))
    takes = allocate(entries, buys)

    Enum.map(entries, fn entry ->
      {entry.sale.id,
       %{
         security_id: entry.sale.security_id,
         proceeds: entry.proceeds,
         taxes: entry.taxes,
         fees: Fraction.new(entry.sale.fees || @zero),
         takes: takes_of(takes, entry.sale.id),
         candidate?: Enum.any?(buys, &candidate?(entry.sale, &1))
       }}
    end)
  end

  # A refund split off a sale (a tax_refund of the sold security on the
  # sale's date and cash account) belongs to that sale, whatever the order
  # the two were booked in. Several sales of the security on that date and
  # account share it in proportion to their booked cash amounts (equally
  # when none is positive): no booking id decides.
  defp refund_shares(refunds, sales) do
    Enum.reduce(refunds, %{}, fn refund, shares ->
      siblings =
        Enum.filter(sales, &(&1.security_id == refund.security_id and &1.date == refund.date))

      weights = refund_weights(siblings)
      total = weights |> Enum.map(&elem(&1, 1)) |> Fraction.sum()
      amount = Fraction.new(cash(refund))

      Enum.reduce(weights, shares, fn {sale, weight}, acc ->
        share = amount |> Fraction.mult(weight) |> Fraction.divide(total)
        Map.update(acc, sale.id, share, &Fraction.add(&1, share))
      end)
    end)
  end

  defp refund_weights(siblings) do
    weights = Enum.map(siblings, &{&1, &1 |> cash() |> Decimal.max(@zero) |> Fraction.new()})

    if Enum.any?(weights, fn {_sale, weight} -> Fraction.positive?(weight) end),
      do: weights,
      else: Enum.map(siblings, &{&1, Fraction.new(1)})
  end

  defp entry(sale, refunded) do
    proceeds = sale |> cash() |> Fraction.new() |> Fraction.add(refunded)

    %{
      sale: sale,
      taxes: sale.taxes |> Kernel.||(@zero) |> Fraction.new() |> Fraction.sub(refunded),
      proceeds: if(Fraction.positive?(proceeds), do: proceeds, else: nil)
    }
  end

  defp cash(row), do: Projection.cash_amount(row) || @zero

  # A buy's cash debit: its booked cash amount on its account, negated.
  defp debit(buy), do: Decimal.negate(cash(buy))

  defp debit_fraction(buy), do: Fraction.new(debit(buy))

  # The allocation (§1.3 as amended): proceeds wait in date groups, one per
  # sale date; on each date the day's group joins the queue, then the day's
  # buys, as one group, take from the oldest group first. A group pairing
  # splits pro rata (`pair/3`). Answers `%{{sale_id, buy_id} => amount}`.
  defp allocate(entries, buys) do
    sales_by_date =
      entries
      |> Enum.filter(& &1.proceeds)
      |> Enum.group_by(& &1.sale.date)

    buys_by_date =
      buys
      |> Enum.filter(&Fraction.positive?(debit_fraction(&1)))
      |> Enum.group_by(& &1.date)

    state = %{
      queue: [],
      remaining: Map.new(entries, &{&1.sale.id, &1.proceeds || Fraction.zero()}),
      need: Map.new(buys, &{&1.id, debit_fraction(&1)}),
      takes: %{}
    }

    (Map.keys(sales_by_date) ++ Map.keys(buys_by_date))
    |> Enum.uniq()
    |> Enum.sort(Date)
    |> Enum.reduce(state, fn date, state ->
      state = %{state | queue: state.queue ++ group(sales_by_date, date)}
      take_day(state, date, Map.get(buys_by_date, date, []))
    end)
    |> Map.fetch!(:takes)
  end

  defp group(sales_by_date, date) do
    case Map.get(sales_by_date, date) do
      nil -> []
      entries -> [{date, Enum.map(entries, & &1.sale)}]
    end
  end

  # The day's buys walk the queue oldest group first, each group within
  # the window of the day.
  defp take_day(state, _date, []), do: state

  defp take_day(state, date, buys) do
    Enum.reduce(state.queue, state, fn {sale_date, sales}, state ->
      if Date.diff(date, sale_date) <= @window_days,
        do: pair(state, sales, buys),
        else: state
    end)
  end

  # One pairing of a proceeds group with a buy group, in rounds. In a round
  # each buy j still owed money takes f x need_j, split over the sales i it
  # may take from (another security, money left) in proportion to their
  # remaining proceeds r_i: x_ij = f x need_j x r_i / E_j, E_j = the sum of
  # those r_i. f is the largest factor, at most 1, that no sale gives more
  # than it has. Without a buy of a sold security, one round is the plain pro
  # rata split: t = min(R, D), x_ij = t x r_i / R x need_j / D. Each round
  # either pays every buy it can (f = 1) or uses up a sale, so the rounds
  # end; the amounts are exact fractions, so no booking order rounds them.
  defp pair(state, sales, buys) do
    live = Enum.filter(sales, &Fraction.positive?(Map.fetch!(state.remaining, &1.id)))

    active =
      for buy <- buys,
          Fraction.positive?(Map.fetch!(state.need, buy.id)),
          eligible = Enum.filter(live, &(&1.security_id != buy.security_id)),
          eligible != [],
          do:
            {buy, eligible,
             eligible |> Enum.map(&Map.fetch!(state.remaining, &1.id)) |> Fraction.sum()}

    case active do
      [] -> state
      active -> round(state, sales, buys, active)
    end
  end

  defp round(state, sales, buys, active) do
    # The round reads the amounts as they stood when it began.
    %{need: need, remaining: remaining} = state

    loads =
      Enum.reduce(active, %{}, fn {buy, eligible, supply}, loads ->
        load = Fraction.divide(Map.fetch!(need, buy.id), supply)

        Enum.reduce(eligible, loads, fn sale, loads ->
          Map.update(loads, sale.id, load, &Fraction.add(&1, load))
        end)
      end)

    one = Fraction.new(1)

    factor =
      loads
      |> Map.values()
      |> Enum.map(&Fraction.divide(one, &1))
      |> Enum.reduce(one, &Fraction.min/2)

    state =
      for {buy, eligible, supply} <- active, sale <- eligible, reduce: state do
        state ->
          amount =
            factor
            |> Fraction.mult(Map.fetch!(need, buy.id))
            |> Fraction.mult(Map.fetch!(remaining, sale.id))
            |> Fraction.divide(supply)

          give(state, sale.id, buy, amount)
      end

    if Fraction.compare(factor, one) == :eq, do: state, else: pair(state, sales, buys)
  end

  defp give(state, sale_id, buy, amount) do
    %{
      state
      | remaining: Map.update!(state.remaining, sale_id, &Fraction.sub(&1, amount)),
        need: Map.update!(state.need, buy.id, &Fraction.sub(&1, amount)),
        takes:
          Map.update(state.takes, sale_id, %{buy.id => {buy, amount}}, fn by_buy ->
            Map.update(by_buy, buy.id, {buy, amount}, fn {buy, sum} ->
              {buy, Fraction.add(sum, amount)}
            end)
          end)
    }
  end

  # A sale's takes, by buy date (the booking id only orders the display of
  # two buys of one date; it decides no amount).
  defp takes_of(takes, sale_id) do
    takes
    |> Map.get(sale_id, %{})
    |> Map.values()
    |> Enum.sort_by(fn {buy, _amount} -> {Date.to_gregorian_days(buy.date), buy.id} end)
    |> Enum.map(fn {buy, amount} -> %{buy: buy, amount: amount} end)
  end

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
    taken = takes |> Enum.map(& &1.amount) |> Fraction.sum()
    [%{buy: first} | _rest] = takes
    base = base(sale, :matched, nil)

    # The sides take the exact fractions (see measure/5).
    switch = %{
      currency: base.currency_code,
      taken: taken,
      proceeds: proceeds,
      taxes: match.taxes,
      fees: match.fees,
      takes: takes
    }

    %{
      base
      | proceeds: Fraction.to_decimal(proceeds),
        buys: Enum.map(takes, &matched_buy/1),
        days_to_first_buy: Date.diff(first.date, sale.date),
        share_of_proceeds_matched: taken |> Fraction.divide(proceeds) |> Fraction.to_decimal(),
        unallocated: proceeds |> Fraction.sub(taken) |> Fraction.to_decimal(),
        spans: spans(sale, switch, context)
    }
  end

  defp no_match(sale, match, reason) do
    proceeds = match && match.proceeds && Fraction.to_decimal(match.proceeds)
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
      amount_taken: Fraction.to_decimal(amount),
      share_of_buy: amount |> Fraction.divide(Fraction.new(debit)) |> Fraction.to_decimal()
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

  # Every figure is an exact fraction until it is shown: each one is a
  # quotient of exact products (stored closes, rates, quantities and
  # amounts), rounded once by `Fraction.to_decimal/1`, so two sides that are
  # equal in exact arithmetic read equal to the last digit and an even
  # switch reads a difference of exactly 0. A close converts to EUR by
  # dividing by its date's stored hub rate once, as `WindowReturn`'s return
  # does, never through the rounded `1 / hub`.
  defp measure(label, end_on, sale, switch, context) do
    with {:ok, kept} <- kept(sale, switch, end_on, context),
         {:ok, hub} <- cash_hub(switch.currency, end_on),
         {:ok, switched} <- switched(switch, end_on, hub, context),
         {:ok, income} <- income_apart(switch, end_on, context) do
      taxes = taxes_apart(switch, hub)

      %{
        span_base(label, end_on, :complete)
        | kept: Fraction.to_decimal(kept),
          switched: Fraction.to_decimal(switched),
          # Before tax (§3): the sale's taxes are added back to the
          # switched side, because the kept side's latent tax is not known.
          difference:
            switched |> Fraction.add(taxes) |> Fraction.sub(kept) |> Fraction.to_decimal(),
          fees_inside: switch |> fees_inside(end_on, hub) |> Fraction.to_decimal(),
          taxes_apart: Fraction.to_decimal(taxes),
          income_apart: Fraction.to_decimal(income)
      }
    else
      {:error, side, reason} -> incomplete(label, end_on, side, reason)
    end
  end

  # kept = a x the sold quantity x the sold security's close at the end, in
  # EUR: taken x quantity x close / (proceeds x the close date's hub rate).
  # The quantity is read in the closes' basis (the splits after the sale).
  defp kept(sale, switch, end_on, context) do
    with {:ok, result} <- WindowReturn.price_return(sale.security, sale.date, end_on),
         {:ok, hub} <- hub(sale.security.currency_code, result.end.date) do
      {:ok,
       switch.taken
       |> Fraction.mult(Fraction.new(sale.quantity))
       |> Fraction.mult(ratio_after(context, sale.security_id, sale.date))
       |> Fraction.mult(Fraction.new(result.end.close))
       |> Fraction.divide(Fraction.mult(switch.proceeds, hub))}
    else
      {:error, reason} -> {:error, :kept, reason}
    end
  end

  # Cash in the account's currency converts at the end's hub rate.
  defp cash_hub(currency, end_on) do
    case hub(currency, end_on) do
      {:ok, hub} -> {:ok, hub}
      {:error, reason} -> {:error, :switched, reason}
    end
  end

  # Units of `currency` per 1 EUR on `on` (`WindowReturn.hub_rate/2`: the
  # most recent stored rate on or before it, EUR exactly 1), as an exact
  # fraction.
  defp hub(currency, on) do
    with {:ok, hub} <- WindowReturn.hub_rate(currency, on), do: {:ok, Fraction.new(hub)}
  end

  defp switched(switch, end_on, hub, context) do
    Enum.reduce_while(switch.takes, {:ok, Fraction.zero()}, fn take, {:ok, sum} ->
      case bought_value(take, end_on, hub, context) do
        {:ok, value} -> {:cont, {:ok, Fraction.add(sum, value)}}
        {:error, reason} -> {:halt, {:error, :switched, reason}}
      end
    end)
  end

  # A buy dated after the end is still cash: the amount it took over the
  # end's hub rate. A buy on or before it is the share this sale paid for x
  # the buy's quantity (in the closes' basis) x the bought security's close
  # at the end, over the close date's hub rate.
  defp bought_value(%{buy: buy, amount: amount}, end_on, hub, context) do
    if Date.compare(buy.date, end_on) == :gt do
      {:ok, Fraction.divide(amount, hub)}
    else
      with {:ok, result} <- end_close(buy.security, end_on),
           {:ok, close_hub} <- hub(buy.security.currency_code, result.end.date) do
        {:ok,
         amount
         |> Fraction.mult(Fraction.new(buy.quantity))
         |> Fraction.mult(ratio_after(context, buy.security_id, buy.date))
         |> Fraction.mult(Fraction.new(result.end.close))
         |> Fraction.divide(Fraction.mult(debit_fraction(buy), close_hub))}
      end
    end
  end

  # The close standing for the end, through the one window-return function:
  # a one-day window, whose start is its end.
  defp end_close(security, end_on) do
    case WindowReturn.price_return(security, end_on, end_on) do
      {:ok, result} -> {:ok, result}
      {:error, reason} when reason in [:no_start_close, :no_end_close] -> {:error, :no_end_close}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Costs and income (ADR-0057 §3) ---

  # a x the sale's taxes (net of its refunds, signed), as cash at the end's
  # hub rate: taken x taxes / (proceeds x hub).
  defp taxes_apart(switch, hub) do
    switch.taken
    |> Fraction.mult(switch.taxes)
    |> Fraction.divide(Fraction.mult(switch.proceeds, hub))
  end

  # a x the sale's fees + each buy's share x its fees, for the buys dated on
  # or before the end (a later buy's money is still cash), over the end's
  # hub rate. The fees are already inside the switched side; this names them.
  defp fees_inside(switch, end_on, hub) do
    sale_fees = switch.taken |> Fraction.mult(switch.fees) |> Fraction.divide(switch.proceeds)

    switch.takes
    |> Enum.filter(&(Date.compare(&1.buy.date, end_on) != :gt))
    |> Enum.reduce(sale_fees, fn %{buy: buy, amount: amount}, sum ->
      amount
      |> Fraction.mult(Fraction.new(buy.fees || @zero))
      |> Fraction.divide(debit_fraction(buy))
      |> Fraction.add(sum)
    end)
    |> Fraction.divide(hub)
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
    |> Enum.reduce_while({:ok, Fraction.zero()}, fn {take, distribution, rows}, {:ok, sum} ->
      case distribution_part(take, distribution, rows, end_on) do
        {:ok, part} -> {:cont, {:ok, Fraction.add(sum, part)}}
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
         {:ok, hub} <- hub(account_currency(distribution), end_on) do
      gross = Decimal.add(distribution.gross_amount || @zero, distribution.taxes || @zero)

      {:ok,
       amount
       |> Fraction.mult(Fraction.new(buy.quantity))
       |> Fraction.mult(splits_between(rows, buy.date, distribution.date))
       |> Fraction.mult(Fraction.new(gross))
       |> Fraction.divide(
         debit_fraction(buy)
         |> Fraction.mult(Fraction.new(held))
         |> Fraction.mult(hub)
       )}
    else
      false -> {:ok, Fraction.zero()}
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
  # buy, as an exact fraction.
  defp splits_between(rows, from, to) do
    rows
    |> Enum.filter(fn row ->
      row.type == "split" and Date.compare(row.date, from) == :gt and
        Date.compare(row.date, to) == :lt
    end)
    |> Enum.reduce({1, 1}, fn row, {p, q} ->
      {p * row.split_ratio_numerator, q * row.split_ratio_denominator}
    end)
    |> ratio()
  end

  # The cumulative ratio of the security's splits after `date` (a split on
  # the date itself applies before that day's trades, ADR-0028 §3), as an
  # exact fraction.
  defp ratio_after(context, security_id, date) do
    context.splits
    |> Map.get(security_id, [])
    |> QuoteAdjustment.cumulative_ratio_after(date)
    |> ratio()
  end

  defp ratio({p, q}), do: Fraction.divide(Fraction.new(p), Fraction.new(q))

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
