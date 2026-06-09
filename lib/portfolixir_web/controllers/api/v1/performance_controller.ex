defmodule PortfolixirWeb.Api.V1.PerformanceController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, id} <- parse_id(portfolio_id),
         portfolio when not is_nil(portfolio) <- Portfolios.get_portfolio(id) do
      period = Map.get(params, "period", "max")
      include_series? = Map.get(params, "series") in ["true", "1"]

      case Performance.for_portfolio(id, period: period) do
        {:ok, result} ->
          json(conn, %{data: JSON.performance(result, include_series?)})

        {:error, :invalid_period} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: %{period: ["is invalid"]}})
      end
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

  defp parse_id(_value), do: :error

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
