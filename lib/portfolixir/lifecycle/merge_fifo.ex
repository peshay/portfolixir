defmodule Portfolixir.Lifecycle.MergeFifo do
  @moduledoc """
  The FIFO restatement a security merge makes (security review 2026-10-12,
  K11), for its preview and its plan digest.

  The realized gains the app reads (`Portfolixir.Portfolios.RealizedGains`,
  a security's trades) are FIFO over **one queue per security**, across
  every depot and portfolio (the ADR-0015 amendment of 2026-10-09). A
  security merge re-points the source's bookings onto the target, so the two
  queues become one and a sale can close an older lot of the other security:
  the realized result of a close year, and the cost still open, can change.
  A depot merge moves no booking between securities, so it changes neither.

  `restatement/4` runs the matcher (`Portfolixir.Ledger.match_trades/2`, fed
  as the trades read feeds it) over each security's rows before and over the
  rows the merge leaves on the target after, and states per close year and
  currency the realized result of the source, of the target and of the
  merged security, and likewise the open lots' cost. Every amount is in the
  currency of the trade or lot it sums — the security's currency, unless a
  booking was priced in another — never converted, so it is the trades
  read's figure; the realized-gains read converts the same figure into the
  base currency at each close date.
  """

  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.TradeMatcher

  @zero Decimal.new("0")

  @typedoc "One side's FIFO figures."
  @type side :: %{
          realized: %{{integer(), String.t()} => Decimal.t()},
          open: %{String.t() => Decimal.t()},
          unmatched: non_neg_integer()
        }

  @doc """
  The restatement: `source_rows` and `target_rows` are each security's rows
  before the merge, `after_rows` the target's rows after it (the source's
  moved rows already relabelled onto the target); `currencies` names the
  source's and the target's currency (`%{source: code, target: code}`).

  Answers `years` (per close year and currency, ascending: `source`,
  `target` and `after`, each `nil` where that side closes no trade in it,
  and `change`, after less the two before), `open_lots` (per currency: the
  open lots' cost of each side and the change), `unmatched_sells` (the
  number of sells no lot covers, per side) and `unchanged` — true when no
  figure moves.
  """
  @spec restatement([struct()], [struct()], [struct()], %{source: String.t(), target: String.t()}) ::
          map()
  def restatement(source_rows, target_rows, after_rows, currencies) do
    source = side(source_rows, currencies.source)
    target = side(target_rows, currencies.target)
    merged = side(after_rows, currencies.target)
    sides = [source, target, merged]

    years =
      sides
      |> Enum.flat_map(&Map.keys(&1.realized))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn {year, currency} = key ->
        figures = %{
          source: Map.get(source.realized, key),
          target: Map.get(target.realized, key),
          after: Map.get(merged.realized, key)
        }

        figures
        |> Map.merge(%{year: year, currency_code: currency})
        |> Map.put(:change, change(figures))
      end)

    open_lots =
      sides
      |> Enum.flat_map(&Map.keys(&1.open))
      |> Enum.uniq()
      |> case do
        [] -> [currencies.target]
        found -> Enum.sort(found)
      end
      |> Enum.map(fn currency ->
        figures = %{
          source: Map.get(source.open, currency, @zero),
          target: Map.get(target.open, currency, @zero),
          after: Map.get(merged.open, currency, @zero)
        }

        figures
        |> Map.put(:currency_code, currency)
        |> Map.put(:change, change(figures))
      end)

    unmatched = %{source: source.unmatched, target: target.unmatched, after: merged.unmatched}

    %{
      years: years,
      open_lots: open_lots,
      unmatched_sells: unmatched,
      unchanged:
        Enum.all?(years ++ open_lots, &Decimal.equal?(&1.change, @zero)) and
          unmatched.after == unmatched.source + unmatched.target
    }
  end

  defp side(rows, currency) do
    matched = Ledger.match_trades(rows, currency)

    %{
      realized:
        Enum.reduce(matched.closed_trades, %{}, fn trade, acc ->
          key = {trade.close_date.year, trade.currency_code || currency}
          Map.update(acc, key, trade.realized_pnl_abs, &Decimal.add(&1, trade.realized_pnl_abs))
        end),
      open:
        Enum.reduce(matched.open_lots, %{}, fn lot, acc ->
          cost = TradeMatcher.lot_cost(lot)
          Map.update(acc, lot.currency_code || currency, cost, &Decimal.add(&1, cost))
        end),
      unmatched: length(matched.orphan_sells)
    }
  end

  defp change(%{source: source, target: target, after: merged}) do
    Enum.reduce([source, target], merged || @zero, fn
      nil, acc -> acc
      value, acc -> Decimal.sub(acc, value)
    end)
  end
end
