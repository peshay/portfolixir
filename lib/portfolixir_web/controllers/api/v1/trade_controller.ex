defmodule PortfolixirWeb.Api.V1.TradeController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, %{"security_id" => security_id}) do
    with {:ok, id} <- parse_id(security_id),
         security when not is_nil(security) <- Catalog.get_security(id) do
      trades = Ledger.list_trades_for_security(security.id)
      json(conn, %{data: JSON.trades(trades)})
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}
  defp parse_id(_), do: :error

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
