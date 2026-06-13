defmodule Portfolixir.Portfolios do
  @moduledoc "Portfolio and linked account setup."

  import Ecto.Query

  alias Portfolixir.Ledger.Transaction
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

  def get_portfolio(id) when is_integer(id), do: Repo.get(Portfolio, id)

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

  @doc """
  Sets (or clears) a portfolio's cash target weight, the SOLL share of cash in
  the allocation's 100% basis (securities + counting cash, see issue #335).

  `weight` is a fraction in `[0, 1]` or `nil` to stop steering a cash quote.
  Returns `{:ok, %Portfolio{}}` or `{:error, %Ecto.Changeset{}}` (a weight out
  of range).
  """
  def set_cash_target(%Portfolio{} = portfolio, weight) do
    update_portfolio(portfolio, %{cash_target_weight: weight})
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

  def get_cash_account(id) when is_integer(id), do: Repo.get(CashAccount, id)

  def update_cash_account(%CashAccount{} = cash_account, attrs) when is_map(attrs) do
    cash_account
    |> CashAccount.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a cash account. All account FKs are `on_delete: :restrict`, so an
  account still referenced by a transaction or a securities account cannot be
  removed; this returns `{:error, :referenced}` instead of raising.
  """
  def delete_cash_account(%CashAccount{} = cash_account) do
    if cash_account_referenced?(cash_account.id) do
      {:error, :referenced}
    else
      Repo.delete(cash_account)
    end
  end

  defp cash_account_referenced?(id) do
    Repo.exists?(
      from(t in Transaction,
        where: t.cash_account_id == ^id or t.counter_cash_account_id == ^id
      )
    ) or Repo.exists?(from(s in SecuritiesAccount, where: s.cash_account_id == ^id))
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

  def get_securities_account(id) when is_integer(id) do
    case Repo.get(SecuritiesAccount, id) do
      nil -> nil
      account -> Repo.preload(account, :cash_account)
    end
  end

  def update_securities_account(%SecuritiesAccount{} = securities_account, attrs)
      when is_map(attrs) do
    securities_account
    |> SecuritiesAccount.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, Repo.preload(updated, :cash_account, force: true)}
      other -> other
    end
  end

  @doc """
  Deletes a securities account. Its FKs are `on_delete: :restrict`, so an account
  still referenced by a transaction cannot be removed; this returns
  `{:error, :referenced}` instead of raising.
  """
  def delete_securities_account(%SecuritiesAccount{} = securities_account) do
    if securities_account_referenced?(securities_account.id) do
      {:error, :referenced}
    else
      Repo.delete(securities_account)
    end
  end

  defp securities_account_referenced?(id) do
    Repo.exists?(
      from(t in Transaction,
        where: t.securities_account_id == ^id or t.counter_securities_account_id == ^id
      )
    )
  end
end
