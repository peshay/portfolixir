defmodule Portfolixir.Ledger.LedgerPropertyTest do
  @moduledoc """
  StreamData property tests for the ledger's money invariants.

  These assert behaviour that must hold for *every* valid combination of
  bookings, not just the hand-picked rows of the example-based suites:

    * cash legs fold to a balance that exactly reconciles with an independent
      Decimal sum of the signed gross amounts (no projection-vs-fold drift);
    * the per-account fold sums, across all accounts, to the same total no
      matter the booking order (no rounding drift across the projection);
    * the real `Transaction` changeset rejects negative magnitudes for the
      quantity/price/fee/tax fields it constrains as positive, for every kind,
      while a `balance_adjustment` snapshot still accepts a negative
      `gross_amount` (an overdraft balance, ADR-0009).

  Generators are small and bounded (a handful of bookings, 2-decimal amounts)
  so the suite stays fast, and every assertion is exact — `Decimal.equal?` or
  exact equality, never a tolerance.
  """
  use Portfolixir.DataCase, async: false
  use ExUnitProperties

  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios

  @runs 25
  @zero Decimal.new("0")

  # Cash-only inflow/outflow kinds whose single cash leg is +/- gross_amount.
  # Excludes balance_adjustment (an absolute {:set} anchor, not a delta).
  @inflow_kinds ["deposit", "interest", "tax_refund"]
  @outflow_kinds ["removal", "fee", "tax"]

  # A positive 2-decimal money magnitude in a bounded range, as a Decimal.
  defp money do
    gen all(cents <- integer(1..1_000_000)) do
      cents |> Decimal.new() |> Decimal.div(100) |> Decimal.round(2)
    end
  end

  defp booking_date do
    gen all(offset <- integer(0..400)) do
      Date.add(~D[2024-01-01], offset)
    end
  end

  defp cash_booking do
    gen all(
          kind <- member_of(@inflow_kinds ++ @outflow_kinds),
          amount <- money(),
          date <- booking_date()
        ) do
      %{kind: kind, amount: amount, date: date}
    end
  end

  defp signed_delta(%{kind: kind, amount: amount}) when kind in @inflow_kinds, do: amount

  defp signed_delta(%{kind: kind, amount: amount}) when kind in @outflow_kinds,
    do: Decimal.negate(amount)

  defp setup_account do
    {:ok, portfolio} = Portfolios.create_portfolio(%{name: "Prop", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR"
      })

    {portfolio, cash}
  end

  defp insert_booking(portfolio, cash, %{kind: kind, amount: amount, date: date}) do
    {:ok, _tx} =
      Ledger.create_transaction(%{
        type: kind,
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        currency_code: "EUR",
        date: date,
        gross_amount: amount
      })
  end

  # User story:
  # As a maintainer relying on derived cash balances,
  # I want every valid sequence of cash bookings to fold to a balance that
  # exactly matches an independent Decimal sum of the signed amounts,
  # so that the projection can never drift from the source bookings or lose a
  # cent to rounding.
  #
  # Acceptance criteria:
  # - For any generated booking sequence, `Ledger.cash_balances/1` for the
  #   account equals the exact Decimal fold of the signed gross amounts.
  # - The reconciliation is exact (`Decimal.equal?`), never tolerance-based.
  property "cash legs fold to a balance that reconciles exactly with the signed amounts" do
    check all(
            bookings <- list_of(cash_booking(), min_length: 1, max_length: 8),
            max_runs: @runs
          ) do
      Repo.transaction(fn ->
        {portfolio, cash} = setup_account()

        Enum.each(bookings, &insert_booking(portfolio, cash, &1))

        derived =
          Ledger.cash_balances(portfolio_id: portfolio.id)
          |> Map.get(cash.id, @zero)

        expected =
          Enum.reduce(bookings, @zero, fn booking, acc ->
            Decimal.add(acc, signed_delta(booking))
          end)

        assert Decimal.equal?(derived, expected)

        Repo.rollback(:done)
      end)
    end
  end

  # User story:
  # As a maintainer reconciling a multi-account portfolio,
  # I want the per-account cash balances to sum to the same grand total
  # regardless of the order the bookings were entered,
  # so that no projection ordering quietly changes my books.
  #
  # Acceptance criteria:
  # - Summing every account balance equals the signed total of all bookings.
  # - Shuffling the booking order yields a byte-identical grand total.
  property "per-account balances sum to an order-independent grand total" do
    check all(
            bookings <- list_of(cash_booking(), min_length: 1, max_length: 8),
            shuffled <- shuffle_of(bookings),
            max_runs: @runs
          ) do
      grand_total = fn ordered ->
        Repo.transaction(fn ->
          {portfolio, cash} = setup_account()
          Enum.each(ordered, &insert_booking(portfolio, cash, &1))

          total =
            Ledger.cash_balances(portfolio_id: portfolio.id)
            |> Map.values()
            |> Enum.reduce(@zero, &Decimal.add(&2, &1))

          Repo.rollback({:total, total})
        end)
        |> case do
          {:error, {:total, total}} -> total
        end
      end

      expected =
        Enum.reduce(bookings, @zero, fn booking, acc ->
          Decimal.add(acc, signed_delta(booking))
        end)

      assert Decimal.equal?(grand_total.(bookings), expected)
      assert Decimal.equal?(grand_total.(shuffled), expected)
    end
  end

  # A deterministic generator that yields a permutation of the given list.
  defp shuffle_of(list) do
    gen all(seed <- integer()) do
      :rand.seed(:exsss, {seed, seed + 1, seed + 2})
      Enum.shuffle(list)
    end
  end

  # User story:
  # As a maintainer entering bookings,
  # I want the transaction changeset to reject negative magnitudes for the
  # quantity/price/fee/tax fields for every kind that carries them,
  # so that a sign error can never corrupt a position or a fee.
  #
  # Acceptance criteria:
  # - A negative `fees` or `taxes` is rejected for any cash kind.
  # - A negative `quantity` or `price` is rejected for a buy.
  property "the changeset rejects negative magnitudes for the constrained fields" do
    check all(
            amount <- money(),
            magnitude <- money(),
            date <- booking_date(),
            max_runs: @runs
          ) do
      negative = Decimal.negate(magnitude)

      # Negative fee on a cash kind.
      neg_fee =
        Transaction.changeset(%Transaction{}, %{
          type: "deposit",
          portfolio_id: 1,
          cash_account_id: 1,
          currency_code: "EUR",
          date: date,
          gross_amount: amount,
          fees: negative
        })

      refute neg_fee.valid?
      assert {_msg, _} = neg_fee.errors[:fees]

      # Negative tax on a cash kind.
      neg_tax =
        Transaction.changeset(%Transaction{}, %{
          type: "tax",
          portfolio_id: 1,
          cash_account_id: 1,
          currency_code: "EUR",
          date: date,
          gross_amount: amount,
          taxes: negative
        })

      refute neg_tax.valid?
      assert {_msg, _} = neg_tax.errors[:taxes]

      # Negative quantity / price on a buy.
      neg_qty =
        Transaction.changeset(%Transaction{}, %{
          type: "buy",
          portfolio_id: 1,
          security_id: 1,
          securities_account_id: 1,
          cash_account_id: 1,
          currency_code: "EUR",
          date: date,
          quantity: negative,
          price: amount
        })

      refute neg_qty.valid?
      assert {_msg, _} = neg_qty.errors[:quantity]

      neg_price =
        Transaction.changeset(%Transaction{}, %{
          type: "buy",
          portfolio_id: 1,
          security_id: 1,
          securities_account_id: 1,
          cash_account_id: 1,
          currency_code: "EUR",
          date: date,
          quantity: amount,
          price: negative
        })

      refute neg_price.valid?
      assert {_msg, _} = neg_price.errors[:price]
    end
  end

  # User story:
  # As a maintainer relying on the "amounts are positive magnitudes" invariant,
  # I want the changeset to reject a negative `gross_amount` for every cash kind
  # whose sign comes from the kind (deposit/removal/interest/fee/tax/tax_refund),
  # so that a sign-flipping amount can never enter through the API/MCP/manual path
  # and corrupt the derived balance (project invariant #3; balance_adjustment is
  # the sole exception, asserted separately).
  #
  # Acceptance criteria:
  # - For each such cash kind, a negative `gross_amount` makes the changeset
  #   invalid with a `gross_amount` error.
  property "the changeset rejects a negative gross_amount for sign-from-kind cash kinds" do
    {portfolio, cash} = setup_account()

    check all(
            kind <- member_of(@inflow_kinds ++ @outflow_kinds),
            magnitude <- money(),
            date <- booking_date(),
            max_runs: @runs
          ) do
      changeset =
        Transaction.changeset(%Transaction{}, %{
          type: kind,
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          currency_code: "EUR",
          date: date,
          gross_amount: Decimal.negate(magnitude)
        })

      refute changeset.valid?, "#{kind} accepted a negative gross_amount"
      assert {_msg, _} = changeset.errors[:gross_amount]
    end
  end

  # User story:
  # As a maintainer recording an overdraft,
  # I want a `balance_adjustment` snapshot to accept a negative `gross_amount`,
  # so that a drawn credit line or overdrawn account can be stated honestly
  # (ADR-0009), unlike the magnitude fields above.
  #
  # Acceptance criteria:
  # - A `balance_adjustment` changeset with a negative `gross_amount` is valid.
  # - The projection anchors the account to that exact negative balance.
  property "balance_adjustment accepts and anchors a negative gross_amount" do
    check all(magnitude <- money(), date <- booking_date(), max_runs: @runs) do
      negative = Decimal.negate(magnitude)

      changeset =
        Transaction.changeset(%Transaction{}, %{
          type: "balance_adjustment",
          portfolio_id: 1,
          cash_account_id: 1,
          currency_code: "EUR",
          date: date,
          gross_amount: negative
        })

      assert changeset.valid?

      effect =
        Projection.effects(%{
          type: "balance_adjustment",
          cash_account_id: 7,
          gross_amount: negative
        })

      assert [{7, {:set, anchored}}] = effect.cash
      assert Decimal.equal?(anchored, negative)
    end
  end
end
