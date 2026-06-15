defmodule PortfolixirWeb.Api.V1.HoldingController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, id} <- parse_id(portfolio_id),
         portfolio when not is_nil(portfolio) <- Portfolios.get_portfolio(id) do
      holdings =
        id
        |> Ledger.holdings_for_portfolio()
        |> filter_holdings(params)

      json(conn, JSON.holdings(holdings, id))
    else
      :error ->
        not_found(conn)

      nil ->
        not_found(conn)
    end
  end

  # Optional in-memory filters on the enriched holdings.
  defp filter_holdings(holdings, params) do
    security_id = optional_id(params["security_id"])
    account_id = optional_id(params["securities_account_id"])

    holdings
    |> filter_by(& &1.security_id, security_id)
    |> filter_by(& &1.securities_account_id, account_id)
  end

  defp filter_by(holdings, _selector, nil), do: holdings

  defp filter_by(holdings, selector, value),
    do: Enum.filter(holdings, fn holding -> selector.(holding) == value end)

  defp optional_id(value) do
    case parse_id(value) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
