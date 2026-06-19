defmodule PortfolixirWeb.Api.V1.AllocationController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Portfolio
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ViewParam

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, cid} <- classification_id(Map.get(params, "classification_id")),
         {:ok, view} <- ViewParam.resolve(params) do
      case Allocation.for_portfolio(pid, cid, ViewParam.opts(view)) do
        {:ok, allocation} ->
          data = allocation |> JSON.allocation() |> ViewParam.put_active(view)
          json(conn, %{data: data})

        {:error, :not_found} ->
          not_found(conn)
      end
    else
      :missing -> unprocessable(conn, %{classification_id: ["is required"]})
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> unprocessable(conn, %{view: ["is invalid"]})
      :view_not_found -> not_found(conn)
    end
  end

  defp classification_id(nil), do: :missing
  defp classification_id(value), do: parse_id(value)

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
