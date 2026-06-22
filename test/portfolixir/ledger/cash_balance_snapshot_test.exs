defmodule Portfolixir.Ledger.CashBalanceSnapshotTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  # User story:
  # As a local portfolio maintainer,
  # I want to set a cash account's balance to an absolute figure as of a date,
  # so that I can keep external cash current without mirroring every booking.
  #
  # Acceptance criteria:
  # - A balance snapshot anchors the account to the stated amount as of its date.
  # - Only bookings dated strictly after the snapshot adjust the balance;
  #   same-date or earlier bookings are considered already reflected in it.
  # - The amount may be negative (an overdraft); the latest snapshot wins.

  defp setup_account do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "P",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    %{portfolio: portfolio, cash: cash}
  end

  defp cash_tx!(portfolio, cash, type, amount, date) do
    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: type,
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })
  end

  defp balance(opts, cash_id) do
    opts |> Ledger.cash_balances() |> Map.fetch!(cash_id)
  end

  test "anchors the balance to a snapshot and applies only later bookings" do
    %{portfolio: portfolio, cash: cash} = setup_account()

    # Historic booking before the snapshot: ignored once anchored.
    cash_tx!(portfolio, cash, "deposit", "1000", ~D[2026-01-01])

    assert {:ok, snapshot} =
             Ledger.set_cash_balance(cash, %{"date" => "2026-06-01", "amount" => "4250"})

    assert snapshot.type == "balance_adjustment"
    assert Decimal.equal?(snapshot.gross_amount, Decimal.new("4250"))

    # Same-date booking: already reflected in the stated balance.
    cash_tx!(portfolio, cash, "deposit", "100", ~D[2026-06-01])
    # Later booking: adjusts the anchored balance.
    cash_tx!(portfolio, cash, "removal", "250", ~D[2026-06-05])

    assert Decimal.equal?(balance([portfolio_id: portfolio.id], cash.id), Decimal.new("4000"))
  end

  test "accepts a negative snapshot balance (overdraft)" do
    %{cash: cash} = setup_account()

    assert {:ok, _} = Ledger.set_cash_balance(cash, %{"date" => "2026-06-01", "amount" => "-50"})

    assert Decimal.equal?(balance([], cash.id), Decimal.new("-50"))
  end

  test "the latest snapshot wins" do
    %{cash: cash} = setup_account()

    {:ok, _} = Ledger.set_cash_balance(cash, %{"date" => "2026-05-01", "amount" => "1000"})
    {:ok, _} = Ledger.set_cash_balance(cash, %{"date" => "2026-06-01", "amount" => "2000"})

    assert Decimal.equal?(balance([], cash.id), Decimal.new("2000"))
  end
end
