defmodule Portfolixir.Ledger.TransactionKindsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
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
    {:ok, security} =
      Catalog.create_security(%{
        name: "Test Security",
        ticker_symbol: "TST",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Test Portfolio", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Test Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Test Depot"
      })

    {:ok, cash_b} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Test Cash 2",
        currency_code: "EUR"
      })

    {:ok, depot_b} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash_b.id,
        name: "Test Depot 2"
      })

    %{
      security: security,
      portfolio: portfolio,
      cash: cash,
      depot: depot,
      cash_b: cash_b,
      depot_b: depot_b
    }
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

      assert {:ok, %Transaction{type: "buy"}} = Ledger.create_transaction(attrs)
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

      assert {:ok, %Transaction{type: "sell"}} = Ledger.create_transaction(attrs)
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

      assert {:error, changeset} = Ledger.create_transaction(attrs)
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

      assert {:ok, %Transaction{type: "sell"}} = Ledger.create_transaction(attrs)
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

      assert {:ok, %Transaction{type: "dividend"}} = Ledger.create_transaction(attrs)
    end

    test "rejects a dividend without a cash account" do
      w = setup_world()

      attrs =
        Map.merge(base(w), %{
          type: "dividend",
          security_id: w.security.id,
          gross_amount: Decimal.new("12.34")
        })

      assert {:error, changeset} = Ledger.create_transaction(attrs)
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

      assert {:error, changeset} = Ledger.create_transaction(attrs)
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

        assert {:ok, %Transaction{type: unquote(kind)}} = Ledger.create_transaction(attrs)
      end

      test "rejects #{kind} without a gross amount" do
        w = setup_world()

        attrs =
          Map.merge(base(w), %{
            type: unquote(kind),
            cash_account_id: w.cash.id
          })

        assert {:error, changeset} = Ledger.create_transaction(attrs)
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

        assert {:ok, %Transaction{type: unquote(kind)}} = Ledger.create_transaction(attrs)
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
                 Ledger.create_transaction(attrs)

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

      assert {:ok, %Transaction{type: "cash_transfer"}} = Ledger.create_transaction(attrs)
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

      assert {:error, changeset} = Ledger.create_transaction(attrs)

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
                 Ledger.create_transaction(attrs)
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

        assert {:error, changeset} = Ledger.create_transaction(attrs)
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

      assert {:ok, %Transaction{type: "security_transfer"}} = Ledger.create_transaction(attrs)
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

      assert {:error, changeset} = Ledger.create_transaction(attrs)

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

      assert {:ok, _} = Ledger.create_transaction(base_attrs)
      assert {:error, changeset} = Ledger.create_transaction(base_attrs)
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

      assert {:ok, _} = Ledger.create_transaction(attrs)
      assert {:ok, _} = Ledger.create_transaction(attrs)
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

      assert {:error, changeset} = Ledger.create_transaction(attrs)
      assert %{type: ["is invalid"]} = errors_on(changeset)
    end
  end
end
