defmodule Portfolixir.Portfolios.CostsTest do
  # Issue #726: the Costs facet — fees and taxes at OVERVIEW level only (the
  # "only" is the requirement: no per-instrument or per-transaction cost
  # table). The facet sums the fee/tax LEGS riding any transaction plus the
  # standalone fee/tax bookings, and nets tax refunds against taxes — it
  # never touches gross amounts, whose fee-inclusiveness differs between buy
  # (inclusive) and sell (net), which is exactly why summing legs is the
  # honest series.
  use Portfolixir.DataCase

  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Costs
  alias Portfolixir.WorldFixtures

  defp standalone!(world, type, amount, date, cash \\ nil) do
    {:ok, tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: (cash || world.cash).id,
        type: type,
        date: date,
        gross_amount: amount,
        currency_code: (cash || world.cash).currency_code
      })

    tx
  end

  # User story (issue #726):
  # As a local portfolio maintainer,
  # I want what the portfolio cost to run — fees and taxes per period,
  # so that costs are one readable figure, not a per-transaction ledger.
  #
  # Acceptance criteria (exact Decimal expectations):
  # - The per-transaction fee/tax legs AND the standalone fee/tax kinds are
  #   summed; a tax_refund nets against taxes.
  # - Foreign-currency costs convert at their booking date (EUR hub,
  #   at-or-before); an unconvertible cost is excluded and named by
  #   currency.
  # - The payload states the series (legs + standalone kinds, refunds
  #   netted, gross amounts untouched), window, reference and gap
  #   treatment.
  test "sums fee and tax legs plus standalone bookings, netting refunds" do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!(name: "Charged ETF", ticker: "CHG")

    # Legs riding a buy: 9.90 fees, 2.10 taxes (January).
    WorldFixtures.buy!(world, security,
      quantity: "10",
      price: "100",
      fees: "9.90",
      taxes: "2.10",
      date: ~D[2026-01-15]
    )

    # Standalone bookings: a 12.00 fee and a 30.00 tax in February, and a
    # 10.00 tax refund in March that nets against taxes.
    standalone!(world, "fee", "12.00", ~D[2026-02-10])
    standalone!(world, "tax", "30.00", ~D[2026-02-15])
    standalone!(world, "tax_refund", "10.00", ~D[2026-03-05])

    report = Costs.report(base_currency: "EUR")

    assert [%{year: 2026} = year] = report.annual
    assert Decimal.equal?(year.months[1].fees, Decimal.new("9.90"))
    assert Decimal.equal?(year.months[1].taxes, Decimal.new("2.10"))
    assert Decimal.equal?(year.months[2].fees, Decimal.new("12.00"))
    assert Decimal.equal?(year.months[2].taxes, Decimal.new("30.00"))
    assert Decimal.equal?(year.months[3].taxes, Decimal.new("-10.00"))
    assert Decimal.equal?(year.fees_total, Decimal.new("21.90"))
    assert Decimal.equal?(year.taxes_total, Decimal.new("22.10"))
    assert Decimal.equal?(year.total, Decimal.new("44.00"))

    assert report.excluded.count == 0
    assert report.computation_basis.series =~ "legs"
    assert report.computation_basis.series =~ "refund"
    assert report.computation_basis.gaps =~ "excluded"
  end

  test "an unconvertible cost is excluded from the totals and named by currency" do
    world = WorldFixtures.base_world()
    standalone!(world, "fee", "5.00", ~D[2026-04-01])

    %{cash: gbp_cash} =
      WorldFixtures.add_depot(world.portfolio,
        currency: "GBP",
        cash_name: "GBP Cash",
        depot_name: "GBP Depot"
      )

    standalone!(world, "fee", "3.00", ~D[2026-04-02], gbp_cash)

    report = Costs.report(base_currency: "EUR")

    assert [%{year: 2026} = year] = report.annual
    assert Decimal.equal?(year.fees_total, Decimal.new("5.00"))
    assert report.excluded.count == 1
    assert report.excluded.currencies == ["GBP"]

    # Storing the rate FOR THAT COST'S OWN DATE brings it in; a rate stored
    # for 2026-04-01 would not, which is the point of the basis.
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "GBP",
          date: ~D[2026-04-02],
          rate: "0.80",
          source: "manual"
        }
      ])

    report = Costs.report(base_currency: "EUR")
    assert [%{year: 2026} = year] = report.annual
    # 3.00 GBP ÷ 0.80 = 3.75 EUR.
    assert Decimal.equal?(year.fees_total, Decimal.new("8.75"))
    assert report.excluded.count == 0
  end
end
