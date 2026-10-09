defmodule Portfolixir.LockRace.SameCurrencyTest do
  # The same-currency booking check (#343, revised by ADR-0015) against a
  # currency change of the account it reads (#922), raced on two real
  # connections by the lock-order harness (#996).
  #
  # The invariant: a booking's currency agrees with its cash account's
  # currency as the account stands when the booking commits -- the same
  # currency, or a cross-currency settlement carrying its rate (ADR-0015),
  # and a transfer's counter account in the transfer's currency -- even
  # while the account's currency changes concurrently.
  #
  # The race: the identity-field freeze (ADR-0050 §11, §16 invariant 15)
  # locks the account row FOR UPDATE and counts committed references only.
  # A booking that read the account's currency without a lock passed its
  # check on the old currency, waited at its foreign-key check for the
  # freeze's lock, and committed once the change had committed: a booking in
  # a currency its account no longer has. Both writers now meet on the
  # account row: the booking reads it FOR KEY SHARE, in id order, inside its
  # transaction, and checks the currency the lock returns, so either the
  # change waits and is frozen by the booking, or the booking waits and
  # reads the new currency.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits, and need no other test's load on the cores.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.LockRace
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Repo

  @moduletag :lock_race

  # The freeze's own lock on the account row; the journal's FOR NO KEY
  # UPDATE before it does not conflict with a booking's key-share lock.
  defp freeze_lock, do: LockRace.query?("FOR UPDATE")

  # The booking's lock on the account rows it checks.
  defp booking_lock, do: LockRace.query?("FOR KEY SHARE")

  setup_all do
    %{db: LockRace.database!()}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  defp owner, do: Actor.owner_ui()

  # A portfolio with EUR cash accounts that nothing references yet -- no
  # booking, no depot -- so the freeze lets their currency change.
  defp world(name, cash_names) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(owner(), %{name: name, base_currency_code: "EUR"})

    accounts =
      Enum.map(cash_names, fn cash_name ->
        {:ok, cash} =
          Portfolios.create_cash_account(owner(), %{
            portfolio_id: portfolio.id,
            name: cash_name,
            currency_code: "EUR"
          })

        cash
      end)

    %{portfolio: portfolio, accounts: accounts}
  end

  defp to_usd(cash), do: Portfolios.update_cash_account(owner(), cash, %{currency_code: "USD"})

  defp deposit(portfolio, cash) do
    Ledger.create_transaction(owner(), %{
      type: "deposit",
      portfolio_id: portfolio.id,
      cash_account_id: cash.id,
      currency_code: "EUR",
      date: ~D[2026-01-05],
      gross_amount: Decimal.new("10")
    })
  end

  defp bookings_on(cash) do
    Repo.all(
      from(t in Transaction,
        where: t.cash_account_id == ^cash.id or t.counter_cash_account_id == ^cash.id,
        select: t.currency_code
      )
    )
  end

  defp currency(cash), do: Repo.get!(CashAccount, cash.id).currency_code

  # User story (#922; ADR-0050 §11; ADR-0036, risk-tier):
  # As the operator changing a cash account's currency while a booking onto
  # it is recorded,
  # I want the two writes to take turns on the account row,
  # so that no booking ever commits in a currency its account no longer has.
  #
  # Acceptance criteria:
  # - With the currency change held after the freeze's lock, a booking onto
  #   the account waits for it, reads the new currency and is refused as a
  #   cross-currency settlement without a rate.
  # - With the booking held after its lock, the currency change waits for it
  #   and is frozen by the booking it then counts.
  # - The same holds for a transfer's counter account, for an update that
  #   moves a booking onto the account, and for the importer's copy of the
  #   check. Neither writer deadlocks.
  test "a booking waits for a currency change of its account and is refused", %{db: db} do
    %{portfolio: portfolio, accounts: [cash]} = world("Race Change First", ["Change First"])

    {changed, booked} =
      LockRace.race!(db, {fn -> to_usd(cash) end, freeze_lock()}, fn ->
        deposit(portfolio, cash)
      end)

    assert {:ok, %CashAccount{currency_code: "USD"}} = changed
    assert {:error, changeset} = booked

    assert {"is required for a cross-currency settlement", _} =
             changeset.errors[:settlement_fx_rate]

    assert currency(cash) == "USD"
    assert bookings_on(cash) == []
  end

  test "a currency change waits for a booking onto its account and is frozen", %{db: db} do
    %{portfolio: portfolio, accounts: [cash]} = world("Race Booking First", ["Booking First"])

    {booked, changed} =
      LockRace.race!(db, {fn -> deposit(portfolio, cash) end, booking_lock()}, fn ->
        to_usd(cash)
      end)

    assert {:ok, %Transaction{currency_code: "EUR"}} = booked
    assert {:error, changeset} = changed
    assert {"is frozen once referenced (1 transaction)", _} = changeset.errors[:currency_code]
    assert currency(cash) == "EUR"
    assert bookings_on(cash) == ["EUR"]
  end

  test "a transfer waits for a currency change of its counter account and is refused",
       %{db: db} do
    %{portfolio: portfolio, accounts: [from, to]} =
      world("Race Counter", ["Counter From", "Counter To"])

    transfer = fn ->
      Ledger.create_transaction(owner(), %{
        type: "cash_transfer",
        portfolio_id: portfolio.id,
        cash_account_id: from.id,
        counter_cash_account_id: to.id,
        currency_code: "EUR",
        date: ~D[2026-01-05],
        gross_amount: Decimal.new("10")
      })
    end

    {changed, transferred} = LockRace.race!(db, {fn -> to_usd(to) end, freeze_lock()}, transfer)

    assert {:ok, %CashAccount{currency_code: "USD"}} = changed
    assert {:error, changeset} = transferred

    assert {"must match the transaction currency (%{currency})", [currency: "EUR"]} =
             changeset.errors[:counter_cash_account_id]

    assert currency(to) == "USD"
    assert bookings_on(to) == []
  end

  test "a booking moved onto an account waits for its currency change and is refused",
       %{db: db} do
    %{portfolio: portfolio, accounts: [home, target]} =
      world("Race Update", ["Update Home", "Update Target"])

    {:ok, booking} = deposit(portfolio, home)

    {changed, moved} =
      LockRace.race!(db, {fn -> to_usd(target) end, freeze_lock()}, fn ->
        Ledger.update_transaction(owner(), booking, %{cash_account_id: target.id})
      end)

    assert {:ok, %CashAccount{currency_code: "USD"}} = changed
    assert {:error, changeset} = moved

    assert {"is required for a cross-currency settlement", _} =
             changeset.errors[:settlement_fx_rate]

    assert currency(target) == "USD"
    assert bookings_on(target) == []
    assert bookings_on(home) == ["EUR"]
  end

  test "an import waits for a currency change of the account it books onto and is refused",
       %{db: db} do
    %{portfolio: portfolio, accounts: [cash]} = world("Race Import", ["Import Cash"])

    body =
      Jason.encode!(%{
        "version" => 1,
        "transactions" => [
          %{
            "type" => "DEPOSIT",
            "account" => "Import Cash",
            "date" => "2026-01-05",
            "currency" => "EUR",
            "amount" => Jason.Fragment.new("10.00")
          }
        ]
      })

    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")

    {changed, imported} =
      LockRace.race!(db, {fn -> to_usd(cash) end, freeze_lock()}, fn ->
        Imports.apply(preview, %{portfolio_id: portfolio.id})
      end)

    assert {:ok, %CashAccount{currency_code: "USD"}} = changed
    assert {:error, %{reason: {:insert_failed, changeset}}} = imported

    assert {"is required for a cross-currency settlement", _} =
             changeset.errors[:settlement_fx_rate]

    assert currency(cash) == "USD"
    assert bookings_on(cash) == []
  end
end
