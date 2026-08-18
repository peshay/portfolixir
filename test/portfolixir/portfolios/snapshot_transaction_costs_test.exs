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

  defp buy!(w, date, qty, price, opts \\ []) do
    gross = Decimal.mult(Decimal.new(qty), Decimal.new(price))

    book!(w, %{
      cash_account_id: w.cash.id,
      securities_account_id: w.depot.id,
      security_id: w.security.id,
      type: "buy",
      date: date,
      quantity: qty,
      price: price,
      gross_amount: Decimal.to_string(gross, :normal),
      fees: Keyword.get(opts, :fees, "0"),
      taxes: Keyword.get(opts, :taxes, "0")
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

  defp seeded_world(trade_opts) do
    w = world()

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-01-01],
      gross_amount: "10000"
    })

    buy!(w, ~D[2026-01-02], "10", "100")

    put_quote!(w.security, ~D[2026-01-02], "100")
    put_quote!(w.security, ~D[2026-03-01], "100")
    put_quote!(w.security, @today, "110")

    snapshot = snapshot!(w, ~D[2026-03-01])

    # A trade INSIDE the window, carrying the costs under test.
    buy!(w, ~D[2026-03-15], "5", "100", trade_opts)

    {w, snapshot}
  end

  test "the comparison carries the cost total, the pre-cost return and a recovery state" do
    {w, snapshot} = seeded_world(fees: "30", taxes: "20")

    result = compare(w, snapshot)

    # §2: the total is the window's trade fees plus taxes, in base currency.
    assert Decimal.equal?(result.transaction_costs, Decimal.new("50"))

    # §2: the pre-cost return is the same walk without those costs, so it is
    # strictly ahead of the net one whenever costs were paid.
    assert Decimal.compare(result.real_ttwror_before_costs, result.real_ttwror) == :gt

    # §3: one of exactly three states.
    assert result.cost_recovery.state in [:recovered, :partly_recovered, :not_recovered]
  end

  test "a window without trades costs nothing and is never 'partly recovered'" do
    {w, snapshot} = seeded_world(fees: "0", taxes: "0")

    result = compare(w, snapshot)

    assert Decimal.equal?(result.transaction_costs, Decimal.new("0"))

    # With no costs the two returns are the same figure, so the middle state
    # -- "ahead before costs, behind after" -- cannot arise.
    assert Decimal.equal?(result.real_ttwror_before_costs, result.real_ttwror)
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

  # §3, the state that is the reason for building this: the changes are ahead
  # of the frozen holdings on their own merits, but the trading costs have not
  # been earned back yet.
  test "partly recovered names the gap that is still outstanding" do
    {w, snapshot} = seeded_world(fees: "5000", taxes: "0")

    result = compare(w, snapshot)

    assert result.cost_recovery.state == :partly_recovered
    assert %Decimal{} = result.cost_recovery.outstanding
    assert Decimal.compare(result.cost_recovery.outstanding, Decimal.new("0")) == :gt
  end

  # §5: the payload states its basis, so a reader never has to infer which
  # costs left the return and which stayed in it.
  test "the payload states its computation basis" do
    {w, snapshot} = seeded_world(fees: "30", taxes: "20")

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
