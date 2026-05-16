defmodule Portfolixir.Ledger do
  @moduledoc "Manual buy and sell transaction ledger."

  import Ecto.Query

  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.SecuritiesAccount
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

  def list_transactions_for_security(security_id) when is_integer(security_id) do
    Repo.all(
      from(transaction in Transaction,
        where: transaction.security_id == ^security_id,
        order_by: [asc: transaction.date, asc: transaction.id],
        preload: [:portfolio, :securities_account, :cash_account]
      )
    )
  end

  def count_transactions do
    Repo.aggregate(Transaction, :count, :id)
  end

  def create_transaction(attrs) when is_map(attrs) do
    with {:ok, attrs} <- derive_linked_cash_account(attrs) do
      %Transaction{}
      |> Transaction.changeset(attrs)
      |> Repo.insert()
    end
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

  defp derive_linked_cash_account(attrs) do
    with {:ok, securities_account_id} <- fetch_integer(attrs, :securities_account_id),
         %SecuritiesAccount{} = securities_account <-
           Repo.get(SecuritiesAccount, securities_account_id) do
      validate_selected_portfolio(attrs, securities_account)
    else
      :missing -> {:ok, attrs}
      :invalid -> {:ok, attrs}
      nil -> {:ok, attrs}
    end
  end

  defp validate_selected_portfolio(attrs, securities_account) do
    case fetch_integer(attrs, :portfolio_id) do
      {:ok, portfolio_id} when portfolio_id != securities_account.portfolio_id ->
        {:error,
         invalid_transaction(
           attrs,
           :securities_account_id,
           "must belong to the selected portfolio"
         )}

      _portfolio_ok ->
        validate_selected_cash_account(attrs, securities_account)
    end
  end

  defp validate_selected_cash_account(attrs, securities_account) do
    case fetch_integer(attrs, :cash_account_id) do
      {:ok, cash_account_id} when cash_account_id != securities_account.cash_account_id ->
        {:error, invalid_transaction(attrs, :cash_account_id, "must match the selected depot")}

      _missing_or_matching ->
        {:ok, put_attr(attrs, :cash_account_id, securities_account.cash_account_id)}
    end
  end

  defp invalid_transaction(attrs, field, message) do
    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Ecto.Changeset.add_error(field, message)
    |> Map.put(:action, :insert)
  end

  defp fetch_integer(attrs, field) do
    value = get_attr(attrs, field)

    cond do
      is_integer(value) ->
        {:ok, value}

      is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> {:ok, integer}
          _invalid -> :invalid
        end

      is_nil(value) ->
        :missing

      true ->
        :invalid
    end
  end

  defp get_attr(attrs, field) do
    Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))
  end

  defp put_attr(attrs, field, value) do
    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, Atom.to_string(field), value)
    else
      Map.put(attrs, field, value)
    end
  end
end
