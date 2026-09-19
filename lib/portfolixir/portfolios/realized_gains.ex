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
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
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

    {converted, excluded} =
      traded_securities()
      |> Enum.flat_map(&closed_trades/1)
      |> Enum.map(&convert_trade(&1, base))
      |> Enum.split_with(&match?({:ok, _}, &1))

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
      excluded: %{
        count: length(excluded),
        securities: excluded |> Enum.map(& &1.security_name) |> Enum.uniq() |> Enum.sort()
      },
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
            "full history, while limit= cuts only the years the matrix shows."
      }
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

  defp closed_trades(security) do
    security.id
    |> Ledger.list_trades_for_security()
    |> Map.get(:closed_trades, [])
    |> Enum.map(fn trade ->
      # #807: the row the facet lists, beside the figure the matrix sums.
      # `security_id` rides along so each row can link to that security's
      # Trades tab, where the same round-trip is shown with its lots.
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
    end)
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
