defmodule Portfolixir.Portfolios.TradeCostsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Performance

  # User story (#708, ADR-0027 amendment §1):
  # As a maintainer reading a snapshot comparison,
  # I want the daily walk to carry the fees and taxes a TRADE cost me,
  # so that the comparison can state what the changes cost and whether they
  # have been earned back — instead of quietly holding them against the real
  # side.
  #
  # Acceptance criteria:
  # - Each walk day carries the fees + taxes of that day's buys and sells, in
  #   the base currency.
  # - Standalone `fee` and `tax` bookings are NOT counted: a custody charge is
  #   not caused by a trade, and the frozen holder would have paid it too.
  # - Dividend withholding is NOT counted — it belongs to the dividend
  #   asymmetry, which is a different follow-up.
  # - A day with no trades carries zero, never nil.

  defp world do
    w = base_world(name: "Costs", cash_name: "Cash", depot_name: "Depot")
    Map.put(w, :security, create_security!(name: "Cost AG", ticker: "CST"))
  end

  defp book!(w, attrs) do
    {:ok, tx} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        Map.merge(%{portfolio_id: w.portfolio.id, currency_code: "EUR"}, attrs)
      )

    tx
  end

  defp costs_on(w, date) do
    %{daily: daily} = Performance.analysis(w.portfolio.id, today: ~D[2026-06-30])
    point = Enum.find(daily, &(Date.compare(&1.date, date) == :eq))
    point && Map.get(point, :trade_costs)
  end

  test "a trade's fees and taxes land on its day" do
    w = world()

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-01-01],
      gross_amount: "10000"
    })

    book!(w, %{
      cash_account_id: w.cash.id,
      securities_account_id: w.depot.id,
      security_id: w.security.id,
      type: "buy",
      date: ~D[2026-02-02],
      quantity: "10",
      price: "100",
      gross_amount: "1012.50",
      fees: "10",
      taxes: "2.50"
    })

    assert Decimal.equal?(costs_on(w, ~D[2026-02-02]), Decimal.new("12.50"))
  end

  test "a day without trades carries zero, not nil" do
    w = world()

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-01-01],
      gross_amount: "10000"
    })

    assert Decimal.equal?(costs_on(w, ~D[2026-01-15]), Decimal.new("0"))
  end

  test "a standalone fee or tax booking is not a trade cost" do
    w = world()

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-01-01],
      gross_amount: "10000"
    })

    # Two shapes, because the boundary can be crossed two ways and testing one
    # lets the other through: the charge of a standalone booking sits in
    # `gross_amount`, so a booking with only that passes even when the kind is
    # wrongly admitted, since the `fees` column is zero either way. Each of
    # these carries a material amount in BOTH columns.
    book!(w, %{
      cash_account_id: w.cash.id,
      type: "fee",
      date: ~D[2026-03-01],
      gross_amount: "25",
      fees: "25"
    })

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "tax",
      date: ~D[2026-03-02],
      gross_amount: "40",
      taxes: "40"
    })

    # The frozen holder would have paid the custody charge too, so it stays
    # inside the return on both sides -- whichever column it was recorded in.
    assert Decimal.equal?(costs_on(w, ~D[2026-03-01]), Decimal.new("0"))
    assert Decimal.equal?(costs_on(w, ~D[2026-03-02]), Decimal.new("0"))
  end

  test "dividend withholding is not a trade cost" do
    w = world()

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-01-01],
      gross_amount: "10000"
    })

    book!(w, %{
      cash_account_id: w.cash.id,
      securities_account_id: w.depot.id,
      security_id: w.security.id,
      type: "buy",
      date: ~D[2026-01-05],
      quantity: "10",
      price: "100",
      gross_amount: "1000"
    })

    book!(w, %{
      cash_account_id: w.cash.id,
      security_id: w.security.id,
      type: "dividend",
      date: ~D[2026-04-01],
      gross_amount: "50",
      taxes: "13"
    })

    assert Decimal.equal?(costs_on(w, ~D[2026-04-01]), Decimal.new("0"))
  end

  test "a sell's costs count as well as a buy's" do
    w = world()

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-01-01],
      gross_amount: "10000"
    })

    book!(w, %{
      cash_account_id: w.cash.id,
      securities_account_id: w.depot.id,
      security_id: w.security.id,
      type: "buy",
      date: ~D[2026-01-05],
      quantity: "10",
      price: "100",
      gross_amount: "1000"
    })

    book!(w, %{
      cash_account_id: w.cash.id,
      securities_account_id: w.depot.id,
      security_id: w.security.id,
      type: "sell",
      date: ~D[2026-05-05],
      quantity: "4",
      price: "120",
      gross_amount: "472",
      fees: "5",
      taxes: "3"
    })

    assert Decimal.equal?(costs_on(w, ~D[2026-05-05]), Decimal.new("8"))
  end
end
