defmodule Portfolixir.Ledger.NegativeHoldingsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, base_world: 1, add_depot: 2, create_security!: 1, buy!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger

  # User story (#570):
  # As a local portfolio maintainer with an imported history,
  # I want a data-quality report of securities whose derived holding quantity
  # is negative — per depot and in total,
  # so that import debris from unmodeled corporate actions is surfaced for
  # repair instead of flowing silently into holdings, allocation and
  # valuation.
  #
  # Acceptance criteria:
  # - The report lists every (depot, security) position with a negative
  #   derived quantity, with depot and security names.
  # - Each listed security also carries its total quantity across all depots,
  #   so a transfer-debris case (negative in one depot, positive in another)
  #   is distinguishable from a truly negative total.
  # - Positions with non-negative quantities do not appear.
  # - Quantities are Decimals.

  defp outbound!(world, depot, security, quantity, date) do
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: depot.id,
        security_id: security.id,
        type: "outbound_delivery",
        date: date,
        quantity: quantity,
        currency_code: "EUR"
      })
  end

  test "lists negative positions per depot with per-security totals" do
    world = base_world(depot_name: "Main Depot")
    second = add_depot(world.portfolio, name: "Second Depot")

    doomed = create_security!(name: "Doomed Co.", ticker: "DOOM", asset_class: "equity")
    fine = create_security!(name: "Fine Co.", ticker: "FINE", asset_class: "equity")

    # An unmodeled corporate action: 500 units left the depot that only ever
    # received 100 — the derived quantity goes to −400.
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: doomed.id,
        type: "inbound_delivery",
        date: ~D[2026-01-02],
        quantity: "100",
        currency_code: "EUR"
      })

    outbound!(world, world.depot, doomed, "500", ~D[2026-02-02])

    # The same security is held +50 in a second depot: the depot row is
    # negative, the security total is −350.
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: second.depot.id,
        security_id: doomed.id,
        type: "inbound_delivery",
        date: ~D[2026-01-03],
        quantity: "50",
        currency_code: "EUR"
      })

    # A healthy position never shows up.
    buy!(world, fine, quantity: "10", price: "5")

    report = Ledger.negative_holdings_report()

    assert [row] = report.rows
    assert row.securities_account_id == world.depot.id
    assert row.depot_name == "Main Depot"
    assert row.portfolio_id == world.portfolio.id
    assert row.security_id == doomed.id
    assert row.security_name == "Doomed Co."
    assert Decimal.equal?(row.quantity, Decimal.new("-400"))

    assert [total] = report.totals
    assert total.security_id == doomed.id
    assert total.security_name == "Doomed Co."
    assert Decimal.equal?(total.total_quantity, Decimal.new("-350"))

    assert report.as_of == Date.utc_today()
    assert report.note =~ "negative"
  end

  test "returns empty lists when no negative holdings exist" do
    world = base_world()
    fine = create_security!(name: "Fine Co.", ticker: "FINE", asset_class: "equity")
    buy!(world, fine, quantity: "10", price: "5")

    report = Ledger.negative_holdings_report()

    assert report.rows == []
    assert report.totals == []
  end
end
