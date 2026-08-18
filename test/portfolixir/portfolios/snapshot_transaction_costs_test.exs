defmodule Portfolixir.Portfolios.SnapshotTransactionCostsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.SnapshotComparison
  alias Portfolixir.Portfolios.Snapshots

  # User story (#708, ADR-0027 amendment of 2026-08-15):
  # As a maintainer who restructured a depot,
  # I want to see what the trades cost and whether they have been earned back,
  # so that "were the changes right?" and "have they paid for themselves yet?"
  # stop being answered by one number that cannot serve both.
  #
  # Acceptance criteria (§2, §3, §4, §5):
  # - The comparison carries the real return BEFORE transaction costs: the same
  #   daily walk with window trade fees/taxes reclassified as external flows.
  # - It carries the transaction-cost total in the base currency.
  # - It carries a three-state recovery: recovered / partly_recovered /
  #   not_recovered.
  # - Only trades INSIDE the window count.
  # - The payload states its basis: window, which cost kinds were removed and
  #   which were kept, base currency, and that the frozen side is price-return
  #   only.

  @today ~D[2026-06-30]

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

  # A buy's gross_amount is INCLUSIVE of its fees and taxes
  # (`Projection.buy_cost/1`). A fixture that passes a bare quantity x price
  # beside a non-zero fee describes a trade whose fee never leaves the cash
  # account — and then the pre-cost figure removes a cost nobody paid, which
  # is how an earlier draft of this file produced a +103 % pre-cost return
  # without failing.
  defp buy!(w, date, qty, price, opts \\ []) do
    fees = Keyword.get(opts, :fees, "0")
    taxes = Keyword.get(opts, :taxes, "0")

    gross =
      Decimal.new(qty)
      |> Decimal.mult(Decimal.new(price))
      |> Decimal.add(Decimal.new(fees))
      |> Decimal.add(Decimal.new(taxes))

    book!(w, %{
      cash_account_id: w.cash.id,
      securities_account_id: w.depot.id,
      security_id: w.security.id,
      type: "buy",
      date: date,
      quantity: qty,
      price: price,
      gross_amount: Decimal.to_string(gross, :normal),
      fees: fees,
      taxes: taxes
    })
  end

  defp snapshot!(w, as_of) do
    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{
        name: "Before",
        as_of: as_of,
        portfolio_id: w.portfolio.id
      })

    snapshot
  end

  defp compare(w, snapshot) do
    {:ok, result} = SnapshotComparison.for_snapshot(snapshot, w.portfolio.id, today: @today)
    result
  end

  # A hand-computable world, and every figure below is checked against the
  # arithmetic rather than against "bigger than the other one".
  #
  #   as-of 2026-03-01: 10 shares at 100 = 1,000, no cash.
  #   frozen side  -> 10 x 110 = 1,100 today, so +10 % exactly.
  #   in-window    -> deposit `funding`, buy 2 at 100 with `fees`. Because
  #                   gross_amount is INCLUSIVE of the fee (Projection.buy_cost),
  #                   an exactly-funded top-up leaves no cash behind.
  #
  # On the trade day: net factor 1,200 / (1,000 + 210) and pre-cost factor
  # 1,200 / (1,000 + 210 - 10) = exactly 1. Then 1,320 / 1,200 to today.
  defp seeded_world(fees) do
    w = world()
    fee = Decimal.new(fees)
    funding = Decimal.add(Decimal.new("200"), fee)

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-01-01],
      gross_amount: "1000"
    })

    buy!(w, ~D[2026-01-02], "10", "100")

    put_quote!(w.security, ~D[2026-01-02], "100")
    put_quote!(w.security, ~D[2026-03-01], "100")
    put_quote!(w.security, @today, "110")

    snapshot = snapshot!(w, ~D[2026-03-01])

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-03-15],
      gross_amount: Decimal.to_string(funding, :normal)
    })

    buy!(w, ~D[2026-03-15], "2", "100", fees: fees)

    {w, snapshot}
  end

  test "the comparison states the cost, the pre-cost return and the recovery" do
    {w, snapshot} = seeded_world("10")

    result = compare(w, snapshot)

    # Exact, because every step of this fixture is hand-computable.
    assert Decimal.equal?(result.transaction_costs, Decimal.new("10"))

    # The frozen side: 10 shares from 100 to 110.
    assert Decimal.equal?(result.snapshot_return, Decimal.new("0.1"))

    # Before costs the real side matches it EXACTLY -- the top-up was funded
    # to the cent, so the only thing separating the two sides is the fee. This
    # is the arithmetic check that a "pre is bigger than net" assertion cannot
    # make: it pins the value, not the direction.
    assert Decimal.equal?(result.real_ttwror_before_costs, Decimal.new("0.1"))

    # After costs: 1,320 / 1,210 - 1.
    assert Decimal.equal?(
             Decimal.round(result.real_ttwror, 10),
             Decimal.round(Decimal.div(Decimal.new("110"), Decimal.new("1210")), 10)
           )
  end

  # §3, and the reason the boundary is `>=` rather than `>`: with the two sides
  # equal before costs, the fee is the ENTIRE gap. Reporting "behind even
  # before costs" there would be false, and false in the direction that
  # discourages a correct decision.
  test "equal before costs is partly recovered, not 'behind even before costs'" do
    {w, snapshot} = seeded_world("10")

    recovery = compare(w, snapshot).cost_recovery

    assert recovery.state == :partly_recovered

    # The outstanding gap is frozen minus net, to the same precision.
    assert Decimal.equal?(
             Decimal.round(recovery.outstanding, 10),
             Decimal.round(
               Decimal.sub(
                 Decimal.new("0.1"),
                 Decimal.div(Decimal.new("110"), Decimal.new("1210"))
               ),
               10
             )
           )
  end

  test "a window without trade costs leaves the two returns identical" do
    {w, snapshot} = seeded_world("0")

    result = compare(w, snapshot)

    assert Decimal.equal?(result.transaction_costs, Decimal.new("0"))
    assert Decimal.equal?(result.real_ttwror_before_costs, result.real_ttwror)

    # With nothing paid the middle state cannot arise: there is no cost to be
    # the reason for a gap.
    refute result.cost_recovery.state == :partly_recovered
  end

  test "only trades inside the window count" do
    w = world()

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-01-01],
      gross_amount: "10000"
    })

    # A costly trade BEFORE the as-of date: already sunk when the snapshot was
    # taken, so it is not something the change since then cost.
    buy!(w, ~D[2026-01-02], "10", "100", fees: "500")

    put_quote!(w.security, ~D[2026-01-02], "100")
    put_quote!(w.security, ~D[2026-03-01], "100")
    put_quote!(w.security, @today, "110")

    snapshot = snapshot!(w, ~D[2026-03-01])

    assert Decimal.equal?(compare(w, snapshot).transaction_costs, Decimal.new("0"))
  end

  # §5: the payload states its basis, so a reader never has to infer which
  # costs left the return and which stayed in it.
  test "the payload states its computation basis" do
    {w, snapshot} = seeded_world("10")

    basis = compare(w, snapshot).basis

    assert basis.window == %{from: ~D[2026-03-01], to: @today}
    assert basis.base_currency == "EUR"
    assert basis.costs_removed == ["trade_fees", "trade_taxes"]
    assert "standalone_fees" in basis.costs_kept
    assert "standalone_taxes" in basis.costs_kept
    assert "dividend_withholding" in basis.costs_kept
    # Unchanged by this amendment, and still true of the frozen side.
    assert basis.price_return_only == true
  end
end
