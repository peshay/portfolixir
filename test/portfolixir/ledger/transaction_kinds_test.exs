defmodule Portfolixir.Ledger.TransactionKindsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, add_depot: 2, create_security!: 1]

  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios

  # User story:
  # As a local portfolio maintainer importing my Portfolio Performance
  # export,
  # I want the ledger to accept every PP transaction kind (dividend,
  # interest, deposit, removal, fee, tax, tax refund, cash transfer,
  # inbound/outbound delivery, security transfer) in addition to the
  # existing buy/sell trades,
  # so that the import preserves my full bookkeeping history with the
  # correct per-row validation.
  #
  # Acceptance criteria:
  # - Each kind is accepted by the changeset when its required fields are
  #   present.
  # - The changeset rejects each kind when a required field is missing.
  # - Decimal precision is preserved for quantity and gross_amount.
  # - `import_hash` is unique across the table when present.

  defp setup_world do
    world = base_world(name: "Test Portfolio", cash_name: "Test Cash", depot_name: "Test Depot")
    security = create_security!(name: "Test Security", ticker: "TST", asset_class: "equity")

    %{cash: cash_b, depot: depot_b} =
      add_depot(world.portfolio, cash_name: "Test Cash 2", depot_name: "Test Depot 2")

    Map.merge(world, %{security: security, cash_b: cash_b, depot_b: depot_b})
  end

  defp base(w) do
    %{
      portfolio_id: w.portfolio.id,
      date: ~D[2026-04-01],
      currency_code: "EUR"
    }
  end

  describe "purchase (buy) kind" do
    test "accepts a buy with all required fields" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "buy",
          security_id: w.security.id,
          securities_account_id: w.depot.id,
          cash_account_id: w.cash.id,
          quantity: Decimal.new("10"),
          price: Decimal.new("150.25"),
          gross_amount: Decimal.new("1502.50")
        })

      assert {:ok, %Transaction{type: "buy"}} =
               Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
    end
  end

  describe "buy/sell with price = 0 (spin-off, write-off)" do
    test "accepts a sell at price 0 (worthless write-off)" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "sell",
          security_id: w.security.id,
          securities_account_id: w.depot.id,
          cash_account_id: w.cash.id,
          quantity: Decimal.new("2000"),
          price: Decimal.new("0.00"),
          gross_amount: Decimal.new("2.00")
        })

      assert {:ok, %Transaction{type: "sell"}} =
               Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
    end

    test "still rejects a buy with negative price" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "buy",
          security_id: w.security.id,
          securities_account_id: w.depot.id,
          cash_account_id: w.cash.id,
          quantity: Decimal.new("10"),
          price: Decimal.new("-1"),
          gross_amount: Decimal.new("-10")
        })

      assert {:error, changeset} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
      assert %{price: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end
  end

  describe "sale (sell) kind" do
    test "accepts a sell with all required fields" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "sell",
          security_id: w.security.id,
          securities_account_id: w.depot.id,
          cash_account_id: w.cash.id,
          quantity: Decimal.new("5"),
          price: Decimal.new("160.00")
        })

      assert {:ok, %Transaction{type: "sell"}} =
               Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
    end
  end

  describe "dividend kind" do
    test "accepts a dividend with security, cash account, gross amount" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "dividend",
          security_id: w.security.id,
          cash_account_id: w.cash.id,
          gross_amount: Decimal.new("12.34")
        })

      assert {:ok, %Transaction{type: "dividend"}} =
               Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
    end

    test "rejects a dividend without a cash account" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "dividend",
          security_id: w.security.id,
          gross_amount: Decimal.new("12.34")
        })

      assert {:error, changeset} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
      assert %{cash_account_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects a dividend without a security" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "dividend",
          cash_account_id: w.cash.id,
          gross_amount: Decimal.new("12.34")
        })

      assert {:error, changeset} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
      assert %{security_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  for kind <- ~w(interest deposit removal) do
    describe "#{kind} (cash-only) kind" do
      test "accepts #{kind} with a cash account and a gross amount" do
        w = setup_world()

        attrs =
          Map.merge(base(w), %{
            type: unquote(kind),
            cash_account_id: w.cash.id,
            gross_amount: Decimal.new("100.00")
          })

        assert {:ok, %Transaction{type: unquote(kind)}} =
                 Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
      end

      test "rejects #{kind} without a gross amount" do
        w = setup_world()

        attrs =
          Map.merge(base(w), %{
            type: unquote(kind),
            cash_account_id: w.cash.id
          })

        assert {:error, changeset} =
                 Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)

        assert %{gross_amount: ["can't be blank"]} = errors_on(changeset)
      end
    end
  end

  for kind <- ~w(fee tax tax_refund) do
    describe "#{kind} kind" do
      test "accepts #{kind} on a cash account alone" do
        w = setup_world()

        attrs =
          Map.merge(base(w), %{
            type: unquote(kind),
            cash_account_id: w.cash.id,
            gross_amount: Decimal.new("3.50")
          })

        assert {:ok, %Transaction{type: unquote(kind)}} =
                 Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
      end

      test "accepts #{kind} attached to a security" do
        w = setup_world()

        attrs =
          Map.merge(base(w), %{
            type: unquote(kind),
            cash_account_id: w.cash.id,
            security_id: w.security.id,
            gross_amount: Decimal.new("3.50")
          })

        assert {:ok, %Transaction{type: unquote(kind), security_id: sid}} =
                 Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)

        assert sid == w.security.id
      end
    end
  end

  describe "cash_transfer kind" do
    test "accepts a transfer between two distinct cash accounts" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "cash_transfer",
          cash_account_id: w.cash.id,
          counter_cash_account_id: w.cash_b.id,
          gross_amount: Decimal.new("500.00")
        })

      assert {:ok, %Transaction{type: "cash_transfer"}} =
               Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
    end

    test "rejects a transfer where source and target are the same account" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "cash_transfer",
          cash_account_id: w.cash.id,
          counter_cash_account_id: w.cash.id,
          gross_amount: Decimal.new("500.00")
        })

      assert {:error, changeset} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)

      assert %{counter_cash_account_id: ["must differ from cash_account_id"]} =
               errors_on(changeset)
    end
  end

  for kind <- ~w(inbound_delivery outbound_delivery) do
    describe "#{kind} kind" do
      test "accepts a delivery moving quantity without a cash impact" do
        w = setup_world()

        attrs =
          Map.merge(base(w), %{
            type: unquote(kind),
            security_id: w.security.id,
            securities_account_id: w.depot.id,
            quantity: Decimal.new("10")
          })

        assert {:ok, %Transaction{type: unquote(kind), cash_account_id: nil}} =
                 Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
      end

      test "rejects a delivery with a non-positive quantity" do
        w = setup_world()

        attrs =
          Map.merge(base(w), %{
            type: unquote(kind),
            security_id: w.security.id,
            securities_account_id: w.depot.id,
            quantity: Decimal.new("0")
          })

        assert {:error, changeset} =
                 Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)

        assert %{quantity: ["must be greater than 0"]} = errors_on(changeset)
      end
    end
  end

  describe "security_transfer kind" do
    test "accepts a transfer between two distinct depots" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "security_transfer",
          security_id: w.security.id,
          securities_account_id: w.depot.id,
          counter_securities_account_id: w.depot_b.id,
          quantity: Decimal.new("5"),
          gross_amount: Decimal.new("1000.00")
        })

      assert {:ok, %Transaction{type: "security_transfer"}} =
               Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
    end

    test "rejects a transfer where source and target depots are the same" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "security_transfer",
          security_id: w.security.id,
          securities_account_id: w.depot.id,
          counter_securities_account_id: w.depot.id,
          quantity: Decimal.new("5")
        })

      assert {:error, changeset} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)

      assert %{counter_securities_account_id: ["must differ from securities_account_id"]} =
               errors_on(changeset)
    end
  end

  describe "import_hash uniqueness" do
    test "rejects a second transaction with the same import_hash" do
      w = setup_world()

      base_attrs =
        Map.merge(base(w), %{
          type: "dividend",
          security_id: w.security.id,
          cash_account_id: w.cash.id,
          gross_amount: Decimal.new("12.34"),
          import_hash: "sha256-test-fixture"
        })

      assert {:ok, _} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), base_attrs)

      assert {:error, changeset} =
               Ledger.create_transaction(Portfolixir.Actor.owner_ui(), base_attrs)

      assert %{import_hash: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows multiple transactions with no import_hash" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "dividend",
          security_id: w.security.id,
          cash_account_id: w.cash.id,
          gross_amount: Decimal.new("12.34")
        })

      assert {:ok, _} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
      assert {:ok, _} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the ledger to handle a transaction whose currency differs from
  # its linked cash account as a cross-currency settlement (issue #388,
  # ADR-0015) — requiring a stored settlement FX rate — rather than
  # rejecting it outright as under #343, while a cash transfer still only
  # moves money between same-currency accounts,
  # so that a USD security bought through a EUR account is bookable without
  # ever silently folding a USD amount into a EUR cash projection.
  #
  # Acceptance criteria:
  # - A transaction whose currency_code equals the linked cash account's
  #   currency is accepted with no FX fields.
  # - A transaction whose currency_code differs from the linked cash
  #   account's currency requires a settlement FX rate; without one (and
  #   with no amounts to derive it) it is rejected on :settlement_fx_rate.
  # - A cash_transfer is rejected when its currency differs from the
  #   counter cash account currency.
  # - The check is pure validation; no FX conversion of stored amounts here.
  describe "currency consistency with linked cash accounts" do
    test "accepts a transaction whose currency matches the cash account" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "deposit",
          cash_account_id: w.cash.id,
          gross_amount: Decimal.new("100.00"),
          currency_code: "EUR"
        })

      assert {:ok, %Transaction{currency_code: "EUR"}} =
               Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
    end

    test "rejects a mismatched-currency transaction with no settlement FX rate" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "deposit",
          cash_account_id: w.cash.id,
          gross_amount: Decimal.new("100.00"),
          currency_code: "USD"
        })

      assert {:error, changeset} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)

      assert %{settlement_fx_rate: ["is required for a cross-currency settlement"]} =
               errors_on(changeset)
    end

    test "rejects a mismatched-currency buy with no settlement FX rate" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "buy",
          security_id: w.security.id,
          securities_account_id: w.depot.id,
          cash_account_id: w.cash.id,
          quantity: Decimal.new("10"),
          price: Decimal.new("150.25"),
          gross_amount: Decimal.new("1502.50"),
          currency_code: "USD"
        })

      assert {:error, changeset} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)

      assert %{settlement_fx_rate: ["is required for a cross-currency settlement"]} =
               errors_on(changeset)
    end

    test "accepts a mismatched-currency buy when a settlement FX rate is supplied" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "buy",
          security_id: w.security.id,
          securities_account_id: w.depot.id,
          cash_account_id: w.cash.id,
          quantity: Decimal.new("10"),
          price: Decimal.new("150.25"),
          gross_amount: Decimal.new("1366.82"),
          currency_code: "USD",
          settlement_fx_rate: Decimal.new("0.909091")
        })

      assert {:ok, %Transaction{currency_code: "USD"}} =
               Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
    end

    test "rejects a mismatched-currency buy with a non-positive settlement FX rate" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "buy",
          security_id: w.security.id,
          securities_account_id: w.depot.id,
          cash_account_id: w.cash.id,
          quantity: Decimal.new("10"),
          price: Decimal.new("150.25"),
          gross_amount: Decimal.new("1502.50"),
          currency_code: "USD",
          settlement_fx_rate: Decimal.new("0")
        })

      assert {:error, changeset} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)

      assert %{settlement_fx_rate: ["must be greater than 0 for a cross-currency settlement"]} =
               errors_on(changeset)
    end

    test "accepts a cash_transfer matching both source and counter accounts" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "cash_transfer",
          cash_account_id: w.cash.id,
          counter_cash_account_id: w.cash_b.id,
          gross_amount: Decimal.new("500.00"),
          currency_code: "EUR"
        })

      assert {:ok, %Transaction{type: "cash_transfer"}} =
               Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
    end

    test "rejects a cash_transfer whose counter account has a different currency" do
      w = setup_world()

      {:ok, cash_usd} =
        Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: w.portfolio.id,
          name: "USD Cash",
          currency_code: "USD"
        })

      attrs =
        Map.merge(base(w), %{
          type: "cash_transfer",
          cash_account_id: w.cash.id,
          counter_cash_account_id: cash_usd.id,
          gross_amount: Decimal.new("500.00"),
          currency_code: "EUR"
        })

      assert {:error, changeset} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)

      assert %{counter_cash_account_id: ["must match the transaction currency (EUR)"]} =
               errors_on(changeset)
    end

    test "rejects updating to a mismatched currency without a settlement FX rate" do
      w = setup_world()

      {:ok, transaction} =
        Ledger.create_transaction(
          Portfolixir.Actor.owner_ui(),
          Map.merge(base(w), %{
            type: "deposit",
            cash_account_id: w.cash.id,
            gross_amount: Decimal.new("100.00"),
            currency_code: "EUR"
          })
        )

      assert {:error, changeset} =
               Ledger.update_transaction(Portfolixir.Actor.owner_ui(), transaction, %{
                 currency_code: "USD"
               })

      assert %{settlement_fx_rate: ["is required for a cross-currency settlement"]} =
               errors_on(changeset)
    end

    test "allows kinds without a cash leg regardless of currency" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "inbound_delivery",
          security_id: w.security.id,
          securities_account_id: w.depot.id,
          quantity: Decimal.new("10"),
          currency_code: "USD"
        })

      assert {:ok, %Transaction{type: "inbound_delivery"}} =
               Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
    end
  end

  describe "type validation" do
    test "rejects an unknown kind" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "totally_made_up_kind",
          cash_account_id: w.cash.id,
          gross_amount: Decimal.new("1.00")
        })

      assert {:error, changeset} = Ledger.create_transaction(Portfolixir.Actor.owner_ui(), attrs)
      assert %{type: ["is invalid"]} = errors_on(changeset)
    end
  end
end
