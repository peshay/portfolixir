defmodule Portfolixir.Portfolios do
  @moduledoc "Portfolio context."

  import Ecto.Query

  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.DepositAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  def list_portfolios do
    Repo.all(Portfolio)
  end

  def first_portfolio do
    Repo.one(from(portfolio in Portfolio, order_by: [asc: portfolio.id], limit: 1))
  end

  def get_portfolio!(id) do
    Repo.get!(Portfolio, id)
  end

  def create_portfolio(attrs) when is_map(attrs) do
    %Portfolio{}
    |> Portfolio.changeset(attrs)
    |> Repo.insert()
  end

  def update_portfolio(%Portfolio{} = portfolio, attrs) when is_map(attrs) do
    portfolio
    |> Portfolio.changeset(attrs)
    |> Repo.update()
  end

  def delete_portfolio(%Portfolio{} = portfolio) do
    Repo.delete(portfolio)
  end

  def list_deposit_accounts do
    Repo.all(from(account in DepositAccount, order_by: [asc: account.name]))
  end

  def list_deposit_accounts_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    Repo.all(
      from(account in DepositAccount,
        where: account.portfolio_id == ^portfolio_id,
        order_by: [asc: account.name]
      )
    )
  end

  def get_deposit_account!(id), do: Repo.get!(DepositAccount, id)

  def create_deposit_account(attrs) when is_map(attrs) do
    %DepositAccount{}
    |> DepositAccount.changeset(attrs)
    |> Repo.insert()
  end

  def update_deposit_account(%DepositAccount{} = account, attrs) when is_map(attrs) do
    account
    |> DepositAccount.changeset(attrs)
    |> Repo.update()
  end

  def delete_deposit_account(%DepositAccount{} = account) do
    Repo.delete(account)
  end

  def list_securities_accounts do
    Repo.all(from(account in SecuritiesAccount, order_by: [asc: account.name]))
  end

  def list_securities_accounts_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    Repo.all(
      from(account in SecuritiesAccount,
        where: account.portfolio_id == ^portfolio_id,
        order_by: [asc: account.name]
      )
    )
  end

  def get_securities_account!(id) do
    Repo.get!(SecuritiesAccount, id)
  end

  def create_securities_account(attrs) when is_map(attrs) do
    %SecuritiesAccount{}
    |> SecuritiesAccount.changeset(attrs)
    |> Repo.insert()
  end

  def update_securities_account(%SecuritiesAccount{} = account, attrs) when is_map(attrs) do
    account
    |> SecuritiesAccount.changeset(attrs)
    |> Repo.update()
  end

  def delete_securities_account(%SecuritiesAccount{} = account) do
    Repo.delete(account)
  end
end
