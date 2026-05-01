defmodule Portfolixir.Connectors.ExternalAccountTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Connectors
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  setup do
    :ok = Catalog.ensure_mvp_currencies!()
    :ok
  end

  defp create_portfolio do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{
        name: "Mapping portfolio",
        description: "Synthetic portfolio for connector mappings",
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp create_deposit_account(portfolio_id) do
    {:ok, account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio_id,
        name: "Main cash",
        currency_code: "EUR"
      })

    account
  end

  defp create_securities_account(portfolio_id) do
    {:ok, account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio_id,
        name: "Main depot",
        currency_code: "EUR"
      })

    account
  end

  test "creates external account mapped to deposit account" do
    portfolio = create_portfolio()
    deposit_account = create_deposit_account(portfolio.id)

    assert {:ok, account} =
             Connectors.create_external_account(%{
               provider: "comdirect",
               external_id: "acct-1001",
               external_name: "Primary cash",
               external_type: "cash",
               currency_code: "EUR",
               status: "active",
               deposit_account_id: deposit_account.id,
               metadata: %{"routing" => "savings", "source" => "api"}
             })

    assert account.provider == "comdirect"
    assert account.external_id == "acct-1001"
    assert account.deposit_account_id == deposit_account.id
    assert account.securities_account_id == nil
    assert account.currency_code == "EUR"
    assert account.status == "active"
    assert account.metadata == %{"routing" => "savings", "source" => "api"}
  end

  test "creates external account mapped to securities account" do
    portfolio = create_portfolio()
    securities_account = create_securities_account(portfolio.id)

    assert {:ok, account} =
             Connectors.create_external_account(%{
               provider: "bunq",
               external_id: "acct-2001",
               external_name: "Primary depot",
               external_type: "brokerage",
               securities_account_id: securities_account.id,
               metadata: %{"environment" => "synthetic"}
             })

    assert account.provider == "bunq"
    assert account.securities_account_id == securities_account.id
    assert account.deposit_account_id == nil
    assert account.external_type == "brokerage"
  end

  test "rejects missing provider" do
    portfolio = create_portfolio()
    deposit_account = create_deposit_account(portfolio.id)

    assert {:error, changeset} =
             Connectors.create_external_account(%{
               external_id: "acct-missing-provider",
               deposit_account_id: deposit_account.id
             })

    assert %{provider: ["can't be blank"]} = errors_on(changeset)
  end

  test "rejects missing external_id" do
    portfolio = create_portfolio()
    deposit_account = create_deposit_account(portfolio.id)

    assert {:error, changeset} =
             Connectors.create_external_account(%{
               provider: "fake",
               deposit_account_id: deposit_account.id
             })

    assert %{external_id: ["can't be blank"]} = errors_on(changeset)
  end

  test "rejects mapping with neither local account set" do
    assert {:error, changeset} =
             Connectors.create_external_account(%{
               provider: "wallet",
               external_id: "wallet-001"
             })

    assert %{deposit_account_id: ["must set either a deposit or securities account"]} =
             errors_on(changeset)

    assert %{securities_account_id: ["must be nil when deposit account is set"]} =
             errors_on(changeset)
  end

  test "rejects mapping with both local accounts set" do
    portfolio = create_portfolio()
    deposit_account = create_deposit_account(portfolio.id)
    securities_account = create_securities_account(portfolio.id)

    assert {:error, changeset} =
             Connectors.create_external_account(%{
               provider: "wallet",
               external_id: "wallet-002",
               deposit_account_id: deposit_account.id,
               securities_account_id: securities_account.id
             })

    assert %{
             deposit_account_id: ["cannot set both a deposit and securities account"],
             securities_account_id: ["cannot set both a deposit and securities account"]
           } = errors_on(changeset)
  end

  test "rejects duplicate provider + external_id" do
    portfolio = create_portfolio()
    deposit_account = create_deposit_account(portfolio.id)

    assert {:ok, _} =
             Connectors.create_external_account(%{
               provider: "comdirect",
               external_id: "duplicate-id",
               deposit_account_id: deposit_account.id
             })

    assert {:error, changeset} =
             Connectors.create_external_account(%{
               provider: "comdirect",
               external_id: "duplicate-id",
               deposit_account_id: deposit_account.id
             })

    assert %{external_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "allows same external_id for different providers" do
    portfolio = create_portfolio()
    deposit_account = create_deposit_account(portfolio.id)

    assert {:ok, first} =
             Connectors.create_external_account(%{
               provider: "comdirect",
               external_id: "shared-id",
               deposit_account_id: deposit_account.id
             })

    assert {:ok, second} =
             Connectors.create_external_account(%{
               provider: "bunq",
               external_id: "shared-id",
               deposit_account_id: deposit_account.id
             })

    assert first.id != second.id
    assert first.provider != second.provider
  end

  test "lists all external accounts" do
    portfolio = create_portfolio()
    deposit_account = create_deposit_account(portfolio.id)
    securities_account = create_securities_account(portfolio.id)

    assert {:ok, _} =
             Connectors.create_external_account(%{
               provider: "comdirect",
               external_id: "list-1",
               deposit_account_id: deposit_account.id
             })

    assert {:ok, _} =
             Connectors.create_external_account(%{
               provider: "bunq",
               external_id: "list-2",
               securities_account_id: securities_account.id
             })

    assert {:ok, _} =
             Connectors.create_external_account(%{
               provider: "wallet",
               external_id: "list-3",
               deposit_account_id: deposit_account.id
             })

    assert length(Connectors.list_external_accounts()) == 3
  end

  test "lists external accounts for a provider only" do
    portfolio = create_portfolio()
    deposit_account = create_deposit_account(portfolio.id)

    assert {:ok, first} =
             Connectors.create_external_account(%{
               provider: "comdirect",
               external_id: "provider-filter-1",
               deposit_account_id: deposit_account.id
             })

    assert {:ok, _} =
             Connectors.create_external_account(%{
               provider: "bunq",
               external_id: "provider-filter-2",
               deposit_account_id: deposit_account.id
             })

    assert {:ok, second} =
             Connectors.create_external_account(%{
               provider: "comdirect",
               external_id: "provider-filter-3",
               deposit_account_id: deposit_account.id
             })

    providers = Connectors.list_external_accounts_for_provider("comdirect")

    assert Enum.map(providers, & &1.id) == [first.id, second.id]
  end

  test "gets external account by provider and external_id" do
    portfolio = create_portfolio()
    deposit_account = create_deposit_account(portfolio.id)

    assert {:ok, created} =
             Connectors.create_external_account(%{
               provider: "fake",
               external_id: "provider-id-lookup",
               deposit_account_id: deposit_account.id
             })

    assert account = Connectors.get_external_account_by_provider_id("fake", "provider-id-lookup")
    assert account.id == created.id
    assert account.provider == "fake"
    assert account.external_id == "provider-id-lookup"
  end

  test "updates mapping from one local account to another" do
    portfolio = create_portfolio()
    first_deposit_account = create_deposit_account(portfolio.id)
    second_deposit_account = create_deposit_account(portfolio.id)

    assert {:ok, account} =
             Connectors.create_external_account(%{
               provider: "fake",
               external_id: "update-1",
               deposit_account_id: first_deposit_account.id
             })

    assert {:ok, updated_account} =
             Connectors.update_external_account_mapping(account, %{
               deposit_account_id: second_deposit_account.id
             })

    assert updated_account.deposit_account_id == second_deposit_account.id
    assert updated_account.id == account.id
  end

  test "provider, status and type values remain strings" do
    portfolio = create_portfolio()
    deposit_account = create_deposit_account(portfolio.id)

    assert {:ok, account} =
             Connectors.create_external_account(%{
               provider: "bitcoin_de",
               external_id: "string-type",
               status: "disabled",
               external_type: "wallet",
               deposit_account_id: deposit_account.id
             })

    assert is_binary(account.provider)
    assert is_binary(account.status)
    assert is_binary(account.external_type)
    assert account.provider == "bitcoin_de"
    assert account.status == "disabled"
    assert account.external_type == "wallet"
  end

  test "does not create atoms from external provider or type input" do
    portfolio = create_portfolio()
    deposit_account = create_deposit_account(portfolio.id)
    provider = "provider-#{System.unique_integer([:positive])}"
    external_type = "type-#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, fn -> String.to_existing_atom(provider) end
    assert_raise ArgumentError, fn -> String.to_existing_atom(external_type) end

    assert {:ok, account} =
             Connectors.create_external_account(%{
               provider: provider,
               external_type: external_type,
               external_id: "atom-safe",
               deposit_account_id: deposit_account.id
             })

    assert account.provider == provider
    assert account.external_type == external_type
    assert_raise ArgumentError, fn -> String.to_existing_atom(provider) end
    assert_raise ArgumentError, fn -> String.to_existing_atom(external_type) end
  end

  test "does not create ledger transactions when creating external account mapping" do
    initial_transactions = Repo.aggregate(Transaction, :count, :id)
    portfolio = create_portfolio()
    deposit_account = create_deposit_account(portfolio.id)

    assert {:ok, _} =
             Connectors.create_external_account(%{
               provider: "wallet",
               external_id: "no-ledger",
               deposit_account_id: deposit_account.id
             })

    assert Repo.aggregate(Transaction, :count, :id) == initial_transactions
  end
end
