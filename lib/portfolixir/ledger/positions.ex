defmodule Portfolixir.Ledger.Positions do
  @moduledoc """
  Derives currently held quantities per `{securities_account, security}`.

  A generic fold over the quantity legs of the canonical per-kind reducer
  (`Portfolixir.Ledger.Projection`, ADR-0011): quantities move with
  `buy`/`sell` trades, `inbound_delivery`/`outbound_delivery` (shares enter
  or leave without a cash leg, e.g. a depot transfer from another bank), and
  `security_transfer` between own depots. A `split` (ADR-0028) contributes a
  multiplicative `{:scale, ...}` leg instead: it scales the security's
  positions of its own portfolio from the fold's pre-split state, first
  within its day. Cost basis and P&L stay with the holdings views, whose
  cost fold follows the shares through the same kinds but only ever adds
  cost for priced acquisitions.

  Transactions are replayed in the shared `{date, intra_day_order, id}`
  order (`Projection.replay_sort/1`) — multiplicative legs do not commute
  with additive ones, so callers need not pre-sort.
  """

  alias Portfolixir.Ledger.Projection

  @zero Decimal.new("0")

  def calculate(transactions) when is_list(transactions) do
    ordered = Projection.replay_sort(transactions)
    account_portfolios = Projection.account_portfolios(ordered)

    Enum.reduce(ordered, %{}, fn transaction, positions ->
      Enum.reduce(
        Projection.effects(transaction).quantities,
        positions,
        &apply_quantity_leg(&1, &2, account_portfolios)
      )
    end)
  end

  # A scale leg multiplies the held quantity of every `{account, security}`
  # position that belongs to the split row's own portfolio (ADR-0028 §1);
  # other portfolios' positions of the same security stay untouched. The
  # scaled quantity quantizes once at volume scale 6 (`scale_quantity/2`).
  defp apply_quantity_leg({:scale, scale}, positions, account_portfolios) do
    Enum.reduce(positions, positions, fn {key, quantity}, acc ->
      if scaled_key?(key, scale, account_portfolios) do
        put_position(acc, key, Projection.scale_quantity(quantity, scale.ratio))
      else
        acc
      end
    end)
  end

  defp apply_quantity_leg({securities_account_id, security_id, delta}, positions, _accounts) do
    key = {securities_account_id, security_id}
    current = Map.get(positions, key, @zero)
    put_position(positions, key, Decimal.add(current, delta))
  end

  defp scaled_key?({account_id, security_id}, scale, account_portfolios) do
    security_id == scale.security_id and
      Map.get(account_portfolios, account_id) == scale.portfolio_id
  end

  # Sold-out or fully transferred positions are dropped so callers only see
  # what is actually held.
  defp put_position(positions, key, quantity) do
    if Decimal.equal?(quantity, @zero) do
      Map.delete(positions, key)
    else
      Map.put(positions, key, quantity)
    end
  end
end
