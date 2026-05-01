defmodule Portfolixir.Connectors do
  @moduledoc "Read-only connector abstraction and capability checks."

  import Ecto.Query

  @read_capabilities [
    "read_accounts",
    "read_balances",
    "read_transactions",
    "read_documents",
    "read_permissions"
  ]

  @write_capabilities [
    "create_payment",
    "place_order",
    "cancel_order",
    "withdraw",
    "transfer"
  ]

  @doc "Expose supported capabilities as strings."
  @spec capabilities() :: [String.t()]
  def capabilities do
    @read_capabilities
  end

  alias Portfolixir.Connectors.ExternalAccount
  alias Portfolixir.Repo

  def create_external_account(attrs) when is_map(attrs) do
    %ExternalAccount{}
    |> ExternalAccount.changeset(attrs)
    |> Repo.insert()
  end

  def list_external_accounts do
    from(account in ExternalAccount, order_by: [asc: account.id])
    |> Repo.all()
  end

  def list_external_accounts_for_provider(provider) when is_binary(provider) do
    from(account in ExternalAccount,
      where: account.provider == ^provider,
      order_by: [asc: account.id]
    )
    |> Repo.all()
  end

  def get_external_account_by_provider_id(provider, external_id)
      when is_binary(provider) and is_binary(external_id) do
    Repo.get_by(ExternalAccount, provider: provider, external_id: external_id)
  end

  def update_external_account_mapping(%ExternalAccount{} = external_account, attrs)
      when is_map(attrs) do
    external_account
    |> ExternalAccount.changeset(attrs)
    |> Repo.update()
  end

  @doc "Alias retained for story intent and readability."
  @spec supported_capabilities() :: [String.t()]
  def supported_capabilities, do: capabilities()

  @spec accounts(module(), map()) ::
          {:ok, [map()]} | {:error, {:unsupported_capability, String.t()}}
  def accounts(provider, config) when is_atom(provider) and is_map(config) do
    call(provider, "read_accounts", config)
  end

  @spec balances(module(), map()) ::
          {:ok, [map()]} | {:error, {:unsupported_capability, String.t()}}
  def balances(provider, config) when is_atom(provider) and is_map(config) do
    call(provider, "read_balances", config)
  end

  @spec transactions(module(), map(), map()) ::
          {:ok, [map()]} | {:error, {:unsupported_capability, String.t()}}
  def transactions(provider, config, opts \\ %{})
      when is_atom(provider) and is_map(config) and is_map(opts) do
    call(provider, "read_transactions", config, opts)
  end

  @spec documents(module(), map(), map()) ::
          {:ok, [map()]} | {:error, {:unsupported_capability, String.t()}}
  def documents(provider, config, opts \\ %{})
      when is_atom(provider) and is_map(config) and is_map(opts) do
    call(provider, "read_documents", config, opts)
  end

  @spec permissions(module(), map()) ::
          {:ok, [String.t()]} | {:error, {:unsupported_capability, String.t()}}
  def permissions(provider, config) when is_atom(provider) and is_map(config) do
    call(provider, "read_permissions", config)
  end

  @spec call(module(), String.t(), map(), map()) ::
          {:ok, [map()] | [String.t()]}
          | {:error, {:unsupported_capability, String.t()}}
          | {:error, {:invalid_capability, term()}}
  def call(provider, capability, config, opts \\ %{})

  def call(provider, capability, config, opts)
      when is_atom(provider) and is_binary(capability) and is_map(config) and is_map(opts) do
    case capability do
      "read_accounts" ->
        provider.accounts(config)

      "read_balances" ->
        provider.balances(config)

      "read_transactions" ->
        provider.transactions(config, opts)

      "read_documents" ->
        provider.documents(config, opts)

      "read_permissions" ->
        provider.permissions(config)

      cap when cap in @write_capabilities ->
        unsupported_capability(cap)

      cap ->
        unsupported_capability(cap)
    end
  end

  def call(_provider, capability, _config, _opts), do: {:error, {:invalid_capability, capability}}

  defp unsupported_capability(capability), do: {:error, {:unsupported_capability, capability}}
end
