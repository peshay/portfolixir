defmodule Portfolixir.Ledger.CashBalanceSeriesTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Portfolios

  # User story (#414):
  # As a maintainer reading one account's history,
  # I want each row to carry the balance the account stood at after that
  # booking,
  # so that I can follow the money down the page instead of adding it up
  # myself.
  #
  # Acceptance criteria:
  # - The balance after each booking is the SAME arithmetic the account
  #   balance uses, so the last row equals `Ledger.cash_balances/1`.
  # - The series is built in replay order (chronological, snapshots last within
  #   a day), never in display order.
  # - A balance snapshot RESETS the running balance rather than adding to it.
  # - Rows that do not touch the account carry no balance at all, rather than a
  #   repeated one.

  defp world do
    w = base_world(name: "Series", cash_name: "Cash", depot_name: "Depot")

    {:ok, other} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        name: "Other Cash",
        currency_code: "EUR"
      })

    Map.merge(w, %{other: other, security: create_security!(name: "Series AG", ticker: "SER")})
  end

  defp book!(w, attrs) do
    {:ok, tx} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        Map.merge(%{portfolio_id: w.portfolio.id, currency_code: "EUR"}, attrs)
      )

    tx
  end

  defp series(cash_account) do
    Projection.cash_balance_series(Ledger.list_transactions(), cash_account.id)
  end

  test "each booking carries the balance the account stood at after it" do
    w = world()

    deposit =
      book!(w, %{
        cash_account_id: w.cash.id,
        type: "deposit",
        date: ~D[2026-01-01],
        gross_amount: "1000"
      })

    buy =
      book!(w, %{
        cash_account_id: w.cash.id,
        securities_account_id: w.depot.id,
        security_id: w.security.id,
        type: "buy",
        date: ~D[2026-02-01],
        quantity: "2",
        price: "100",
        gross_amount: "200"
      })

    fee =
      book!(w, %{
        cash_account_id: w.cash.id,
        type: "fee",
        date: ~D[2026-03-01],
        gross_amount: "10"
      })

    balances = series(w.cash)

    assert Decimal.equal?(balances[deposit.id], Decimal.new("1000"))
    assert Decimal.equal?(balances[buy.id], Decimal.new("800"))
    assert Decimal.equal?(balances[fee.id], Decimal.new("790"))

    # The last row is the account balance: one arithmetic, not two.
    assert Decimal.equal?(balances[fee.id], Ledger.cash_balances()[w.cash.id])
  end

  test "the series follows replay order, not the order the rows were written" do
    w = world()

    # Booked newest-first; the series must still read 1000 -> 700.
    later =
      book!(w, %{
        cash_account_id: w.cash.id,
        type: "removal",
        date: ~D[2026-05-01],
        gross_amount: "300"
      })

    earlier =
      book!(w, %{
        cash_account_id: w.cash.id,
        type: "deposit",
        date: ~D[2026-04-01],
        gross_amount: "1000"
      })

    balances = series(w.cash)

    assert Decimal.equal?(balances[earlier.id], Decimal.new("1000"))
    assert Decimal.equal?(balances[later.id], Decimal.new("700"))
  end

  test "a balance snapshot resets the running balance instead of adding to it" do
    w = world()

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-01-01],
      gross_amount: "1000"
    })

    snapshot =
      book!(w, %{
        cash_account_id: w.cash.id,
        type: "balance_adjustment",
        date: ~D[2026-06-01],
        gross_amount: "42"
      })

    after_snapshot =
      book!(w, %{
        cash_account_id: w.cash.id,
        type: "deposit",
        date: ~D[2026-07-01],
        gross_amount: "8"
      })

    balances = series(w.cash)

    assert Decimal.equal?(balances[snapshot.id], Decimal.new("42"))
    assert Decimal.equal?(balances[after_snapshot.id], Decimal.new("50"))
  end

  test "a transaction that does not touch the account carries no balance" do
    w = world()

    mine =
      book!(w, %{
        cash_account_id: w.cash.id,
        type: "deposit",
        date: ~D[2026-01-01],
        gross_amount: "1000"
      })

    theirs =
      book!(w, %{
        cash_account_id: w.other.id,
        type: "deposit",
        date: ~D[2026-02-01],
        gross_amount: "500"
      })

    balances = series(w.cash)

    assert Map.has_key?(balances, mine.id)
    refute Map.has_key?(balances, theirs.id)
  end

  test "a cash transfer moves the balance on both of its accounts" do
    w = world()

    book!(w, %{
      cash_account_id: w.cash.id,
      type: "deposit",
      date: ~D[2026-01-01],
      gross_amount: "1000"
    })

    transfer =
      book!(w, %{
        cash_account_id: w.cash.id,
        counter_cash_account_id: w.other.id,
        type: "cash_transfer",
        date: ~D[2026-02-01],
        gross_amount: "250"
      })

    assert Decimal.equal?(series(w.cash)[transfer.id], Decimal.new("750"))
    assert Decimal.equal?(series(w.other)[transfer.id], Decimal.new("250"))
  end
end
