defmodule Portfolixir.Portfolios.ExternalFlowsTest do
  # Issue #725: the Deposits & withdrawals facet's aggregate read — the
  # owner's "Ersparnis". Booked deposit/removal cash flows only, per period;
  # the performance walk's invested-capital figure additionally counts
  # deliveries at market value and balance-snapshot residuals, and that
  # difference is STATED (in the payload and on the surface) rather than
  # left for a reader to discover by comparing two numbers.
  use Portfolixir.DataCase

  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.ExternalFlows
  alias Portfolixir.WorldFixtures

  defp removal!(world, amount, date, cash \\ nil) do
    {:ok, tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: (cash || world.cash).id,
        type: "removal",
        date: date,
        gross_amount: amount,
        currency_code: (cash || world.cash).currency_code
      })

    tx
  end

  # User story (issue #725):
  # As a local portfolio maintainer,
  # I want deposits and withdrawals per period, separate from what the
  # portfolio earned,
  # so that "how much of my own money went in and came out" is one honest
  # read instead of a mental subtraction.
  #
  # Acceptance criteria (exact Decimal expectations):
  # - Deposits and withdrawals aggregate as two series per month, with a
  #   net; a foreign-currency flow converts at its booking date (EUR hub,
  #   at-or-before).
  # - A flow with no stored booking-date rate is excluded and named by its
  #   cash account (the #724 shape, one rule across the facets).
  # - The payload states the basis AND the deliberate difference from the
  #   invested-capital figure (deliveries and balance snapshots not
  #   counted).
  test "aggregates deposits and withdrawals per period on the stated basis" do
    world = WorldFixtures.base_world()
    WorldFixtures.deposit!(world, "1000.00", ~D[2026-01-10])
    WorldFixtures.deposit!(world, "500.00", ~D[2026-02-05])
    removal!(world, "200.00", ~D[2026-02-20])

    %{cash: usd_cash} =
      WorldFixtures.add_depot(world.portfolio,
        currency: "USD",
        cash_name: "USD Cash",
        depot_name: "USD Depot"
      )

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: usd_cash.id,
        type: "deposit",
        date: ~D[2026-02-10],
        gross_amount: "125.00",
        currency_code: "USD"
      })

    # 1 EUR = 1.25 USD stored on the flow's OWN booking date → 125 USD =
    # 100 EUR. A rate from an earlier day would leave the flow excluded and
    # named: the Cash-flow area converts on the date itself or not at all.
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-02-10],
          rate: "1.25",
          source: "manual"
        }
      ])

    report = ExternalFlows.report(base_currency: "EUR")

    assert [%{year: 2026} = year] = report.annual
    assert Decimal.equal?(year.months[1].deposits, Decimal.new("1000.00"))
    assert Decimal.equal?(year.months[2].deposits, Decimal.new("600.00"))
    assert Decimal.equal?(year.months[2].withdrawals, Decimal.new("200.00"))
    assert Decimal.equal?(year.deposits_total, Decimal.new("1600.00"))
    assert Decimal.equal?(year.withdrawals_total, Decimal.new("200.00"))
    assert Decimal.equal?(year.net_total, Decimal.new("1400.00"))

    assert report.excluded.count == 0
    assert report.computation_basis.series =~ "deposit"
    assert report.computation_basis.gaps =~ "excluded"
    assert report.computation_basis.excludes =~ "deliver"
  end

  test "a flow with no rate at its booking date is excluded and named by account" do
    world = WorldFixtures.base_world()
    WorldFixtures.deposit!(world, "300.00", ~D[2026-03-01])

    %{cash: gbp_cash} =
      WorldFixtures.add_depot(world.portfolio,
        currency: "GBP",
        cash_name: "GBP Cash",
        depot_name: "GBP Depot"
      )

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: gbp_cash.id,
        type: "deposit",
        date: ~D[2026-03-05],
        gross_amount: "80.00",
        currency_code: "GBP"
      })

    report = ExternalFlows.report(base_currency: "EUR")

    assert [%{year: 2026} = year] = report.annual
    assert Decimal.equal?(year.deposits_total, Decimal.new("300.00"))
    assert report.excluded.count == 1
    assert report.excluded.accounts == ["GBP Cash"]
  end
end
