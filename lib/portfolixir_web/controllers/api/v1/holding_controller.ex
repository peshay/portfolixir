defmodule PortfolixirWeb.Api.V1.HoldingController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Ledger
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, %{"portfolio_id" => portfolio_id}) do
    case parse_id(portfolio_id) do
      {:ok, id} ->
        holdings =
          id
          |> Ledger.positions_for_portfolio()
          |> Enum.map(&JSON.holding(&1, id))

        json(conn, %{data: holdings})

      :error ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "not found"}})
    end
  end

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end
end
