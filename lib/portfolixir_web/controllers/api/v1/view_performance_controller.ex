defmodule PortfolixirWeb.Api.V1.ViewPerformanceController do
  @moduledoc """
  JSON API for the cross-portfolio view performance (#577): one view's
  TTWROR/IRR across all portfolios — exactly the deduplicated account scope
  the view valuation endpoint covers, so the total and the return always
  speak about the same accounts. Financial decimals are serialized as
  strings; `?period=` and `?series=` behave like the portfolio performance
  endpoint.

  `total/2` serves the same read with no view (#1056, Sprint 19 plan D-7):
  `GET /api/v1/performance`, the Everything walk `Performance.for_view(nil)`,
  every account of every portfolio counted once, always in EUR, with
  `view_id` null and no view echo; its `computation_basis` names that scope
  and currency.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Portfolios.Performance
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.PeriodParam
  alias PortfolixirWeb.Api.V1.ViewParam

  def show(conn, %{"view_id" => view_id} = params) do
    with {:ok, vid} <- IdParam.parse(view_id),
         %View{} = view <- Buckets.get_view(vid) do
      read(conn, view, params)
    else
      _ -> not_found(conn)
    end
  end

  def total(conn, params), do: read(conn, nil, params)

  # `view` nil is the Everything scope (#1056).
  defp read(conn, view, params) do
    include_series? = Map.get(params, "series") in ["true", "1"]

    with {:ok, period} <- PeriodParam.resolve(params),
         {:ok, result} <- Performance.for_view(ViewParam.id(view), period: period) do
      data =
        result
        |> JSON.view_performance(include_series?)
        |> ViewParam.put_active(view)

      json(conn, %{data: data})
    else
      # An unknown period string, a malformed year, or a backwards range
      # (#563) share the 422 contract.
      {:error, :invalid_period} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{period: ["is invalid"]}})

      # The view vanished between the lookup and the walk (TOCTOU): a plain
      # 404, never a 500.
      {:error, :view_not_found} ->
        not_found(conn)
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
