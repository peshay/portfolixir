defmodule Portfolixir.Connectors.SyncRunTest do
  use Portfolixir.DataCase, async: true
  alias Portfolixir.Connectors.SyncRun
  alias Portfolixir.Connectors.Provider
  alias Portfolixir.Connectors.FakeProvider
  alias Portfolixir.Imports.{ImportRun, ImportSource, RawImportItem}
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @connector_name "Connector Bank"
  @idless_connector_name "Idless Connector"
  @secret_connector_name "Secret Keeper"
  @error_connector_name "Error Connector"
  @spy_connector_name "Spy Connector"

  defmodule IdlessProvider do
    @moduledoc false
    @behaviour Provider

    def accounts(_config), do: {:ok, [%{"type" => "cash"}]}
    def balances(_config), do: {:ok, []}
    def transactions(_config, _opts), do: {:ok, []}
    def documents(_config, _opts), do: {:ok, []}
    def permissions(_config), do: {:ok, []}
  end

  defmodule SecretfulProvider do
    @moduledoc false
    @behaviour Provider

    def accounts(_config),
      do: {:ok, [%{"id" => "acct-secret", "api_key" => "abc", "meta" => %{"token" => "nope"}}]}

    def balances(_config), do: {:ok, []}
    def transactions(_config, _opts), do: {:ok, []}
    def documents(_config, _opts), do: {:ok, []}
    def permissions(_config), do: {:ok, []}
  end

  defmodule ErrorProvider do
    @moduledoc false
    @behaviour Provider

    def accounts(_config), do: {:ok, [%{"id" => "acct-ok", "name" => "ok"}]}

    def balances(_config),
      do: {:error, {:downstream_unavailable, "balances endpoint unavailable"}}

    def transactions(_config, _opts), do: {:ok, []}
    def documents(_config, _opts), do: {:ok, []}
    def permissions(_config), do: {:ok, ["read_accounts", "read_balances"]}
  end

  defmodule ChangedAccountProvider do
    @moduledoc false
    @behaviour Provider

    def accounts(config) do
      version = Map.get(config, :version, 1)

      {:ok,
       [
         %{"id" => "acct-1", "name" => "Main #{version}", "currency" => "EUR"},
         %{"id" => "acct-2", "name" => "Savings", "currency" => "EUR"}
       ]}
    end

    def balances(_config), do: {:ok, []}
    def transactions(_config, _opts), do: {:ok, []}
    def documents(_config, _opts), do: {:ok, []}
    def permissions(_config), do: {:ok, []}
  end

  defmodule SpyProvider do
    @moduledoc false
    @behaviour Provider

    def accounts(_config), do: {:ok, []}
    def balances(_config), do: {:ok, []}
    def transactions(_config, _opts), do: {:ok, []}
    def documents(_config, _opts), do: {:ok, []}
    def permissions(_config), do: {:ok, []}

    def create_payment(_config), do: send(self(), :write_capability_called)
  end

  @secret_fields %{"api_key" => true, "token" => true, "secret" => true, "password" => true}

  test "sync with FakeProvider creates connector import source" do
    assert {:ok, summary} = SyncRun.run(FakeProvider, @connector_name, %{}, %{})

    source = Repo.get!(ImportSource, summary["import_source_id"])
    assert source.name == "Connector: #{@connector_name}"
    assert source.type == "connector"
    assert source.status == "active"
  end

  test "sync creates an import run" do
    assert {:ok, summary} = SyncRun.run(FakeProvider, @connector_name, %{}, %{})
    run = Repo.get!(ImportRun, summary["import_run_id"])

    assert run.status == "completed"
    assert run.import_source_id == summary["import_source_id"]
    assert is_map(run.summary)
    assert run.summary["provider"] == @connector_name
  end

  test "sync creates raw import items for accounts" do
    assert {:ok, summary} = SyncRun.run(FakeProvider, @connector_name, %{}, %{})
    items = items_for_run(summary["import_run_id"])

    account_items = filter_payload_by_record_type(items, "account")
    assert length(account_items) == 2
    assert Enum.all?(account_items, fn item -> item.status == "new" end)

    assert Enum.all?(account_items, fn item ->
             item.payload["provider"] == @connector_name and
               item.payload["record_type"] == "account" and
               is_binary(item.payload["external_id"])
           end)

    assert Enum.all?(account_items, fn item ->
             is_binary(item.content_hash) and String.starts_with?(item.content_hash, "sha256:")
           end)
  end

  test "sync creates raw import items for balances" do
    assert {:ok, summary} = SyncRun.run(FakeProvider, @connector_name, %{}, %{})

    balance_items =
      filter_payload_by_record_type(items_for_run(summary["import_run_id"]), "balance")

    assert length(balance_items) == 2

    assert Enum.all?(balance_items, fn item ->
             Map.has_key?(item.payload["payload"], "current")
           end)
  end

  test "sync creates raw import items for transactions" do
    assert {:ok, summary} = SyncRun.run(FakeProvider, @connector_name, %{}, %{})

    transaction_items =
      filter_payload_by_record_type(items_for_run(summary["import_run_id"]), "transaction")

    assert length(transaction_items) == 2
    assert Enum.all?(transaction_items, fn item -> is_binary(item.external_id) end)
  end

  test "sync creates raw import items for documents" do
    assert {:ok, summary} = SyncRun.run(FakeProvider, @connector_name, %{}, %{})

    document_items =
      filter_payload_by_record_type(items_for_run(summary["import_run_id"]), "document")

    assert length(document_items) == 1
    assert Enum.all?(document_items, fn item -> item.external_id == "doc-3001" end)
  end

  test "sync records permissions deterministically" do
    assert {:ok, summary} = SyncRun.run(FakeProvider, @connector_name, %{}, %{})

    permission_items =
      filter_payload_by_record_type(items_for_run(summary["import_run_id"]), "permission")

    permission_values = Enum.map(permission_items, & &1.payload["payload"]["permission"])

    assert Enum.sort(permission_values) == [
             "read_accounts",
             "read_balances",
             "read_documents",
             "read_permissions",
             "read_transactions"
           ]

    assert length(permission_items) == 5
  end

  test "sync summary has stable top-level keys" do
    assert {:ok, summary} = SyncRun.run(FakeProvider, @connector_name, %{}, %{})

    assert MapSet.new(Map.keys(summary)) ==
             MapSet.new([
               "provider",
               "import_source_id",
               "import_run_id",
               "created",
               "skipped",
               "changed",
               "conflicts",
               "failed",
               "warnings",
               "record_counts"
             ])
  end

  test "sync does not create duplicate raw items when run twice" do
    assert {:ok, first_summary} = SyncRun.run(FakeProvider, @connector_name, %{}, %{})
    initial_count = Repo.aggregate(RawImportItem, :count, :id)
    assert {:ok, second_summary} = SyncRun.run(FakeProvider, @connector_name, %{}, %{})

    assert second_summary["import_source_id"] == first_summary["import_source_id"]
    assert Repo.aggregate(RawImportItem, :count, :id) == initial_count
  end

  test "second sync creates new import run but does not reassign existing raw items" do
    assert {:ok, first_summary} = SyncRun.run(FakeProvider, @connector_name, %{}, %{})
    {:ok, second_summary} = SyncRun.run(FakeProvider, @connector_name, %{}, %{})

    assert first_summary["import_source_id"] == second_summary["import_source_id"]
    assert second_summary["import_run_id"] != first_summary["import_run_id"]

    existing_raw_imports =
      Repo.all(
        from(item in RawImportItem,
          where: item.import_source_id == ^second_summary["import_source_id"]
        )
      )

    assert Enum.all?(existing_raw_imports, fn item ->
             item.import_run_id == first_summary["import_run_id"]
           end)
  end

  test "reimport with changed external-id payload is classified as changed/conflict without duplicates" do
    provider_name = "Changed Account Connector"

    assert {:ok, first_summary} =
             SyncRun.run(ChangedAccountProvider, provider_name, %{version: 1}, %{})

    initial_count = Repo.aggregate(RawImportItem, :count, :id)

    assert {:ok, second_summary} =
             SyncRun.run(ChangedAccountProvider, provider_name, %{version: 2}, %{})

    assert second_summary["import_source_id"] == first_summary["import_source_id"]
    assert Repo.aggregate(RawImportItem, :count, :id) == initial_count
    assert second_summary["changed"]["accounts"] == 1
    assert second_summary["changed"]["raw_items"] == 1
    assert second_summary["conflicts"]["accounts"] == 1
    assert second_summary["conflicts"]["raw_items"] == 1

    assert Enum.any?(
             second_summary["warnings"],
             &String.contains?(&1, "Changed accounts detected")
           )
  end

  test "records without external id are deduped by deterministic content hash" do
    assert {:ok, summary} = SyncRun.run(IdlessProvider, @idless_connector_name, %{}, %{})
    count = Repo.aggregate(RawImportItem, :count, :id)

    assert {:ok, _second_summary} = SyncRun.run(IdlessProvider, @idless_connector_name, %{}, %{})

    assert Repo.aggregate(RawImportItem, :count, :id) == count
    assert length(items_for_run(summary["import_run_id"])) == 1
    assert List.first(items_for_run(summary["import_run_id"])).content_hash
  end

  test "raw payload does not contain secrets" do
    assert {:ok, summary} = SyncRun.run(SecretfulProvider, @secret_connector_name, %{}, %{})
    item = List.first(items_for_run(summary["import_run_id"]))

    assert item.payload["provider"] == @secret_connector_name
    assert not contains_secret_key?(item.payload)
  end

  test "provider_name remains a string and does not create atoms" do
    provider_name = "provider-#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, fn -> String.to_existing_atom(provider_name) end

    assert {:ok, summary} = SyncRun.run(FakeProvider, provider_name, %{}, %{})
    assert is_binary(summary["provider"])
    assert summary["provider"] == provider_name

    assert_raise ArgumentError, fn -> String.to_existing_atom(provider_name) end
  end

  test "provider read error is captured as warning and does not create ledger writes" do
    existing_transactions = Repo.aggregate(Transaction, :count, :id)

    assert {:ok, summary} = SyncRun.run(ErrorProvider, @error_connector_name, %{}, %{})
    assert summary["failed"]["balances"] == 1
    assert Enum.any?(summary["warnings"], fn warning -> String.contains?(warning, "balances") end)

    run = Repo.get!(ImportRun, summary["import_run_id"])
    assert run.status == "completed"

    assert Repo.aggregate(Transaction, :count, :id) == existing_transactions
  end

  test "no write connector capability is called" do
    assert {:ok, _summary} = SyncRun.run(SpyProvider, @spy_connector_name, %{}, %{})
    refute_receive(:write_capability_called)
  end

  defp items_for_run(import_run_id) do
    Repo.all(
      from(item in RawImportItem,
        where: item.import_run_id == ^import_run_id,
        order_by: [asc: item.id]
      )
    )
  end

  defp filter_payload_by_record_type(items, record_type) do
    Enum.filter(items, fn item -> item.payload["record_type"] == record_type end)
  end

  defp contains_secret_key?(value) when is_map(value) do
    Enum.any?(value, fn
      {key, child} ->
        key_string = to_string(key)

        Map.has_key?(@secret_fields, key_string) or
          String.ends_with?(key_string, "_token") or
          String.contains?(key_string, "secret") or
          contains_secret_key?(child)
    end)
  end

  defp contains_secret_key?(value) when is_list(value),
    do: Enum.any?(value, &contains_secret_key?/1)

  defp contains_secret_key?(_value), do: false
end
