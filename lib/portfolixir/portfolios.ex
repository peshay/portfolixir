defmodule Portfolixir.Portfolios do
  @moduledoc "Portfolio and linked account setup."

  import Ecto.Query

  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  def list_portfolios do
    Repo.all(from(portfolio in Portfolio, order_by: [asc: portfolio.id]))
  end

  def count_portfolios do
    Repo.aggregate(Portfolio, :count, :id)
  end

  def first_portfolio do
    Repo.one(from(portfolio in Portfolio, order_by: [asc: portfolio.id], limit: 1))
  end

  def get_portfolio!(id), do: Repo.get!(Portfolio, id)

  def create_portfolio(attrs) when is_map(attrs) do
    %Portfolio{}
    |> Portfolio.changeset(attrs)
    |> Repo.insert()
  end

  def change_portfolio(%Portfolio{} = portfolio, attrs \\ %{}) do
    Portfolio.changeset(portfolio, attrs)
  end

  def list_cash_accounts do
    Repo.all(from(account in CashAccount, order_by: [asc: account.name, asc: account.id]))
  end

  def list_cash_accounts_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    Repo.all(
      from(account in CashAccount,
        where: account.portfolio_id == ^portfolio_id,
        order_by: [asc: account.name, asc: account.id]
      )
    )
  end

  def count_cash_accounts do
    Repo.aggregate(CashAccount, :count, :id)
  end

  def create_cash_account(attrs) when is_map(attrs) do
    %CashAccount{}
    |> CashAccount.changeset(attrs)
    |> Repo.insert()
  end

  def change_cash_account(%CashAccount{} = cash_account, attrs \\ %{}) do
    CashAccount.changeset(cash_account, attrs)
  end

  def list_securities_accounts do
    Repo.all(
      from(account in SecuritiesAccount,
        order_by: [asc: account.name, asc: account.id],
        preload: [:cash_account]
      )
    )
  end

  def list_securities_accounts_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    Repo.all(
      from(account in SecuritiesAccount,
        where: account.portfolio_id == ^portfolio_id,
        order_by: [asc: account.name, asc: account.id],
        preload: [:cash_account]
      )
    )
  end

  def count_securities_accounts do
    Repo.aggregate(SecuritiesAccount, :count, :id)
  end

  def create_securities_account(attrs) when is_map(attrs) do
    %SecuritiesAccount{}
    |> SecuritiesAccount.changeset(attrs)
    |> Repo.insert()
  end

  def change_securities_account(%SecuritiesAccount{} = securities_account, attrs \\ %{}) do
    SecuritiesAccount.changeset(securities_account, attrs)
  end
end
