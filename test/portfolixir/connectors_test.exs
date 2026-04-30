defmodule Portfolixir.ConnectorsTest do
  use ExUnit.Case, async: false

  alias Portfolixir.Connectors
  alias Portfolixir.Connectors.FakeProvider

  test "FakeProvider returns accounts" do
    assert {:ok, accounts} = FakeProvider.accounts(%{})
    assert is_list(accounts)
    assert length(accounts) == 2

    assert [
             %{
               "id" => "acct-1001",
               "name" => "Main cash account",
               "currency_code" => "USD",
               "type" => "cash",
               "provider_ref" => "prov-acct-1001"
             },
             %{
               "id" => "acct-2001",
               "name" => "Crypto account",
               "currency_code" => "BTC",
               "type" => "crypto",
               "provider_ref" => "prov-acct-2001"
             }
           ] = accounts
  end

  test "FakeProvider returns balances" do
    assert {:ok, balances} = FakeProvider.balances(%{})
    assert is_list(balances)
    assert length(balances) == 2

    expected_balances = [
      %{
        "account_id" => "acct-1001",
        "currency_code" => "USD",
        "current" => %{
          "available" => Decimal.new("1020.40"),
          "total" => Decimal.new("1045.50")
        }
      },
      %{
        "account_id" => "acct-2001",
        "currency_code" => "BTC",
        "current" => %{
          "available" => Decimal.new("0.2500"),
          "total" => Decimal.new("0.2500")
        }
      }
    ]

    assert expected_balances == balances
  end

  test "FakeProvider returns transactions" do
    assert {:ok, transactions} = FakeProvider.transactions(%{}, %{"limit" => 2})
    assert is_list(transactions)
    assert length(transactions) == 2

    expected_transactions = [
      %{
        "id" => "txn-2001",
        "account_id" => "acct-1001",
        "status" => "settled",
        "amount" => Decimal.new("124.80"),
        "currency_code" => "USD",
        "type" => "deposit",
        "executed_at" => "2026-01-05T00:00:00Z"
      },
      %{
        "id" => "txn-2002",
        "account_id" => "acct-2001",
        "status" => "settled",
        "amount" => Decimal.new("0.0100"),
        "currency_code" => "BTC",
        "type" => "credit",
        "executed_at" => "2026-01-06T00:00:00Z"
      }
    ]

    assert expected_transactions == transactions
  end

  test "FakeProvider returns documents" do
    assert {:ok, documents} = FakeProvider.documents(%{}, %{"status" => "open"})
    assert is_list(documents)
    assert length(documents) == 1

    assert [
             %{
               "id" => "doc-3001",
               "type" => "statement",
               "file_name" => "sample-statement.pdf",
               "account_id" => "acct-1001",
               "status" => "open"
             }
           ] = documents
  end

  test "FakeProvider permissions can be inspected" do
    assert {:ok, permissions} = FakeProvider.permissions(%{})

    assert permissions == [
             "read_accounts",
             "read_balances",
             "read_transactions",
             "read_documents",
             "read_permissions"
           ]
  end

  test "read capabilities are allowed" do
    config = %{"environment" => "test"}

    assert {:ok, _} = Connectors.call(FakeProvider, "read_accounts", config)
    assert {:ok, _} = Connectors.call(FakeProvider, "read_balances", config)
    assert {:ok, _} = Connectors.call(FakeProvider, "read_transactions", config, %{})
    assert {:ok, _} = Connectors.call(FakeProvider, "read_documents", config, %{})
    assert {:ok, _} = Connectors.call(FakeProvider, "read_permissions", config)
  end

  test "unsupported write capabilities return explicit error" do
    for capability <- [
          "create_payment",
          "place_order",
          "cancel_order",
          "withdraw",
          "transfer"
        ] do
      assert {:error, {:unsupported_capability, ^capability}} =
               Connectors.call(FakeProvider, capability, %{})
    end
  end

  test "unsupported arbitrary capability returns explicit error" do
    assert {:error, {:unsupported_capability, "unsupported_capability_name"}} =
             Connectors.call(FakeProvider, "unsupported_capability_name", %{})
  end

  test "connector does not create atoms from arbitrary capability input" do
    unknown_capability =
      "unsupported_capability_" <> Integer.to_string(System.unique_integer([:positive]))

    assert_raise ArgumentError, fn ->
      String.to_existing_atom(unknown_capability)
    end

    assert {:error, {:unsupported_capability, ^unknown_capability}} =
             Connectors.call(FakeProvider, unknown_capability, %{})

    assert_raise ArgumentError, fn ->
      String.to_existing_atom(unknown_capability)
    end
  end
end
