defmodule PortfolixirWeb.ReadAPIController do
  @moduledoc """
  Read-only JSON API for portfolio snapshots and ledger projections.

  NOTE: authentication is not implemented yet. These endpoints are intended for
  local/development use until authentication and access controls are added.
  """

  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  def portfolio_snapshot(conn, params) do
    case resolve_portfolio(params) do
      {:ok, portfolio} ->
        json(conn, %{
          portfolio: serialize_portfolio(portfolio),
          positions: serialize_positions(Ledger.positions_for_portfolio(portfolio.id)),
          cash_balances:
            serialize_cash_balances(Ledger.cash_balances_for_portfolio(portfolio.id)),
          generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "portfolio not found"})
    end
  end

  def positions(conn, params) do
    case resolve_portfolio(params) do
      {:ok, portfolio} ->
        json(conn, %{
          portfolio_id: portfolio.id,
          positions: serialize_positions(Ledger.positions_for_portfolio(portfolio.id))
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "portfolio not found"})
    end
  end

  def transactions(conn, params) do
    case resolve_portfolio(params) do
      {:ok, portfolio} ->
        json(conn, %{
          portfolio_id: portfolio.id,
          transactions:
            serialize_transactions(Ledger.list_transactions_for_portfolio(portfolio.id))
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "portfolio not found"})
    end
  end

  def cash_balances(conn, params) do
    case resolve_portfolio(params) do
      {:ok, portfolio} ->
        json(conn, %{
          portfolio_id: portfolio.id,
          cash_balances: serialize_cash_balances(Ledger.cash_balances_for_portfolio(portfolio.id))
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "portfolio not found"})
    end
  end

  defp resolve_portfolio(params) do
    with {:ok, portfolio_id} <- requested_portfolio_id(params),
         %Portfolios.Portfolio{} = portfolio <- Portfolios.get_portfolio(portfolio_id) do
      {:ok, portfolio}
    else
      nil ->
        {:error, :not_found}

      :none ->
        case Portfolios.first_portfolio() do
          nil -> {:error, :not_found}
          %Portfolios.Portfolio{} = portfolio -> {:ok, portfolio}
        end

      :not_found ->
        {:error, :not_found}

      _other ->
        {:error, :not_found}
    end
  end

  defp requested_portfolio_id(%{"portfolio_id" => portfolio_id}) when is_binary(portfolio_id) do
    case Integer.parse(portfolio_id) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> :not_found
    end
  end

  defp requested_portfolio_id(_params), do: :none

  defp serialize_portfolio(portfolio) do
    currency = Catalog.get_currency_by_code(portfolio.base_currency_code)

    %{
      id: portfolio.id,
      name: portfolio.name,
      description: portfolio.description,
      base_currency: %{
        code: portfolio.base_currency_code,
        name: currency && currency.name
      }
    }
  end

  defp serialize_positions(positions) do
    positions
    |> Enum.sort_by(fn {key, _quantity} -> key end)
    |> Enum.map(fn {{securities_account_id, security_id}, quantity} ->
      %{
        securities_account_id: securities_account_id,
        security_id: security_id,
        quantity: decimal_to_string(quantity)
      }
    end)
  end

  defp serialize_transactions(transactions) do
    Enum.map(transactions, fn transaction ->
      %{
        id: transaction.id,
        type: transaction.type,
        date: Date.to_iso8601(transaction.date),
        currency_code: transaction.currency_code,
        amount: decimal_to_string(transaction.amount),
        quantity: decimal_to_string(transaction.quantity),
        price: decimal_to_string(transaction.price),
        fees: decimal_to_string(transaction.fees),
        taxes: decimal_to_string(transaction.taxes),
        deposit_account_id: transaction.deposit_account_id,
        securities_account_id: transaction.securities_account_id,
        security_id: transaction.security_id,
        notes: transaction.notes
      }
    end)
  end

  defp serialize_cash_balances(cash_balances) do
    %{
      balances:
        Enum.map(cash_balances.balances, fn {{deposit_account_id, currency_code}, balance} ->
          %{
            deposit_account_id: deposit_account_id,
            currency_code: currency_code,
            balance: decimal_to_string(balance)
          }
        end),
      missing_cash_impacts:
        Enum.map(cash_balances.missing_cash_impacts, fn impact ->
          %{
            transaction_id: impact.transaction_id,
            type: impact.type,
            reason: Atom.to_string(impact.reason)
          }
        end)
    }
  end

  defp decimal_to_string(%Decimal{} = value), do: Decimal.to_string(value)
  defp decimal_to_string(_value), do: nil
end
