defmodule Portfolixir.Ledger do
  @moduledoc "Manual buy and sell transaction ledger."

  import Ecto.Query

  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  def list_transactions do
    Repo.all(ordered_transactions() |> preload([:security, :cash_account, :securities_account]))
  end

  def list_transactions_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    Repo.all(
      from(transaction in ordered_transactions(),
        where: transaction.portfolio_id == ^portfolio_id,
        preload: [:security, :cash_account, :securities_account]
      )
    )
  end

  def count_transactions do
    Repo.aggregate(Transaction, :count, :id)
  end

  def create_transaction(attrs) when is_map(attrs) do
    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert()
  end

  def change_transaction(%Transaction{} = transaction, attrs \\ %{}) do
    Transaction.changeset(transaction, attrs)
  end

  def positions_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    portfolio_id
    |> list_transactions_for_portfolio()
    |> Positions.calculate()
  end

  defp ordered_transactions do
    from(transaction in Transaction,
      order_by: [desc: transaction.date, desc: transaction.id]
    )
  end
end
