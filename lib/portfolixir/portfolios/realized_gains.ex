defmodule Portfolixir.Portfolios.RealizedGains do
  @moduledoc """
  Read-time realized-gains report across **all** securities (issue #724): the
  FIFO-matched closed round-trips the ledger already derives per security
  (`Ledger.list_trades_for_security/2`), collected into one cash-flow-shaped
  aggregate — realized P&L per period, by each trade's **close date**.

  ## FX basis (D-1, signed 2026-08-20)

  Each sale converts into the base currency through the **EUR hub**
  (`Portfolixir.Fx`) at the rate stored on **its own close date**, because the
  realized figure is a historical fact tied to its date. A sale whose close-date rate is not
  stored is **excluded from the converted totals and named** (count plus
  security names) — never converted at a neighbouring date's rate, never
  silently dropped. This is deliberately stricter than Income's
  parity-with-counter behaviour: a realized figure is a headline number, and
  a guessed rate would be a guessed gain.

  The basis travels in the payload (`computation_basis`, `conversion_note`)
  per the AGENTS.md metric rule.

  ## The trades, and the three figures over them (#807)

  Since Sprint 13 the report also carries the closed round-trips themselves —
  the list the facet's name promises — and three figures derived from exactly
  the same converted set: the **realised total**, the **hit rate** (the share
  of closed trades that realised a gain) and the **average holding period**.

  Derived, not stored, and derived from the SAME set as the matrix: a sale
  whose close-date rate is not stored is excluded from the figures, the list
  and the matrix alike, and stays named in `excluded`. With no closed trades
  the hit rate and the average holding period are `nil` rather than `0` —
  the average of nothing is not zero, and a rate over an empty set is not
  0 %.

  ## The annualized return per trade (#984)

  Each trade carries `annualized_return` and `annualized_return_reason`
  from `Ledger.TradeReturn`, the figure the security's own trades read
  serves: the trade's money-weighted return per year in its own currency,
  `nil` under 365 days of holding or when no rate solves the trade's flows.
  `computation_basis.annualized_return` states the rule.

  ## The sells no buy was matched to (#984, T1b)

  The matcher's orphan sells were dropped here without a word: shares that
  arrived by an inbound delivery open no lot, so their sale is no trade and
  was missing from every figure. They are named now in `unmatched_sells`
  (count, and per sell the security, date and unmatched quantity), the
  UX-DR25 shape of `excluded`, and stay out of every figure.

  ## The newest trades alone (#1030)

  `newest_trades/2` serves the Overview card: the report's newest rows,
  its exclusions and its base currency, computed without the rest — one
  read of every sold security's transactions instead of the trades read
  per security, and the annualized return only for the rows returned.
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.TradeReturn
  alias Portfolixir.Portfolios

  @zero Decimal.new("0")
  @months 1..12

  @doc """
  Builds the realized-gains report across all securities and portfolios.

  Options:

    * `:base_currency` — overrides the default (the first portfolio's base
      currency, `"EUR"` when none exists).
    * `:limit` — keeps the newest `limit` years of the annual matrix (#776);
      `computation_basis.window` names the cut when years were dropped.
  """
  def report(opts \\ []) do
    base = Keyword.get_lazy(opts, :base_currency, &default_base/0)
    limit = Keyword.get(opts, :limit)

    matched = Enum.map(traded_securities(), &security_trades/1)

    {converted, excluded} =
      matched
      |> Enum.flat_map(fn {closed, _unmatched} -> closed end)
      |> Enum.map(&convert_trade(&1, base))
      |> Enum.split_with(&match?({:ok, _}, &1))

    unmatched =
      matched
      |> Enum.flat_map(fn {_closed, unmatched} -> unmatched end)
      |> Enum.sort_by(& &1.date, {:desc, Date})

    converted = Enum.map(converted, fn {:ok, trade} -> trade end)
    excluded = Enum.map(excluded, fn {:excluded, trade} -> trade end)

    full = annual_matrix(converted)
    annual = newest_years(full, limit)
    trades = Enum.sort_by(converted, & &1.close_date, {:desc, Date})

    %{
      base_currency: base,
      annual: annual,
      trades: trades,
      summary: summary(trades),
      limit: limit,
      excluded: excluded_summary(excluded),
      # #984 (T1b, UX-DR25): the matcher's orphan sells, named rather than
      # dropped — a sell with no lot is no trade, so it is in no figure.
      unmatched_sells: %{count: length(unmatched), sells: unmatched},
      conversion_note:
        "Each sale converted to #{base} via the EUR hub at the rate stored on " <>
          "its own close date; a sale with no stored rate for that day is " <>
          "excluded from the totals and named, never converted at a " <>
          "neighbouring date's rate.",
      computation_basis: %{
        series:
          "realized_pnl_abs per FIFO-matched closed trade (proceeds net of sell fees and taxes, minus consumed basis)",
        window: window(full, annual, "grouped by each trade's close date"),
        reference: "EUR hub rates at or before each close date (D-1, issue #724)",
        gaps:
          "a sale with no stored close-date rate is excluded from the converted totals and named in excluded",
        summary:
          "The three figures are derived from the SAME converted trades as the matrix and the " <>
            "list, never from a wider set: realized_total is their sum in #{base}; hit_rate is " <>
            "the share of them whose realised result is strictly positive (a break-even trade " <>
            "counts as a miss), at scale 4; average_holding_period_days is the unweighted mean " <>
            "of holding_period_days, rounded to a whole day. A sale excluded for a missing " <>
            "close-date rate is in none of the three. With no closed trades the hit rate and " <>
            "the average holding period are null rather than zero — the average of nothing is " <>
            "not zero. The matrix is unaffected by limit= here: the figures always read the " <>
            "full history, while limit= cuts only the years the matrix shows.",
        annualized_return: TradeReturn.basis(),
        # The ADR-0015 amendment of 2026-10-07 (#1108): every trade's basis,
        # proceeds and realized_pnl_abs are in its currency_code, fees and
        # taxes included, before the close-date conversion.
        fees_and_taxes: Ledger.trade_fees_basis(),
        unmatched_sells:
          "A sell the FIFO matcher could not pair with a buy is no closed trade, so it is in " <>
            "none of the figures, the list or the matrix: the matcher keeps one queue per " <>
            "security across every depot, opened by buys only, and an inbound delivery opens " <>
            "no lot, so the sale of delivered-in shares has none; a sell larger than the " <>
            "shares bought closes what it can and leaves the rest. unmatched_sells names each, " <>
            "newest first, with the quantity no lot covered."
      }
    }
  end

  @doc """
  The newest `limit` closed trades of `report/1`, with its `excluded` and
  its `base_currency`: what the Overview card shows (#1030), computed
  without the rest of the report.

  The rows, their order (equal close dates included), their figures and the
  exclusions are the report's own — the same matcher input, the same
  conversion at each close date, the same stable sort — but the
  transactions are read once for every sold security, no open lot is
  decorated, no latest close is looked up, only the `limit` trades returned
  are annualized, and neither the matrix nor the three figures are built.
  Every closed trade is still converted, because a sale the rates cannot
  convert is named in `excluded` whether or not it would be among the
  newest.

  Options: `:base_currency`, as for `report/1`.
  """
  def newest_trades(limit, opts \\ []) when is_integer(limit) and limit > 0 do
    base = Keyword.get_lazy(opts, :base_currency, &default_base/0)

    {converted, excluded} =
      Ledger.closed_trades_of_sold_securities()
      |> Enum.flat_map(fn {security, closed} ->
        Enum.map(closed, &{trade_row(security, &1), &1})
      end)
      |> Enum.map(fn {row, trade} -> {convert_trade(row, base), trade} end)
      |> Enum.split_with(&match?({{:ok, _row}, _trade}, &1))

    trades =
      converted
      |> Enum.map(fn {{:ok, row}, trade} -> {row, trade} end)
      |> Enum.sort_by(fn {row, _trade} -> row.close_date end, {:desc, Date})
      |> Enum.take(limit)
      |> Enum.map(fn {row, trade} -> Map.merge(row, TradeReturn.annualized(trade)) end)

    %{
      base_currency: base,
      trades: trades,
      excluded: excluded_summary(Enum.map(excluded, fn {{:excluded, row}, _trade} -> row end))
    }
  end

  defp excluded_summary(excluded) do
    %{
      count: length(excluded),
      securities: excluded |> Enum.map(& &1.security_name) |> Enum.uniq() |> Enum.sort()
    }
  end

  # #776: a limit keeps the newest years of the matrix (sorted newest first);
  # the window names the cut when one happened, so a shorter answer never
  # reads as a shorter history.
  defp newest_years(annual, nil), do: annual
  defp newest_years(annual, n) when is_integer(n) and n > 0, do: Enum.take(annual, n)

  defp window(full, kept, grouping) when length(kept) < length(full),
    do: "the newest #{length(kept)} years of the full ledger history, #{grouping}"

  defp window(_full, _kept, grouping), do: "full ledger history, #{grouping}"

  defp default_base do
    case Portfolios.first_portfolio() do
      %{base_currency_code: base} when is_binary(base) -> base
      _none -> "EUR"
    end
  end

  # The securities that can carry closed trades: every security with a sell
  # booked. Read once from the ledger; the local dataset is bounded.
  defp traded_securities do
    sold_ids =
      Ledger.list_transactions()
      |> Enum.filter(&(&1.type == "sell"))
      |> Enum.map(& &1.security_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    for id <- sold_ids, security = Catalog.get_security(id), not is_nil(security) do
      security
    end
  end

  # One matcher read per security serves both halves: its closed trades and
  # its orphan sells (#984, T1b).
  defp security_trades(security) do
    trades = Ledger.list_trades_for_security(security.id)

    {closed_trades(security, Map.get(trades, :closed_trades, [])),
     unmatched_sells(security, Map.get(trades, :orphan_sells, []))}
  end

  defp unmatched_sells(security, orphans) do
    Enum.map(orphans, fn orphan ->
      %{
        security_id: security.id,
        security_name: security.name,
        date: orphan.date,
        quantity: orphan.quantity
      }
    end)
  end

  defp closed_trades(security, closed) do
    Enum.map(closed, fn trade ->
      security
      |> trade_row(trade)
      |> Map.merge(%{
        # #984: the per-trade figure the security's own read serves, so the
        # two never disagree; it annualizes realized_pnl_pct in the trade's
        # currency, not realized_base.
        annualized_return: trade.annualized_return,
        annualized_return_reason: trade.annualized_return_reason
      })
    end)
  end

  # #807: the row the facet lists, beside the figure the matrix sums.
  # `security_id` rides along so each row can link to that security's
  # Trades tab, where the same round-trip is a row of its closed trades.
  # The annualized return is merged by the caller: `report/1` takes the one
  # the trades read attached, `newest_trades/2` computes it for the rows it
  # returns only (#1030).
  defp trade_row(security, trade) do
    %{
      security_id: security.id,
      security_name: security.name,
      open_date: trade.open_date,
      close_date: trade.close_date,
      quantity: trade.quantity,
      basis: trade.basis,
      proceeds: trade.proceeds,
      holding_period_days: trade.holding_period_days,
      realized_pnl_pct: trade.realized_pnl_pct,
      currency_code: trade.currency_code || security.currency_code,
      realized_pnl_abs: trade.realized_pnl_abs
    }
  end

  # #807: the three figures, over the converted trades and nothing wider.
  defp summary([]) do
    %{
      realized_total: @zero,
      hit_rate: nil,
      average_holding_period_days: nil,
      trade_count: 0
    }
  end

  defp summary(trades) do
    count = length(trades)
    total = Enum.reduce(trades, @zero, &Decimal.add(&2, &1.realized_base))
    winners = Enum.count(trades, &(Decimal.compare(&1.realized_base, @zero) == :gt))

    %{
      realized_total: total,
      # A break-even trade counts as a miss: it did not realise a gain, and
      # rounding it into the hit rate would flatter the figure.
      hit_rate: winners |> Decimal.new() |> Decimal.div(Decimal.new(count)) |> Decimal.round(4),
      # Decimal rather than `Kernel.//2`: days are not money, but
      # `Ledger.TradeMatcher` already derives each `holding_period_days`
      # through `Decimal.round/2`, and one of the two averaging a set of
      # integers through a float is the kind of split that is only ever
      # noticed once it is wrong.
      average_holding_period_days:
        trades
        |> Enum.map(& &1.holding_period_days)
        |> Enum.sum()
        |> Decimal.new()
        |> Decimal.div(Decimal.new(count))
        |> Decimal.round(0)
        |> Decimal.to_integer(),
      trade_count: count
    }
  end

  # D-1's rate-availability clause is the reason this is `convert_on/4` and
  # not `convert/4`: the latter values at the most recent rate ON OR BEFORE the
  # date, so a sale on an unpriced day would be converted at a neighbouring
  # date's rate -- exactly what the signed decision forbids -- and would be
  # excluded only when no rate path existed at all.
  defp convert_trade(trade, base) do
    case Fx.convert_on(trade.realized_pnl_abs, trade.currency_code, base, trade.close_date) do
      {:ok, converted} -> {:ok, Map.put(trade, :realized_base, converted)}
      {:error, :no_rate} -> {:excluded, trade}
    end
  end

  defp annual_matrix(trades) do
    trades
    |> Enum.group_by(& &1.close_date.year)
    |> Enum.sort_by(fn {year, _} -> year end, :desc)
    |> Enum.map(fn {year, year_trades} ->
      months =
        Map.new(@months, fn month ->
          total =
            year_trades
            |> Enum.filter(&(&1.close_date.month == month))
            |> Enum.reduce(@zero, &Decimal.add(&2, &1.realized_base))

          {month, total}
        end)

      %{
        year: year,
        months: months,
        total: Enum.reduce(Map.values(months), @zero, &Decimal.add/2)
      }
    end)
  end
end
