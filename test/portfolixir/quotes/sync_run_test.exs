defmodule Portfolixir.Quotes.SyncRunTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Imports.RawImportItem
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Quotes.SyncRun
  alias Portfolixir.Repo

  defmodule ChangedQuoteProvider do
    @behaviour Portfolixir.Quotes.Provider

    @impl true
    def capabilities(_config), do: {:ok, ["read_latest_quote", "read_historical_quotes"]}

    @impl true
    def historical_quotes(_config, _security_ref) do
      {:ok,
       [
         %{date: ~D[2024-01-02], close: "199.99", source: "fake", currency_code: "EUR"},
         %{date: ~D[2024-01-03], close: "103.10", source: "fake", currency_code: "EUR"}
       ]}
    end

    @impl true
    def latest_quote(_config, _security_ref), do: {:ok, nil}
  end

  defmodule ErrorProvider do
    @behaviour Portfolixir.Quotes.Provider

    @impl true
    def capabilities(_config), do: {:ok, ["read_latest_quote", "read_historical_quotes"]}

    @impl true
    def historical_quotes(_config, _security_ref), do: {:error, :provider_unavailable}

    @impl true
    def latest_quote(_config, _security_ref), do: {:error, :provider_unavailable}
  end

  setup do
    :ok = Catalog.ensure_mvp_currencies!()

    {:ok, security} =
      Catalog.create_security(%{
        name: "MSCI World ETF",
        symbol: "EUNL",
        provider_symbol: "EUNL.DE",
        currency_code: "EUR"
      })

    %{security: security}
  end

  test "sync persists fake historical quotes", %{security: security} do
    assert {:ok, summary} = SyncRun.sync_security(Portfolixir.Quotes.FakeProvider, security.id)

    quotes = Catalog.list_security_quotes(security.id)

    assert length(quotes) == 2
    assert summary.security_id == security.id
    assert summary.created == 2
    assert summary.updated == 0
    assert summary.failed == 0
  end

  test "sync latest quote works if implemented", %{security: security} do
    assert {:ok, summary} =
             SyncRun.sync_security(Portfolixir.Quotes.FakeProvider, security.id, %{
               sync_latest: true
             })

    latest = Catalog.get_latest_security_quote(security.id)

    assert latest.date == ~D[2024-01-03]
    assert summary.created == 2
    assert summary.skipped == 1
  end

  test "repeated sync is idempotent", %{security: security} do
    assert {:ok, first} = SyncRun.sync_security(Portfolixir.Quotes.FakeProvider, security.id)
    assert {:ok, second} = SyncRun.sync_security(Portfolixir.Quotes.FakeProvider, security.id)

    assert first.created == 2
    assert second.created == 0
    assert second.updated == 0
    assert second.skipped == 3
    assert second.failed == 0
  end

  test "changed quote updated or skipped according to policy", %{security: security} do
    assert {:ok, _} = SyncRun.sync_security(Portfolixir.Quotes.FakeProvider, security.id)

    assert {:ok, summary} =
             SyncRun.sync_security(ChangedQuoteProvider, security.id, %{sync_latest: false})

    assert summary.updated == 1
    assert summary.skipped == 1
    assert summary.created == 0

    [changed | _] =
      Catalog.list_security_quotes(security.id)
      |> Enum.filter(&(&1.date == ~D[2024-01-02]))

    assert Decimal.to_string(changed.close) == "199.99"
  end

  test "unknown security returns clear error" do
    assert {:error, :security_not_found} =
             SyncRun.sync_security(Portfolixir.Quotes.FakeProvider, -1)
  end

  test "provider error captured in summary/warnings", %{security: security} do
    assert {:ok, summary} = SyncRun.sync_security(ErrorProvider, security.id)

    assert summary.failed == 2
    assert Enum.any?(summary.warnings, &String.contains?(&1, "historical_quotes failed"))
    assert Enum.any?(summary.warnings, &String.contains?(&1, "latest_quote failed"))
  end

  test "no ledger transactions or raw import items are created", %{security: security} do
    initial_tx_count = Repo.aggregate(Transaction, :count, :id)
    initial_raw_count = Repo.aggregate(RawImportItem, :count, :id)

    assert {:ok, _summary} = SyncRun.sync_security(Portfolixir.Quotes.FakeProvider, security.id)

    assert Repo.aggregate(Transaction, :count, :id) == initial_tx_count
    assert Repo.aggregate(RawImportItem, :count, :id) == initial_raw_count
  end

  test "no unsupported capabilities called", %{security: security} do
    assert {:ok, summary} = SyncRun.sync_security(Portfolixir.Quotes.FakeProvider, security.id)

    assert summary.failed == 0
    assert summary.warnings == []
  end
end
