defmodule Portfolixir.Ledger.PositionCostsTest do
  # `Ledger.position_costs/1` (ADR-0050 §7, L3b): the holdings' moving-average
  # cost fold read per position, with the result each position's sales
  # realized. The depot merge states these before and after; this pins the
  # fold itself. Every figure is synthetic.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, sell!: 3, create_security!: 1]

  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction

  # User story:
  # As the operator previewing a depot merge,
  # I want each position's moving-average cost and realized result stated
  # by the same fold the holdings read,
  # so that the figures a merge promises are the ones I read afterwards.
  #
  # Acceptance criteria:
  # - Two buys (10 @ 100, 10 @ 120) and a sale of 5 @ 130: 15 left at a
  #   running average of 110, cost 1650, realized 5 × (130 − 110) = 100.
  # - Fees and taxes are in neither the cost nor the realized result.
  # - quantity, cost_basis and avg_cost equal the holdings read.
  test "the moving-average cost and realized result of a position" do
    world = base_world(name: "Costs World", depot_name: "Costs Depot")
    security = create_security!(name: "Costs Fund", ticker: "CSTF")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2025-01-02], fees: "4")
    buy!(world, security, quantity: "10", price: "120", date: ~D[2025-01-03])
    sell!(world, security, quantity: "5", price: "130", date: ~D[2025-01-04], taxes: "3")

    figures =
      world.portfolio.id
      |> rows()
      |> Ledger.position_costs()
      |> Map.fetch!({world.depot.id, security.id})

    assert n(figures.quantity) == dec("15")
    assert n(figures.cost_basis) == dec("1650")
    assert n(figures.avg_cost) == dec("110")
    assert n(figures.realized_result) == dec("100")

    [holding] = Ledger.holdings_for_portfolio(world.portfolio.id, prices: %{})
    assert n(holding.quantity) == n(figures.quantity)
    assert n(holding.cost_basis) == n(figures.cost_basis)
    assert n(holding.avg_cost) == n(figures.avg_cost)
  end

  # Acceptance criteria:
  # - A position that was never sold has a realized result of zero.
  # - A security booked in another currency without a security-currency
  #   amount has no derivable cost or sale price: the cost basis and the
  #   realized result are nil, never guessed.
  test "no sale realizes zero; without a security-currency leg the result is nil" do
    world = base_world(name: "Costs World 2", depot_name: "Costs Depot 2")
    held = create_security!(name: "Held Fund", ticker: "HLDF")
    foreign = create_security!(name: "Foreign Fund", ticker: "FRNF", currency: "USD")
    buy!(world, held, quantity: "2", price: "50", date: ~D[2025-01-02])
    # Booked in the account's EUR without a USD amount: no security-currency
    # leg is derivable for either booking.
    buy!(world, foreign, quantity: "4", price: "10", date: ~D[2025-01-02])
    sell!(world, foreign, quantity: "1", price: "11", date: ~D[2025-01-05])

    costs = world.portfolio.id |> rows() |> Ledger.position_costs()

    assert n(costs[{world.depot.id, held.id}].realized_result) == dec("0")
    assert costs[{world.depot.id, foreign.id}].cost_basis == nil
    assert costs[{world.depot.id, foreign.id}].realized_result == nil
  end

  defp rows(portfolio_id) do
    Repo.all(
      from(t in Transaction,
        where: t.portfolio_id == ^portfolio_id,
        preload: [:security, :cash_account]
      )
    )
  end

  defp dec(value), do: value |> Decimal.new() |> Decimal.normalize()
  defp n(%Decimal{} = value), do: Decimal.normalize(value)
end
