defmodule PortfolixirWeb.Api.V1.PerformanceController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ViewParam

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, id} <- parse_id(portfolio_id),
         portfolio when not is_nil(portfolio) <- Portfolios.get_portfolio(id),
         {:ok, view} <- ViewParam.resolve(params) do
      period = Map.get(params, "period", "max")
      include_series? = Map.get(params, "series") in ["true", "1"]
      opts = Keyword.put(ViewParam.opts(view), :period, period)

      case Performance.for_portfolio(id, opts) do
        {:ok, result} ->
          data = result |> JSON.performance(include_series?) |> ViewParam.put_active(view)
          json(conn, %{data: data})

        {:error, :invalid_period} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: %{period: ["is invalid"]}})

        # The view vanished between resolve and read (fix round TOCTOU):
        # still a plain 404, never a 500.
        {:error, :view_not_found} ->
          not_found(conn)
      end
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      {:error, :view} -> unprocessable(conn, %{view: ["is invalid"]})
      :view_not_found -> not_found(conn)
    end
  end

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
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
