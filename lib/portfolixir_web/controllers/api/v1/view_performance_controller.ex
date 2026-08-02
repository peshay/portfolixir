defmodule PortfolixirWeb.Api.V1.ViewPerformanceController do
  @moduledoc """
  JSON API for the cross-portfolio view performance (#577): one view's
  TTWROR/IRR across all portfolios — exactly the deduplicated account scope
  the view valuation endpoint covers, so the total and the return always
  speak about the same accounts. Financial decimals are serialized as
  strings; `?period=` and `?series=` behave like the portfolio performance
  endpoint.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Portfolios.Performance
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ViewParam

  def show(conn, %{"view_id" => view_id} = params) do
    with {:ok, vid} <- parse_id(view_id),
         %View{} = view <- Buckets.get_view(vid) do
      period = Map.get(params, "period", "max")
      include_series? = Map.get(params, "series") in ["true", "1"]

      case Performance.for_view(view.id, period: period) do
        {:ok, result} ->
          data =
            result
            |> JSON.view_performance(include_series?)
            |> ViewParam.put_active(view)

          json(conn, %{data: data})

        {:error, :invalid_period} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: %{period: ["is invalid"]}})

        # The view vanished between the lookup and the walk (TOCTOU): a plain
        # 404, never a 500.
        {:error, :view_not_found} ->
          not_found(conn)
      end
    else
      _ -> not_found(conn)
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
