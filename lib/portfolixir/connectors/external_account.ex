defmodule Portfolixir.Connectors.ExternalAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Portfolios.DepositAccount
  alias Portfolixir.Portfolios.SecuritiesAccount

  schema "external_accounts" do
    field(:provider, :string)
    field(:external_id, :string)
    field(:external_name, :string)
    field(:external_type, :string)
    field(:currency_code, :string)
    field(:status, :string, default: "active")
    field(:metadata, :map, default: %{})

    belongs_to(:deposit_account, DepositAccount)
    belongs_to(:securities_account, SecuritiesAccount)

    timestamps()
  end

  @doc false
  def changeset(external_account, attrs) do
    external_account
    |> cast(attrs, [
      :provider,
      :external_id,
      :external_name,
      :external_type,
      :currency_code,
      :status,
      :deposit_account_id,
      :securities_account_id,
      :metadata
    ])
    |> validate_required([:provider, :external_id])
    |> validate_required_local_account()
    |> validate_not_multiple_local_accounts()
    |> foreign_key_constraint(:deposit_account_id)
    |> foreign_key_constraint(:securities_account_id)
    |> unique_constraint(:external_id, name: :external_accounts_provider_external_id_uq)
  end

  defp validate_required_local_account(changeset) do
    deposit_account_id = get_field(changeset, :deposit_account_id)
    securities_account_id = get_field(changeset, :securities_account_id)

    if is_nil(deposit_account_id) and is_nil(securities_account_id) do
      changeset
      |> add_error(:deposit_account_id, "must set either a deposit or securities account")
      |> add_error(:securities_account_id, "must be nil when deposit account is set")
    else
      changeset
    end
  end

  defp validate_not_multiple_local_accounts(changeset) do
    deposit_account_id = get_field(changeset, :deposit_account_id)
    securities_account_id = get_field(changeset, :securities_account_id)

    if !is_nil(deposit_account_id) and !is_nil(securities_account_id) do
      changeset
      |> add_error(:deposit_account_id, "cannot set both a deposit and securities account")
      |> add_error(:securities_account_id, "cannot set both a deposit and securities account")
    else
      changeset
    end
  end
end
