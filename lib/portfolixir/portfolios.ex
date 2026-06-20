defmodule Portfolixir.Portfolios do
  @moduledoc "Portfolio and linked account setup."

  import Ecto.Query

  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Repo

  def list_portfolios do
    from(portfolio in Portfolio, order_by: [asc: portfolio.id])
    |> Repo.all()
    |> Enum.map(&load_cash_target/1)
  end

  def count_portfolios do
    Repo.aggregate(Portfolio, :count, :id)
  end

  def first_portfolio do
    from(portfolio in Portfolio, order_by: [asc: portfolio.id], limit: 1)
    |> Repo.one()
    |> load_cash_target()
  end

  def get_portfolio!(id), do: Repo.get!(Portfolio, id) |> load_cash_target()

  def get_portfolio(id) when is_integer(id), do: Repo.get(Portfolio, id) |> load_cash_target()

  def create_portfolio(attrs) when is_map(attrs) do
    %Portfolio{}
    |> Portfolio.changeset(attrs)
    |> Repo.insert()
    |> persist_cash_target()
  end

  def update_portfolio(%Portfolio{} = portfolio, attrs) when is_map(attrs) do
    portfolio
    |> Portfolio.changeset(attrs)
    |> Repo.update()
    |> persist_cash_target()
  end

  @doc """
  Sets (or clears) a portfolio's cash target weight, the SOLL share of cash in
  the allocation's 100% basis (securities + counting cash, see issue #335).

  Since ADR-0020 the cash target lives on the portfolio's Gesamt cash plan
  (`Portfolixir.Portfolios.Targets`); this writes there and returns the portfolio
  with the value loaded into its virtual field, preserving the prior contract.

  `weight` is a fraction in `[0, 1]` or `nil` to stop steering a cash quote.
  Returns `{:ok, %Portfolio{}}` or `{:error, %Ecto.Changeset{}}` (a weight out
  of range).
  """
  def set_cash_target(%Portfolio{} = portfolio, weight) do
    case Targets.set_cash_target(portfolio.id, weight) do
      :ok -> {:ok, %{portfolio | cash_target_weight: weight}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # Populates the virtual cash_target_weight from the portfolio-wide Gesamt cash
  # plan, so reads keep exposing the value the column used to carry (ADR-0020).
  defp load_cash_target(nil), do: nil

  defp load_cash_target(%Portfolio{} = portfolio) do
    %{portfolio | cash_target_weight: Targets.get_cash_target(portfolio.id)}
  end

  # Write-through: after a portfolio write, persist the virtual cash target onto
  # the Gesamt cash plan when the changeset carried one (it casts and validates a
  # `[0, 1]` fraction). A nil weight clears the steered quote.
  defp persist_cash_target({:ok, %Portfolio{} = portfolio}) do
    weight = portfolio.cash_target_weight
    :ok = Targets.set_cash_target(portfolio.id, weight)
    {:ok, %{portfolio | cash_target_weight: weight}}
  end

  defp persist_cash_target(other), do: other

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
