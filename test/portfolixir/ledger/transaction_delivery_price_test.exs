defmodule Portfolixir.Ledger.TransactionDeliveryPriceTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger

  # Closing-act finding (edge-case hunter, Sprint 11 Lane X): since #779 a
  # delivery's booked price drives the day's external flow and the lot
  # queue, so it is validated like a trade's price — never negative.
  #
  # Acceptance criteria:
  # - A delivery with a negative price is refused on the price field.
  # - A delivery at 0 (a write-off) and without a price stay accepted.
  test "a delivery's booked price is never negative" do
    world = base_world(name: "DP", cash_name: "DP Cash", depot_name: "DP Depot")
    security = create_security!(name: "Delivered Co", ticker: "DLV")

    attrs = %{
      portfolio_id: world.portfolio.id,
      securities_account_id: world.depot.id,
      security_id: security.id,
      type: "inbound_delivery",
      date: ~D[2026-01-10],
      quantity: "5",
      currency_code: "EUR"
    }

    assert {:error, changeset} =
             Ledger.create_transaction(Actor.owner_ui(), Map.put(attrs, :price, "-80"))

    assert %{price: [_ | _]} = errors_on(changeset)

    assert {:ok, _} = Ledger.create_transaction(Actor.owner_ui(), Map.put(attrs, :price, "0"))

    assert {:ok, _} =
             Ledger.create_transaction(Actor.owner_ui(), %{
               attrs
               | type: "outbound_delivery",
                 date: ~D[2026-01-11],
                 quantity: "2"
             })
  end
end
