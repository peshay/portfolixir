defmodule Portfolixir.Ledger.Positions do
  @moduledoc """
  Derives currently held quantities per `{securities_account, security}`.

  A generic fold over the quantity legs of the canonical per-kind reducer
  (`Portfolixir.Ledger.Projection`, ADR-0011): quantities move with
  `buy`/`sell` trades, `inbound_delivery`/`outbound_delivery` (shares enter
  or leave without a cash leg, e.g. a depot transfer from another bank), and
  `security_transfer` between own depots. Cost basis and P&L stay with the
  holdings views, whose cost fold follows the shares through the same kinds
  but only ever adds cost for priced acquisitions.
  """

  alias Portfolixir.Ledger.Projection

  @zero Decimal.new("0")

  def calculate(transactions) when is_list(transactions) do
    Enum.reduce(transactions, %{}, fn transaction, positions ->
      Enum.reduce(Projection.effects(transaction).quantities, positions, &apply_quantity_leg/2)
    end)
  end

  # Sold-out or fully transferred positions are dropped so callers only see
  # what is actually held.
  defp apply_quantity_leg({securities_account_id, security_id, delta}, positions) do
    key = {securities_account_id, security_id}
    positions = Map.update(positions, key, delta, &Decimal.add(&1, delta))

    if Decimal.equal?(Map.fetch!(positions, key), @zero) do
      Map.delete(positions, key)
    else
      positions
    end
  end
end
