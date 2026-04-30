defmodule Portfolixir.Connectors.FakeProvider do
  @moduledoc "Deterministic connector provider for tests and local development."

  @behaviour Portfolixir.Connectors.Provider

  @sample_accounts [
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
  ]

  @sample_balances [
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

  @sample_transactions [
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

  @sample_documents [
    %{
      "id" => "doc-3001",
      "type" => "statement",
      "file_name" => "sample-statement.pdf",
      "account_id" => "acct-1001",
      "status" => "open"
    }
  ]

  @sample_permissions [
    "read_accounts",
    "read_balances",
    "read_transactions",
    "read_documents",
    "read_permissions"
  ]

  def accounts(_config), do: {:ok, @sample_accounts}

  def balances(_config), do: {:ok, @sample_balances}

  def transactions(_config, _opts), do: {:ok, @sample_transactions}

  def documents(_config, _opts), do: {:ok, @sample_documents}

  def permissions(_config), do: {:ok, @sample_permissions}
end
