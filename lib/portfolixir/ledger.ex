defmodule Portfolixir.Ledger do
  @moduledoc "Transaction ledger context."

  import Ecto.Query

  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Ledger.CashBalances
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Repo

  def list_transactions do
    Repo.all(ordered_transactions())
  end

  def list_transactions_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    Repo.all(
      from(transaction in ordered_transactions(),
        where: transaction.portfolio_id == ^portfolio_id
      )
    )
  end

  def list_transactions_for_security(portfolio_id, security_id)
      when is_integer(portfolio_id) and is_integer(security_id) do
    Repo.all(
      from(transaction in ordered_transactions(),
        where:
          transaction.portfolio_id == ^portfolio_id and transaction.security_id == ^security_id
      )
    )
  end

  def list_transactions_for_security(_portfolio_id, _security_id), do: []

  def cash_balances_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    portfolio_id
    |> list_transactions_for_portfolio()
    |> Repo.preload(:securities_account)
    |> CashBalances.calculate()
  end

  def positions_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    portfolio_id
    |> list_transactions_for_portfolio()
    |> Positions.calculate()
  end

  def get_transaction!(id) do
    Repo.get!(Transaction, id)
  end

  def create_transaction(attrs) when is_map(attrs) do
    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert()
  end

  def update_transaction(%Transaction{} = transaction, attrs) when is_map(attrs) do
    transaction
    |> Transaction.changeset(attrs)
    |> Repo.update()
  end

  def delete_transaction(%Transaction{} = transaction) do
    Repo.delete(transaction)
  end

  defp ordered_transactions do
    from(transaction in Transaction,
      order_by: [desc: transaction.date, desc: transaction.inserted_at, desc: transaction.id]
    )
  end
end
