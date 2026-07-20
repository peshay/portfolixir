defmodule Portfolixir.Ledger.TradeMatcher do
  @moduledoc """
  FIFO trade matcher.

  Folds a chronological list of buy/sell transactions for one security
  into:

  - `:open_lots`    — remaining unmatched buy quantities (oldest first)
  - `:closed_trades` — realised round-trips, one entry per sell, with
                      weighted-average cost basis across consumed lots
  - `:orphan_sells` — sell quantities with no preceding buy stock, so the
                      caller can surface them rather than silently losing
                      data

  All math is `Decimal`. The matcher is pure and database-agnostic.

  Matching still considers only the priced `buy`/`sell` kinds. A `split`
  (ADR-0028 §3) is a named mandatory change site: it scales open lot
  quantities by its ratio and divides the per-share `buy_price`, keeping
  each lot's total cost invariant (`decorate_open_lot` computes
  quantity x buy_price); a split row scales only lots of its own portfolio.
  """

  alias Portfolixir.Ledger.Projection

  @type tx :: %{
          required(:type) => String.t(),
          required(:date) => Date.t(),
          required(:quantity) => Decimal.t(),
          required(:price) => Decimal.t(),
          optional(:id) => term(),
          optional(:portfolio_id) => term(),
          optional(:fees) => Decimal.t(),
          optional(:taxes) => Decimal.t(),
          optional(:currency_code) => String.t(),
          optional(:split_ratio_numerator) => pos_integer(),
          optional(:split_ratio_denominator) => pos_integer()
        }

  @doc """
  Match `transactions` (any chronological order — they will be sorted by
  the shared `{date, intra_day_order, id}` replay order, oldest first, so a
  split applies before its day's trades) into open lots, closed trades and
  orphan sells.
  """
  @spec match([tx()]) :: %{
          open_lots: list(map()),
          closed_trades: list(map()),
          orphan_sells: list(map())
        }
  def match(transactions) when is_list(transactions) do
    sorted = Projection.replay_sort(transactions)

    state = %{lots: :queue.new(), closed: [], orphans: []}

    final =
      Enum.reduce(sorted, state, fn tx, acc ->
        case tx.type do
          "buy" -> handle_buy(acc, tx)
          "sell" -> handle_sell(acc, tx)
          "split" -> handle_split(acc, tx)
          _ -> acc
        end
      end)

    %{
      open_lots: :queue.to_list(final.lots),
      closed_trades: Enum.reverse(final.closed),
      orphan_sells: Enum.reverse(final.orphans)
    }
  end

  defp handle_buy(state, tx) do
    lot = %{
      open_date: tx.date,
      quantity: tx.quantity,
      original_quantity: tx.quantity,
      buy_price: tx.price,
      buy_fees: fee(tx, :fees),
      buy_taxes: fee(tx, :taxes),
      currency_code: Map.get(tx, :currency_code),
      # Carried so a split — booked one row per portfolio (ADR-0028 §1) —
      # scales only its own portfolio's lots.
      portfolio_id: Map.get(tx, :portfolio_id)
    }

    %{state | lots: :queue.in(lot, state.lots)}
  end

  # Scales the open lots of the split's own portfolio: lot quantity
  # multiplies by p/q (quantized once at volume scale 6, ADR-0028 §3), the
  # per-share buy_price divides by the ratio at full precision, so the lot's
  # total cost stays invariant. Fee/tax prorating stays consistent because
  # `original_quantity` scales alongside `quantity`.
  defp handle_split(state, tx) do
    ratio = {tx.split_ratio_numerator, tx.split_ratio_denominator}
    portfolio_id = Map.get(tx, :portfolio_id)

    lots =
      state.lots
      |> :queue.to_list()
      |> Enum.map(&scale_lot(&1, portfolio_id, ratio))
      |> :queue.from_list()

    %{state | lots: lots}
  end

  defp scale_lot(lot, portfolio_id, {numerator, denominator} = ratio) do
    if Map.get(lot, :portfolio_id) == portfolio_id do
      %{
        lot
        | quantity: Projection.scale_quantity(lot.quantity, ratio),
          original_quantity: Projection.scale_quantity(lot.original_quantity, ratio),
          buy_price: lot.buy_price |> Decimal.mult(denominator) |> Decimal.div(numerator)
      }
    else
      lot
    end
  end

  defp handle_sell(state, tx) do
    consume(state, tx.quantity, tx, [])
  end

  defp consume(state, remaining_sell_qty, tx, consumed_lots) do
    if Decimal.equal?(remaining_sell_qty, 0) do
      finalize_sell(state, tx, consumed_lots, Decimal.new(0))
    else
      case :queue.out(state.lots) do
        {:empty, _} ->
          orphan_state =
            if consumed_lots == [] do
              %{state | orphans: [orphan(tx, remaining_sell_qty) | state.orphans]}
            else
              # We consumed at least one lot; record the closed trade for
              # what we did consume AND log the remainder as orphan so the
              # caller knows the sell over-shot.
              partial_orphan = orphan(tx, remaining_sell_qty)
              %{state | orphans: [partial_orphan | state.orphans]}
            end

          finalize_sell(orphan_state, tx, consumed_lots, remaining_sell_qty)

        {{:value, lot}, rest} ->
          cond do
            Decimal.compare(lot.quantity, remaining_sell_qty) in [:gt] ->
              # Lot has more than enough — partial consume, lot stays.
              remaining_in_lot = Decimal.sub(lot.quantity, remaining_sell_qty)
              consumed = %{lot | quantity: remaining_sell_qty}
              residual_lot = %{lot | quantity: remaining_in_lot}
              new_lots = :queue.in_r(residual_lot, rest)

              finalize_sell(
                %{state | lots: new_lots},
                tx,
                [consumed | consumed_lots],
                Decimal.new(0)
              )

            Decimal.equal?(lot.quantity, remaining_sell_qty) ->
              # Exact consume — lot fully consumed.
              finalize_sell(%{state | lots: rest}, tx, [lot | consumed_lots], Decimal.new(0))

            true ->
              # Lot fully consumed, still need more.
              new_remaining = Decimal.sub(remaining_sell_qty, lot.quantity)
              consume(%{state | lots: rest}, new_remaining, tx, [lot | consumed_lots])
          end
      end
    end
  end

  defp finalize_sell(state, _tx, [], _remaining), do: state

  defp finalize_sell(state, tx, consumed_lots, _remaining_after_orphan) do
    consumed = Enum.reverse(consumed_lots)
    total_qty = sum_decimals(consumed, & &1.quantity)

    # Use the sum of lot-level gross amounts as the basis (not avg * qty)
    # to avoid Decimal.div precision drift when ratios don't terminate.
    gross_basis =
      Enum.reduce(consumed, Decimal.new(0), fn lot, acc ->
        Decimal.add(acc, Decimal.mult(lot.quantity, lot.buy_price))
      end)

    weighted_buy_price = safe_div(gross_basis, total_qty)

    allocated_buy_fees =
      consumed
      |> Enum.reduce(Decimal.new(0), fn lot, acc ->
        Decimal.add(acc, prorate(lot.buy_fees, lot.quantity, lot.original_quantity))
      end)

    allocated_buy_taxes =
      consumed
      |> Enum.reduce(Decimal.new(0), fn lot, acc ->
        Decimal.add(acc, prorate(lot.buy_taxes, lot.quantity, lot.original_quantity))
      end)

    sell_fees = fee(tx, :fees)
    sell_taxes = fee(tx, :taxes)

    basis =
      gross_basis
      |> Decimal.add(allocated_buy_fees)
      |> Decimal.add(allocated_buy_taxes)

    proceeds =
      Decimal.sub(Decimal.mult(total_qty, tx.price), sell_fees)
      |> Decimal.sub(sell_taxes)

    realized = Decimal.sub(proceeds, basis)
    realized_pct = safe_div(realized, basis)

    weighted_open_date_days =
      consumed
      |> Enum.reduce(Decimal.new(0), fn lot, acc ->
        days = Decimal.new(Date.diff(tx.date, lot.open_date))
        Decimal.add(acc, Decimal.mult(lot.quantity, days))
      end)
      |> safe_div(total_qty)

    holding_period_days =
      weighted_open_date_days
      |> Decimal.round(0)
      |> Decimal.to_integer()

    trade = %{
      open_date: List.first(consumed).open_date,
      close_date: tx.date,
      quantity: total_qty,
      avg_buy_price: weighted_buy_price,
      avg_sell_price: tx.price,
      buy_fees: allocated_buy_fees,
      buy_taxes: allocated_buy_taxes,
      sell_fees: sell_fees,
      sell_taxes: sell_taxes,
      basis: basis,
      proceeds: proceeds,
      realized_pnl_abs: realized,
      realized_pnl_pct: realized_pct,
      holding_period_days: holding_period_days,
      currency_code: Map.get(tx, :currency_code)
    }

    %{state | closed: [trade | state.closed]}
  end

  defp orphan(tx, qty) do
    %{
      date: tx.date,
      quantity: qty,
      price: tx.price,
      currency_code: Map.get(tx, :currency_code)
    }
  end

  defp fee(tx, key) do
    case Map.get(tx, key) do
      nil -> Decimal.new(0)
      %Decimal{} = d -> d
      other -> Decimal.new(to_string(other))
    end
  end

  defp sum_decimals(list, fun) do
    Enum.reduce(list, Decimal.new(0), fn item, acc -> Decimal.add(acc, fun.(item)) end)
  end

  # Avoid the `consumed / original * fees` Decimal.div round-trip when
  # consumed equals original — common path for full-lot consumes.
  defp prorate(value, consumed, original) do
    cond do
      Decimal.equal?(value, 0) -> Decimal.new(0)
      Decimal.equal?(consumed, original) -> value
      true -> Decimal.mult(value, safe_div(consumed, original))
    end
  end

  defp safe_div(_num, %Decimal{coef: 0}), do: Decimal.new(0)
  defp safe_div(num, den), do: Decimal.div(num, den)
end
