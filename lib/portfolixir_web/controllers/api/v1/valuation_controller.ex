defmodule PortfolixirWeb.Api.V1.ValuationController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ViewParam

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, id} <- parse_id(portfolio_id),
         portfolio when not is_nil(portfolio) <- Portfolios.get_portfolio(id),
         {:ok, view} <- ViewParam.resolve(params) do
      data =
        id
        |> Valuation.for_portfolio(ViewParam.opts(view))
        |> JSON.valuation()
        |> ViewParam.put_active(view)

      json(conn, %{data: data})
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> unprocessable(conn, %{view: ["is invalid"]})
      :view_not_found -> not_found(conn)
    end
  end

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
