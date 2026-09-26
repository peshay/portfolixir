defmodule Portfolixir.Ledger.SettlementGuardTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  # Risk-tier (ADR-0036): a ledger invariant. Every fixture is an exact
  # Decimal; the tolerance boundary is pinned on both sides.

  defp world do
    world = base_world(name: "Guard", cash_name: "EUR Cash", depot_name: "Depot")

    Map.put(
      world,
      :security,
      create_security!(name: "US Guard Co", ticker: "USG", currency: "USD")
    )
  end

  defp trade(w, type, overrides) do
    base = %{
      portfolio_id: w.portfolio.id,
      securities_account_id: w.depot.id,
      cash_account_id: w.cash.id,
      security_id: w.security.id,
      type: type,
      date: ~D[2026-04-01],
      quantity: Decimal.new("10"),
      price: Decimal.new("200.00"),
      currency_code: "USD",
      security_amount: Decimal.new("2000.00"),
      settlement_amount: Decimal.new("1818.18"),
      settlement_fx_rate: Decimal.new("0.90909"),
      fees: Decimal.new("4.90"),
      taxes: Decimal.new("0")
    }

    Ledger.create_transaction(Actor.owner_ui(), Map.merge(base, overrides))
  end

  defp gross_error(changeset), do: errors_on(changeset)[:gross_amount]

  # User story (#395, owner decision 2026-07-19):
  # As the operator booking a USD security through a EUR cash account,
  # I want the cash the booking moves to agree with the settlement it records,
  # so that a typo in either figure cannot leave the cash balance and the cost
  # basis telling two different stories.
  #
  # Acceptance criteria:
  # - A cross-currency buy's cash amount (`gross_amount`, inclusive of fees and
  #   taxes) equals the settlement amount plus fees and taxes; a sell's (net
  #   of them) equals the settlement amount minus fees and taxes.
  # - "Equals" is within ADR-0016's tolerance: one minor unit (0.01) at the
  #   money scale, checked at full precision — 0.01 off passes, 0.02 fails.
  # - A mismatch is a changeset error on `gross_amount` naming the amount the
  #   settlement implies; nothing is corrected silently.
  # - A same-currency booking (no settlement amount) is untouched.
  describe "the guard on a cross-currency trade" do
    test "a buy's cash is the settlement plus fees and taxes, within one cent" do
      w = world()

      assert {:ok, %Transaction{}} = trade(w, "buy", %{gross_amount: Decimal.new("1823.08")})
      assert {:ok, %Transaction{}} = trade(w, "buy", %{gross_amount: Decimal.new("1823.09")})
      assert {:ok, %Transaction{}} = trade(w, "buy", %{gross_amount: Decimal.new("1823.07")})

      assert {:error, changeset} = trade(w, "buy", %{gross_amount: Decimal.new("1823.10")})
      assert [message] = gross_error(changeset)
      assert message =~ "1823.08"

      # The trade value alone, fees forgotten, is the typo the guard exists for.
      assert {:error, changeset} = trade(w, "buy", %{gross_amount: Decimal.new("1818.18")})
      assert [_message] = gross_error(changeset)
    end

    test "a sell's cash is the settlement net of fees and taxes" do
      w = world()

      overrides = %{taxes: Decimal.new("12.50"), fees: Decimal.new("5.00")}

      assert {:ok, %Transaction{}} =
               trade(w, "sell", Map.put(overrides, :gross_amount, Decimal.new("1800.68")))

      assert {:error, changeset} =
               trade(w, "sell", Map.put(overrides, :gross_amount, Decimal.new("1818.18")))

      assert [message] = gross_error(changeset)
      assert message =~ "1800.68"
    end

    # Closing act, edge-case hunter (hostile input): the legs are magnitudes
    # like every other amount; a negative settlement with an explicit rate
    # could otherwise meet the guard with fees larger than the trade.
    test "the settlement legs are never negative" do
      w = world()

      assert {:error, changeset} =
               trade(w, "buy", %{
                 settlement_amount: Decimal.new("-5"),
                 security_amount: Decimal.new("-5.50"),
                 fees: Decimal.new("10"),
                 gross_amount: Decimal.new("5")
               })

      errors = errors_on(changeset)
      assert errors[:settlement_amount]
      assert errors[:security_amount]
    end

    test "a same-currency trade carries no settlement and is not checked" do
      w = world()
      usd = create_security!(name: "EUR Guard Co", ticker: "EUG", currency: "EUR")

      assert {:ok, %Transaction{}} =
               trade(w, "buy", %{
                 security_id: usd.id,
                 currency_code: "EUR",
                 security_amount: nil,
                 settlement_amount: nil,
                 settlement_fx_rate: nil,
                 gross_amount: Decimal.new("123.45")
               })
    end

    test "the arithmetic is exact at full precision" do
      assert SettlementGuard.tolerance() == Decimal.new("0.01")

      assert Decimal.equal?(
               SettlementGuard.expected_cash(
                 "buy",
                 Decimal.new("1818.181818"),
                 Decimal.new("4.90"),
                 Decimal.new("0.000001")
               ),
               Decimal.new("1823.081819")
             )

      assert Decimal.equal?(
               SettlementGuard.expected_cash(
                 "sell",
                 Decimal.new("1818.181818"),
                 Decimal.new("5"),
                 Decimal.new("12.5")
               ),
               Decimal.new("1800.681818")
             )

      assert SettlementGuard.expected_cash("dividend", Decimal.new("1"), Decimal.new("0"), nil) ==
               nil
    end
  end

  # Acceptance criteria (closing act, fix round B): a row derived from its cash
  # amount — the Portfolio Performance import, the settlement backfill — meets
  # the guard by construction: `trade_amount/4` is the guard's relation
  # inverted, for a buy and for a sell, exactly.
  test "the trade amount read off the cash round-trips through the guard" do
    gross = Decimal.new("1021.37")
    fees = Decimal.new("4.90")
    taxes = Decimal.new("12.05")

    buy = SettlementGuard.trade_amount("buy", gross, fees, taxes)
    sell = SettlementGuard.trade_amount("sell", gross, fees, taxes)

    assert Decimal.equal?(buy, Decimal.new("1004.42"))
    assert Decimal.equal?(sell, Decimal.new("1038.32"))
    assert Decimal.equal?(SettlementGuard.expected_cash("buy", buy, fees, taxes), gross)
    assert Decimal.equal?(SettlementGuard.expected_cash("sell", sell, fees, taxes), gross)
    assert SettlementGuard.trade_amount("dividend", gross, fees, taxes) == nil
    assert SettlementGuard.trade_amount("buy", nil, fees, taxes) == nil
  end

  # User story (plan D-5):
  # As the operator editing the note of an old cross-currency booking,
  # I want the edit to go through,
  # so that a rule added in Sprint 15 does not turn a harmless correction of a
  # row that predates it into a refused write.
  #
  # Acceptance criteria:
  # - The guard runs on insert, and on an update that changes gross_amount,
  #   settlement_amount, fees, taxes or the type.
  # - An update that changes none of them — the note, the date — is not
  #   re-checked; an existing row is never revalidated behind the operator's
  #   back.
  # - The read-only check lists such a row and rewrites nothing.
  describe "when the guard runs (D-5)" do
    setup do
      w = world()
      {:ok, tx} = trade(w, "buy", %{gross_amount: Decimal.new("1823.08")})

      # A row that predates the guard and misses it: written past the
      # changeset, the way history already in a database looks.
      {:ok, {1, _}} =
        Repo.transaction(fn ->
          {type, _label} = Actor.to_columns(Actor.owner_ui())
          Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])

          Transaction
          |> where(id: ^tx.id)
          |> Repo.update_all(set: [gross_amount: Decimal.new("1818.18")])
        end)

      %{legacy: Repo.get!(Transaction, tx.id), world: w}
    end

    test "an edit that touches no amount is not re-checked", %{legacy: legacy} do
      assert {:ok, updated} =
               Ledger.update_transaction(Actor.owner_ui(), legacy, %{notes: "re-read the note"})

      assert updated.notes == "re-read the note"

      assert {:ok, _} =
               Ledger.update_transaction(Actor.owner_ui(), updated, %{date: ~D[2026-04-02]})
    end

    test "an edit that touches an amount or the type is", %{legacy: legacy} do
      for attrs <- [
            %{fees: Decimal.new("5.00")},
            %{taxes: Decimal.new("0.10")},
            %{settlement_amount: Decimal.new("1818.19")},
            %{gross_amount: Decimal.new("1818.19")},
            %{type: "sell"}
          ] do
        assert {:error, changeset} = Ledger.update_transaction(Actor.owner_ui(), legacy, attrs),
               "#{inspect(attrs)} was not re-checked"

        assert [_message] = gross_error(changeset)
      end

      # And the repair itself passes.
      assert {:ok, _} =
               Ledger.update_transaction(Actor.owner_ui(), legacy, %{
                 gross_amount: Decimal.new("1823.08")
               })
    end

    test "the read-only check lists the row and rewrites nothing", %{legacy: legacy} do
      assert [row] = SettlementGuard.violations()
      assert row.id == legacy.id
      assert Decimal.equal?(row.gross_amount, Decimal.new("1818.18"))
      assert Decimal.equal?(row.expected_cash, Decimal.new("1823.08"))
      assert Decimal.equal?(row.difference, Decimal.new("-4.90"))

      assert Decimal.equal?(
               Repo.get!(Transaction, legacy.id).gross_amount,
               Decimal.new("1818.18")
             )
    end
  end

  # E25 S6 (#891), F71 (risk-tier: the cash projection). Without a cash
  # amount the projection books quantity × price, plus fees and taxes on a
  # buy and less them on a sale, into the account — and the guard used to
  # skip such a row, so a cross-currency trade priced in the security's
  # currency booked that currency's units as the account's cash. The guard
  # now compares the settlement with the cash the projection will book.
  describe "a cross-currency trade without a cash amount (F71)" do
    # User story:
    # As the agent booking a USD security through a EUR cash account,
    # I want a trade sent without its cash amount checked against the cash
    # the ledger will book from quantity × price,
    # so that a trade priced in dollars never moves dollars' worth of euros.
    #
    # Acceptance criteria:
    # - A buy or a sell without gross_amount whose quantity × price (with
    #   fees and taxes) misses the settlement's cash by more than 0.01 is
    #   refused, the error on gross_amount naming both amounts.
    # - Nothing is written.
    test "a trade lacking gross whose quantity × price misses the settlement is refused" do
      w = world()

      assert {:error, changeset} = trade(w, "buy", %{})
      assert [message] = gross_error(changeset)
      assert message =~ "2004.9"
      assert message =~ "1823.08"

      assert {:error, changeset} =
               trade(w, "sell", %{taxes: Decimal.new("12.50"), fees: Decimal.new("5.00")})

      assert [message] = gross_error(changeset)
      assert message =~ "1982.5"
      assert message =~ "1800.68"

      assert Repo.all(Transaction) |> Enum.filter(&(&1.security_id == w.security.id)) == []
    end

    # Acceptance criteria:
    # - A trade without gross_amount whose quantity × price is the
    #   settlement — the shape the settlement backfill and the Portfolio
    #   Performance import store for a row without a cash amount — passes,
    #   and its update of the note is not re-checked.
    test "a legacy trade whose quantity × price is its settlement still passes" do
      w = world()

      assert {:ok, tx} =
               trade(w, "buy", %{
                 price: Decimal.new("181.818"),
                 currency_code: "EUR",
                 settlement_amount: Decimal.new("1818.18")
               })

      assert tx.gross_amount == nil
      assert {:ok, _} = Ledger.update_transaction(Actor.owner_ui(), tx, %{notes: "backfilled"})
    end

    # Acceptance criteria:
    # - Without a cash amount, a change of quantity or price changes the
    #   cash booked, so it is re-checked; with one, it is not (D-5).
    test "without a cash amount a quantity or price edit is re-checked" do
      w = world()

      {:ok, tx} =
        trade(w, "buy", %{
          price: Decimal.new("181.818"),
          currency_code: "EUR",
          settlement_amount: Decimal.new("1818.18")
        })

      assert {:error, changeset} =
               Ledger.update_transaction(Actor.owner_ui(), tx, %{price: Decimal.new("200.00")})

      assert [_message] = gross_error(changeset)

      {:ok, with_gross} = trade(w, "buy", %{gross_amount: Decimal.new("1823.08")})

      assert {:ok, _} =
               Ledger.update_transaction(Actor.owner_ui(), with_gross, %{
                 price: Decimal.new("201.00")
               })
    end

    # Acceptance criteria:
    # - The read-only check lists a stored trade without gross_amount whose
    #   booked cash misses its settlement, with the booked amount as its
    #   gross and the difference, and rewrites nothing.
    test "the read-only check lists a stored trade lacking gross that misses" do
      w = world()

      {:ok, tx} =
        trade(w, "buy", %{
          price: Decimal.new("181.818"),
          currency_code: "EUR",
          settlement_amount: Decimal.new("1818.18")
        })

      {:ok, {1, _}} =
        Repo.transaction(fn ->
          {type, _label} = Actor.to_columns(Actor.owner_ui())
          Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])

          Transaction
          |> where(id: ^tx.id)
          |> Repo.update_all(set: [price: Decimal.new("200.00")])
        end)

      assert [row] = SettlementGuard.violations()
      assert row.id == tx.id
      assert row.gross_amount == nil
      assert Decimal.equal?(row.booked_cash, Decimal.new("2004.90"))
      assert Decimal.equal?(row.expected_cash, Decimal.new("1823.08"))
      assert Decimal.equal?(row.difference, Decimal.new("181.82"))
    end
  end
end
