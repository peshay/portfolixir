defmodule Portfolixir.Ledger.ProjectionTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction

  # User story:
  # As a maintainer adding a new booking kind to the ledger,
  # I want each kind's cash, quantity and external-flow semantics defined in
  # exactly one reducer,
  # so that cash balances, positions and the performance walk pick the kind up
  # consistently without per-kind edits in every read model.
  #
  # Acceptance criteria:
  # - `Projection.effects/1` covers every kind in `Transaction.kinds/0` and
  #   raises for a kind it has not been taught — the single place to extend.
  # - The cash and positions read models are generic folds over the
  #   projection's effect legs: the loop tests below iterate over *all*
  #   supported kinds without naming one, so a new kind needs one reducer
  #   clause and no test or consumer change.
  # - Balance snapshots (ADR-0009) keep their anchor semantics through the
  #   fold: same-day bookings are absorbed, only later ones adjust, the
  #   latest snapshot wins.

  @cash 1
  @cash_b 2
  @depot 11
  @depot_b 12
  @security 21

  defp dec(value), do: Decimal.new(value)

  defp tx(kind, attrs \\ %{}) do
    Map.merge(
      %{
        id: 1,
        type: kind,
        date: ~D[2026-04-01],
        currency_code: "EUR",
        cash_account_id: nil,
        counter_cash_account_id: nil,
        securities_account_id: nil,
        counter_securities_account_id: nil,
        security_id: nil,
        quantity: nil,
        price: nil,
        fees: nil,
        taxes: nil,
        gross_amount: nil
      },
      attrs
    )
  end

  # One representative, fully-populated transaction per supported kind.
  defp representative("buy") do
    tx("buy", %{
      cash_account_id: @cash,
      securities_account_id: @depot,
      security_id: @security,
      quantity: dec("10"),
      price: dec("50"),
      fees: dec("5"),
      taxes: dec("2"),
      gross_amount: dec("507")
    })
  end

  defp representative("sell") do
    tx("sell", %{
      cash_account_id: @cash,
      securities_account_id: @depot,
      security_id: @security,
      quantity: dec("4"),
      price: dec("60"),
      fees: dec("3"),
      taxes: dec("1"),
      gross_amount: dec("236")
    })
  end

  defp representative(kind)
       when kind in ~w(dividend interest deposit removal fee tax tax_refund balance_adjustment) do
    tx(kind, %{cash_account_id: @cash, security_id: @security, gross_amount: dec("100")})
  end

  defp representative("cash_transfer") do
    tx("cash_transfer", %{
      cash_account_id: @cash,
      counter_cash_account_id: @cash_b,
      gross_amount: dec("50")
    })
  end

  defp representative(kind) when kind in ~w(inbound_delivery outbound_delivery) do
    tx(kind, %{securities_account_id: @depot, security_id: @security, quantity: dec("3")})
  end

  defp representative("security_transfer") do
    tx("security_transfer", %{
      securities_account_id: @depot,
      counter_securities_account_id: @depot_b,
      security_id: @security,
      quantity: dec("3")
    })
  end

  defp assert_legs(actual, expected) do
    assert length(actual) == length(expected)

    for {leg, expected_leg} <- Enum.zip(actual, expected) do
      assert_leg(leg, expected_leg)
    end
  end

  defp assert_leg({account_id, {op, amount}}, {expected_id, {expected_op, expected_amount}}) do
    assert account_id == expected_id
    assert op == expected_op
    assert Decimal.equal?(amount, expected_amount)
  end

  defp assert_leg({account_id, security_id, delta}, {expected_acct, expected_sec, expected_delta}) do
    assert account_id == expected_acct
    assert security_id == expected_sec
    assert Decimal.equal?(delta, expected_delta)
  end

  describe "effects/1 — the canonical per-kind table" do
    test "deposit and removal move cash and are external flows" do
      deposit = Projection.effects(representative("deposit"))
      assert_legs(deposit.cash, [{@cash, {:add, dec("100")}}])
      assert deposit.quantities == []
      assert deposit.external

      removal = Projection.effects(representative("removal"))
      assert_legs(removal.cash, [{@cash, {:add, dec("-100")}}])
      assert removal.quantities == []
      assert removal.external
    end

    test "dividend, interest and tax refund are internal cash credits" do
      for kind <- ~w(dividend interest tax_refund) do
        effect = Projection.effects(representative(kind))
        assert_legs(effect.cash, [{@cash, {:add, dec("100")}}])
        assert effect.quantities == []
        refute effect.external
      end
    end

    test "fee and tax are internal cash debits" do
      for kind <- ~w(fee tax) do
        effect = Projection.effects(representative(kind))
        assert_legs(effect.cash, [{@cash, {:add, dec("-100")}}])
        assert effect.quantities == []
        refute effect.external
      end
    end

    test "a buy debits its gross cost and adds quantity" do
      effect = Projection.effects(representative("buy"))
      assert_legs(effect.cash, [{@cash, {:add, dec("-507")}}])
      assert_legs(effect.quantities, [{@depot, @security, dec("10")}])
      refute effect.external
    end

    test "a sell credits its net proceeds and removes quantity" do
      effect = Projection.effects(representative("sell"))
      assert_legs(effect.cash, [{@cash, {:add, dec("236")}}])
      assert_legs(effect.quantities, [{@depot, @security, dec("-4")}])
      refute effect.external
    end

    test "buy/sell cash falls back to quantity*price with fees and taxes" do
      buy = representative("buy") |> Map.put(:gross_amount, nil) |> Projection.effects()
      assert_legs(buy.cash, [{@cash, {:add, dec("-507")}}])

      sell = representative("sell") |> Map.put(:gross_amount, nil) |> Projection.effects()
      assert_legs(sell.cash, [{@cash, {:add, dec("236")}}])
    end

    test "a cash transfer moves cash between own accounts internally" do
      effect = Projection.effects(representative("cash_transfer"))
      assert_legs(effect.cash, [{@cash, {:add, dec("-50")}}, {@cash_b, {:add, dec("50")}}])
      assert effect.quantities == []
      refute effect.external
    end

    test "deliveries move quantity without cash and are external flows" do
      inbound = Projection.effects(representative("inbound_delivery"))
      assert inbound.cash == []
      assert_legs(inbound.quantities, [{@depot, @security, dec("3")}])
      assert inbound.external

      outbound = Projection.effects(representative("outbound_delivery"))
      assert outbound.cash == []
      assert_legs(outbound.quantities, [{@depot, @security, dec("-3")}])
      assert outbound.external
    end

    test "a security transfer moves quantity between own depots internally" do
      effect = Projection.effects(representative("security_transfer"))
      assert effect.cash == []

      assert_legs(effect.quantities, [
        {@depot, @security, dec("-3")},
        {@depot_b, @security, dec("3")}
      ])

      refute effect.external
    end

    test "a balance snapshot anchors the account to an absolute balance, externally" do
      effect = Projection.effects(representative("balance_adjustment"))
      assert_legs(effect.cash, [{@cash, {:set, dec("100")}}])
      assert effect.quantities == []
      assert effect.external
    end

    test "covers every supported booking kind" do
      for kind <- Transaction.kinds() do
        effect = Projection.effects(representative(kind))
        assert is_list(effect.cash)
        assert is_list(effect.quantities)
        assert is_boolean(effect.external)
      end
    end

    test "raises for a kind it has not been taught — the single place to extend" do
      assert_raise FunctionClauseError, fn ->
        Projection.effects(tx("share_split"))
      end
    end
  end

  describe "cash_balances/1 — generic fold over effect cash legs" do
    test "sums add legs of every kind with the direction the projection states" do
      transactions =
        Transaction.kinds()
        |> Enum.reject(&(&1 == "balance_adjustment"))
        |> Enum.with_index(1)
        |> Enum.map(fn {kind, id} -> Map.put(representative(kind), :id, id) end)

      expected =
        Enum.reduce(transactions, %{}, fn transaction, acc ->
          Enum.reduce(Projection.effects(transaction).cash, acc, fn {id, {:add, delta}}, acc ->
            Map.update(acc, id, delta, &Decimal.add(&1, delta))
          end)
        end)

      balances = Projection.cash_balances(transactions)

      assert Map.keys(balances) |> Enum.sort() == Map.keys(expected) |> Enum.sort()

      for {account_id, balance} <- balances do
        assert Decimal.equal?(balance, Map.fetch!(expected, account_id))
      end
    end

    test "a snapshot anchors the balance regardless of processing order" do
      transactions = [
        tx("removal", %{
          id: 4,
          date: ~D[2026-06-05],
          cash_account_id: @cash,
          gross_amount: dec("250")
        }),
        tx("deposit", %{
          id: 1,
          date: ~D[2026-01-01],
          cash_account_id: @cash,
          gross_amount: dec("1000")
        }),
        tx("balance_adjustment", %{
          id: 2,
          date: ~D[2026-06-01],
          cash_account_id: @cash,
          gross_amount: dec("4250")
        }),
        # Same-day booking with a later id: already reflected in the snapshot.
        tx("deposit", %{
          id: 3,
          date: ~D[2026-06-01],
          cash_account_id: @cash,
          gross_amount: dec("100")
        })
      ]

      balances = Projection.cash_balances(transactions)

      assert Decimal.equal?(Map.fetch!(balances, @cash), dec("4000"))
    end

    test "the latest snapshot wins and may be negative" do
      transactions = [
        tx("balance_adjustment", %{
          id: 1,
          date: ~D[2026-05-01],
          cash_account_id: @cash,
          gross_amount: dec("1000")
        }),
        tx("balance_adjustment", %{
          id: 2,
          date: ~D[2026-06-01],
          cash_account_id: @cash,
          gross_amount: dec("-50")
        })
      ]

      assert Decimal.equal?(Map.fetch!(Projection.cash_balances(transactions), @cash), dec("-50"))
    end

    test "legs without a cash account are skipped" do
      assert Projection.cash_balances([tx("deposit", %{gross_amount: dec("100")})]) == %{}
    end
  end

  describe "read models stay generic over kinds" do
    test "positions reproduce the projection's quantity legs for every kind" do
      for kind <- Transaction.kinds() do
        transaction = representative(kind)

        expected =
          Enum.reduce(Projection.effects(transaction).quantities, %{}, fn
            {account_id, security_id, delta}, acc ->
              Map.update(acc, {account_id, security_id}, delta, &Decimal.add(&1, delta))
          end)
          |> Map.reject(fn {_key, value} -> Decimal.equal?(value, 0) end)

        assert Positions.calculate([transaction]) == expected
      end
    end

    test "snapshots replay after the other bookings of their day" do
      snapshot = representative("balance_adjustment")
      booking = representative("deposit")

      assert Projection.intra_day_order(booking) < Projection.intra_day_order(snapshot)
    end
  end
end
