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
  alias Portfolixir.Portfolios.Performance
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

  # -- the ADR-0015 amendment of 2026-10-07: the account's currency (#1107) ------

  defp rate!(quote_currency, date, rate) do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: quote_currency,
          date: date,
          rate: rate,
          source: "manual"
        }
      ])
  end

  # User story (#1107, the ADR-0015 amendment's identity 2):
  # As a maintainer who buys a USD security through my EUR account,
  # I want the Costs facet to count the fees and taxes my broker charged in
  # euros as euros,
  # so that the facet and the performance walk read one figure for the same
  # booked costs, and it is the cash the trade moved beyond its settlement.
  #
  # Acceptance criteria (exact Decimal expectations, risk-tier):
  # - Buy 10 at 100 USD settled 790.00 EUR, fees 5.00 and taxes 1.00 EUR,
  #   1 EUR = 1.25 USD: the month reads fees 5.00, taxes 1.00, total 6.00 EUR
  #   (before the amendment 4.00, 0.80 and 4.80).
  # - The total equals the walk's trade costs for that day and the cash
  #   minus the settlement (796.00 − 790.00).
  # - computation_basis says the costs are read in the cash account's
  #   currency.
  test "a cross-currency trade's fees and taxes are read in its cash account's currency (identity 2)" do
    world = WorldFixtures.base_world(name: "Cost Cross", cash_name: "Cost Cash")
    fund = WorldFixtures.create_security!(name: "Cost Fund", ticker: "CSF", currency: "USD")

    # 1 EUR = 1.25 USD from before the walk's first day and on the booking
    # date itself, the one date the facet reads.
    rate!("USD", ~D[2026-05-01], "1.25")
    rate!("USD", ~D[2026-05-05], "1.25")
    WorldFixtures.deposit!(world, "2000", ~D[2026-05-04])

    buy =
      WorldFixtures.cross_trade!(world, fund,
        quantity: "10",
        price: "100",
        settled: "790.00",
        fees: "5.00",
        taxes: "1.00",
        gross: "796.00",
        date: ~D[2026-05-05]
      )

    report = Costs.report(base_currency: "EUR")

    assert [%{year: 2026} = year] = report.annual
    assert Decimal.equal?(year.months[5].fees, Decimal.new("5.00"))
    assert Decimal.equal?(year.months[5].taxes, Decimal.new("1.00"))
    assert Decimal.equal?(year.total, Decimal.new("6.00"))
    assert report.excluded.count == 0

    %{daily: daily} = Performance.analysis(world.portfolio.id, today: ~D[2026-05-10])
    walk_costs = daily |> Enum.find(&(&1.date == ~D[2026-05-05])) |> Performance.trade_costs_of()
    assert Decimal.equal?(year.total, walk_costs)
    assert Decimal.equal?(year.total, Decimal.sub(buy.gross_amount, buy.settlement_amount))

    assert report.computation_basis.currency =~ "cash account's currency"
  end

  # User story (#1107):
  # As a maintainer whose account's currency has no stored rate on a day,
  # I want a cost that cannot be converted named by the currency it is in,
  # the account's,
  # so that the note tells me which rate to fetch.
  #
  # Acceptance criteria:
  # - A cross-currency trade through a GBP account with no GBP rate, priced
  #   in USD which has one, is excluded and named GBP (before the amendment
  #   it was converted from USD, as if its fees were dollars).
  # - A cross-currency trade through a EUR account, priced in CHF which has
  #   no rate, is converted from EUR (before: excluded and named CHF).
  test "a cost that cannot be converted is named by its cash account's currency" do
    world = WorldFixtures.base_world(name: "Cost Names", cash_name: "Euro Cost Cash")

    pound_world =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          cash_currency: "GBP",
          cash_name: "Pound Cost Cash",
          depot_name: "Pound Cost Depot"
        )
      )

    dollar =
      WorldFixtures.create_security!(name: "Dollar Cost Co", ticker: "DCC", currency: "USD")

    franc = WorldFixtures.create_security!(name: "Franc Cost AG", ticker: "FCA", currency: "CHF")

    rate!("USD", ~D[2026-06-02], "1.25")

    # 4 at 50 USD settled 160.00 GBP, fees 2.00 GBP: no GBP rate is stored.
    WorldFixtures.cross_trade!(pound_world, dollar,
      quantity: "4",
      price: "50",
      settled: "160.00",
      fees: "2.00",
      gross: "162.00",
      date: ~D[2026-06-02]
    )

    # 2 at 90 CHF settled 190.00 EUR, fees 3.00 EUR: no CHF rate is stored.
    WorldFixtures.cross_trade!(world, franc,
      quantity: "2",
      price: "90",
      settled: "190.00",
      fees: "3.00",
      gross: "193.00",
      date: ~D[2026-06-02]
    )

    report = Costs.report(base_currency: "EUR")

    assert [%{year: 2026} = year] = report.annual
    assert Decimal.equal?(year.fees_total, Decimal.new("3.00"))
    assert report.excluded.count == 1
    assert report.excluded.currencies == ["GBP"]
  end
end
