defmodule Portfolixir.Portfolios.AllocationNegativeHoldingsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Allocation

  # User story (#570):
  # As a local portfolio maintainer,
  # I want negative-quantity positions to stay visible in the allocation
  # instead of silently hiding the unassigned bucket,
  # so that import debris from unmodeled corporate actions never blends in
  # (or worse, makes healthy unassigned positions disappear with it).
  #
  # Acceptance criteria:
  # - An unassigned pot with a NEGATIVE total value is still reported, with
  #   its positions (previously it was dropped entirely, hiding the healthy
  #   positions grouped with the debris).
  # - The negative position keeps its negative quantity in the entry.
  test "reports the unassigned bucket even when debris makes its value negative" do
    world = base_world()

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    healthy = create_security!(name: "World ETF", ticker: "WLD", asset_class: "etf")
    doomed = create_security!(name: "Doomed Co.", ticker: "DOOM", asset_class: "equity")

    buy!(world, healthy, quantity: "8", price: "100")
    put_quote!(healthy, ~D[2026-06-01], "110")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: doomed.id,
        type: "outbound_delivery",
        date: ~D[2026-02-02],
        quantity: "500",
        currency_code: "EUR"
      })

    put_quote!(doomed, ~D[2026-06-01], "10")

    {:ok, allocation} = Allocation.for_portfolio(world.portfolio.id, classification.id, [])

    assert %{positions: positions} = allocation.unassigned
    # 880 + (−500 × 10) = −4120.
    assert Decimal.equal?(allocation.unassigned.market_value, Decimal.new("-4120"))

    doomed_entry = Enum.find(positions, &(&1.security_id == doomed.id))
    assert Decimal.equal?(doomed_entry.quantity, Decimal.new("-500"))

    healthy_entry = Enum.find(positions, &(&1.security_id == healthy.id))
    assert Decimal.equal?(healthy_entry.quantity, Decimal.new("8"))
  end
end
