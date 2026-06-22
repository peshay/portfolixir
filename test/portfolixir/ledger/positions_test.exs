defmodule Portfolixir.Ledger.PositionsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  # User story:
  # As a local portfolio maintainer importing my Portfolio Performance history,
  # I want deliveries and security transfers to move my held quantities just
  # like PP shows them,
  # so that positions that entered my depots without a cash leg are not
  # missing from the valuation and allocation.
  #
  # Acceptance criteria:
  # - An inbound delivery adds quantity; an outbound delivery removes it.
  # - A security transfer moves quantity between two own depots without
  #   changing the portfolio-level total.
  # - Buy/sell arithmetic is unchanged.

  defp setup_world do
    %{portfolio: portfolio, cash: cash, depot: depot_a} =
      world = base_world(name: "P", cash_name: "Cash", depot_name: "Depot A")

    # A second depot sharing the same cash account, so a security transfer can
    # move quantity between two own depots without a cash leg.
    {:ok, depot_b} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot B"
      })

    security = create_security!(name: "Moved Co.", ticker: "MOVE", asset_class: "equity")

    world
    |> Map.drop([:depot])
    |> Map.merge(%{depot_a: depot_a, depot_b: depot_b, security: security})
  end

  defp delivery!(w, kind, depot, qty, date) do
    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: depot.id,
        security_id: w.security.id,
        type: kind,
        date: date,
        quantity: qty,
        currency_code: "EUR"
      })
  end

  test "deliveries move quantity in and out of a depot" do
    w = setup_world()

    delivery!(w, "inbound_delivery", w.depot_a, "10", ~D[2026-01-02])
    delivery!(w, "outbound_delivery", w.depot_a, "4", ~D[2026-01-10])

    positions = Ledger.positions_for_portfolio(w.portfolio.id)

    assert Decimal.equal?(positions[{w.depot_a.id, w.security.id}], Decimal.new("6"))
  end

  test "a security transfer moves quantity between own depots, total unchanged" do
    w = setup_world()

    delivery!(w, "inbound_delivery", w.depot_a, "10", ~D[2026-01-02])

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot_a.id,
        counter_securities_account_id: w.depot_b.id,
        security_id: w.security.id,
        type: "security_transfer",
        date: ~D[2026-01-05],
        quantity: "3",
        currency_code: "EUR"
      })

    positions = Ledger.positions_for_portfolio(w.portfolio.id)

    assert Decimal.equal?(positions[{w.depot_a.id, w.security.id}], Decimal.new("7"))
    assert Decimal.equal?(positions[{w.depot_b.id, w.security.id}], Decimal.new("3"))
  end
end
